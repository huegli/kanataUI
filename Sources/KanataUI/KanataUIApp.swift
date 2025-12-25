import SwiftUI

@main
struct KanataUIApp: App {
    @State private var appState = AppState()
    @State private var kanataManager: KanataManager?

    var body: some Scene {
        MenuBarExtra {
            MenuContent(appState: appState, kanataManager: kanataManager)
        } label: {
            Image(systemName: "keyboard")
                .symbolRenderingMode(.hierarchical)
                .opacity(appState.isRunning ? 1.0 : 0.5)
        }
    }

    init() {
        let state = AppState()
        _appState = State(initialValue: state)

        let manager = KanataManager(
            appState: state,
            processLauncher: RealProcessLauncher(),
            systemDialogs: RealSystemDialogs()
        )
        _kanataManager = State(initialValue: manager)

        setupTerminationHandler(manager: manager)
    }

    private func setupTerminationHandler(manager: KanataManager) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                manager.cleanup()
            }
        }
    }
}

struct MenuContent: View {
    let appState: AppState
    let kanataManager: KanataManager?

    var body: some View {
        Text("Kanata: \(appState.isRunning ? "Running" : "Stopped")")
            .foregroundStyle(.secondary)

        Divider()

        Button(appState.isRunning ? "Stop Kanata" : "Start Kanata") {
            if appState.isRunning {
                kanataManager?.stopKanata()
            } else {
                kanataManager?.startKanata()
            }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
