# 开发指南

任务相关的工作流与组件参考。关于不可协商的设计规则,先读 [architecture.md](architecture.md) —— 它始终优先于本文档的任何内容。

## XPC 通信流程

本节是开发时的速查。若需要理解 `Core` 为什么被两侧引用、library 与进程的区别、Agent 注册、完整调用时序、connection 生命周期和失败语义,先读 [XPC 实现与使用指南](xpc.md)。

所有面都通过 `KeyboardLockerServiceProtocol` 与 Agent 通信(Mach 服务 `io.lzhlovesjyq.keyboardlocker.agent`)。

1. App 建立 connection 后先调用 `XPCClient.serviceDescriptor()`,验证 protocol version、required capabilities 和 bundled Agent build;只有兼容后才调用新增 selector。descriptor 在 fresh connection 上重试后仍失败、但旧 `status` 成功时，只能按 unverified base contract 处理，不能断言它一定是 legacy Agent。capability-gated Client API 会在同一条具体 connection generation 上重新握手，先验证 major 相同及该 selector 的引入 minor，再检查 capability 并发送 selector；connection 变化后不能复用旧 grant。
2. wrapper(App/CLI/……)通过异步的 `XPCClient` 发出一次**无状态一次性调用**:`lock` / `unlock` / `status` / `lockStatusSnapshot` / `currentSettings`。App 的首次安全测试使用独立的 `beginSafetyCheck`,由 Agent 强制该轮锁在 10 秒后自动解锁。App 还经同一边界查询 Agent 的 Accessibility 状态,并可由明确用户动作请求 Agent 触发权限 prompt。失败会抛错(Agent 挂掉时表现为抛出的错误,绝不挂起)。
3. Client 与 Listener 都在 activate 前安装同 Team + 精确 signing identifier 的 XPC requirement；系统完成双向认证后，Agent 的 `ServiceDelegate` 才接受连接并路由到 `AgentService`。
4. Agent bootstrap 创建一个贯穿进程生命周期的 `AgentService`，它拥有设置真相源(`KeyboardLockerSettingsStore`,位于 `Service`)和唯一的 `LockEngine` 实例，并驱动 `lock(settings:allowsControlCUnlock:)` / `unlock()`；所有 listener connection 都接收同一个 service object。
5. `LockEngine` 创建 CGEventTap,并在任何状态变化时调用 `LockStateBroadcaster.broadcast()`。
6. wrapper 通过 `LockStateSubscriber.subscribe(initialState:_:)`(返回 `ObserverToken`)或 `LockStateSubscriber.stateChanges`(`AsyncStream<Bool>`)观察状态。subscriber 会在 observer 安装完成后立即拉取一次权威初始状态,后续信号串行合并并再次查询 —— 绝不从"我这次调用是否成功"或通知 payload 推断。

> 锁是一个由 Agent 拥有的全局布尔值,且 `lock()` 对物理运行状态是**严格幂等**的：已锁时重复调用不会重建 event tap、修改当前设置、锁定起点或 auto-unlock deadline。唯一的 metadata 变化是普通 wrapper 的显式 `lock` 会接管 Focus 创建的当前 generation,使之后的 Focus disable 不再撤销这个更新的用户意图。Focus 本身是 activation-triggered：一次 activation 最多创建一个 Focus-owned generation,不承诺在 Focus active 期间持续 relock；显式 unlock、热键、timeout、event-tap failure 或 Agent restart 都可以让它提前结束。只有 `LockEngine` 的显式 settings update 才会重新应用设置并从该次更新重新开始 timeout window;`applySettings` 只在 unlocked 时发起该 update,locked 时新值仅落盘等下次 lock。不存在客户端持有的通用"会话";每次调用都是一次性的。Agent 必须经 `SMAppService` 注册,`launchd` 才能按需拉起它 —— App 在启动时通过 `AgentRegistrar` 完成这件事(见下文)。

## 组件地图

只列出不那么显而易见的职责;签名请读源码。

