# 开发指南

任务相关的工作流与组件参考。关于不可协商的设计规则,先读 [architecture.md](architecture.md) —— 它始终优先于本文档的任何内容。

## XPC 通信流程

所有面都通过 `KeyboardLockerServiceProtocol` 与 Agent 通信(Mach 服务 `io.lzhlovesjyq.keyboardlocker.agent`)。

1. wrapper(App/CLI/……)通过异步的 `XPCClient` 发出一次**无状态一次性调用**:`lock` / `unlock` / `status` / `currentSettings`。失败会抛错(Agent 挂掉时表现为抛出的错误,绝不挂起)。
2. Agent 的 `ServiceDelegate` 接受连接(在 `XPCAccessControl` 校验代码签名 + bundle ID 之后),并路由到 `AgentService`。
3. `AgentService` 拥有设置真相源(`KeyboardLockerSettingsStore`,位于 `Service`),并驱动 `LockEngine.shared.lock(settings:)` / `unlock()`。
4. `LockEngine` 创建 CGEventTap,并在任何状态变化时调用 `LockStateBroadcaster.broadcast()`。
5. wrapper 通过 `LockStateSubscriber.subscribe(_:)`(返回 `ObserverToken`)或 `LockStateSubscriber.stateChanges`(`AsyncStream<Bool>`)观察状态 —— 绝不从"我这次调用是否成功"推断。

> 锁是一个由 Agent 拥有的全局布尔值,且 `lock()` 是**幂等**的(已锁时再锁会重新应用设置并返回成功)。不存在客户端拥有的"会话";每次调用都是一次性的。Agent 必须经 `SMAppService` 注册,`launchd` 才能按需拉起它 —— App 在启动时通过 `AgentRegistrar` 完成这件事(见下文)。

## 组件地图

只列出不那么显而易见的职责;签名请读源码。

**Common**(`Core/Sources/Common/`)—— 所有 target 共享
- `Shared.swift`:`KeyboardLockerServiceProtocol`(锁操作 + `currentSettings`)、`SharedConstants`(Mach 名、bundle-ID 白名单、CLI 常量)、`NotificationNames.stateChanged`。
- `KeyboardLockerSettings.swift`:`KeyboardLockerSettings`(`autoUnlockPolicy` = `.disabled`/`.timed(seconds:)`、`unlockHotkey`、`showsUnlockNotification`)+ `.default` + `encodedForXPC()`/`decodedFromXPC(_:)`(跨 `@objc` 边界的 JSON 传输)。
- `KeyCodeConverter.swift`:通过 `UCKeyTranslate` 做布局感知的 `CGKeyCode` → 快捷键字符串(⌃⌥⇧⌘ 顺序)。

**Client**(`Core/Sources/Client/`)—— App/CLI 使用,绝不 import `Service`
- `XPCClient.swift`:异步 / 可抛错的 `XPCClient.shared`,持有一条自动重连的连接;`lock`/`unlock`/`status`/`currentSettings`。没有 "session" 类型。
- `LockStateSubscriber.swift`:订阅 Darwin + Distributed 广播,把每个信号当作提示,并通过 `XPCClient.status()` 拉取权威状态(带重试、去重)→ `ObserverToken`,另有 `stateChanges`(`AsyncStream<Bool>`)。只有长命 UI 需要它;一次性面直接读 `status()`(见 architecture 的"状态同步")。

**Service**(`Core/Sources/Service/`)—— 仅 Agent 使用
- `LockEngine.swift`:CGEventTap 单例、幂等的 `lock(settings:)`、`updateSettings(_:)`、自动解锁定时器、热键检测、`OSAllocatedUnfairLock` 状态、`os.Logger`。
- `KeyboardLockerSettingsStore.swift`:基于 `UserDefaults` 的设置持久化 —— 放在 `Service` 内,以确保没有 wrapper 能拥有自己的 store(契约的真相源规则)。
- `LockStateBroadcaster.swift`:发出 Darwin + Distributed 通知(均无载荷,只是"状态已变"的信号;订阅方收到后回拉 `status()`)。
- `AccessibilityManager.swift`、`XPCAccessControl.swift`(release = 签名 + Team ID + 白名单;debug = 仅白名单)、`XPCServerConnection.swift`。

**App**(`KeyboardLocker/`)—— 薄 SwiftUI wrapper
- `AgentRegistrar.swift`:启动时做 `SMAppService.agent(plistName:)` 注册(幂等)。
- `LockController.swift`:`@MainActor ObservableObject` 视图状态 —— 发出异步 `XPCClient` 调用、反映广播状态,不含任何锁/设置逻辑。

## 常见任务

### 新增一个设置项
1. 给 `KeyboardLockerSettings` 加一个 `Codable`/`Sendable` 属性,并更新 `.default`。
2. 如果引擎会消费它,在 `LockEngine.lock(settings:)` / `updateSettings(_:)` 中读取。
3. 目前 wrapper 只能通过 `XPCClient.currentSettings()` **读取**设置(由 Agent 经 `KeyboardLockerSettingsStore` 加载)。写入路径(`applySettings` + UI)尚未接线;要让用户改设置,先在 Agent + `KeyboardLockerServiceProtocol` 上补写入方法(见"新增一个 XPC 方法"),再由 Agent 持久化 —— wrapper **不得**拥有 store(见架构契约)。

### 新增一个 XPC 方法
1. 在 `Common/Shared.swift` 的 `KeyboardLockerServiceProtocol` 里加签名。无法用 `@objc` 表达的值(如 `KeyboardLockerSettings`)以 JSON `Data` 跨界 —— 复用 `encodedForXPC()`/`decodedFromXPC(_:)`。
2. 在 `KeyboardLockerAgent/AgentService.swift` 中实现它。
3. 如果某个面需要,在 `Client/` 的 `XPCClient` 上加一个薄的异步封装。

### 修改事件过滤
在 `LockEngine.handleEvent(proxy:type:event:)` 中:返回 `nil` 拦截、返回 `Unmanaged.passUnretained(event)` 放行,并在满足解锁条件(热键或超时)时调用 `unlock()`。`Hotkey.matches(keyCode:flags:)` 会通过 `relevantModifierMask` 过滤掉 CapsLock/NumLock。

### CLI 安装
`CLIInstaller` 把 `/usr/local/bin/klock` 软链到 app bundle 内的 CLI 二进制(保证版本一致),并通过 AppleScript 请求管理员权限。`install()`/`uninstall()` 返回 `InstallResult`(`.success` / `.alreadyInstalled` / `.cancelled` / `.failed(Error)`);用 `isInstalled` / `isCurrentVersionInstalled` 判断状态。

## 测试须知

- 缺少 Accessibility 权限时,`LockEngine.lock` 抛出 `.accessibilityPermissionDenied`(在创建 event tap 之前检查)。
- XPC 调用要成功,Agent 必须正在运行 / 已注册(`SMAppService`)。
- 引擎操作会派发到主线程,以便访问 CFRunLoop。
- 系统可能禁用 event tap(超时 / 用户输入);`LockEngine` 会尝试重新启用。
