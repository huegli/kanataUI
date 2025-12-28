# Kanata-UI

## High Level Design Spec
The purpose of this application is to act as a UI interface to the kanata command line application. The kanata CLI is launched as a background process with the specified configuration file, running with sudo privileges.

## UI Interface
Kanata-UI shall be a macOS menu bar application.

### Menu Bar Icon
- **Active state**: SF Symbol `keyboard` (when kanata is running)
- **Inactive state**: SF Symbol `keyboard` with reduced opacity (when kanata is not running)

### User Interactions
Standard macOS menu bar convention:
- **Left-click**: Show context menu
- **Right-click**: Show context menu (same behavior)

### Context Menu
- Status indicator (Running/Stopped)
- Toggle option (Start Kanata / Stop Kanata)
- Quit option

### Initial State
- The app always starts in the inactive state on launch

### Quitting Behavior
- When the app quits, it must also terminate the kanata process (via SIGTERM)

## kanata Background Process

### Command
```
sudo /opt/homebrew/bin/kanata --cfg /Users/nikolai/dotfiles/kanata.kbd
```

### Configuration
- Config path is hardcoded to `/Users/nikolai/dotfiles/kanata.kbd`

### Authentication
- Use `osascript` with `do shell script "..." with administrator privileges` to prompt for sudo password

### Process Termination
- Use SIGTERM for graceful shutdown when stopping kanata

### Error Handling
All error conditions are fatal - show alert and quit the application:

| Scenario | Behavior |
|----------|----------|
| Kanata binary missing | Alert, then quit |
| Config file missing | Alert, then quit |
| Kanata process crashes | Alert, then quit |
| Launch failure | Alert, then quit |
| User cancels sudo prompt | Quit silently (no alert) |

## Implementation & Development
- Swift/SwiftUI (macOS only)
- Xcode Project
- macOS 26 (Tahoe)

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

- [ ] App launches in inactive state (reduced opacity icon)
- [ ] Click menu bar icon → shows context menu with status, toggle, quit
- [ ] Start Kanata → prompts for password → icon becomes full opacity
- [ ] Cancel password prompt → app quits silently
- [ ] Stop Kanata → SIGTERM sent → icon returns to reduced opacity
- [ ] Kill kanata process externally → alert shown → app quits
- [ ] Start with missing kanata binary → alert → app quits
- [ ] Start with missing config file → alert → app quits
- [ ] Quit app while kanata running → kanata process terminated

## Future Improvements

> **Note:** These features are OUT OF SCOPE for the initial implementation. They are documented here for future reference only.

### Settings & Configuration
- **Configurable paths**: User-editable kanata binary and config file paths via a preferences window
- **Launch at login**: Option to start Kanata-UI automatically when macOS starts
- **Auto-start kanata**: Option to automatically start kanata when the app launches

### Multiple Configurations
- Support for multiple kanata config files
- Quick-switch between configurations from the menu
- Remember last-used configuration

### Monitoring & Debugging
- **Log viewer**: Window to display kanata stdout/stderr output
- **Config validation**: Check config file syntax before launching kanata

### UX Enhancements
- **Global keyboard shortcut**: System-wide hotkey to toggle kanata on/off
- **macOS notifications**: Use Notification Center for state changes instead of blocking alerts
- **Touch Bar support**: Quick toggle button for MacBooks with Touch Bar
