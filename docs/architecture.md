# 核心架构契约

**这是项目的根本规则。每一个功能面 —— App、`klock`、Shortcuts、AppleScript、Widgets 以及后续新增的任何形态 —— 都必须遵守它。当某个改动与本契约冲突时,契约优先;修改的是那个改动,而不是契约。**

## 为什么是单核(从旧方案学到的)

本契约不是凭空的偏好,而是对一版**跑偏的旧实现**的直接回应。旧方案工程质量不差(依赖注入、职责分层、注释齐全),却选错了架构轴,导致多个功能面之间的锁状态根本无法对齐。把它的失败模式记在这里,是为了让契约的每条规则都有据可依,后来者(包括未来的自己)不再重蹈。

- **进程内单例不是跨进程共享。** 旧方案让 App、CLI、AppleScript 各自 `import` 核心并持有 `KeyboardLockCore.shared`。`static let shared` 是**进程内**单例——三个进程三个实例,不是同一个。于是 CLI `lock` 锁的是 CLI 进程自己的 event tap,CLI 一退出锁就被 `deinit` 拆掉,锁**活不过命令**;App 与 CLI 的 `isLocked` 是两个变量,永远对不上。
  → **教训**:「一个物理键盘 = 一个全局状态」这个领域事实,必须映射为「一个**进程**持有它」(Agent + XPC),而不是「一个**类型**持有它」。语言层单例解决不了进程边界。
- **回调式状态推送只能通知本进程。** 旧核心用 `var onLockStateChanged: ((Bool, Date?) -> Void)?` 广播变化,闭包只能绑本进程对象;CLI 改了状态,App 的回调永远收不到。旧架构连「跨进程同步」的入口都没有。
  → **教训**:多面场景下必须用系统级广播(见下文"状态同步"),而非进程内回调。
- **分层分对了,轴选错了。** 旧方案按"关注点"垂直分层非常漂亮,却没有先按"进程边界"水平切分,于是每一层都被复制进三个进程。
  → **教训**:干净的类型分层 ≠ 正确的系统架构。有多个入口进程时,**第一刀切在进程边界(谁执行 / 谁只是 wrapper),再谈类型优雅**。
- **各进程独立读 `UserDefaults` → 设置漂移。** 旧方案每个进程各持一份配置,CLI 改了热键 App 不知道。
  → **教训**:设置也只能有一个真相源(Agent),wrapper 只经 XPC 读写(见下文"各职责的归属")。

一句话:**有进程边界时,先按进程切,再谈类型优雅;单例和回调是进程内工具,不要拿来跨进程。** 下面的规则都是这句话的展开。

## 单核原则

**Agent 是唯一执行真实工作的地方。** 其他所有面(App、CLI、Shortcuts、AppleScript、Widgets、扩展)都是**薄 wrapper**,职责仅限两件事:

1. 把用户意图翻译成对 Agent 的一次 XPC 调用;
2. 通过通知观察全局状态。

wrapper 永远不拥有行为或状态。如果两个 wrapper 看起来需要同一段逻辑,那段逻辑属于核心,而不该复制进每个 wrapper。

```
App ─────┐
CLI ─────┤
Shortcut ┼── XPC ──▶ Agent  ◀── the ONLY executor
AppleScript┤            ├─ LockEngine        (event tap, lock lifecycle)
Widget ──┘            ├─ Settings ownership (source of truth)
                       └─ Accessibility      (permission gate)
```

这里的 `Core`、SwiftPM product、运行进程和 XPC connection 是不同层次。完整的构建依赖图、进程图和调用时序见 [XPC 实现与使用指南](xpc.md)。

## 各职责的归属

| 关注点 | 归属 | 规则 |
|---------|------|------|
| 锁/解锁执行(CGEventTap) | **Agent**(`Service/LockEngine`) | 只在这里运行,不在别处。没有任何 wrapper 触碰 CGEventTap。 |
| 设置(真相源) | **Agent** | Agent 加载并拥有设置、负责应用它们。wrapper 绝不自己持有 `UserDefaults`,只经 XPC 访问。当前仅暴露读取(`currentSettings`);写入(`applySettings`)尚未接线,加入时同样必须经 Agent,绝不在 wrapper 侧落地。 |
| Accessibility 权限 | **Agent** | Agent 持有权限,并在执行锁定时校验(`AccessibilityManager.hasPermission()`)。wrapper 只能经 XPC 查询状态或请求 Agent 触发系统 prompt,不得自行调用 Accessibility API。权限 prompt 是异步的;请求完成不代表已授权,wrapper 必须重新查询。 |
| 状态广播 | **Agent**(`LockStateBroadcaster`) | 只有核心发出状态。wrapper 只订阅,从不发出。 |
| UI / 意图翻译 | **Wrapper** | wrapper 可以持有视图状态,并协调只存在于自身进程的系统边界(例如 App 的 `SMAppService` 生命周期);不得复制 Agent 的锁、设置或 Accessibility 领域逻辑。 |

