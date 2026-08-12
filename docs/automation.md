# 自动化

KeyboardLocker 的 Shortcuts、Focus Filter、Services、URL Scheme、AppleScript、CLI、Widget 与 Control 都是同一个 Agent capability 的薄 wrapper;Notifications 由 Agent 进程自己发布(见下文)。首次使用任一入口前,先启动一次 KeyboardLocker App 或运行 `klock register-agent`,让 App 注册后台 Agent。

所有入口共享以下语义：

- `lock` 与 `unlock` 是幂等的 desired-state action。
- `lock` 会消费 macOS 交付给 Agent event tap 的标准按键和键盘 system control,包括音量、亮度、播放控制、eject 与 power；鼠标和触控板输入继续可用。macOS 没有交付给 event tap 的硬件或系统保留路径不在可保证范围内。
- `status` 每次都从 Agent 查询权威状态；wrapper 不维护本地副本。
- lock 是全局状态,不属于发起它的 Shortcut、AppleScript 或 shell process。任意普通入口的显式 `unlock` 都会解开同一个全局锁。Focus Filter 的关闭事件使用更窄的条件释放规则,只解除它自己创建且未被后续显式 `lock` 接管的锁。
- `toggle` 在 Agent 的串行执行边界内原子翻转全局锁并返回翻转后的状态;它不是 wrapper 先读 `status()` 再决定方向的 client-side 组合,因此不存在并发竞态。自动化需要确定终态时,仍应显式选择 `lock` 或 `unlock`。
- Agent 不可达、权限不足或结果无法确认时,action wrapper 会明确失败,Widget 会显示 unavailable；任何入口都不会把失败猜成 unlocked。

## Shortcuts

KeyboardLocker 提供四个可组合 action：

- `Lock Keyboard`
- `Unlock Keyboard`
- `Toggle Keyboard Lock`
- `Get Keyboard Lock Status`

`Toggle Keyboard Lock` 把翻转交给 Agent 原子执行,并返回翻转后的 Boolean;`Get Keyboard Lock Status` 返回当前权威 Boolean,两者都可直接接入 Shortcuts 的条件分支。

macOS 26 及以上,应用声明了 `AppShortcutsProvider`,为 lock / unlock / toggle 注册 promoted App Shortcuts,无需手动配置即可从 Spotlight、Quick Keys 与 Siri 调用。更早的 macOS 版本不生成 promoted App Shortcuts 或 invocation phrase,这些 action 从 Shortcuts 的 action library 中选择。

## Focus Filter

macOS 13 及以上可在 **System Settings > Focus** 中为某个 Focus 添加 KeyboardLocker 的 `Keyboard Lock` filter。启用该 Focus 时,系统把 `Lock Keyboard = true` 发送给独立的 App Intents extension,触发一次 lock acquisition；关闭时会用参数默认值 `false` 再次执行 intent,对该次 activation 创建的 generation 做条件清理。因此主 App 未运行时,系统交付的 Focus 生命周期事件仍能经 XPC 到达 Agent。

Focus Filter 是 activation-triggered wrapper,不是“只要 Focus active 就持续保持 locked”的 policy。它采用条件 ownership,不会把全局 lock 误当成自己的资源：

- 若 Focus 启用时已经由其他入口锁定,它不会认领该锁；Focus 关闭时保持 locked。
- 若 Focus 从 unlocked 创建锁,它只拥有该次 activation 创建的一个 lock generation；使用 Agent 当前 settings,包括现有 auto-unlock policy。
- 若随后任一普通 wrapper 再次显式调用 `lock`,该用户意图会接管同一 generation 的持久性,但不会重建 event tap、改变活动设置或延长 auto-unlock deadline；Focus 关闭时保持 locked。
- 显式 unlock、解锁热键、auto-unlock timeout、event-tap failure 或 Agent 退出 / 重启都可以在 Focus 仍 active 时提前结束原 generation；迟到的 Focus 关闭事件不能解除之后新建的锁。
- generation 提前结束后,KeyboardLocker 不会因为同一个 Focus 仍 active 而自动 relock；Agent 重启也不会查询或 replay 当前 Focus。需要重新触发时,切换 Focus 或从任一普通 wrapper 显式执行 `lock`。

Focus extension 保持 sandbox,只获得访问 KeyboardLocker Agent Mach service 的 lookup 权限；Agent 仍要求同 Team 与精确 extension signing identifier。Agent 或 Accessibility 不可用时,intent 会明确失败,不会伪造 Focus 已经应用。

