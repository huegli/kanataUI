import Testing
@testable import KanataUI

@Suite("AppState Tests")
struct AppStateTests {

    @Test("AppState initializes with inactive state")
    func initialState() {
        let state = AppState()

        #expect(!state.isRunning)
        #expect(state.kanataPID == nil)
    }

    @Test("AppState can transition to running")
    func transitionToRunning() {
        let state = AppState()

        state.isRunning = true
        state.kanataPID = 12345

        #expect(state.isRunning)
        #expect(state.kanataPID == 12345)
    }

    @Test("AppState can transition back to stopped")
    func transitionToStopped() {
        let state = AppState()
        state.isRunning = true
        state.kanataPID = 12345

        state.isRunning = false
        state.kanataPID = nil

        #expect(!state.isRunning)
        #expect(state.kanataPID == nil)
    }
}