**Common**(`Core/Sources/Common/`)—— 所有 target 共享
- `Shared.swift`:`KeyboardLockerServiceProtocol`(bootstrap descriptor、legacy/interactive/Focus/safety-check 锁操作、lock status snapshot、replacement drain、Accessibility 状态 / 请求、settings 读取与写入)、`LockRequestOutcome`、`SharedConstants`(Mach 名、Agent ID、client allowlist)、`NotificationNames`(`stateChanged` 状态信号;`blockedInput` 被吞按键的 presentation hint,详情见 architecture 的"状态同步")。protocol 1.1 的 `currentSettings` 只为旧 Client 保留；当前 Client 经 additive `currentSettingsWithError` 读取并接收显式编码错误。protocol 1.3 新增 capability-gated interactive lock selector；protocol 1.4 新增 capability-gated `lockStatusSnapshot`；protocol 1.5 新增 capability-gated `setFocusFilterLockEnabled`,旧 `status` / `lockKeyboard` ABI 保持不变。protocol 1.6 新增 capability-gated `toggleKeyboard`,把原子翻转放进 Agent 串行边界并返回翻转后状态；protocol 1.7 新增 capability-gated `beginSafetyCheck`,由 Agent 为该轮锁强制安装固定 10 秒 auto-unlock fail-safe。protocol 1.8 新增 capability-gated `applySettings`:Agent 校验并持久化设置后返回落盘后的权威值,locked 时只落盘不改动当前锁。protocol 1.9 新增 capability-gated `beginTimedLock`:单次锁覆写 auto-unlock 时长(沿用持久化设置其余项,`validated()` 护栏强制有限/取整/落入 5–3600 秒,不回写 store,已锁时原子返回 alreadyLocked 且 override 不作用于既有锁)。protocol 1.10 新增 capability-gated `lockHistory`:只读返回 Agent 有界锁定历史(格式见 `LockHistory.swift`)。`KeyboardLockerSettings.validated()` 在此文件所在的 `Common` 层定义写入护栏,由 Agent 强制,供所有写入面共用。
- `LockHistory.swift`:`LockHistoryEntry`(起点 / 终点 / 解锁原因,`UnlockRecord.Reason` 同样前向兼容)与 `LockHistory` format 1(含 `retentionLimit` = 200,Agent 的 trim 策略与 wrapper 文案共用此常量),有大小上限的 JSON XPC 编解码,未知 format version 显式拒绝。历史是 presentation/diagnostics-only,不参与任何判定。
- `LockStatusSnapshot.swift`:`LockStatusSnapshot` format 1 和有大小上限的 JSON XPC 编解码。snapshot 原子携带 capture time、布尔状态、锁定起点、auto-unlock deadline、active settings 与上次解锁记录(`UnlockRecord` = 原因 + 权威时刻,additive 可选字段,旧 payload 缺 key 解码为 nil)；duration/countdown 由 consumer 根据权威时间点派生,不作为会迅速过期的 transport 字段。
- `ServiceDescriptor.swift`:`ServiceDescriptor`、protocol version、稳定字符串 capability、additive replacement phase、opaque `ServiceReplacementTicket` 与 ticket-specific status;以有大小上限的 JSON `Data` 跨 XPC。descriptor 显式 decode 永久 bootstrap 字段,为 additive 字段提供默认值,未知字段/capability 可由旧 Client 忽略。
- `XPCCodeSigningRequirement.swift`:从当前进程已验证的 Apple 签名读取 Team ID,生成同 Team + 精确 identifier 的双向 XPC requirement 字符串,并用 `SecRequirementCreateWithString` 校验其可编译(编译结果仅作一次性校验后丢弃;安装到连接时由系统重新解析字符串);unsigned/ad-hoc 进程 fail closed。
- `KeyboardLockerSettings.swift`:`KeyboardLockerSettings`(`autoUnlockPolicy` = `.disabled`/`.timed(seconds:)`、`unlockHotkey`、`unlockPhrase` 可选键入短语、`soundEffectsEnabled` 与 `blockedInputFeedbackEnabled` 两个 Feedback 开关、`lockHotkey` 可选全局锁定热键;后四者均为 additive Codable 字段,旧 payload 缺 key 时分别解码为 nil 与启用)+ `.default` + throwing `encodedForXPC()`/`decodedFromXPC(_:)`(跨 `@objc` 边界、有大小上限的 JSON 传输)。缺失、损坏或过大的 Agent payload 会显式失败，wrapper 不会伪造 `.default` 快照。`validated()` 是写入护栏的单一真相源:热键必须含至少一个可被 matcher 保留的修饰键(与 `Hotkey.matches` 共用 `relevantModifierMask`)、keyCode 必须能被 ASCII-capable layout 映射(经 `KeyCodeConverter`)、`.timed` 秒数取整后须落在 `allowedAutoUnlockRange`(5...3600)且有限、`unlockPhrase` 经 `normalizedUnlockPhrase` 小写规范化且长度 3–64、仅 ASCII 字母/数字/空格并至少含一个非空格(字符集 `isAllowedInUnlockPhrase` 与引擎 matcher 共用)、`lockHotkey` 非 nil 时走同一 `Hotkey.validated()` 规则;`.disabled` 允许通过。`Hotkey.validated()` 单独暴露,供热键录制器逐次反馈,不复制规则。
- `KeyCodeConverter.swift`:通过 `UCKeyTranslate` 做布局感知的 `CGKeyCode` → 快捷键字符串(⌃⌥⇧⌘ 顺序)与 shift 感知的按键 → 键入字符映射(`typedCharacter(for:shiftDown:)`,供引擎短语匹配器使用;只接受单字符结果,dead-key 残余与控制序列返回 nil)。读取 **ASCII-capable keyboard layout**(`TISCopyCurrentASCIICapableKeyboardLayoutInputSource`)而非当前 input source——拼音等输入法不带 Unicode layout data,会把热键渲染成 `?`。TIS/TSM 查询统一串行到 main thread,避免并发测试或多个 wrapper 同时生成显示文本时触发 HIToolbox abort。

**Client**(`Core/Sources/Client/`)—— App/CLI 使用,绝不 import `Service`
- `XPCClient.swift`:异步 / 可抛错的 `XPCClient.shared`,持有一条按需重建的连接;interruption 会主动 invalidate 当前 object，阻止它透明附着到另一代 Agent 后复用旧 capability grant。所有调用共享有界响应超时,超时只失效对应连接。`unlock` 超时后可用权威 Boolean 状态校准；普通 `lock` 与 Focus selector 的成功还包含本地状态看不到的 provenance,因此首次 timeout 后会在 fresh connection 上重发同一个幂等请求,第二次仍超时则明确报告 outcome unknown。每个 capability-gated API 都在同一 connection 上读取 descriptor，先拒绝不同 major 或低于 selector 引入版本的 minor，再检查 capability 后调用 selector（含只读的 `lockHistory`,protocol 1.10）。replacement wire request 与 ticket 双重绑定 `agentInstanceID`,并提供 prepare/commit/status/cancel 与显式 connection reset。`applySettings(_:)` capability-gated;发送前先 `encodedForXPC`,reply 携带 Agent 落盘后的权威 settings(而非请求值,因 Agent 会规范化),reply 丢失后重查 `currentSettings()` 与 `validated()` 后的期望值比对而非重发。没有业务 "session" 类型。
- `ServiceCompatibility.swift`:纯值兼容性规则与任意精度 dotted-numeric `ServiceBuildVersion` —— major 必须相等、running minor 不得低于最低版本、required capabilities 必须齐全,且运行中 Agent 的 identifier/version/build 必须与 bundled Agent 一致。
- `LockStateSubscriber.swift`:先安装 Darwin + Distributed observer,再立即拉取一次权威状态;后续把每个信号当作提示,通过 `XPCClient.status()` 串行校准(带重试、signal coalescing、去重和 cancellation fence)→ `ObserverToken`,另有会先产出当前权威状态的 `stateChanges`(`AsyncStream<Bool>`)。取消会丢弃尚未进入 handler 的结果,但不会回溯撤销已经开始执行的 handler。长命 UI 使用 snapshot seed 避免重复呈现相同状态;一次性面直接读 `status()`(见 architecture 的"状态同步")。
- `UnlockStatusPoller.swift`:`XPCClient.waitUntilUnlocked()` 的可测试等待组合。notification stream 提供及时更新,内部 poller 周期性查询权威状态以恢复丢通知和 Agent 重启；transport failure 后 reset connection,连续三次失败则抛错,不把不可达猜成 unlocked。任一路径确认解锁后都会取消另一条路径,取消 polling 时主动失效本轮 connection,避免等待完整 XPC response timeout。

