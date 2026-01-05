// KanataUIApp.swift
// Main entry point for the Kanata UI macOS menu bar application.
//
// =============================================================================
// SWIFT & SWIFTUI CONCEPTS EXPLAINED
// =============================================================================
//
// This file demonstrates several key Swift and SwiftUI concepts:
//
// 1. SWIFTUI FRAMEWORK
//    SwiftUI is Apple's declarative UI framework. Instead of imperatively
//    creating UI elements (like "create button, set title, add to view"),
//    you declare what the UI should look like and SwiftUI handles the rest.
//
// 2. PROPERTY WRAPPERS (@State, @Environment)
//    Property wrappers add behavior to properties. The @ symbol indicates
//    a property wrapper. Common ones:
//    - @State: Holds mutable state that belongs to a view. When changed,
//              SwiftUI automatically re-renders the view.
//    - @Environment: Reads values from the SwiftUI environment (system-wide
//                    settings and actions like openWindow, colorScheme, etc.)
//
// 3. PROTOCOLS
//    Swift protocols are similar to interfaces in other languages. They define
//    a contract that conforming types must fulfill. `App` and `View` are
//    protocols that require a `body` property.
//
// 4. OPAQUE RETURN TYPES (some View, some Scene)
//    The `some` keyword means "a specific type that conforms to this protocol,
//    but I'm not telling you which one." This hides complex nested generic
//    types that SwiftUI creates when composing views.
//
// =============================================================================
// MACOS MENU BAR APP BEST PRACTICES
// =============================================================================
//
// - Use MenuBarExtra for menu bar-only apps (no dock icon)
// - Keep menu content simple and responsive
// - Use system SF Symbols for consistent iconography
// - Handle app termination gracefully (cleanup background processes)
// - Provide keyboard shortcuts for common actions (like Cmd+Q for quit)
//
// =============================================================================

import SwiftUI

// -----------------------------------------------------------------------------
// @main ATTRIBUTE
// -----------------------------------------------------------------------------
// The @main attribute marks this struct as the application's entry point.
// In traditional programming, you'd have a main() function. In SwiftUI,
// @main tells the compiler "start the app by instantiating this struct."
// There can only be one @main in your entire application.
// -----------------------------------------------------------------------------

@main
struct KanataUIApp: App {
    // -------------------------------------------------------------------------
    // @State PROPERTY WRAPPER
    // -------------------------------------------------------------------------
    // @State creates a source of truth for mutable data within a view/app.
    //
    // Key points:
    // - SwiftUI manages the storage behind the scenes
    // - When the value changes, SwiftUI automatically updates any views
    //   that read this state
    // - The underscore prefix (_appState) accesses the underlying State
    //   wrapper itself, used in init() for custom initialization
    // - `private` is a best practice: state should be owned by the view
    //   that declares it
    // -------------------------------------------------------------------------
    @State private var appState = AppState()
    @State private var kanataManager: KanataManager?

