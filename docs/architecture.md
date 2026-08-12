# 核心架构契约

**这是项目的根本规则。每一个功能面 —— App、`klock`、Shortcuts、Focus Filter、Services、URL Scheme、AppleScript、Widgets、Notifications 以及后续新增的任何形态 —— 都必须遵守它。当某个改动与本契约冲突时,契约优先;修改的是那个改动,而不是契约。**

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

**Agent 是唯一执行真实工作的地方。** 其他所有面(App、CLI、Shortcuts、Focus Filter、Services、URL Scheme、AppleScript、Widgets、扩展)都是**薄 wrapper**,职责仅限两件事:

1. 把用户意图翻译成对 Agent 的一次 XPC 调用;
2. 通过通知观察全局状态。

wrapper 永远不拥有行为或状态。如果两个 wrapper 看起来需要同一段逻辑,那段逻辑属于核心,而不该复制进每个 wrapper。

```
App ─────────┐
CLI ─────────┤
Shortcut ────┤
Services/URL ┤
Focus ───────┼── XPC ──▶ Agent  ◀── the ONLY executor
AppleScript ─┤              ├─ LockEngine        (event tap, lock lifecycle)
Widget ──────┘              ├─ Settings ownership (source of truth)
                            ├─ Accessibility      (permission gate)
                            └─ Lock notification (discoverability surface)
```

这里的 `Core`、SwiftPM product、运行进程和 XPC connection 是不同层次。完整的构建依赖图、进程图和调用时序见 [XPC 实现与使用指南](xpc.md)。

## 各职责的归属

| 关注点 | 归属 | 规则 |
|---------|------|------|
| 锁/解锁执行(CGEventTap) | **Agent**(`Service/LockEngine`) | 只在这里运行,不在别处。没有任何 wrapper 触碰 CGEventTap。 |
| 设置(真相源) | **Agent** | Agent 加载并拥有设置、负责应用它们。wrapper 绝不自己持有 `UserDefaults`,只经 XPC 访问。当前仅暴露读取(`XPCClient.currentSettings()`);写入(`applySettings`)尚未接线,加入时同样必须经 Agent,绝不在 wrapper 侧落地。读取失败必须显式呈现为 unavailable,不能把 wrapper 的 `.default` 冒充为 Agent 当前值。 |
| 锁状态快照 | **Agent**(`Service/LockEngine`) | `XPCClient.lockStatusSnapshot()` 一次返回同一 execution turn 中的 `isLocked`、锁定起点、auto-unlock deadline 与 active settings。wrapper 可以缓存它用于呈现,但不能从缓存反推或修改 Agent 状态。 |
| Accessibility 权限 | **Agent** | Agent 持有权限,并在执行锁定时校验(`AccessibilityManager.hasPermission()`)。wrapper 只能经 XPC 查询状态或请求 Agent 触发系统 prompt,不得自行调用 Accessibility API。权限 prompt 是异步的;请求完成不代表已授权,wrapper 必须重新查询。 |
| 状态广播 | **Agent**(`LockStateBroadcaster`) | 只有核心发出状态。wrapper 只订阅,从不发出。 |
| 锁定可发现性通知 | **Agent**(`LockStatusNotifier`) | "Keyboard Locked" 通知的投递与移除跟随引擎的同一次状态转换,任何入口、App 是否运行都覆盖;wrapper 不发布锁状态通知。Agent 启动时清除上一代退出留下的残留。 |
| UI / 意图翻译 | **Wrapper** | wrapper 可以持有视图状态,并协调只存在于自身进程的系统边界(例如 App 的 `SMAppService` 生命周期);不得复制 Agent 的锁、设置或 Accessibility 领域逻辑。 |

App 的 Agent readiness/replacement 协调属于 wrapper 与 Service Management、XPC 两个系统边界之间的应用层编排,不是第二份锁核心。它必须保持为无锁状态真相源的薄协调器：`AppCoordinator` 只消费 Agent/系统查询并暴露应用状态与动作，不依赖 presentation framework；后续 UI 只能映射这些状态与动作。任何 CGEventTap、设置持久化和 Accessibility 判定仍只在 Agent 内执行。

App 可以持久化纯 presentation 状态,例如“是否已完成首次安全测试”;这类标记不得包含或推导锁状态、Agent settings 或 Accessibility 状态,也不能参与任何领域行为判定。诊断报告同样只是对当前权威查询的只读、脱敏呈现,不得缓存成另一份真相源。

## 全局锁语义

