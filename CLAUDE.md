# Kanata-UI

## High Level Design Spec
The purpose of this application is to act as a UI interface to the kanata command line application. The kanata CLI is launched as a background process with the specified configuration file, running with sudo privileges.

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
- Edit Config (opens config file in TextEdit)
- Relaunch (stops kanata if running, then restarts with updated config)
- Settings submenu (system settings, reveal files in Finder)
- View Debug Log (opens Console.app)
- Quit option

### Initial State
- The app automatically starts kanata on launch after validating the configuration file
- Config validation uses `kanata --check --cfg <config>` (does not require sudo)
- If validation passes, the app prompts for password and launches kanata
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
- Use `osascript` with `do shell script "..." with administrator privileges` to prompt for sudo password

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
protocol ProcessLauncher {
    func launch(command: String) throws -> Int  // returns PID
    func terminate(pid: Int, signal: Int32)
}

protocol SystemDialogs {
    func showAlert(message: String)
}
```

Test coverage:
- State transitions (inactive → active, active → inactive)
- Error handling logic
- Process lifecycle management (with mocked launcher)

### Manual Testing Checklist
Integration scenarios requiring real system interaction:

- [ ] App launches → validates config → prompts for password → kanata starts → filled icon
- [ ] Click menu bar icon → shows context menu with status, Edit Config, Relaunch, Settings, Quit
- [ ] Edit Config → TextEdit opens with config file
- [ ] Relaunch → stops current process → validates config → prompts for password → restarts
- [ ] Relaunch with invalid config → shows error dialog with Edit/Recheck/Quit options
- [ ] Cancel password prompt on launch → app quits silently
- [ ] Kill kanata process externally → alert shown → app quits
- [ ] Start with missing kanata binary → alert → app quits
- [ ] Start with missing config file → alert → app quits
- [ ] Invalid config on launch → alert with 3 buttons → click Quit → app quits
- [ ] Invalid config → click Edit Config → TextEdit opens → alert shown again
- [ ] Invalid config → fix config externally → click Recheck → validation passes → continues
- [ ] Quit app while kanata running → kanata process terminated

## Future Improvements

> **Note:** These features are OUT OF SCOPE for the initial implementation. They are documented here for future reference only.

### Settings & Configuration
- **Configurable paths**: User-editable kanata binary and config file paths via a preferences window
- **Launch at login**: Option to start Kanata-UI automatically when macOS starts

### UX Enhancements
- **macOS notifications**: Use Notification Center for state changes instead of blocking alerts