    // -------------------------------------------------------------------------
    // THE BODY PROPERTY (Required by App protocol)
    // -------------------------------------------------------------------------
    // The `body` property defines the app's structure. For macOS apps, this
    // returns one or more "Scenes" - top-level containers like windows or
    // menu bar extras.
    //
    // `some Scene` is an opaque return type - the compiler knows the exact
    // type, but we don't have to spell it out. This is necessary because
    // SwiftUI view/scene types can be extremely complex nested generics.
    //
    // This is a COMPUTED PROPERTY (no = sign, just a getter block).
    // SwiftUI calls this whenever it needs to rebuild the UI structure.
    // -------------------------------------------------------------------------
    var body: some Scene {
        // ---------------------------------------------------------------------
        // MenuBarExtra - MACOS-SPECIFIC SCENE TYPE
        // ---------------------------------------------------------------------
        // MenuBarExtra creates a menu bar app (icon in the top-right of the
        // screen). This is the standard pattern for utility apps that run
        // in the background.
        //
        // Parameters:
        // - First closure: The menu content (what appears when clicked)
        // - label: The icon shown in the menu bar
        //
        // BEST PRACTICE: Use SF Symbols (Apple's icon system) for menu bar
        // icons to match the system aesthetic. Access them with
        // Image(systemName: "symbol.name").
        // ---------------------------------------------------------------------
        MenuBarExtra {
            MenuContent(
                appState: appState,
                kanataManager: kanataManager
            )
        } label: {
            // -----------------------------------------------------------------
            // SF SYMBOLS FOR STATE INDICATION
            // -----------------------------------------------------------------
            // SF Symbols are Apple's system icons. They automatically adapt
            // to the current context (light/dark mode, size, weight).
            //
            // UPDATED (v1.0.1): Use DIFFERENT icons for active vs inactive.
            // Previously we used opacity to indicate state, but users reported
            // the difference was not noticeable enough in the menu bar.
            //
            // New approach:
            // - "keyboard.fill": Filled/solid icon when kanata is RUNNING
            // - "keyboard": Outline icon when kanata is STOPPED
            //
            // This creates a much more visible distinction between states.
            // The filled icon clearly signals "active/on" while the outline
            // suggests "inactive/off" - a common iOS/macOS design pattern.
            //
            // .symbolRenderingMode(.hierarchical) adds depth to multi-layer
            // symbols, though both keyboard variants are single-layer.
            // -----------------------------------------------------------------
            Image(systemName: appState.isRunning ? "keyboard.fill" : "keyboard")
                .symbolRenderingMode(.hierarchical)
        }

    }

    // -------------------------------------------------------------------------
    // CUSTOM INITIALIZER
    // -------------------------------------------------------------------------
    // Swift structs get an automatic memberwise initializer, but we need
    // custom initialization logic here to set up our dependencies.
    //
    // IMPORTANT: When using @State with custom init, you must use the
    // underscore prefix (_appState) to access the State wrapper itself
    // and use State(initialValue:) to set it.
    //
    // BEST PRACTICE: Initialize dependencies in init() rather than at
    // property declaration when they depend on each other.
    // -------------------------------------------------------------------------
    init() {
        // Create AppState first since KanataManager depends on it
        let state = AppState()
        _appState = State(initialValue: state)

        // Create the manager with all its dependencies
        // This demonstrates DEPENDENCY INJECTION - passing dependencies
        // into the initializer rather than creating them internally.
        // This makes the code more testable and flexible.
        let manager = KanataManager(
            appState: state,
            processLauncher: RealProcessLauncher(),
            systemDialogs: RealSystemDialogs()
        )
        _kanataManager = State(initialValue: manager)

        // Set up cleanup when the app terminates
        setupTerminationHandler(manager: manager)

        // Set up auto-start when the app finishes launching
        setupLaunchHandler(manager: manager)
    }

    // -------------------------------------------------------------------------
    // NOTIFICATION CENTER - OBSERVING SYSTEM EVENTS
    // -------------------------------------------------------------------------
    // NotificationCenter is the standard way to observe system events in
    // Apple platforms. Here we listen for app termination to clean up.
    //
    // BEST PRACTICE: Always clean up background processes when your app
    // terminates. Users expect that quitting your app stops everything
    // it started.
    //
    // IMPORTANT FIX (v1.0.1): The cleanup must run SYNCHRONOUSLY.
    // Previously, we used `Task { @MainActor in ... }` which schedules
    // the cleanup asynchronously. This caused a race condition where the
    // app could exit BEFORE the cleanup completed, leaving the kanata
    // process orphaned and running in the background.
    //
    // The fix uses MainActor.assumeIsolated() which:
    // 1. Asserts we're already on the main thread (we are, via queue: .main)
    // 2. Runs the closure synchronously, blocking until complete
    // 3. Ensures cleanup finishes BEFORE the app terminates
    //
    // WHY NOT USE DispatchQueue.main.sync?
    // DispatchQueue.main.sync would deadlock because we're already on main.
    // MainActor.assumeIsolated() is the Swift concurrency way to say
    // "I know I'm on the main actor, just run this code."
    // -------------------------------------------------------------------------
    private func setupTerminationHandler(manager: KanataManager) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,     // Observe from any sender
            queue: .main     // Handle on main thread (required for UI work)
        ) { _ in
            // CRITICAL: Run cleanup SYNCHRONOUSLY to ensure it completes
            // before the app exits. The previous async Task approach caused
            // the kanata process to remain running after app quit.
            //
            // MainActor.assumeIsolated() tells the compiler "I'm already on
            // the main actor, run this synchronously." This is safe because:
            // 1. We specified queue: .main in addObserver
            // 2. willTerminateNotification is always delivered on main thread
            MainActor.assumeIsolated {
                manager.cleanup()
            }
        }
    }

    // -------------------------------------------------------------------------
    // AUTO-START ON LAUNCH
    // -------------------------------------------------------------------------
    // Automatically start kanata when the app finishes launching.
    //
    // WHY USE didFinishLaunchingNotification INSTEAD OF init()?
    // - init() runs before the UI is fully set up
    // - The password prompt (osascript) can block the main thread
    // - If this happens before MenuBarExtra is ready, the icon won't appear
    //
    // By waiting for didFinishLaunchingNotification, we ensure:
    // 1. The MenuBarExtra is visible in the menu bar
    // 2. The app is fully initialized and ready for user interaction
    // 3. The password dialog appears on top of a properly set up app
    //
    // The flow is:
    // 1. Validate environment (binary and config exist)
    // 2. Validate config file syntax using `kanata --check`
    // 3. Prompt for password and launch kanata
    //
    // If any step fails, the app shows an alert and quits.
    // If the user cancels the password prompt, the app quits silently.
    // -------------------------------------------------------------------------
    private func setupLaunchHandler(manager: KanataManager) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                manager.startKanata()
            }
        }
    }
}

