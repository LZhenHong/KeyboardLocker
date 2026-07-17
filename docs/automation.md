# 自动化

KeyboardLocker 的 Shortcuts、AppleScript 与 CLI 都是同一个 Agent capability 的薄 wrapper。首次使用任一入口前,先启动一次 KeyboardLocker App,让它注册后台 Agent。

所有入口共享以下语义：

- `lock` 与 `unlock` 是幂等的 desired-state action。
- `status` 每次都从 Agent 查询权威状态；wrapper 不维护本地副本。
- lock 是全局状态,不属于发起它的 Shortcut、AppleScript 或 shell process。任意入口的 `unlock` 都会解开同一个全局锁。
- 当前没有暴露 client-side `toggle`。需要确定结果时,显式选择 `lock` 或 `unlock`。
- Agent 不可达、权限不足或结果无法确认时,wrapper 会明确失败,不会把失败猜成 unlocked。

## Shortcuts

KeyboardLocker 提供三个可组合 action：

- `Lock Keyboard`
- `Unlock Keyboard`
- `Get Keyboard Lock Status`

`Get Keyboard Lock Status` 返回 typed Boolean,可直接接入 Shortcuts 的条件分支。当前版本没有声明 `AppShortcutsProvider`;这些 action 从 Shortcuts 的 action library 中选择,不会作为 promoted shortcut 自动出现,也没有预注册的 invocation phrase。

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
klock unlock
```

`status` 当前输出供人阅读的 `Locked` 或 `Unlocked`。在增加明确的 machine-readable output contract 前,脚本不要把这段文本当成稳定 JSON/API。所有命令在调用成功时返回 exit code `0`,参数或 Agent 调用失败时返回 `1`。

不要把 `lock --no-wait` / `unlock` 当成 acquire/release pair：若调用 `lock --no-wait` 时全局状态本来已经 locked,后续无条件执行 `unlock` 会解除其他 wrapper 建立的锁。需要这种 ownership 语义时,应先在 Agent contract 中设计明确的 lease/session capability,而不是在 shell 中模拟。