**Service**(`Core/Sources/Service/`)—— 仅 Agent 使用
- `LockEngine.swift`:`@MainActor` 隔离、由进程生命周期 `AgentService` 实例独占的 CGEventTap 引擎；提供物理状态幂等且返回 atomic outcome 的 `lock(settings:allowsControlCUnlock:)`、Focus-owned generation、显式 `updateSettings(_:)`、同一 runtime turn 生成的 `statusSnapshot`、自动解锁定时器(单调时钟在休眠期间暂停,系统唤醒时按墙钟 deadline 校准:过期即解锁,否则按剩余时长重排,不改写已发布的 deadline)、热键与键入短语检测(`UnlockPhraseMatcher` 滚动后缀匹配,按锁代际重建:退格编辑、修饰键组合与非字符键重置缓冲、忽略 autorepeat,缓冲永不落盘/进 snapshot/写日志)、被吞按键的 blocked-input 上报(仅 keyDown 与 keyboard system control,非解锁手势才报;keyUp/flagsChanged 不参与,避免解锁热键释放动作误报;active settings 的 `blockedInputFeedbackEnabled` 门控,按锁代际节流——每代首次即报、之后每 4 秒至多一条,新一代重新武装)、随每次解锁记录原因与权威时刻的 `UnlockRecord`(经 snapshot 发布)、每代锁结束/状态清除前经 lock-history hook 上报 `LockHistoryEntry`(由 `LockHistoryRecorder` 消费)、事务式 tap/source 安装与 `os.Logger`。event policy 消费标准按键及 system-defined keyboard control,同时明确放行鼠标 / 触控板 pointer event。Focus activation 最多创建并标记一个 generation；普通 duplicate `lock` 不会修改活动设置、临时 `Ctrl+C` 手势或 deadline,但会清除当前 Focus ownership marker；Focus disable、timer 与热键回调都使用 generation fence,不能解除后续新锁。marker 只存在于 Agent 进程内,显式 unlock、热键、timeout、event-tap failure 或 Agent restart 可以提前结束 generation,且不会因 Focus 仍 active 而自动 relock。资源未全部可用前不提交 locked 状态；运行中 tap 无法重新启用时 fail open 到 unlocked 并广播权威状态。引擎的全部外部副作用(Accessibility 查询、tap 安装、定时器排程、按键字符映射、系统唤醒观察、状态广播、时钟)经 `LockEngineDependencies` / `InstalledEventTap` 注入缝进入,`LockEngineTests` 因此能确定性驱动这些路径。
- `KeyboardLockerSettingsStore.swift`:基于 `UserDefaults` 的设置持久化 —— 放在 `Service` 内,以确保没有 wrapper 能拥有自己的 store(契约的真相源规则)。`load()` 在本地损坏时回退 `.default` 并记录错误(读路径不能让 Agent 起不来);`save(_:)` 相反,编码失败必须抛出,不能静默丢弃写入让调用方误以为配置已生效。
- `LockStateBroadcaster.swift`:发出 Darwin + Distributed 通知(均无载荷,只是"状态已变"的信号;订阅方收到后回拉 `status()`)。`broadcastBlockedInput()` 复用同一双通道发出 `NotificationNames.blockedInput` —— 被吞按键的 presentation hint,节流在引擎输入边界完成,订阅方展示前必须重新核对权威锁状态。
- `LockStatusNotifier.swift`:Agent 进程内的 "Keyboard Locked" 系统通知 owner。`AgentService` composition root 把它接到 engine 的 state-change handler；live 路径在状态转换完成后先广播状态信号，再由 notifier 读取进程内 `statusSnapshot` 拼装正文(解锁热键 + auto-unlock 截止时间),经 `UNUserNotificationCenter` 投递/移除固定 identifier 的通知;`Unlock Now` action 由 Agent 本地执行幂等 unlock。首次锁定时请求通知权限,拒绝则静默降级。`start()` 在 bootstrap 时安装 action category 并清除上一代 Agent 退出留下的残留通知。通知生命周期与锁生命周期由此绑定在同一进程,不会比锁活得更久。
- `LockSoundPlayer.swift`:Agent 进程内的锁定/解锁提示音 owner,与 notifier 共用同一个 state-change 槽位和进程内 `statusSnapshot`。只在 locked/unlocked 边沿各播放一声(重复 publish 的同一状态保持静默),由该代 active settings 的 `soundEffectsEnabled` 门控;live 实现用 `NSSound` 系统音,半音量播放,声音缺失时静默降级。与通知一样,提示音生命周期绑在 Agent 进程内,任何 wrapper 不播放状态提示音。
- `LockHistoryRecorder.swift` / `LockHistoryStore.swift`:Agent 进程内的有界锁定历史 owner 与其 `UserDefaults` 持久化。引擎的 lock-history hook 在每代锁结束、状态清除前产生一条 `LockHistoryEntry`;recorder 追加并按 `LockHistory.retentionLimit`(200)淘汰最旧条目后落盘,落盘失败只记 `os.Logger` 日志——历史是 presentation-only,绝不能阻塞产生它的解锁路径。store 在本地数据损坏时回退空历史并记录错误(与 settings store 同一容错形态)。`AgentService` composition root 负责接线,`lockHistory` selector(protocol 1.10)只读返回当前条目。
- `ReplacementTransaction.swift`:纯 `idle → prepared → committed` 状态机；prepared 可 cancel/expire，committed 不可 cancel/expire，只能由 Agent 进程退出终止。它不触碰 TCC 或 Service Management，可由 `ServiceTests` 确定性覆盖。
- `MainActorTimerScheduler.swift`:单次 MainActor 定时器抽象(返回取消闭包)及其 live 实现;`LockEngine` 的 auto-unlock 与 `AgentService` 的 replacement 过期共用,测试中替换为手动调度。
- `AgentService.swift`:nonisolated XPC wire adapter；Agent bootstrap 只创建一个贯穿进程生命周期的实例，并把它交给所有 listener connection。这个实例私有创建并持有唯一的 `LockEngine`、`LockStatusNotifier`、可变设置、注入的 `SettingsPersisting` 与 replacement transaction，把所有可变状态与引擎操作切到 `MainActor`；它不是语言层 static singleton。`applySettings` 按 decode → `validated()` → 拒绝 replacement drain → `save()` → 更新内存值 → **仅 unlocked 时** `engine.updateSettings` → 回复权威值 的顺序执行,任一步失败都不落盘。测试 initializer 仍可注入普通引擎 double、`SettingsPersisting` fake、descriptor 与 prepare 过期调度；replacement barrier、instance-ID fence、locked refusal、settings 写入(含 locked 时不触碰引擎的回归门)、错误码映射与过期/取消语义由 `ServiceTests` 确定性覆盖。
- `AccessibilityManager.swift`(Agent 身份下的实时权限查询与 prompt 请求)、`XPCAccessControl.swift`(生成 Listener 的受信 Client requirement)、`XPCServerConnection.swift`。