物理键盘只有一个,所以锁状态是**一个由 Agent 拥有的全局布尔值**。不存在按客户端或按会话划分的锁归属。

- 任何 wrapper 都可以锁;任何 wrapper 都可以解锁。CLI 发起的锁,App 可以解开,反之亦然。
- locked 的输入范围是 macOS 交付给 `CGEventTap` 的键盘来源事件：标准 `keyDown` / `keyUp` / `flagsChanged`,以及 `NX_SUBTYPE_AUX_CONTROL_BUTTONS`、`NX_SUBTYPE_EJECT_KEY`、`NX_SUBTYPE_POWER_KEY` 这三类 system-defined keyboard control。音量、亮度和播放控制因此必须被消费；鼠标 / 触控板 pointer event(包括 `NX_SUBTYPE_AUX_MOUSE_BUTTONS`)必须继续可用。macOS 没有交付给 event tap 的硬件或系统保留路径不在可保证范围内。
- 锁操作是**无状态的一次性 XPC 调用**(`lock` / `unlock` / `toggle` / `status`),彼此对称。不要把锁建模成客户端"拥有"的"会话"—— wrapper 的连接生命周期与锁的生命周期无关。
- `toggle` 是同一全局锁的原子翻转:在 Agent 的串行执行边界内于同一 execution turn 完成"读当前状态 + 反向 mutation",并向调用方返回翻转后的布尔值。锁定方向使用普通非交互 `lock` 语义(含 Focus persistence takeover),解锁方向等价于显式 `unlock`;wrapper 不得先读 `status()` 再自行决定方向来模拟 toggle。
- `lock` 对物理运行状态是严格幂等操作。Agent 已处于 locked 时,重复 `lock` 直接成功且不修改 event tap、当前设置、输入手势、锁定起点或 auto-unlock deadline；只有显式 settings update 才能重新应用设置并重新计算 timeout window。唯一的内部 metadata 变化是：若该代锁由 Focus Filter 创建,之后来自普通 wrapper 的显式 `lock` 会接管其持久性,使 Focus 关闭时不再解除这个更新的用户意图。
- safety check 是 capability-gated 的一次性 Agent 操作：仅在 unlocked 时创建新锁,沿用 Agent 持久化的解锁热键,但把该轮 active settings 的 auto-unlock 强制为固定 10 秒。fail-safe timer 由 Agent/`LockEngine` 持有,因此 App 退出、崩溃或 XPC 断开都不能让测试失去自动解锁兜底；该 override 不写回 settings store。若调用时已 locked,Agent 原子返回 already locked 且不修改既有锁。App 只在重新查询到权威 unlocked 后把 presentation completion 标记为完成。
- interactive lock request 会原子返回本次调用是否完成 `unlocked → locked`。这个 outcome 只描述状态转换,不建立客户端所有权、引用计数或 session。只有真正完成转换的 interactive request 才会让该轮全局锁额外接受 `Ctrl+C` 解锁；重复请求不得改变既有锁的输入手势。发起并等待中的 CLI 进程对本轮锁负有退出清理责任：它观察 SIGTERM/SIGHUP/SIGINT,退出前尽力释放锁(有界等待后无论如何退出)。wire protocol 不携带 interactive lock 的代际令牌,清理无法区分自己创建的锁与等待期间由他入口重建的锁——若本轮锁已被解开且另一入口重新锁定,清理会释放较新的锁,这与任意入口可解锁同一全局锁的契约一致;SIGKILL/SIGSTOP 不可观察,遗留锁仍由解锁热键、通知 Unlock Now、auto-unlock 等全局途径解开。这是输入手势语义的进程侧延伸,不构成 session 或所有权。
- Focus Filter 是 **activation-triggered acquisition**,不是“Focus active 期间持续保持 locked”的 policy。Focus 激活时的 `true` 最多尝试一次 `unlocked → locked`,并只在成功创建锁时记录该 Focus-owned generation；Focus 关闭时的 `false` 只条件性解除仍由它创建且未被普通 `lock` 接管的同一代。已有普通锁不会被 Focus 认领。显式 unlock、解锁热键、auto-unlock timeout、event-tap failure 或 Agent 退出 / 重启都可以在 Focus 仍 active 时提前结束该 generation；实现不会查询当前 Focus 后自动重建锁,也不会在同一次 Focus activation 内持续 relock。这个进程内 marker 不暴露给 wrapper,也不改变“任意入口可显式 unlock 同一个全局锁”的契约。
- `status()` 保留为兼容旧 wrapper 的最小布尔查询；需要呈现锁定时长、auto-unlock deadline 或 active settings 的 wrapper 使用 capability-gated `lockStatusSnapshot()`。snapshot 传输权威时间点,不传会立即过期的 duration/countdown counter。
- 要对状态变化做出反应,订阅全局广播(`LockStateSubscriber`)。绝不从"我这次调用是否成功"去推断状态。

