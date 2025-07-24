# KeyboardLocker URL Schemes Guide

KeyboardLocker now supports external control through URL Schemes, allowing other applications, scripts, or system automation tools to remotely control keyboard locking functionality.

## Supported URL Commands

### Basic Syntax
```
keyboardlocker://<command>
```

### Available Commands

#### 1. Lock Keyboard
```bash
open "keyboardlocker://lock"
```
- **Function**: Lock keyboard input
- **Response**: Shows "Keyboard locked" on success, "Locked" if already locked
- **Error**: Shows "Failed to lock keyboard. Please check accessibility permissions." if insufficient permissions

#### 2. Unlock Keyboard
```bash
open "keyboardlocker://unlock"
```
- **Function**: Unlock keyboard input
- **Response**: Shows "Keyboard unlocked" on success, "Unlocked" if already unlocked
- **Error**: Shows "Failed to unlock keyboard" on failure

#### 3. Toggle Lock State
```bash
open "keyboardlocker://toggle"
```
- **Function**: Automatically toggle keyboard lock state (locked ↔ unlocked)
- **Response**: Shows corresponding lock or unlock message based on toggle result

#### 4. Get Current Status
```bash
open "keyboardlocker://status"
```
- **Function**: Query current keyboard lock status
- **Response**: "Locked" or "Unlocked"

## Error Handling

### Common Errors
- **Invalid URL scheme**: "Invalid URL scheme. Expected 'keyboardlocker'"
- **Missing command**: "Missing command in URL"
- **Unknown command**: "Unknown command: xxx. Supported commands: lock, unlock, toggle, status"
- **Manager unavailable**: "Keyboard lock manager not available"

## Integration Examples

### Using in AppleScript
```applescript
-- Lock keyboard
do shell script "open 'keyboardlocker://lock'"

-- Unlock keyboard
do shell script "open 'keyboardlocker://unlock'"

-- Get status
do shell script "open 'keyboardlocker://status'"
```

### Using in Shell Scripts
```bash
#!/bin/bash

# Lock keyboard and wait
open "keyboardlocker://lock"
sleep 1

# Perform operations that need to prevent keyboard interference
echo "Performing critical operations..."
sleep 5

# Unlock keyboard
open "keyboardlocker://unlock"
```

### Using in Python
```python
import subprocess
import time

def control_keyboard(command):
    """Control keyboard lock state"""
    url = f"keyboardlocker://{command}"
    subprocess.run(["open", url])

# Usage example
control_keyboard("lock")
time.sleep(5)
control_keyboard("unlock")
```

## Automation Tool Integration

### Shortcuts (Shortcuts App)
You can create shortcuts in the macOS Shortcuts app:
1. Add "Run Shell Script" action
2. Enter command: `open "keyboardlocker://lock"`
3. Save as shortcut

### Alfred Workflow
Create an Alfred Workflow for quick control:
```bash
# Alfred Script Filter
open "keyboardlocker://toggle"
```

### Keyboard Maestro
Create a macro in Keyboard Maestro:
1. Add "Execute Shell Script" action
2. Enter: `open "keyboardlocker://lock"`

## Important Notes

1. **Permission Requirements**: KeyboardLocker requires accessibility permissions to function properly
2. **Application State**: Ensure KeyboardLocker application is running
3. **Response Delay**: URL commands may have slight delays; consider adding appropriate wait times in scripts
4. **Error Checking**: Recommended to check command execution results in automation scripts

## Logging and Debugging

URL command execution is logged to the console. You can view logs through:
```bash
# View KeyboardLocker logs
log stream --predicate 'subsystem == "io.lzhlovesjyq.KeyboardLocker"'
```

Or open the Console.app application to view detailed logs.