**SystemSurfaces**(`Core/Sources/SystemSurfaces/`)—— 仅 containing App、Widget 与 Focus extension 使用的 presentation adapter
- `LockStateSurfaceInvalidator.swift`:集中定义稳定的 Widget / Control kind,并把 `WidgetCenter` 与 macOS 26+ `ControlCenter` 包装成 nonthrowing reload request。它不 import `Client` / `Service`,不查询或携带锁状态,也不链接到 Agent / CLI；系统可以延后或合并请求,因此它不是状态广播或第二份真相源。(CLI 不链接还有实证依据:`chronod` 会忽略来自非 extension 容器进程的 reload 请求——`Ignoring restricted or unknown extension io.lzhlovesjyq.keyboardlocker.klock`,macOS 26 实测。)

**App**(`KeyboardLocker/`)—— 长命的 menu-bar 薄 wrapper，并承载一次性系统 action；领域操作只调用 Client,presentation refresh 只调用 SystemSurfaces
- `AgentRegistrar.swift`:通过 `SMAppService.agent(plistName:)` 确保注册,读取 bundled Agent metadata 并比较运行中 descriptor;replacement 会等待旧 Agent 退出后重新注册 bundled 版本。
- `KeyboardLockerApplication.swift` / `StatusItemController.swift`:进程级 AppKit 生命周期与 menu-bar status item。它们只渲染 `AppCoordinator.Snapshot` 并把用户动作转发给 coordinator,不直接读取或持有锁/设置状态。status item 左键点击 toggle 一个 SwiftUI popover(不设 `NSStatusItem.menu`);首次 readiness 达到 ready + unlocked 后提示一次可跳过的 10 秒安全测试。`StatusItemController` 拥有 coordinator 的唯一 observer 槽位,把每个 snapshot 同时扇出给菜单栏图标(symbol/tooltip)与 `AppUIStore`。需要模态 `NSAlert` 或跳系统设置的动作(agent update/restart、锁定时退出、关闭 auto-unlock、CLI 管理、诊断、开 Login Items / Accessibility pane)都留在这里,经 `PopoverActions` 注入 SwiftUI 层;呈现 alert 前先关闭 popover,使 alert 不被遮挡。锁定时点图标即弹出、含 Unlock,是鼠标可达的解锁出口。被拦输入的 HUD 也挂在这里:`BlockedInputHUDController` 订阅 Agent 的 blocked-input 信号,只有协调器权威快照仍为 locked 时才生成 hint(热键显示串 + 短语手势存在位,不含短语本体),经一个不抢焦点、不拦截鼠标的屏幕中央 bezel(音量/亮度 HUD 同款位置,大锁形 glyph + 进场 pop 动画)显示约 2.4 秒,且权威快照转为 unlocked 时立即撤下(文案只在 locked 时为真,不能比锁活得久;presenter 用代际守卫防止退场动画与新一次 show 竞争);双通道信号在 App 侧再做 1 秒合并。权威快照携带 auto-unlock deadline 时,菜单栏图标旁还会显示每秒走字的倒计时:等宽数字字体 + 恒定五字符 `mm:ss` 格式(`MenuBarCountdown`,纯格式化逻辑可单测)+ `variableLength` 自适应排版(内容宽恒定 → 自适应总宽也恒定),保证走秒期间宽度不变、不推挤相邻图标,只有锁/解锁状态转换时宽度才变化一次。
- `UI/`:SwiftUI popover 层,承载于 AppKit `NSPopover` + `NSHostingController`(App 入口保持 accessory `@main`,不改成 SwiftUI `App`/`MenuBarExtra`,以免动到 activation policy、services provider 与 URL handling 三条已测路径)。`PopoverPresenter` 持有 `.transient` 的 `NSPopover`,`toggle`/`show`/`close` 锚定到 status item button。`PopoverRootView` 用轻量 `@State` enum 在 `StatusPage` ↔ `SettingsPage` 间切换(非 `NavigationStack`)。`AppUIStore`(`ObservableObject`,部署到 macOS 13)只把 `AppCoordinator.Snapshot` 桥成可观察状态并转发动作,不含领域逻辑,由 controller 调 `receive(_:)` 推送而非自行抢占 observer;并提供纯呈现路由(`recoveryActions`、`canRunSafetyCheck`)。`StatusPage` 显示锁状态卡片、由权威 `autoUnlockTargetDate` 派生的倒计时、起点、active 解锁热键、unlocked 时的上次解锁记录(原因 + 时刻)、主动作与逐状态恢复按钮,底部工具条含手势提示(跟随当前可用动作:unlocked 且配置了锁定热键时提示锁定手势,locked 时提示解锁手势,设置不可读时不显示)、统计页入口、齿轮与 `⋯` overflow(ready 且 unlocked 时提供 5/10/30 分钟快捷定时锁,一次性覆写本轮 auto-unlock,不回写设置)。`StatsPage` 显示锁定统计:`onAppear` 时经 `AppCoordinator.loadLockHistory()` 拉取 Agent 有界历史(`HistoryState` idle/loading/loaded/unavailable,失败显示 unavailable 而非空表),由 `LockHistoryStats` 纯函数(注入 now/calendar,可单测)派生今日与近 7 天的锁定次数/总时长、按解锁方式的分布(条目归属其结束日、时长截断到非负、滚动 7 天窗),空历史显示引导文案。`SettingsPage` 带返回导航,编辑持久化设置:全局锁定热键开关与录制(默认建议 ⌃⌘K,关闭即注销)、解锁热键录制、解锁短语开关与文本(共享 `validated()` 护栏即时反馈)、auto-unlock 档位、`.disabled` 二次确认、Feedback 区的提示音与被拦输入提示开关;两支热键在录制 / 启用时都会经 `SystemShortcutConflicts` 做冲突检查——对照 `com.apple.symbolichotkeys` 里的已启用系统快捷键(Spotlight、输入法切换、截图、Mission Control 等,常见 ID 有社区考据名,未知 ID 走通用文案)以及与另一支热键重复(会变成 toggle),命中只显示非阻塞警告,不拒绝写入(plist 格式无官方文档,best-effort);读取失败显示 unavailable 而非默认值,locked 时提示"下次锁生效"。`HotkeyCapture` 是纯翻译(捕获→候选热键,复用 `Hotkey.validated()`,丢弃 matcher 忽略的修饰键,Escape/Return 结束录制),`HotkeyRecorderField`/`HotkeyRecorderView` 是其 AppKit 捕获宿主;`PopoverActions` 是 AppKit 确认动作的注入缝。
- `LockHotkeyController.swift`:全局锁定热键的 App 侧 owner。按 settings 值用 Carbon `RegisterEventHotKey` 注册/注销(修饰键映射只测四个可用 flag,CapsLock 残余自然归零),命中后只发一个意图——`AppCoordinator.performLock()`(显式幂等 `lock`,绝不解锁);注册、注销与失败回调都注入,去重逻辑(只在值变化时重注册、失败按编辑只报一次)由 `KeyboardLockerModelTests` 覆盖。`StatusItemController` 在 `render` 中按 `editableSettings.lockHotkey` 驱动它,注册失败弹一次"组合被占用"的 alert。手势不对称(锁定在 App、解锁在 Agent)是契约级决策,见 architecture 的"全局锁语义"。
- `SafetyCheckExperienceStore.swift`:只持久化 App presentation 层的“安全测试已完成”标记,不存储或推导锁状态、settings 或 Accessibility 状态。只有 Agent 已创建测试锁、且 App 后续重新取得权威 unlocked 时才写入完成。
- `KeyboardLockerDiagnostics.swift`:按用户动作实时收集 App/Agent 版本、protocol/capability、Service Management、Accessibility、权威 lock snapshot 与最近错误,生成可复制的稳定文本报告。报告不采集 keyboard input、username、hostname 或 file path；错误文本还会对 path-like token 做二次脱敏。单项查询失败会成为显式 unavailable/error 行,不阻断其余诊断。
- `AppIntents/KeyboardLockAppIntents.swift`:可在 Shortcuts 中组合的 `Lock Keyboard`、`Unlock Keyboard`、`Toggle Keyboard Lock` 与返回 `Bool` 的 `Get Keyboard Lock Status` action。它们是 one-shot wrapper，每次执行只经 `AgentLockActionServing` 调用 Agent，不缓存状态、不订阅通知。`Toggle Keyboard Lock` 调用 Agent 串行边界内的原子 `toggle` 并返回翻转后的 `Bool`,不做 client-side 状态合成。`AppIntents/KeyboardLockerShortcuts.swift` 在 macOS 26+ 声明 `AppShortcutsProvider`,为 lock / unlock / toggle 注册 promoted App Shortcuts 与 invocation phrases;更早的 macOS 只从 Shortcuts action library 暴露这些 intent。
- `AppleScript/KeyboardLockerScriptCommands.swift` / `KeyboardLocker.sdef`:向 Cocoa Scripting 暴露 `lock keyboard`、`unlock keyboard` 与 `get keyboard lock status`。命令先 suspend 当前 Apple event，异步调用同一个 `AgentLockActionServing`，再以结果或显式错误 resume；它们不持有本地状态，也不把 XPC 不可达猜成 unlocked。
- `Automation/ExternalAutomationController.swift`:Services 与 URL event 共用的串行 one-shot executor。每个 action 只调用 `AgentLockActionServing` 的对应 desired-state/query method；跨多次 submit 也保持接收顺序,并把 authoritative status 或合并后的 failure 交给 presentation boundary。
- `Automation/KeyboardLockerServicesProvider.swift`:将 `NSServices` 的三个 Objective-C selector 适配成 `.lock` / `.unlock` / `.status`。handler 经 `ExternalAutomationController.submitAndWait` 有界等待串行链结果(默认 15s,覆盖 XPC 应答窗口加幂等重试),失败或超时同步写入 error out-pointer 回传调用方;短生命周期的 pointer 与 pasteboard 不会被捕获进异步 Task。AppKit 在主线程调用 handler 时泵 run loop 等待,避免硬阻塞饿死 main-actor 执行链。
- `Automation/KeyboardLockerURLRoute.swift`:只把 `keyboardlocker://lock|unlock|status` 的严格 canonical URL 映射为 action。它拒绝额外 URL component,不回显原始输入,并把多个 URL 转成保序的 action/failure request；custom scheme 不声称 caller authentication。
- `Automation/AppKitExternalAutomationPresenter.swift`:主 App 内统一呈现外部 automation 的 status 与异步 failure；显示 alert 前激活 accessory App,避免提示留在后台。
- `AgentCoordinationServices.swift`:App 内部的可注入依赖边界。live adapter 把 `XPCClient`、`LockStateSubscriber` 与 `AgentRegistrar` 暴露为按用途拆分的最小 protocol；`AgentLockActionServing` 只提供 one-shot wrapper 所需的 `lock` / `unlock` / `toggle` / `status`,`AgentTimedLockServing` 单独承载 popover 快捷定时锁的 `beginTimedLock`(窄协议,automation fake 不必 stub 触发不了的能力),`AgentSettingsServing` 提供 `currentSettings` / `applySettings` / `lockStatusSnapshot`,协调器和系统 action 都无需依赖无关 Client surface。live lock/unlock/toggle 与 `applySettings` 成功后请求 system-surface reload(Widget 显示解锁热键,设置变更需刷新),status 不请求；live state observer 在新 observation lifetime 和每个已回拉、去重的权威变化上提交 presentation hint,从而覆盖 App 运行期间的 CLI、timer、热键与 fail-open 变化。
- `AgentReadinessCoordinator.swift`:一次性收集 registration、descriptor handshake/重连、兼容性、replacement phase、Accessibility 与权威锁状态,返回不含 UI 的 domain outcome。
- `AgentReplacementCoordinator.swift`:执行 App 侧 Agent 替换顺序。`AgentUpdatePlan` 用类型区分已协商的 safe replacement 与需要用户授权的 forced fallback,所有自动/手动更新共用 prepare → commit → restart → reconnect 边界。
- `AppCoordinator.swift`:不依赖 presentation framework 的 `@MainActor` 应用协调器 —— 持有异步任务/订阅生命周期、单次自动更新策略和 replacement progress polling,把 domain outcome 收敛为可观察的应用 snapshot；不直接实现 handshake、replacement transaction、锁或设置逻辑。`Snapshot` 除锁布尔外还携带权威 `LockStatusSnapshot`(起点/deadline/active settings)与 `SettingsState`(loading/loaded/unavailable)。设置读取失败呈现 unavailable 而非回退 `.default`;`hasSettingsPendingNextLock` 表示 locked 期间写入的 stored settings 与当前锁 enforcing 的 active settings 不同,须等下次 lock 生效。Agent 不再可信(update required、approval、unavailable、replacement)时清空这些 detail,detail 查询失败不降级 ready 状态。