## 状态同步

因为状态只存在于唯一一处(Agent),wrapper 保持同步的方式就是始终以它为准。wrapper 有两种形态,读取状态的方式不同:

- **一次性面(one-shot)** —— CLI 的 `status`/`unlock`、AppleScript、Shortcuts(App Intents)、Services、URL action 与任何脚本。它们在运行的那一刻向 Agent 发问(`XPCClient.status()` 或 `lockStatusSnapshot()`)并据此行动。它们不缓存任何状态,因此**天生就是同步的**,不需要订阅。不要给一次性面加通知处理。
- **长命的状态反映面** —— menu-bar App 等持续运行的 UI。它们必须既接收状态变化 signal,又在**变为可见 / 启动时校准** —— 因为进程被挂起期间可能错过某次广播。只显示布尔状态的现有 App 可以继续使用 `LockStateSubscriber`；需要起点、deadline 与 active settings 的界面在 signal 或重新可见时重新拉取 `lockStatusSnapshot()`。通知与本地缓存都不是真相源。
- **系统托管的 snapshot 面** —— Widget、Control 等由系统按需启动的 provider。它们不假定进程常驻,也不安装长命 subscription；每次生成 timeline/value 时读取 `lockStatusSnapshot()`,把本地值只当 presentation cache。交互 action 发送明确的 desired state,不从 cache 做 client-side toggle；Agent 确认 mutation 后可以请求系统重新运行 provider。

`LockStateSubscriber` 把通知当作*提示*而非真相:订阅后的初始校准和收到的任一信号(Darwin 或 Distributed)都会向 Agent 拉取权威状态。多个并发信号被串行合并,相同状态被去重;subscription 取消后,尚未进入 handler 的在途结果会被丢弃。已经开始执行的 handler 不可被回溯撤销。Agent 之所以在两个通道都广播,只是为了让被挂起的 App 能被唤醒(Darwin)、让正在运行的 App 能及时更新(Distributed)。通知的载荷永远不是真相源。

`SystemSurfaces` 的 reload request 是 presentation invalidation,不是领域状态广播：它不携带状态、不触碰 Agent,只请求 WidgetKit / ControlCenter 重新执行 provider。主 App、Widget 与 Focus extension 可以在 Agent 确认 mutation 后请求刷新；主 App 运行时还把已经由 `LockStateSubscriber` 回拉并去重的外部变化桥接为刷新提示。CLI 与 Agent 不链接 presentation module——这不只是边界约定：实测(macOS 26)`chronod` 会把非 extension 容器进程的 reload 请求按 `Ignoring restricted or unknown extension` 忽略,因此 `klock` 即使链接 `SystemSurfaces` 也无法真正触发刷新。主 App 未运行时,CLI、热键或 event-tap failure 造成的变化只能等待 WidgetKit 的下一次 provider execution；系统始终可以合并或延后 reload,因此任何 wrapper 都不得承诺即时 UI 同步。

`klock lock` 先发出 atomic interactive lock request。只有 outcome 为 acquired 时,它才等待并报告后续解锁；本轮 event tap 会把 `Ctrl+C` 当作额外解锁手势并在 Agent 内消费该事件。若 outcome 为 already locked,CLI 必须说明本命令没有创建新锁并立即退出,不能把 App 或另一个 CLI 已建立的锁变成自己的可取消 session。acquired 后的等待同时使用 `LockStateSubscriber` 获得及时更新,并周期性查询 `status()` 以恢复双通道通知都丢失或 Agent 重启的场景;连续无法取得权威状态时必须报错退出,不能把 transport failure 猜成 unlocked。

`klock lock --no-wait` 是独立的 one-shot desired-state action：它调用幂等 `lock()`,在 Agent 确认 locked 后立即退出,不启用临时 `Ctrl+C` 手势,也不等待后续 unlock。它同样不拥有 lock；之后执行的 `klock unlock` 会解开全局锁,而不是只撤销某个脚本创建的锁。

## 新增 wrapper 的规则(Widget、Shortcut、AppleScript……)

编写 wrapper 之前,逐条确认以下几点:

