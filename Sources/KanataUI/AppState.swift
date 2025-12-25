import Foundation
import Observation

@Observable
final class AppState {
    var isRunning: Bool = false
    var kanataPID: Int?
}