**WidgetKit extension**(`KeyboardLockerWidgets/`)—— sandboxed、按需运行的 Widget/Control wrapper；领域操作只调用 Client,presentation refresh 只调用 SystemSurfaces
- `KeyboardLockerControlModel.swift`:Widget/Control 共用的可测试纯协调模型。Control value loader 直接返回 Agent 查询结果；desired-state action 只在 XPC lock/unlock 成功后请求 reload,不做 client-side toggle。
- `KeyboardLockerControl.swift`:macOS 26+ `Keyboard Lock` Control、XPC live adapters 与 `SetValueIntent`。on/off 分别映射到幂等 `lock`/`unlock`,成功后刷新 Control value 和状态 Widget timeline。
- `KeyboardLockerWidgetAction.swift`:macOS 14+ 状态 Widget 的内部、不可发现 `AppIntent`;`Lock` / `Unlock` 映射到明确 desired state,成功后请求刷新 timeline,失败则原样传播。
- `KeyboardLockerWidgetTimeline.swift`:每次 timeline execution 经 `XPCClient.lockStatusSnapshot()` 读取 Agent 的权威原子快照。loader 把 transport failure 建模为显式 unavailable entry,并请求 15 分钟 regular fallback 或更早的 auto-unlock deadline reconciliation；不订阅长命通知、不维护第二份状态。
- `KeyboardLockerStatusWidget.swift`:small/medium 状态 presentation,显示 locked/unlocked、deadline、解锁热键与 Agent unavailable；macOS 14+ 提供 explicit desired-state action,macOS 13 保持只读。WidgetKit 可以合并 timeline policy,因此该 UI 不承诺实时刷新。
- `KeyboardLockerWidgets.entitlements`:保留 App Sandbox,只增加 Agent Mach service 的 global lookup temporary exception。Agent 仍以同 Team + 精确 extension identifier 的 listener requirement 独立认证调用方。

