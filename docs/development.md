# 开发指南

任务相关的工作流与组件参考。关于不可协商的设计规则,先读 [architecture.md](architecture.md) —— 它始终优先于本文档的任何内容。

## XPC 通信流程

本节是开发时的速查。若需要理解 `Core` 为什么被两侧引用、library 与进程的区别、Agent 注册、完整调用时序、connection 生命周期和失败语义,先读 [XPC 实现与使用指南](xpc.md)。

所有面都通过 `KeyboardLockerServiceProtocol` 与 Agent 通信(Mach 服务 `io.lzhlovesjyq.keyboardlocker.agent`)。

1. App 建立 connection 后先调用 `XPCClient.serviceDescriptor()`,验证 protocol version、required capabilities 和 bundled Agent build;只有兼容后才调用新增 selector。descriptor 在 fresh connection 上重试后仍失败、但旧 `status` 成功时，只能按 unverified base contract 处理，不能断言它一定是 legacy Agent。capability-gated Client API 会在同一条具体 connection generation 上重新握手并发送 feature selector，connection 变化后不能复用旧 grant。
2. wrapper(App/CLI/……)通过异步的 `XPCClient` 发出一次**无状态一次性调用**:`lock` / `unlock` / `status` / `lockStatusSnapshot` / `currentSettings`。App 还经同一边界查询 Agent 的 Accessibility 状态,并可由明确用户动作请求 Agent 触发权限 prompt。失败会抛错(Agent 挂掉时表现为抛出的错误,绝不挂起)。
3. Client 与 Listener 都在 activate 前安装同 Team + 精确 signing identifier 的 XPC requirement；系统完成双向认证后，Agent 的 `ServiceDelegate` 才接受连接并路由到 `AgentService`。
4. `AgentService` 拥有设置真相源(`KeyboardLockerSettingsStore`,位于 `Service`),并驱动 `LockEngine.shared.lock(settings:allowsControlCUnlock:)` / `unlock()`。
5. `LockEngine` 创建 CGEventTap,并在任何状态变化时调用 `LockStateBroadcaster.broadcast()`。
6. wrapper 通过 `LockStateSubscriber.subscribe(initialState:_:)`(返回 `ObserverToken`)或 `LockStateSubscriber.stateChanges`(`AsyncStream<Bool>`)观察状态。subscriber 会在 observer 安装完成后立即拉取一次权威初始状态,后续信号串行合并并再次查询 —— 绝不从"我这次调用是否成功"或通知 payload 推断。

> 锁是一个由 Agent 拥有的全局布尔值,且 `lock()` 是**严格幂等**的：已锁时重复调用会直接成功,不修改当前设置、锁定起点或 auto-unlock deadline。只有显式 settings update 才会重新应用设置并从该次更新重新开始 timeout window。不存在客户端拥有的"会话";每次调用都是一次性的。Agent 必须经 `SMAppService` 注册,`launchd` 才能按需拉起它 —— App 在启动时通过 `AgentRegistrar` 完成这件事(见下文)。

## 组件地图

只列出不那么显而易见的职责;签名请读源码。

**Common**(`Core/Sources/Common/`)—— 所有 target 共享
- `Shared.swift`:`KeyboardLockerServiceProtocol`(bootstrap descriptor、legacy/interactive 锁操作、lock status snapshot、replacement drain、Accessibility 状态 / 请求、settings snapshot)、`LockRequestOutcome`、`SharedConstants`(Mach 名、Agent ID、client allowlist)、`NotificationNames.stateChanged`。protocol 1.1 的 `currentSettings` 只为旧 Client 保留；当前 Client 经 additive `currentSettingsWithError` 读取并接收显式编码错误。protocol 1.3 新增 capability-gated interactive lock selector；protocol 1.4 新增 capability-gated `lockStatusSnapshot`,旧 `status` / `lockKeyboard` ABI 保持不变。
- `LockStatusSnapshot.swift`:`LockStatusSnapshot` format 1 和有大小上限的 JSON XPC 编解码。snapshot 原子携带 capture time、布尔状态、锁定起点、auto-unlock deadline 与 active settings；duration/countdown 由 consumer 根据权威时间点派生,不作为会迅速过期的 transport 字段。
- `ServiceDescriptor.swift`:`ServiceDescriptor`、protocol version、稳定字符串 capability、additive replacement phase、opaque `ServiceReplacementTicket` 与 ticket-specific status;以有大小上限的 JSON `Data` 跨 XPC。descriptor 显式 decode 永久 bootstrap 字段,为 additive 字段提供默认值,未知字段/capability 可由旧 Client 忽略。
- `XPCCodeSigningRequirement.swift`:从当前进程已验证的 Apple 签名读取 Team ID,生成并预编译同 Team + 精确 identifier 的双向 XPC requirement；unsigned/ad-hoc 进程 fail closed。
- `KeyboardLockerSettings.swift`:`KeyboardLockerSettings`(`autoUnlockPolicy` = `.disabled`/`.timed(seconds:)`、`unlockHotkey`)+ `.default` + throwing `encodedForXPC()`/`decodedFromXPC(_:)`(跨 `@objc` 边界、有大小上限的 JSON 传输)。缺失、损坏或过大的 Agent payload 会显式失败，wrapper 不会伪造 `.default` 快照。
- `KeyCodeConverter.swift`:通过 `UCKeyTranslate` 做布局感知的 `CGKeyCode` → 快捷键字符串(⌃⌥⇧⌘ 顺序)。

