import Foundation

@MainActor
protocol SystemDialogs {
    func showFatalAlert(title: String, message: String)
    func runPrivilegedScript(_ script: String) throws -> String
}