**App Intents extension**(`KeyboardLockerFocusIntents/`)—— sandboxed、按需运行的 Focus Filter wrapper；领域操作只调用 Client,presentation refresh 只调用 SystemSurfaces
- `KeyboardLockFocusFilterIntent.swift`:macOS 13+ `SetFocusFilterIntent`;参数默认值为 `false`,使 Focus 关闭时向 Agent 发送该 activation generation 的条件 disable。`true` 是一次 activation-triggered acquisition,不是 while-active keep-alive；`perform()` 只调用 capability-gated `setFocusFilterLockEnabled`,成功后请求 system-surface reload,不以普通 `unlock` 模拟条件释放,也不在 Agent restart 后查询或 replay 当前 Focus。
- `AppIntentsExtension.swift` / `Info.plist`:独立 `com.apple.appintents-extension` 入口,使主 App 未运行时系统仍可执行 Focus 生命周期事件。
- `KeyboardLockerFocusIntents.entitlements`:保留 App Sandbox,只增加 Agent Mach service 的 global lookup temporary exception。Agent allowlist 只新增 `io.lzhlovesjyq.keyboardlocker.focus-intents` 精确 signing identifier。

## 常见任务

### 新增一个用户可编辑设置
用户可编辑设置已接入:`applySettings`(protocol 1.8)经 Agent XPC 写入并持久化,`SettingsPage` 提供 UI。新增一个字段时:
1. 给 `KeyboardLockerSettings` 加一个 `Codable`/`Sendable` 属性,并更新 `.default`。
2. 如果引擎会消费它,在 `LockEngine.lock(settings:allowsControlCUnlock:)` / `updateSettings(_:)` 中读取。
3. 如果它有锁死或无效风险,在 `KeyboardLockerSettings.validated()` 补一条护栏并加 `CommonTests`——Agent 的 `applySettings` 已强制该方法,无需在 UI 侧另写校验。
4. 在 `SettingsPage` 暴露编辑控件,写入仍只经 `AppCoordinator.applySettings(_:)` → `XPCClient.applySettings(_:)`;wrapper **不得**拥有 store(见架构契约)。locked 时是否立即生效沿用现有语义:Agent 只在 unlocked 时把新值应用到引擎。