App 的 Agent readiness/replacement 协调属于 wrapper 与 Service Management、XPC 两个系统边界之间的应用层编排,不是第二份锁核心。它必须保持为无锁状态真相源的薄协调器：输入来自 Agent/系统查询,输出由 `LockController` 映射到 UI；任何 CGEventTap、设置持久化和 Accessibility 判定仍只在 Agent 内执行。

## 全局锁语义

物理键盘只有一个,所以锁状态是**一个由 Agent 拥有的全局布尔值**。不存在按客户端或按会话划分的锁归属。

- 任何 wrapper 都可以锁;任何 wrapper 都可以解锁。CLI 发起的锁,App 可以解开,反之亦然。
- 锁操作是**无状态的一次性 XPC 调用**(`lock` / `unlock` / `status`),彼此对称。不要把锁建模成客户端"拥有"的"会话"—— wrapper 的连接生命周期与锁的生命周期无关。
- 要对状态变化做出反应,订阅全局广播(`LockStateSubscriber`)。绝不从"我这次调用是否成功"去推断状态。

## 状态同步

因为状态只存在于唯一一处(Agent),wrapper 保持同步的方式就是始终以它为准。wrapper 有两种形态,读取状态的方式不同:

- **一次性面(one-shot)** —— CLI 的 `status`/`unlock`、AppleScript、Shortcuts(App Intents)、任何脚本。它们在运行的那一刻向 Agent 发问(`XPCClient.status()`)并据此行动。它们不缓存任何状态,因此**天生就是同步的**,不需要订阅。不要给一次性面加通知处理。
- **长命的状态反映面** —— App 菜单栏、未来的 Widgets。它们持续显示状态,因此必须既**订阅**(`LockStateSubscriber`),又在**变为可见 / 启动时校准**(拉取 `status()`)—— 因为进程被挂起期间可能错过某次广播。`LockStateSubscriber` 会先安装两个 observer,再立即做一次权威初始查询;只要初始查询成功或后续 signal 到达,snapshot 与 subscription 之间的变化就会被校准。调用方仍需在重新可见时做完整 readiness reconciliation。

`LockStateSubscriber` 把通知当作*提示*而非真相:订阅后的初始校准和收到的任一信号(Darwin 或 Distributed)都会向 Agent 拉取权威状态。多个并发信号被串行合并,相同状态被去重;subscription 取消后,尚未进入 handler 的在途结果会被丢弃。已经开始执行的 handler 不可被回溯撤销。Agent 之所以在两个通道都广播,只是为了让被挂起的 App 能被唤醒(Darwin)、让正在运行的 App 能及时更新(Distributed)。通知的载荷永远不是真相源。

`klock lock` 是一个会等待并报告后续解锁的长命命令,不是一次性 `status`。它同时使用 `LockStateSubscriber` 获得及时更新,并周期性查询 `status()` 以恢复双通道通知都丢失或 Agent 重启的场景;连续无法取得权威状态时必须报错退出,不能把 transport failure 猜成 unlocked。

## 新增 wrapper 的规则(Widget、Shortcut、AppleScript……)

编写 wrapper 之前,逐条确认以下几点:

1. **只 import `Client`,绝不 import `Service`。** wrapper 只通过 XPC 客户端与核心通信。把 `Service`(LockEngine、event tap)引入 wrapper 是违约。
2. **不新增领域逻辑。** 如果 wrapper 需要核心尚未暴露的行为,先把它加到 Agent + `KeyboardLockerServiceProtocol`,再调用;不要在 wrapper 侧实现。
3. **不持有独立状态。** 没有私有 `UserDefaults`,没有本地锁标志。设置和锁状态都从核心读取。
4. **不向其他进程发出任何东西。** 只有 Agent 广播状态。
5. **Agent 不可达时诚实降级。** 每个 wrapper 都必须处理"核心不可达"(见下方 Agent 生命周期要求),而不是假定调用成功。
6. **按自身形态读取状态。** 判断这个 wrapper 属于"状态同步"里的哪一种形态:一次性面直接调 `status()`,**不加**任何通知处理;长命 UI 通过 `LockStateSubscriber` 订阅,*并且*在变为可见时校准。

## Agent 生命周期要求

即使 App 没有运行,wrapper 也依赖 Agent 可达。Agent 必须向系统注册(`SMAppService`),以便 `launchd` 能按需为任何 XPC 客户端拉起它。假定 Agent 已经在运行(例如"因为 App 恰好开着")的 wrapper 是错误的。