1. **只 import `Client`,绝不 import `Service`。** wrapper 只通过 XPC 客户端与核心通信。把 `Service`(LockEngine、event tap)引入 wrapper 是违约。
2. **不新增领域逻辑。** 如果 wrapper 需要核心尚未暴露的行为,先把它加到 Agent + `KeyboardLockerServiceProtocol`,再调用;不要在 wrapper 侧实现。
3. **不持有独立状态。** 没有私有 `UserDefaults`,没有本地锁标志。设置和锁状态都从核心读取。
4. **不广播业务状态。** 只有 Agent 发出状态变化 signal；wrapper 不得发送带 payload 的状态通知或把本地值当真相。containing App / extension 在 Agent 确认 mutation 后可以通过 `SystemSurfaces` 请求系统刷新 Widget / Control,但该请求只是无状态 presentation hint。
5. **Agent 不可达时诚实降级。** 每个 wrapper 都必须处理"核心不可达"(见下方 Agent 生命周期要求),而不是假定调用成功。
6. **按自身形态读取状态。** 判断这个 wrapper 属于"状态同步"里的哪一种形态:一次性面直接 query,**不加**任何通知处理;长命 UI 订阅 signal 并重新 query；系统托管的 snapshot provider 每次 execution 读取 `lockStatusSnapshot()`,交互 action 则发送 explicit desired state。

## Agent 生命周期要求

即使 App 没有运行,wrapper 也依赖 Agent 可达。Agent 必须向系统注册(`SMAppService`),以便 `launchd` 能按需为任何 XPC 客户端拉起它。假定 Agent 已经在运行(例如"因为 App 恰好开着")的 wrapper 是错误的。

App 必须区分 `SMAppService` 的 enabled、requires-approval、not-found 和 registration-failure 状态。只有 enabled 才继续查询 Agent;requires-approval 必须提供 Login Items 恢复入口。Agent 已 enabled 但 XPC 失败属于不可达,不能伪装成未锁定或缺少 Accessibility 权限。`enabled` 只表示系统允许该 service 运行,不证明当前进程就是 App 内 bundled 版本。

App 在调用新能力前必须先读取 `ServiceDescriptor`,分别验证 XPC protocol major/minor、required capabilities 和 bundled Agent 的 identifier/version/build。descriptor 中的身份字段只用于兼容性与更新判断,不能代替 XPC connection 的代码签名认证。descriptor 必须在 fresh connection 上重试后才能降级；若两次 descriptor 都失败而旧 `status` 成功，只能断言 base contract 可达，不能断言远端一定是 legacy Agent。此时只允许使用旧 `status` / `unlock` 做显式安全迁移，不得继续调用新 selector。

XPC peer authentication 必须由系统双向执行。Agent Listener 在 activate 前安装同 Team + 每个 wrapper 精确 signing identifier 的 connection requirement；wrapper connection 在 activate 前安装同 Team + 精确 Agent signing identifier 的 requirement。WidgetKit extension 使用单独的 `io.lzhlovesjyq.keyboardlocker.widgets` 身份承载 Widget 与 Control；Focus App Intents extension 使用 `io.lzhlovesjyq.keyboardlocker.focus-intents`;两者保持 App Sandbox,并只通过 Mach lookup temporary exception 访问 KeyboardLocker Agent 的 global service。Services 与 URL event 在主 App 进程内执行,因此 XPC peer 仍是主 App；这只认证 KeyboardLocker,不认证最初触发 Service 或 custom URL 的外部 caller。Debug 不得降级成 identifier-only，不能通过 PID 后查静态签名来代替 XPC runtime 的 requirement。Team ID 从各进程自身已验证的签名读取；unsigned/ad-hoc 进程 fail closed。

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
- wrapper 在设置 payload 缺失或损坏时回退 `.default` → wrapper 凭空制造第二份“当前设置”,展示的解锁方式可能与 Agent 实际执行不一致。
- 引入"会话"抽象、暗示客户端拥有锁 → 造成"某个面无法解开另一个面锁上的锁"这种迷惑行为。
- 锁/设置逻辑在 App 与 CLI 之间重复 → 正是 DRY 规则要禁止的维护爆炸。
- wrapper 为了"直接调引擎"而 import `Service` → 绕过了单核。
- 一次性面(CLI/AppleScript/Shortcuts)订阅广播,或在多次调用之间缓存锁状态 → 徒增复杂度并制造新的漂移源;它运行时直接调 `status()` 即可。
- 把通知载荷当作状态、而不去拉取 `status()` → 过期/乱序/丢失的通知会悄悄让 UI 失去同步。