### 新增一个 XPC 方法
1. 先判断它是否 optional/additive。不得在同一 protocol major 内修改或移除既有 selector、参数顺序或 reply 形状;破坏性变化需要新 major,无法保留 selector union 时需要新 Mach service。
2. 在 `Common/Shared.swift` 的 `KeyboardLockerServiceProtocol` 里加签名,同时在 `ServiceCapability` 增加一个从不复用的稳定名字,并按兼容需求更新 protocol minor / required capability。无法用 `@objc` 表达的值(如 `KeyboardLockerSettings`)以有大小上限的 JSON `Data` 跨界。
3. 在 `Core/Sources/Service/AgentService.swift` 中实现它并在 descriptor 中声明 capability。
4. 在 `Client/` 的 `XPCClient` 上加一个薄的异步封装;调用前必须完成 descriptor handshake 并检查 capability。
5. 在 `Core/Tests/ClientTests/` 补充 old/future descriptor fixture、round-trip、build ordering 与兼容性测试；Server 状态机在 `Core/Tests/ServiceTests/` 覆盖 exclusivity、stale ticket/timer、cancel、expiry 与 committed fail-closed 语义。

### 修改事件过滤
在 `LockEngine.handleEvent(type:event:)` 中:返回 `nil` 拦截、返回 `Unmanaged.passUnretained(event)` 放行,并在满足解锁条件(热键或超时)时调用 `unlock()`。`Hotkey.matches(keyCode:flags:)` 会通过 `relevantModifierMask` 过滤掉 CapsLock/NumLock。

## 测试须知

`Core/Tests` 与 `KeyboardLockerModelTests` 统一使用 Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect` / `#require`)；不要在新测试中重新引入 XCTest。现有 `swift test`、`xcodebuild test` 与 CI entrypoint 不变。

### 在 Terminal 中使用开发版 `klock`

开发阶段可用脚本安装、检查或移除指向 Debug App 内已签名 `klock` 的 symbolic link：

```bash
./scripts/install-klock-dev.sh install
./scripts/install-klock-dev.sh status
./scripts/install-klock-dev.sh uninstall
```

默认目标是 `~/.local/bin/klock`，也可通过 `--bin-dir PATH` 或 `KLOCK_BIN_DIR` 指定其他用户可写目录。脚本会先验证 bundled executable 的 code signature、精确 signing identifier，以及 App、Agent、CLI 三者的 Team identifier 一致性；遇到已有文件或其他 link 时会拒绝覆盖。它不会复制 binary、修改 shell profile 或调用 `sudo`。若目标目录不在 `PATH`，脚本只打印需要添加的 `export PATH=...`，由用户决定写入哪个 shell 配置。

已构建的 App 也在 popover 的 Settings 页提供 **Manage klock Command…**。该入口遵循同一所有权边界：只创建或移除指向当前 App bundle 的 link；需要配置 `PATH` 时仅提供可复制命令，不会静默修改 dotfile。

`klock` 自身不注册后台 Agent——`SMAppService` 注册只能由 App bundle 执行。首次使用前运行 `klock register-agent` 或至少启动一次 KeyboardLocker App；Agent 未注册时，CLI 各命令也会给出对应恢复提示。

`klock lock` 只有在本次请求原子创建全局锁时才进入等待，并提示 `Ctrl+C`。这个按键由 Agent event tap 识别后直接解锁，不依赖 Terminal 先收到被锁定输入并生成 `SIGINT`。等待期间进程收到 SIGTERM/SIGHUP/SIGINT 时,会在退出前尽力释放它创建的锁(GCD 信号源 + 有界等待;`KlockTerminationGuard` 为可注入缝),退出码保持 `128 + signal` 惯例;SIGKILL/SIGSTOP 不可捕获,遗留锁由全局解锁途径兜底。若 Agent 已被 App 或其他 CLI 锁定，命令会报告 `Already locked. This command did not create a new lock.` 后成功退出，不改变既有锁。自动化脚本应使用 `klock lock --no-wait`：它确认全局状态为 locked 后立即退出，不启用临时 `Ctrl+C` 手势，也不等待 unlock。单次定时锁用 `klock lock --for 10m`（`90`、`45s` 写法等价）一次性覆写本轮 auto-unlock，不回写保存的设置；已锁时报告 override 未作用于既有锁。

