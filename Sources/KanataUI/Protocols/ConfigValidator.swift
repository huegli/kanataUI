// ConfigValidator.swift
// Protocol for validating kanata configuration files.
//
// =============================================================================
// WHY ABSTRACT CONFIG VALIDATION?
// =============================================================================
//
// Config validation runs the `kanata --check` command to verify the config
// file syntax. This is a real system operation that:
// - Requires the kanata binary to exist
// - Spawns a subprocess
// - Takes time to execute
//
// By abstracting this behind a protocol, we can:
// - Test config validation error handling without the real binary
// - Simulate various validation outcomes (success, failure, different errors)
// - Speed up tests by avoiding real process spawning
//
// =============================================================================

import Foundation

// -----------------------------------------------------------------------------
// PROTOCOL DEFINITION
// -----------------------------------------------------------------------------

/// Protocol for validating kanata configuration files.
///
/// This abstraction allows unit tests to mock validation results without
/// running the actual kanata binary.
@MainActor
protocol ConfigValidator {
    /// Validates a kanata configuration file.
    ///
    /// - Parameter configPath: Path to the config file to validate
    /// - Throws: KanataError.configInvalid if validation fails
    func validate(configPath: String) throws
}

// -----------------------------------------------------------------------------
// REAL IMPLEMENTATION
// -----------------------------------------------------------------------------

/// Production implementation that runs `kanata --check` to validate configs.
@MainActor
final class RealConfigValidator: ConfigValidator {

    /// Path to the kanata binary
    private let binaryPath: String

    /// Initialize with the path to the kanata binary.
    /// - Parameter binaryPath: Path to the kanata executable
    init(binaryPath: String = KanataManager.kanataBinaryPath) {
        self.binaryPath = binaryPath
    }

    /// Validates the config by running `kanata --check --cfg <path>`.
    ///
    /// This runs without sudo because validation doesn't access keyboard hardware.
    /// It only parses and validates the config file syntax.
    ///
    /// - Parameter configPath: Path to the config file
    /// - Throws: KanataError.configInvalid if validation fails
    func validate(configPath: String) throws {
        DebugLog.shared.log("Validating config file...")

        // Build the validation command
        let command = "\(binaryPath) --check --cfg \(configPath)"
        DebugLog.shared.log("Validation command: \(command)")

        // Create a Process to run the validation
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        // Capture both stdout and stderr
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            // Read output for logging
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: outputData, encoding: .utf8) ?? ""
            let stderr = String(data: errorData, encoding: .utf8) ?? ""

            // terminationStatus 0 means success
            if process.terminationStatus == 0 {
                DebugLog.shared.log("Config validation: OK")
                return
            }

            // Validation failed - combine output for error message
            let errorOutput = stderr.isEmpty ? stdout : stderr
            DebugLog.shared.log("Config validation failed:\n\(errorOutput)", level: .error)
            throw KanataError.configInvalid(errorOutput)
        } catch let error as KanataError {
            throw error
        } catch {
            DebugLog.shared.log("Config validation process error: \(error)", level: .error)
            throw KanataError.configInvalid("Failed to run validation: \(error.localizedDescription)")
        }
    }
}