## Services

KeyboardLocker 在 macOS 的 **Services** 菜单注册三个不依赖当前选中文本的原生 action：

- `Lock Keyboard`
- `Unlock Keyboard`
- `Show Keyboard Lock Status`

它们可以从其他 App 的 Services 菜单调用,也可以在 **System Settings > Keyboard > Keyboard Shortcuts > Services** 中绑定全局快捷键。三个入口都交给同一个串行 executor：lock/unlock 直接发送 desired state,status 从 Agent 读取权威 Boolean 后显示提示；并发到达的 action 按接收顺序执行。

AppKit Services 的 handler 没有与异步 XPC 对应的 suspend/resume contract,因此 provider 只同步受理请求并立即返回,不会阻塞主线程等待 Agent。后续失败由 KeyboardLocker 激活并显示明确错误。需要调用方拿到事务级结果或 machine-readable status 时,使用 AppleScript、Shortcuts action 或 `klock status --json`,不要把 Services 的返回当作完成确认。

## URL Scheme

Launcher、浏览器或其他本地 App 可以打开三个 canonical deep link：

```text
keyboardlocker://lock
keyboardlocker://unlock
keyboardlocker://status
```

Parser 对 scheme 与 host 使用 URL 规定的大小写不敏感比较,但只接受上述 `scheme://host` 结构。userinfo、port、path（包括尾随 `/`）、query、fragment、percent-encoded action 与未知 host 都会被拒绝；错误提示不会回显原始 URL,避免意外暴露调用方放入 query 的数据。一次收到多个 URL 时按交付顺序串行执行。

`lock` / `unlock` 成功时静默完成；`status` 读取 Agent 的权威 Boolean 并显示 alert。custom URL scheme 没有结果返回通道,因此 machine-readable 查询仍使用 `klock status --json`。

安全边界必须明确：macOS custom URL scheme 不提供 caller authentication,任何能请求系统打开 URL 的本地 App 或网页都可能触发这些 action。Agent 只会看到经过签名认证的 KeyboardLocker App,无法识别最初调用方；严格 parsing 解决的是输入歧义,不是授权。不要在 query 中加入 token 来伪装鉴权。当前实现把这个 unauthenticated convenience surface 作为公开 contract,包括 `unlock`。

## Widget

`Keyboard Lock Status` Widget 支持 small 和 medium family。每次生成 timeline 时,extension 都通过 XPC 读取 Agent 的 `LockStatusSnapshot`,并显示 locked/unlocked、auto-unlock countdown 或 manual unlock，以及当前解锁热键。它不使用 App Group、`UserDefaults` 或自己的状态缓存；Agent 不可达时会明确显示 `Agent Unavailable`。

macOS 14 及以上的 Widget 提供 `Lock` / `Unlock` 按钮。按钮把当前展示的 snapshot 翻译成明确的 desired state：`Lock` 只调用幂等 `lock`,`Unlock` 只调用幂等 `unlock`,不会先重新读取状态再执行 client-side toggle。即使用户点击时 snapshot 已过期,action 也不会被翻译成相反方向。Agent 确认成功后才请求刷新 timeline；调用失败会由 App Intent 明确返回错误,不做 optimistic update。macOS 13 上保持只读。

Widget 使用 15 分钟 regular fallback；若 auto-unlock deadline 更早,则请求在 deadline 后立即校准。主 App、Shortcuts、AppleScript、Services、URL、Focus、Widget 与 Control 在 Agent 确认 mutation 后都会请求刷新状态 Widget 和可用的 Control；主 App 运行时,其权威状态订阅还会把 CLI、auto-unlock、解锁热键与 event-tap fail-open 的变化桥接成 presentation reload。主 App 未运行时,CLI、热键或 event-tap failure 只能等待下一次 WidgetKit provider execution——CLI 自身无法请求刷新：实测(macOS 26)`chronod` 会把非 extension 容器进程的 reload 请求按 `Ignoring restricted or unknown extension` 忽略。timeline 与显式 reload 都只是系统调度提示；WidgetKit 可以根据刷新预算合并或延后执行,因此 Widget 是系统级状态概览,不是实时监视器。倒计时文本仍由系统持续渲染。

## Control