Shortcuts、Focus Filter、Services、URL Scheme、AppleScript、CLI、Widget 与 Control 的完整用法和跨 wrapper 语义见 [automation.md](automation.md)。

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
- 首次安全测试的 ModelTests 覆盖 Agent 成功创建后等待权威 unlocked 才完成、并发既有锁拒绝与 presentation invalidation；ServiceTests 覆盖固定 10 秒 override、沿用持久化热键、不写回 settings store 及 replacement drain 拒绝。真实 Quartz event tap、TCC prompt 和用户按键解锁仍属于真机手动验证边界。
- 设置写入路径:`CommonTests` 覆盖 `validated()` 护栏逐条(无修饰键 / 仅 CapsLock / 不可映射 keyCode / 边界 5 与 3600 / 越界 / 非有限 / `.disabled` / 分数取整);`ServiceTests` 覆盖 `applySettings` 落盘并可 `load()` 读回、**locked 时不调用 `engine.updateSettings` 的回归门**、unlocked 时调用、非法/不可解码 payload 不落盘且报错、持久化失败保留旧值、replacement drain 期间拒绝写入;`ClientTests` 覆盖 1.7 descriptor 触发 `missingCapability`、minor floor 拒绝、以及 capability→minor 表的完整性(与实现同源,不再维护第二份副本)。`KeyboardLockerModelTests` 覆盖 `AppUIStore` 的派生状态、读取失败呈现 unavailable(不回退 `.default`)、locked 期间的 pending 语义、`HotkeyCapture` 纯函数矩阵(修饰键映射 / 接受即通过 Agent 校验 / Escape/Return 终止)。真实 `NSEvent` 捕获、`NSPopover` 呈现与 status-item 点击、热键实机解锁与 Widget 刷新属于真机手动验证边界(见方案的手动验证清单:改热键后用新热键解锁、locked 时改 Never 仍在原 deadline 解锁、设置改动后 Widget 跟随、Agent 不可达时设置页显示 unavailable)。

### 覆盖边界与已知限制

测试覆盖有意停止在需要真实系统边界的层面;以下是当前接受的残余风险与实现特性,排查问题时先对照,不要重新"发现"它们:

- `LockEngine` 的纯策略(event policy、schedule 计算、runtime state、tap 安装事务、短语滚动匹配)与引擎语义(Accessibility 预检、tap 安装/拆除、auto-unlock 排程/触发/陈旧代际拒绝、唤醒校准、热键与 Control-C 与短语手势分发、tap-disable re-enable/fail-open、Focus 代际所有权)均已单测 —— 后者由 `LockEngineTests` 经注入缝(`InstalledEventTap`、`MainActorTimerScheduler`、`characterForKeyCode`、wake 观察、权限/广播/时钟闭包)确定性驱动;剩余不可单测的只有 Quartz 对真实硬件事件的拦截本身(平台集成事实,靠真机验证——短语路径已在真机实测:注入设置后经 CGEventPost 合成打字解锁,snapshot 报 `phrase` 原因)。
- App 侧 `AgentReadinessCoordinator` / `AgentReplacementCoordinator` 已由 `KeyboardLockerModelTests` 经 fake client/lifecycle 覆盖(handshake 重试、unverified fallback、safe/forced 计划、prepare→commit→restart 顺序、cancel/redetection、Task 取消路径);forced 且无锁态可读的计划结构上不可能产生 `.failed`(该路径不存在任何可抛错调用)。`klock` 的参数矩阵与命令执行路径(未知命令、多余参数、already-locked 退出、stdout/stderr 路由与退出码、`register-agent` 的探测/启动/轮询路径、termination guard 的安装/取消矩阵与信号后解锁逻辑)已由 `KlockCommandLineTests` 覆盖;`version` 的执行路径依赖 `Bundle.main` 未测(其解析已覆盖),`KlockAppOpener` 的 bundle 定位与 `/usr/bin/open` 调用、live termination guard 的真实信号投递依赖真实进程环境,经手动验证(kill/kill -HUP 实测解锁与退出码)。
- auto-unlock 定时器使用单调时钟(系统休眠期间暂停),而 snapshot 携带的 `autoUnlockTargetDate` 是墙钟时间:Agent 经注入的 wake seam 监听系统唤醒并按墙钟 deadline 校准——休眠跨过 deadline 时唤醒即解锁,否则按剩余墙钟时长重排定时器,锁仍在原公告时刻结束且已发布 deadline 不被改写(`LockEngineTests` 确定性覆盖);wrapper 仍不得把 deadline 当作保证的解锁时刻(Agent 退出或关机不受其约束),Widget 的 deadline reconciliation 只是提前校准提示。
- `KeyboardLockerSettingsStore` 在本地持久化数据损坏时回退 `.default` 并记录 `os.Logger` 错误(仅 Agent 写该 key,风险有界;该路径已由 `ServiceTests` 覆盖);跨进程的 wire codec 保持严格显式失败,不受影响。
- Client 任意调用的超时或 `waitUntilUnlocked` 取消会失效进程内**共享**的缓存 connection:并发的无关在途调用会收到一次 `serviceUnavailable`,下一次调用自愈,这不是 Agent 故障。
- unsigned/ad-hoc fail-closed:requirement 对异类签名的拒绝已由 `XPCCodeSigningRequirementEvaluationTests` 经 `SecStaticCodeCheckValidity` 静态评估确定性覆盖(Apple 系统签名、ad-hoc、完全未签名三类 fixture 均被拒;`anchor apple` 对照证明评估管线本身正确),`XPCAccessControlTests` 按名验证 listener requirement 的 fail-closed 构造。端到端由 `scripts/verify-unsigned-client-refusal.sh` 承载：临时 control 使用本地 bundled `klock` 的 Team 与精确 identifier 签名，在 ad-hoc probe 前后读取同一个 `agentInstanceID`；只有 control 两次都可达同一 Agent generation 且 ad-hoc client 被拒绝才 PASS。Agent 不可达、发生 replacement 或无法取得本地签名 identity 都返回 exit 2 (`INDETERMINATE`)，不会把 service unavailability 当作拒绝证据。该 runbook 需 locally team-signed build 和 GUI session，手动执行，不进 CI。
- CI 由 `.github/workflows/ci.yml` 承载(macOS runner,依次跑 Core 测试、全量 build、`KeyboardLockerModelTests`)。runner 没有签名身份,app build 与 ModelTests 以 `CODE_SIGNING_ALLOWED=NO` 运行;因此签名认证的**运行时**行为不属于 CI 门禁,发布前仍需本地签名构建验证(签名拒绝的端到端验证用上一条的 runbook 脚本)。