// =============================================================================
// MenuContent - THE DROPDOWN MENU VIEW
// =============================================================================
// This is a separate View struct that defines what appears when the user
// clicks the menu bar icon.
//
// BEST PRACTICE: Extract complex view hierarchies into separate structs.
// This improves:
// - Readability (smaller, focused components)
// - Reusability (can use the same view elsewhere)
// - Performance (SwiftUI can optimize updates better)
// - Testability (can preview/test components in isolation)
// =============================================================================

struct MenuContent: View {
    // -------------------------------------------------------------------------
    // PROPERTY TYPES IN SWIFTUI VIEWS
    // -------------------------------------------------------------------------
    // These are regular properties (not @State) because they're passed IN
    // from a parent view. They're the view's "inputs."
    //
    // - `let` means immutable - the view can't change these values
    // - The parent owns the actual state; we just read it
    // - When the parent's state changes, SwiftUI creates a new MenuContent
    //   with the updated values
    // -------------------------------------------------------------------------
    let appState: AppState
    let kanataManager: KanataManager?

    // -------------------------------------------------------------------------
    // APP VERSION - COMPUTED PROPERTY
    // -------------------------------------------------------------------------
    // Reads the version from the app's Info.plist bundle dictionary.
    // CFBundleShortVersionString is the standard macOS key for the
    // user-facing version number (e.g., "1.0.9").
    //
    // Bundle.main.infoDictionary contains all keys from Info.plist.
    // We use optional chaining (?[]) and nil coalescing (??) to safely
    // handle cases where the key doesn't exist (e.g., during development
    // without a full app bundle).
    //
    // BEST PRACTICE: Always provide a fallback for bundle values since
    // they may not be available in all execution contexts.
    // -------------------------------------------------------------------------
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.9"
    }

    // -------------------------------------------------------------------------
    // VIEW BODY - THE UI DECLARATION
    // -------------------------------------------------------------------------
    // This is where we declare what the view looks like. SwiftUI views
    // are VALUE TYPES (structs, not classes), which means:
    // - They're cheap to create and destroy
    // - SwiftUI frequently recreates them when state changes
    // - Don't store mutable state directly in properties (use @State)
    //
    // The body is called whenever SwiftUI needs to update the UI.
    // -------------------------------------------------------------------------
    var body: some View {
        // ---------------------------------------------------------------------
        // ABOUT SECTION
        // ---------------------------------------------------------------------
        // Display app name and version as the first menu item.
        // This follows macOS conventions where About info appears at the top.
        // Using .foregroundStyle(.secondary) dims the text to indicate it's
        // informational rather than an actionable item.
        // ---------------------------------------------------------------------
        Text("Kanata-UI v\(appVersion)")
            .foregroundStyle(.secondary)

        Divider()

        // Text view displaying the current status
        // String interpolation with \() works inside string literals
        Text("Kanata: \(appState.isRunning ? "Running" : "Stopped")")
            .foregroundStyle(.secondary)  // Dimmed text color

        // Conditional rendering with `if let` - only show PID if we have one
        // This is Swift's OPTIONAL BINDING - safely unwrapping optional values
        if let pid = appState.kanataPID {
            Text("PID: \(pid)")
                .foregroundStyle(.secondary)
                .font(.caption)  // Smaller font size
        }

        // Divider creates a horizontal line separator in menus
        Divider()

        // ---------------------------------------------------------------------
        // EDIT CONFIG BUTTON
        // ---------------------------------------------------------------------
        // Opens the kanata configuration file in TextEdit for editing.
        // Uses the same approach as the config error dialog - launch TextEdit
        // via the `open -a TextEdit` command.
        //
        // This allows users to quickly edit their config without navigating
        // to the file manually.
        // ---------------------------------------------------------------------
        Button("Edit Config") {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "TextEdit", KanataManager.kanataConfigPath]
            try? process.run()
        }

        // ---------------------------------------------------------------------
        // RELAUNCH BUTTON
        // ---------------------------------------------------------------------
        // Stops the currently running kanata process and relaunches it.
        // This is useful after editing the config file - the user can reload
        // the new configuration without manually stopping and starting.
        //
        // The relaunchKanata() method handles:
        // 1. Stopping the current process (if running)
        // 2. Re-validating the config (catches any new errors)
        // 3. Relaunching with the updated config
        // ---------------------------------------------------------------------
        Button("Relaunch") {
            kanataManager?.relaunchKanata()
        }

        Divider()

        // ---------------------------------------------------------------------
        // MENU - NESTED SUBMENUS
        // ---------------------------------------------------------------------
        // Menu creates a submenu with a disclosure arrow. Good for grouping
        // related but less frequently used options.
        //
        // BEST PRACTICE: Keep top-level menu items to essential actions.
        // Group secondary options in submenus to reduce visual clutter.
        // ---------------------------------------------------------------------
        Menu("Settings") {
            // Open macOS System Settings to specific privacy panes
            // The x-apple.systempreferences: URL scheme is macOS-specific
            Button("Open Input Monitoring Settings...") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Open Accessibility Settings...") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            // NSWorkspace.shared.selectFile reveals a file in Finder
            // This is a common macOS pattern for "show in Finder" functionality
            Button("Reveal Kanata Binary in Finder") {
                NSWorkspace.shared.selectFile(KanataManager.kanataBinaryPath, inFileViewerRootedAtPath: "")
            }

            Button("Reveal Config File in Finder") {
                NSWorkspace.shared.selectFile(KanataManager.kanataConfigPath, inFileViewerRootedAtPath: "")
            }
        }

        // ---------------------------------------------------------------------
        // VIEW DEBUG LOG - OPENS CONSOLE.APP
        // ---------------------------------------------------------------------
        // Opens Console.app with a predefined search filter for this app's
        // subsystem. This leverages macOS's unified logging system (os.log)
        // which automatically captures and persists all our log messages.
        //
        // The URL scheme "x-apple.systempreferences:" is for System Settings.
        // For Console.app, we use NSWorkspace to open the app directly.
        //
        // CONSOLE.APP TIPS FOR USERS:
        // - After opening, type "subsystem:com.nikolai.KanataUI" in search
        // - Enable "Include Info Messages" from the Action menu to see all logs
        // ---------------------------------------------------------------------
        Button("View Debug Log") {
            // Open Console.app - the standard macOS log viewer
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
        }

        Divider()

        // ---------------------------------------------------------------------
        // KEYBOARD SHORTCUTS
        // ---------------------------------------------------------------------
        // .keyboardShortcut() adds a keyboard shortcut to a button.
        // "q" with no modifiers defaults to Cmd+Q, the standard quit shortcut.
        //
        // BEST PRACTICE: Use standard macOS keyboard shortcuts for common
        // actions (Cmd+Q for quit, Cmd+W for close window, etc.)
        // ---------------------------------------------------------------------
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