**Client**(`Core/Sources/Client/`)—— App/CLI 使用,绝不 import `Service`
- `XPCClient.swift`:异步 / 可抛错的 `XPCClient.shared`,持有一条按需重建的连接;interruption 会主动 invalidate 当前 object，阻止它透明附着到另一代 Agent 后复用旧 capability grant。所有调用共享有界响应超时,超时只失效对应连接。legacy `lock` / `unlock` 超时后重新查询权威状态,无法确认时明确报告 outcome unknown；`lockInteractively()` 与 `lockStatusSnapshot()` 都在同一 connection 上完成 descriptor/capability gate 后调用对应 selector。replacement wire request 与 ticket 双重绑定 `agentInstanceID`,并提供 prepare/commit/status/cancel 与显式 connection reset。没有业务 "session" 类型。
- `ServiceCompatibility.swift`:纯值兼容性规则与任意精度 dotted-numeric `ServiceBuildVersion` —— major 必须相等、running minor 不得低于最低版本、required capabilities 必须齐全,且运行中 Agent 的 identifier/version/build 必须与 bundled Agent 一致。
- `LockStateSubscriber.swift`:先安装 Darwin + Distributed observer,再立即拉取一次权威状态;后续把每个信号当作提示,通过 `XPCClient.status()` 串行校准(带重试、signal coalescing、去重和 cancellation fence)→ `ObserverToken`,另有会先产出当前权威状态的 `stateChanges`(`AsyncStream<Bool>`)。取消会丢弃尚未进入 handler 的结果,但不会回溯撤销已经开始执行的 handler。长命 UI 使用 snapshot seed 避免重复呈现相同状态;一次性面直接读 `status()`(见 architecture 的"状态同步")。
- `UnlockStatusPoller.swift`:`XPCClient.waitUntilUnlocked()` 的可测试等待组合。notification stream 提供及时更新,内部 poller 周期性查询权威状态以恢复丢通知和 Agent 重启；transport failure 后 reset connection,连续三次失败则抛错,不把不可达猜成 unlocked。任一路径确认解锁后都会取消另一条路径,取消 polling 时主动失效本轮 connection,避免等待完整 XPC response timeout。

**Service**(`Core/Sources/Service/`)—— 仅 Agent 使用
- `LockEngine.swift`:`@MainActor` 隔离的 CGEventTap 单例、严格幂等且返回 atomic outcome 的 `lock(settings:allowsControlCUnlock:)`、显式 `updateSettings(_:)`、同一 runtime turn 生成的 `statusSnapshot`、自动解锁定时器、热键检测、事务式 tap/source 安装与 `os.Logger`。重复 `lock` 不会修改活动设置、临时 `Ctrl+C` 手势或 deadline；资源未全部可用前不提交 locked 状态；运行中 tap 无法重新启用时 fail open 到 unlocked 并广播权威状态。
- `KeyboardLockerSettingsStore.swift`:基于 `UserDefaults` 的设置持久化 —— 放在 `Service` 内,以确保没有 wrapper 能拥有自己的 store(契约的真相源规则)。
- `LockStateBroadcaster.swift`:发出 Darwin + Distributed 通知(均无载荷,只是"状态已变"的信号;订阅方收到后回拉 `status()`)。
- `ReplacementTransaction.swift`:纯 `idle → prepared → committed` 状态机；prepared 可 cancel/expire，committed 不可 cancel/expire，只能由 Agent 进程退出终止。它不触碰 TCC 或 Service Management，可由 `ServiceTests` 确定性覆盖。
- `AccessibilityManager.swift`(Agent 身份下的实时权限查询与 prompt 请求)、`XPCAccessControl.swift`(生成 Listener 的受信 Client requirement)、`XPCServerConnection.swift`。

