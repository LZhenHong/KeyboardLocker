# 自动化

KeyboardLocker 的 Shortcuts、Focus Filter、AppleScript、CLI、Widget 与 Control 都是同一个 Agent capability 的薄 wrapper。首次使用任一入口前,先启动一次 KeyboardLocker App,让它注册后台 Agent。

所有入口共享以下语义：

- `lock` 与 `unlock` 是幂等的 desired-state action。
- `status` 每次都从 Agent 查询权威状态；wrapper 不维护本地副本。
- lock 是全局状态,不属于发起它的 Shortcut、AppleScript 或 shell process。任意普通入口的显式 `unlock` 都会解开同一个全局锁。Focus Filter 的关闭事件使用更窄的条件释放规则,只解除它自己创建且未被后续显式 `lock` 接管的锁。
- 当前没有暴露 client-side `toggle`。需要确定结果时,显式选择 `lock` 或 `unlock`。
- Agent 不可达、权限不足或结果无法确认时,action wrapper 会明确失败,Widget 会显示 unavailable；任何入口都不会把失败猜成 unlocked。

## Shortcuts

KeyboardLocker 提供三个可组合 action：

- `Lock Keyboard`
- `Unlock Keyboard`
- `Get Keyboard Lock Status`

`Get Keyboard Lock Status` 返回 typed Boolean,可直接接入 Shortcuts 的条件分支。当前版本没有声明 `AppShortcutsProvider`;这些 action 从 Shortcuts 的 action library 中选择。Apple 当前不在 macOS 支持 promoted App Shortcuts,因此应用不会注册 invocation phrase。

## Focus Filter

macOS 13 及以上可在 **System Settings > Focus** 中为某个 Focus 添加 KeyboardLocker 的 `Keyboard Lock` filter。启用该 Focus 时,系统把 `Lock Keyboard = true` 发送给独立的 App Intents extension；关闭时会用参数默认值 `false` 再次执行 intent,因此主 App 未运行时也能经 XPC 把 desired state 交给 Agent。

Focus Filter 采用条件 ownership,不会把全局 lock 误当成自己的资源：

- 若 Focus 启用时已经由其他入口锁定,它不会认领该锁；Focus 关闭时保持 locked。
- 若 Focus 从 unlocked 创建锁,它只拥有该次 lock generation。
- 若随后任一普通 wrapper 再次显式调用 `lock`,该用户意图会接管同一 generation 的持久性,但不会重建 event tap、改变活动设置或延长 auto-unlock deadline；Focus 关闭时保持 locked。
- 若原 generation 已经由显式 unlock、热键或 timeout 结束,迟到的 Focus 关闭事件不能解除之后新建的锁。

Focus extension 保持 sandbox,只获得访问 KeyboardLocker Agent Mach service 的 lookup 权限；Agent 仍要求同 Team 与精确 extension signing identifier。Agent 或 Accessibility 不可用时,intent 会明确失败,不会伪造 Focus 已经应用。

## Widget

`Keyboard Lock Status` Widget 支持 small 和 medium family。每次生成 timeline 时,extension 都通过 XPC 读取 Agent 的 `LockStatusSnapshot`,并显示 locked/unlocked、auto-unlock countdown 或 manual unlock，以及当前解锁热键。它不使用 App Group、`UserDefaults` 或自己的状态缓存；Agent 不可达时会明确显示 `Agent Unavailable`。

Widget 会请求每分钟校准一次,若 auto-unlock deadline 更早,则请求在 deadline 后立即校准。该时间只是 WidgetKit timeline policy；系统可以根据刷新预算合并或延后执行,因此 Widget 是系统级状态概览,不是实时监视器。倒计时文本会由系统持续渲染,但从其他 wrapper 发起的手动 lock/unlock 可能要到下一次获准刷新才显示。

## Control

macOS 26 及以上提供 `Keyboard Lock` Control。Control 的 value provider 每次经 XPC 查询 Agent 的权威 Boolean；用户操作产生的是明确的 desired state：on 调用 `lock`,off 调用 `unlock`。它不会先读取旧值再做 client-side toggle,因此并发状态变化不会把一次操作翻译成错误方向。

Agent 确认 action 成功后,extension 会请求刷新 `Keyboard Lock Status` Widget timeline 和 Control value。调用失败会由 App Intent 明确返回错误,也不会先刷新出未经确认的 UI 状态。Control API 在当前 macOS SDK 中从 macOS 26 起可用；macOS 13–15 仍只注册状态 Widget。

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

命令会等待异步 Agent 调用完成后再回复 Apple event。XPC timeout 返回 Apple event timeout (`-1712`),其余 Agent 调用失败返回 Apple event failed (`-10000`),并保留 Client 提供的恢复建议。

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
```

`status` 默认输出供人阅读的 `Locked` 或 `Unlocked`。自动化使用 `status --json`,其稳定 contract 是单行 `{"locked":true}` 或 `{"locked":false}`。两种状态都表示查询成功并返回 exit code `0`;参数或 Agent 调用失败返回 `1`,因此脚本不需要把 unlocked 与 transport failure 混在同一个 exit code 中。

不要把 `lock --no-wait` / `unlock` 当成 acquire/release pair：若调用 `lock --no-wait` 时全局状态本来已经 locked,后续无条件执行 `unlock` 会解除其他 wrapper 建立的锁。需要这种 ownership 语义时,应先在 Agent contract 中设计明确的 lease/session capability,而不是在 shell 中模拟。
