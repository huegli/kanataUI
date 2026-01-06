# Kanata-UI

## High Level Design Spec
The purpose of this application is to act as a UI interface to the kanata command line application. The kanata CLI is launched as a background process with the specified configuration file, running with sudo privileges.

## Initial Setup (One-Time)

For the best experience (no password prompts), complete these one-time setup steps:

### 1. Input Monitoring Permission
KanataUI needs Input Monitoring permission to allow kanata to access keyboard input.

1. Open **System Settings → Privacy & Security → Input Monitoring**
2. Click the **+** button and add **KanataUI.app**
3. Enable the checkbox next to KanataUI

### 2. Passwordless Sudo (Optional but Recommended)
To avoid password prompts on launch, relaunch, and quit:

```bash
sudo visudo -f /etc/sudoers.d/kanata
```

Add this line (replace `username` with your macOS username):
```
username ALL=(ALL) NOPASSWD: /opt/homebrew/bin/kanata, /bin/kill
```

Save and exit (`:wq` in vi).

**Why both commands?**
- `/opt/homebrew/bin/kanata` - for launching kanata with root privileges
- `/bin/kill` - for stopping the kanata process (which runs as root)

### 3. Verify Setup
```bash
# Test passwordless kanata launch
sudo -n /opt/homebrew/bin/kanata --help

# Test passwordless kill (should show usage, not password prompt)
sudo -n kill --help

# Both should work without asking for password
```

### Why These Permissions?
- **Input Monitoring**: Required for kanata to intercept and remap keyboard events
- **Passwordless sudo for kanata**: kanata needs root privileges to access raw keyboard input
- **Passwordless sudo for kill**: Since kanata runs as root, stopping it also requires root privileges

## UI Interface
Kanata-UI shall be a macOS menu bar application.

### Menu Bar Icon
- **Active state**: SF Symbol `keyboard.fill` (filled icon when kanata is running)
- **Inactive state**: SF Symbol `keyboard` (outline icon when kanata is not running)

### User Interactions
Standard macOS menu bar convention:
- **Left-click**: Show context menu
- **Right-click**: Show context menu (same behavior)

### Context Menu
- Status indicator (Running/Stopped with PID)
- Edit Config (safe config editing workflow - see below)
- Relaunch (stops kanata if running, then restarts with updated config)
- Settings submenu (system settings, reveal files in Finder)
- View Debug Log (opens Console.app)
- Quit option

### Edit Config Workflow
The Edit Config menu option provides a safe editing workflow that protects the original config until changes are validated:

1. Creates a temporary copy of the current config file
2. Opens TextEdit with the temporary copy
3. Waits for the user to close TextEdit
4. Validates the edited config using `kanata --check`
5. If validation passes:
   - Copies the edited config back to the original location
   - Automatically relaunches kanata with the new config
6. If validation fails:
   - Shows an alert with two options:
     - **Re-edit**: Opens TextEdit again with the temp file to fix errors
     - **Revert**: Discards changes and keeps the original config
   - This loop continues until validation passes or user chooses Revert

### Initial State
- The app automatically starts kanata on launch after validating the configuration file
- Config validation uses `kanata --check --cfg <config>` (does not require sudo)
- If validation passes:
  - With passwordless sudo configured: kanata starts silently
  - Without passwordless sudo: prompts for password, then launches kanata
- If validation fails, the user can choose to:
  - **Quit**: Exit the application
  - **Edit Config**: Open the config file in TextEdit for editing
  - **Recheck**: Re-run validation after making changes

### Quitting Behavior
- When the app quits, it must also terminate the kanata process (via SIGKILL)

## kanata Background Process

### Command
```
sudo /opt/homebrew/bin/kanata --cfg /Users/nikolai/dotfiles/kanata.kbd
```