**App**(`KeyboardLocker/`)—— 长命的 menu-bar 薄 wrapper，并承载一次性系统 action；两者都只调用 Client
- `AgentRegistrar.swift`:通过 `SMAppService.agent(plistName:)` 确保注册,读取 bundled Agent metadata 并比较运行中 descriptor;replacement 会等待旧 Agent 退出后重新注册 bundled 版本。
- `KeyboardLockerApplication.swift` / `StatusMenuController.swift`:进程级 AppKit 生命周期与 status-menu presentation。它们只渲染 `AppCoordinator.Snapshot` 并把用户动作转发给 coordinator,不直接读取或持有锁/设置状态。
- `AppIntents/KeyboardLockAppIntents.swift`:可在 Shortcuts 中组合的 `Lock Keyboard`、`Unlock Keyboard` 与返回 `Bool` 的 `Get Keyboard Lock Status` action。它们是 one-shot wrapper，每次执行只经 `AgentLockActionServing` 调用 Agent，不缓存状态、不订阅通知，也不注册 macOS 不支持的 promoted App Shortcuts。
- `AgentCoordinationServices.swift`:App 内部的可注入依赖边界。live adapter 把 `XPCClient`、`LockStateSubscriber` 与 `AgentRegistrar` 暴露为按用途拆分的最小 protocol；`AgentLockActionServing` 只提供 one-shot wrapper 所需的 `lock` / `unlock` / `status`,协调器和系统 action 都无需依赖无关 Client surface。
- `AgentReadinessCoordinator.swift`:一次性收集 registration、descriptor handshake/重连、兼容性、replacement phase、Accessibility 与权威锁状态,返回不含 UI 的 domain outcome。
- `AgentReplacementCoordinator.swift`:执行 App 侧 Agent 替换顺序。`AgentUpdatePlan` 用类型区分已协商的 safe replacement 与需要用户授权的 forced fallback,所有自动/手动更新共用 prepare → commit → restart → reconnect 边界。
- `AppCoordinator.swift`:不依赖 presentation framework 的 `@MainActor` 应用协调器 —— 持有异步任务/订阅生命周期、单次自动更新策略和 replacement progress polling,把 domain outcome 收敛为可观察的应用 snapshot；不直接实现 handshake、replacement transaction、锁或设置逻辑。

## 常见任务

### 新增一个设置项
1. 给 `KeyboardLockerSettings` 加一个 `Codable`/`Sendable` 属性,并更新 `.default`。
2. 如果引擎会消费它,在 `LockEngine.lock(settings:allowsControlCUnlock:)` / `updateSettings(_:)` 中读取。
3. 目前 wrapper 只能通过 `XPCClient.currentSettings()` **读取**设置(由 Agent 经 `KeyboardLockerSettingsStore` 加载)。写入路径(`applySettings` + UI)尚未接线;要让用户改设置,先在 Agent + `KeyboardLockerServiceProtocol` 上补写入方法(见"新增一个 XPC 方法"),再由 Agent 持久化 —— wrapper **不得**拥有 store(见架构契约)。

### 新增一个 XPC 方法
1. 先判断它是否 optional/additive。不得在同一 protocol major 内修改或移除既有 selector、参数顺序或 reply 形状;破坏性变化需要新 major,无法保留 selector union 时需要新 Mach service。
2. 在 `Common/Shared.swift` 的 `KeyboardLockerServiceProtocol` 里加签名,同时在 `ServiceCapability` 增加一个从不复用的稳定名字,并按兼容需求更新 protocol minor / required capability。无法用 `@objc` 表达的值(如 `KeyboardLockerSettings`)以有大小上限的 JSON `Data` 跨界。
3. 在 `KeyboardLockerAgent/AgentService.swift` 中实现它并在 descriptor 中声明 capability。
4. 在 `Client/` 的 `XPCClient` 上加一个薄的异步封装;调用前必须完成 descriptor handshake 并检查 capability。
5. 在 `Core/Tests/ClientTests/` 补充 old/future descriptor fixture、round-trip、build ordering 与兼容性测试；Server 状态机在 `Core/Tests/ServiceTests/` 覆盖 exclusivity、stale ticket/timer、cancel、expiry 与 committed fail-closed 语义。

### 修改事件过滤
在 `LockEngine.handleEvent(type:event:)` 中:返回 `nil` 拦截、返回 `Unmanaged.passUnretained(event)` 放行,并在满足解锁条件(热键或超时)时调用 `unlock()`。`Hotkey.matches(keyCode:flags:)` 会通过 `relevantModifierMask` 过滤掉 CapsLock/NumLock。

## 测试须知

### 在 Terminal 中使用开发版 `klock`

开发阶段可用脚本安装、检查或移除指向 Debug App 内已签名 `klock` 的 symbolic link：