macOS 26 及以上提供 `Keyboard Lock` Control。Control 的 value provider 每次经 XPC 查询 Agent 的权威 Boolean；用户操作产生的是明确的 desired state：on 调用 `lock`,off 调用 `unlock`。它不会先读取旧值再做 client-side toggle,因此并发状态变化不会把一次操作翻译成错误方向。

Agent 确认 action 成功后,extension 会请求刷新 `Keyboard Lock Status` Widget timeline 和 Control value。调用失败会由 App Intent 明确返回错误,也不会先刷新出未经确认的 UI 状态。Control API 在当前 macOS SDK 中从 macOS 26 起可用；macOS 13–15 不注册 Control,其中 macOS 14–15 的状态 Widget 可交互,macOS 13 的状态 Widget 只读。

## Notifications

任一入口使键盘进入 locked 时,**Agent 进程自己**发布一条 `Keyboard Locked` 通知：内容直接来自 Agent 持有的 active settings 与 auto-unlock deadline,展示当前解锁热键,并在 timed auto-unlock policy 下附带截止时间。通知使用固定 identifier,重复锁定只替换内容,不会堆叠;任一入口解开同一个全局锁——显式 unlock、解锁热键、auto-unlock timeout 或 event-tap fail-open——通知都随同一次状态转换移除。因为投递/移除与锁状态转换发生在同一进程,通知不会比锁活得更久,与哪个 wrapper 在运行无关;若 Agent 在 locked 时退出(event tap 随进程释放),残留通知由下一次 Agent 启动时清除。

通知携带 `Unlock Now` 操作按钮。键盘被锁时鼠标与触控板仍然可用,点击按钮由 Agent 本地执行幂等 `unlock`,不需要拉起任何 App。

通知是 presentation-only 的便利面:首次锁定时向系统请求通知权限,被拒绝或未授予时不发送、不报错;通知内容永远不是状态源。通知以 Agent 的 bundle 身份发布,在系统设置中显示为 KeyboardLocker(display name 与主 App 对齐)。

## AppleScript

应用 scripting dictionary 提供三个 command：

```applescript
tell application "KeyboardLocker"
  lock keyboard
  set isLocked to get keyboard lock status
  unlock keyboard
  return isLocked
end tell
```

开发构建可能与已安装版本使用相同 bundle identifier。验证特定 build 时,用绝对 app path 避免 Launch Services 命中另一份应用：

```applescript
tell application "/absolute/path/to/KeyboardLocker.app"
  get keyboard lock status
end tell
```

命令会等待异步 Agent 调用完成后再回复 Apple event。只有原始 `status()` 查询(如 `get keyboard lock status`)的 XPC timeout 返回 Apple event timeout (`-1712`);`lock keyboard` / `unlock keyboard` 在 Client 内会先做一次幂等重试,最终超时以 outcome unknown 归入 Apple event failed (`-10000`),其余 Agent 调用失败同样返回 `-10000`,并保留 Client 提供的恢复建议。

## CLI

交互式锁定会等待后续 unlock。只有本次命令真正创建新锁时,Agent 才为该轮锁临时启用 `Ctrl+C` 解锁：

```bash
klock lock
```

自动化应使用 one-shot 模式。它在 Agent 确认 locked 后立即退出,不会启用 `Ctrl+C`,也不会等待：

```bash
klock lock --no-wait
```

其他命令：

```bash
klock status
klock status --json
klock unlock
klock register-agent
```

`register-agent` 在 Agent 不可达时启动一次 KeyboardLocker App 来完成 `SMAppService` 注册(注册只能由 App bundle 执行),随后短暂轮询确认 Agent 可达；若出现 Login Items 批准或 Accessibility 授权要求,命令会指出对应的系统设置入口。Agent 已经可达时它不启动 App,直接报告。

`status` 默认输出供人阅读的 `Locked` 或 `Unlocked`。自动化使用 `status --json`,其稳定 contract 是单行 `{"locked":true}` 或 `{"locked":false}`。两种状态都表示查询成功并返回 exit code `0`;参数或 Agent 调用失败返回 `1`,因此脚本不需要把 unlocked 与 transport failure 混在同一个 exit code 中。

不要把 `lock --no-wait` / `unlock` 当成 acquire/release pair：若调用 `lock --no-wait` 时全局状态本来已经 locked,后续无条件执行 `unlock` 会解除其他 wrapper 建立的锁。需要这种 ownership 语义时,应先在 Agent contract 中设计明确的 lease/session capability,而不是在 shell 中模拟。