### Configuration
- Config path is hardcoded to `/Users/nikolai/dotfiles/kanata.kbd`
- Log file: `~/Library/Logs/kanata-ui.log` (kanata's stdout/stderr output)

### Config Validation
- Before launching kanata, validate the config file using `kanata --check --cfg <config>`
- This runs without sudo (no keyboard access needed for validation)
- Validates config syntax before prompting for password (better UX)
- If validation fails, show an alert with three options:
  - **Recheck** (default): Re-run validation
  - **Edit Config**: Open config in TextEdit, then show alert again
  - **Quit**: Exit the application
- This loop continues until validation passes or user quits

### Authentication
The app uses a hybrid approach for privilege escalation (both launching and terminating kanata):

1. **Passwordless sudo (preferred)**: First tries `sudo -n` (non-interactive mode)
   - If the user has configured sudoers rules, no password prompt is shown
   - To enable, create `/etc/sudoers.d/kanata` with:
     ```
     username ALL=(ALL) NOPASSWD: /opt/homebrew/bin/kanata, /bin/kill
     ```

2. **osascript fallback**: If passwordless sudo fails, falls back to `osascript` with `do shell script "..." with administrator privileges` which prompts for password

### Process Termination
- Use SIGKILL for immediate, reliable termination when stopping kanata
- Note: SIGTERM was found to be ignored by kanata; SIGKILL cannot be caught or ignored

### Error Handling
Most error conditions are fatal (show alert and quit). Config validation errors are recoverable.

| Scenario | Behavior |
|----------|----------|
| Kanata binary missing | Alert, then quit |
| Config file missing | Alert, then quit |
| Config validation fails | Alert with Recheck/Edit/Quit options |
| Input Monitoring permission missing | Alert with instructions, then quit |
| Kanata process crashes | Alert, then quit |
| Launch failure | Alert, then quit |
| User cancels sudo prompt | Quit silently (no alert) |

## Implementation & Development
### Tech Stack
- Swift/SwiftUI (macOS only)
- Xcode Project
- macOS 26 (Tahoe)
### Development Cycle
- Each time you make a change, increase the the 3rd number in the version number. Do not increase the second or first number unless explicitly asked
- After each change, run the tests to ensure nothing has been broken and rebuild the application
- If successful, check in all changes with a meaningful commit message
- IMPORTANT: Update CLAUDE.md if the actual implementation no longer matches what is specified in CLAUDE.md

## Comments
- Add detailed comments to all the files that make up this project.
- Assume that the reader has some good general understanding of programing but is a beginner in Swift and not familiar with particular MacOS Application specific programming patterns and conventions like protocols, SwiftUI. 
- Highlight in particular best practices to use for MacOS App Development using Swift
- IMPORTANT: Keep the comments updated as you make changes to the code!!!

## Testing Strategy

### Approach: Hybrid (Unit Tests + Manual Checklist)

### Unit Tests
Abstract system interactions behind protocols to enable mocking:

```swift
// Process management
protocol ProcessLauncher {
    func launch(command: String) throws -> Int  // returns PID
    func terminate(pid: Int, signal: Int32) -> Bool
    func isProcessRunning(pid: Int) -> Bool
}

// UI dialogs
protocol SystemDialogs {
    func showFatalAlert(title: String, message: String)
    func showAlert(title: String, message: String)
    func showConfigErrorAlert(title: String, message: String, configPath: String) -> ConfigErrorAction
    func showEditConfigErrorAlert(title: String, message: String) -> EditConfigErrorAction
    func runPrivilegedScript(_ script: String) throws -> String
}

// Config validation (runs kanata --check)
protocol ConfigValidator {
    func validate(configPath: String) throws
}

// App termination
protocol AppTerminator {
    func terminate()
}
```

**Test coverage (19 tests in 2 suites):**

AppState Tests:
- Initial state (inactive, no PID)
- Transition to running state
- Transition back to stopped state

KanataManager Tests:
- Environment validation (binary exists, config exists, both missing cases)
- startKanata error handling (missing binary, missing config alerts)
- startKanata success (sets running state, stores PID)
- stopKanata (terminates process with SIGKILL, updates state)
- cleanup (stops kanata if running, no-op if not running)
- Config validation (shows error dialog when invalid, recheck flow, edit config flow)
- relaunchKanata (stops before restart, starts when not running, handles stop failure)
- Password cancellation (silent quit without error dialog)

### Manual Testing Checklist
Integration scenarios requiring real system interaction:

**With passwordless sudo configured:**
- [ ] App launches → validates config → kanata starts silently (no password prompt) → filled icon
- [ ] Relaunch → stops current process → validates config → restarts silently

**Without passwordless sudo (fallback):**
- [ ] App launches → validates config → prompts for password → kanata starts → filled icon
- [ ] Relaunch → stops current process → validates config → prompts for password → restarts
- [ ] Cancel password prompt on launch → app quits silently

**General:**
- [ ] Click menu bar icon → shows context menu with status, Edit Config, Relaunch, Settings, Quit
- [ ] Relaunch with invalid config → shows error dialog with Edit/Recheck/Quit options
- [ ] Kill kanata process externally → alert shown → app quits
- [ ] Start with missing kanata binary → alert → app quits
- [ ] Start with missing config file → alert → app quits
- [ ] Invalid config on launch → alert with 3 buttons → click Quit → app quits
- [ ] Invalid config on launch → click Edit Config → TextEdit opens → alert shown again
- [ ] Invalid config on launch → fix config externally → click Recheck → validation passes → continues
- [ ] Quit app while kanata running → kanata process terminated
- [ ] Missing Input Monitoring permission → IOHIDDeviceOpen error detected → alert with instructions → app quits

**Edit Config Workflow:**
- [ ] Edit Config → creates temp copy → TextEdit opens with temp file
- [ ] Close TextEdit with valid changes → config saved → kanata relaunched
- [ ] Close TextEdit with invalid changes → error alert with Re-edit/Revert options
- [ ] Click Re-edit → TextEdit opens again with temp file
- [ ] Click Revert → original config preserved → alert dismissed

## Future Improvements

> **Note:** These features are OUT OF SCOPE for the initial implementation. They are documented here for future reference only.

### Settings & Configuration
- **Configurable paths**: User-editable kanata binary and config file paths via a preferences window
- **Launch at login**: Option to start Kanata-UI automatically when macOS starts

### UX Enhancements
- **macOS notifications**: Use Notification Center for state changes instead of blocking alerts