```bash
./scripts/install-klock-dev.sh install
./scripts/install-klock-dev.sh status
./scripts/install-klock-dev.sh uninstall
```

默认目标是 `~/.local/bin/klock`，也可通过 `--bin-dir PATH` 或 `KLOCK_BIN_DIR` 指定其他用户可写目录。脚本会先验证 bundled executable 的 code signature、精确 signing identifier，以及 App、Agent、CLI 三者的 Team identifier 一致性；遇到已有文件或其他 link 时会拒绝覆盖。它不会复制 binary、修改 shell profile 或调用 `sudo`。若目标目录不在 `PATH`，脚本只打印需要添加的 `export PATH=...`，由用户决定写入哪个 shell 配置。

已构建的 App 也在 status menu 中提供 **Command Line Tool…**。该入口遵循同一所有权边界：只创建或移除指向当前 App bundle 的 link；需要配置 `PATH` 时仅提供可复制命令，不会静默修改 dotfile。

`klock` 自身不注册后台 Agent。首次使用前必须至少启动一次 KeyboardLocker App；Agent 未注册时，CLI 会给出对应恢复提示。

`klock lock` 只有在本次请求原子创建全局锁时才进入等待，并提示 `Ctrl+C`。这个按键由 Agent event tap 识别后直接解锁，不依赖 Terminal 先收到被锁定输入并生成 `SIGINT`。若 Agent 已被 App 或其他 CLI 锁定，命令会报告 `Already locked. This command did not create a new lock.` 后成功退出，不改变既有锁。

### Homebrew Cask 发布计划（尚未实现）

正式分发计划采用 Homebrew Cask，而不是把 `klock` 作为独立 Formula 重新编译。Cask 应安装同一个经过 Developer ID 签名和 notarization 的 `KeyboardLocker.app`，并用 `binary` artifact 暴露 App bundle 内的 `Contents/MacOS/klock`；这样 App、CLI 与 Agent 保持同一版本和签名来源。

开始实现前需要先具备 versioned release artifact、稳定下载地址、SHA-256、Developer ID 签名及 notarization 验证。首个交付目标为项目自己的 tap，发布流程稳定且满足上游接收要求后，再评估提交到官方 Homebrew Cask 仓库。当前仓库尚未新增 Cask definition 或 release automation。

### 重置本地 Agent 注册

需要复现首次启动或清理调试注册状态时，运行：

```bash
./scripts/reset-keyboardlocker.sh
```

脚本会构建 Debug App、退出正在运行的 KeyboardLocker、请求 Agent 解锁，然后由 App 自身通过 `SMAppService.unregister()` 移除自己的 LaunchAgent 注册，并确认对应的 `launchd` service 与 Agent 进程都已消失。下次启动 App 时会按首次启动路径重新注册 Agent。

该操作是应用范围的开发重置：不会调用影响其他应用的 `sfltool resetbtm`，也不会重置 Accessibility/TCC 权限或删除 Agent 持有的用户设置。

- 缺少 Accessibility 权限时,`LockEngine.lock` 抛出 `.accessibilityPermissionDenied`(在创建 event tap 之前检查)。
- `requestAccessibilityPermission()` 只表示 Agent 已请求系统显示异步 prompt;用户操作完成后必须重新调用 `hasAccessibilityPermission()`。
- XPC 调用要成功,Agent 必须正在运行 / 已注册(`SMAppService`),且 App、CLI 与 Agent 都必须使用同一 Apple Team 的项目签名。Debug 与 Release 都执行双向 XPC code-signing requirement；unsigned/ad-hoc 可执行文件即使复制 signing identifier 也会被拒绝。
- `klock` target 必须保留 generated embedded Info.plist section；这是让实际 code-signing identifier 等于 `io.lzhlovesjyq.keyboardlocker.klock` 的载体。只设置 `PRODUCT_BUNDLE_IDENTIFIER` 而不嵌入 Info.plist 时，`codesign` 会退回裸名称 `klock`，Agent 会拒绝它。
- `AgentService` 是 nonisolated XPC adapter；它把所有 Agent 可变状态与引擎操作切到 `MainActor`,以便在同一隔离域维护 CFRunLoop、timer、settings 和 replacement transaction。
- 系统可能禁用 event tap(超时 / 用户输入);`LockEngine` 会尝试重新启用。若重新启用仍失败，会清理 tap/timer、切换为 unlocked 并广播，绝不继续报告虚假的 locked 状态。
- App 协调器通过 protocol injection 与 presentation layer 解耦。`KeyboardLockerModelTests` 是 non-hosted test target,通过 fake Client/lifecycle/state observer 覆盖确定性协调流程,不触碰 live `SMAppService`/XPC。