App 必须区分 `SMAppService` 的 enabled、requires-approval、not-found 和 registration-failure 状态。只有 enabled 才继续查询 Agent;requires-approval 必须提供 Login Items 恢复入口。Agent 已 enabled 但 XPC 失败属于不可达,不能伪装成未锁定或缺少 Accessibility 权限。`enabled` 只表示系统允许该 service 运行,不证明当前进程就是 App 内 bundled 版本。

App 在调用新能力前必须先读取 `ServiceDescriptor`,分别验证 XPC protocol major/minor、required capabilities 和 bundled Agent 的 identifier/version/build。descriptor 中的身份字段只用于兼容性与更新判断,不能代替 XPC connection 的代码签名认证。descriptor 必须在 fresh connection 上重试后才能降级；若两次 descriptor 都失败而旧 `status` 成功，只能断言 base contract 可达，不能断言远端一定是 legacy Agent。此时只允许使用旧 `status` / `unlock` 做显式安全迁移，不得继续调用新 selector。

XPC peer authentication 必须由系统双向执行。Agent Listener 在 activate 前安装同 Team + 主 App/CLI 精确 signing identifier 的 connection requirement；App/CLI connection 在 activate 前安装同 Team + 精确 Agent signing identifier 的 requirement。Debug 不得降级成 identifier-only，不能通过 PID 后查静态签名来代替 XPC runtime 的 requirement。Team ID 从各进程自身已验证的签名读取；unsigned/ad-hoc 进程 fail closed。

capability grant 必须绑定到读取 descriptor 的同一条 client-side connection generation。所有 optional method 都要在一条具体 connection 上完成 handshake 与 capability check，再经同一个 `NSXPCConnection` 发出；connection 失效就同时失去 grant。named connection object 仍可能在 interruption 后面对新进程，因此 replacement wire request 必须携带 expected `agentInstanceID`，由 Agent 在副作用前原子验证，Client 也必须验证返回 ticket。

Agent 更新必须遵守以下边界:

- 当前锁为 locked 时绝不自动退出 Agent,因为进程退出会释放其 event tap;UI 必须明确说明并由用户选择 `Unlock and Replace Agent`。
- unlocked 也不能仅凭一次 `status()` 就自动替换,因为另一个 wrapper 可能随后重新 lock。只有 identifier 与 protocol major 相同、bundled `CFBundleVersion` 可比较且严格更高、并且 Agent 同时声明 prepared 与 committed-drain capability 时,App 才可自动更新。运行中 Agent build 更高时绝不自动降级。
- `prepareForReplacement` 必须在 Agent 的串行执行边界安装短期 fail-safe barrier,再按策略解锁并返回独占 ownership ticket。Agent 必须拒绝第二个 prepare，不能覆盖 ticket 或转移 cancellation 权限。
- legacy Agent、major 不兼容、身份不匹配或缺少 replacement capability 的 Agent 只能通过明确用户动作更新。无法建立 drain 时 UI 必须说明 replacement 窗口中的新 lock 可能被进程退出释放。
- 替换顺序固定为 prepare/unlock → 幂等 commit 为不可取消、不可过期的 drain → 仅在 commit reply 成功后提交并等待 `SMAppService.unregister()` → 注册 bundled Agent → 失效旧 Client connection → 建立新 connection → 重新读取 descriptor。新 descriptor 必须兼容且 `agentInstanceID` 必须变化;任何失败都停止。每个 App 进程对同一 bundled build 最多自动尝试一次,不得形成 restart loop。
- prepared drain 可以在 commit 前由 owner cancel 或短期 expire；committed drain 只能随旧 Agent 进程退出清除，绝不能用 heartbeat loss 或固定 timeout 推断在途 unregister 已取消。commit reply 丢失时由 exact ticket 的 `replacementStatus` 恢复真实结果。其他 App 通过 additive `replacementPhase` 解释 UI，只能周期性重新握手，不得接管、cancel 或再次 unregister。commit 后 coordinator crash 的极端窗口选择 fail closed；若长期未恢复，需要重启 macOS，而不能冒险让第二次 unregister 释放后来建立的活动锁。

## 需要警惕的违约

以下是本契约要防范的具体失败模式:

- wrapper 自己持有 `KeyboardLockerSettingsStore` / `UserDefaults` → 设置与核心漂移(Agent 会基于过期或默认设置行动)。
- 引入"会话"抽象、暗示客户端拥有锁 → 造成"某个面无法解开另一个面锁上的锁"这种迷惑行为。
- 锁/设置逻辑在 App 与 CLI 之间重复 → 正是 DRY 规则要禁止的维护爆炸。
- wrapper 为了"直接调引擎"而 import `Service` → 绕过了单核。
- 一次性面(CLI/AppleScript/Shortcuts)订阅广播,或在多次调用之间缓存锁状态 → 徒增复杂度并制造新的漂移源;它运行时直接调 `status()` 即可。
- 把通知载荷当作状态、而不去拉取 `status()` → 过期/乱序/丢失的通知会悄悄让 UI 失去同步。
