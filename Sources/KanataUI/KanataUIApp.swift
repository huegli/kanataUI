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
    @State private var showingDebugLog = false

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
                kanataManager: kanataManager,
                showDebugLog: { showingDebugLog = true }
            )
        } label: {
            // -----------------------------------------------------------------
            // SF SYMBOLS AND RENDERING MODES
            // -----------------------------------------------------------------
            // SF Symbols are Apple's system icons. They automatically adapt
            // to the current context (light/dark mode, size, weight).
            //
            // .symbolRenderingMode(.hierarchical) uses opacity variations
            // to create depth in multi-layer symbols.
            //
            // .opacity() modifies transparency. Here we use it to show
            // running (full opacity) vs stopped (50% opacity) state.
            // This is a common macOS menu bar pattern for status indication.
            // -----------------------------------------------------------------
            Image(systemName: "keyboard")
                .symbolRenderingMode(.hierarchical)
                .opacity(appState.isRunning ? 1.0 : 0.5)
        }

        // ---------------------------------------------------------------------
        // WINDOW SCENE
        // ---------------------------------------------------------------------
        // Window creates a standard macOS window. The `id` parameter allows
        // us to open it programmatically using `openWindow(id: "debug-log")`.
        //
        // .defaultSize() sets the initial window dimensions. Users can
        // resize it, but this is the starting size.
        // ---------------------------------------------------------------------
        Window("Debug Log", id: "debug-log") {
            DebugLogView()
        }
        .defaultSize(width: 600, height: 400)
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
    // The closure captures `manager` to ensure we have a reference to it
    // when the notification fires.
    // -------------------------------------------------------------------------
    private func setupTerminationHandler(manager: KanataManager) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,     // Observe from any sender
            queue: .main     // Handle on main thread (required for UI work)
        ) { _ in
            // Task { @MainActor in ... } ensures this runs on the main thread.
            // This is required because KanataManager is marked @MainActor.
            // See KanataManager.swift for explanation of @MainActor.
            Task { @MainActor in
                manager.cleanup()
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
    let showDebugLog: () -> Void  // A closure (function) with no params/return

    // -------------------------------------------------------------------------
    // @Environment PROPERTY WRAPPER
    // -------------------------------------------------------------------------
    // @Environment reads values from SwiftUI's environment system. The
    // environment is like a dependency injection container that flows down
    // through the view hierarchy.
    //
    // `\.openWindow` is a KEY PATH that identifies which environment value
    // to read. Key paths in Swift are type-safe references to properties.
    //
    // `openWindow` is an action that lets us open windows by their ID.
    // This is how we open the debug log window from a menu button.
    // -------------------------------------------------------------------------
    @Environment(\.openWindow) private var openWindow

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
        // BUTTON WITH CLOSURE ACTION
        // ---------------------------------------------------------------------
        // Button takes a label (text) and an action closure (what to do when
        // clicked). The trailing closure syntax puts the action outside the
        // parentheses for readability.
        //
        // The ternary operator (condition ? valueIfTrue : valueIfFalse)
        // switches the button text and action based on state.
        // ---------------------------------------------------------------------
        Button(appState.isRunning ? "Stop Kanata" : "Start Kanata") {
            if appState.isRunning {
                kanataManager?.stopKanata()
            } else {
                kanataManager?.startKanata()
            }
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

        Menu("Debug") {
            Button("Show Debug Log") {
                // Use the environment's openWindow action to open our window
                openWindow(id: "debug-log")
            }

            Button("Copy Debug Log") {
                // NSPasteboard is macOS's clipboard API
                // BEST PRACTICE: Always clearContents() before setting new data
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(DebugLog.shared.formattedLog, forType: .string)
            }

            Button("Show Kanata Log in Finder") {
                NSWorkspace.shared.selectFile(KanataManager.logFilePath, inFileViewerRootedAtPath: "")
            }
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

// =============================================================================
// DebugLogView - A WINDOW FOR VIEWING LOG OUTPUT
// =============================================================================
// This view is displayed in the debug log window. It demonstrates:
// - Timer-based updates with Combine's publish(every:)
// - Text selection and scrolling
// - Copy to clipboard functionality
// =============================================================================

struct DebugLogView: View {
    // @State for local mutable data that this view owns
    @State private var logText = ""

    // -------------------------------------------------------------------------
    // TIMER WITH COMBINE
    // -------------------------------------------------------------------------
    // Timer.publish creates a Combine publisher that emits values at intervals.
    // .autoconnect() starts it immediately. This is used to periodically
    // refresh the log display.
    //
    // ALTERNATIVE: For more complex cases, consider using .onChange() or
    // the Observation framework to react to actual data changes instead
    // of polling.
    // -------------------------------------------------------------------------
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        // VStack arranges children vertically
        // alignment: .leading aligns children to the left edge
        // spacing: 8 adds 8 points between children
        VStack(alignment: .leading, spacing: 8) {
            // HStack arranges children horizontally
            HStack {
                Text("Debug Log")
                    .font(.headline)

                // Spacer pushes subsequent items to the right
                Spacer()

                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logText, forType: .string)
                }

                Button("Clear") {
                    DebugLog.shared.clear()
                    logText = ""
                }
            }
            .padding(.horizontal)
            .padding(.top)

            // ScrollView allows content to scroll when it exceeds bounds
            ScrollView {
                Text(logText.isEmpty ? "(no log entries)" : logText)
                    .font(.system(.body, design: .monospaced))  // Fixed-width font
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)  // Allow selecting text
                    .padding()
            }
            // nsColor bridges to AppKit's NSColor for system colors
            .background(Color(nsColor: .textBackgroundColor))
        }
        // ---------------------------------------------------------------------
        // VIEW LIFECYCLE MODIFIERS
        // ---------------------------------------------------------------------
        // .onAppear runs code when the view first appears on screen.
        // Good for initial data loading.
        // ---------------------------------------------------------------------
        .onAppear {
            logText = DebugLog.shared.formattedLog
        }
        // ---------------------------------------------------------------------
        // .onReceive subscribes to a Combine publisher (our timer).
        // Each time the timer fires, this closure runs.
        // The `_` ignores the timer's output value (we don't need it).
        // ---------------------------------------------------------------------
        .onReceive(timer) { _ in
            logText = DebugLog.shared.formattedLog
        }
    }
}
