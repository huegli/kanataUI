// AppState.swift
// Observable application state for the Kanata UI application.
//
// =============================================================================
// SWIFT OBSERVATION FRAMEWORK
// =============================================================================
//
// This file demonstrates Swift's modern Observation framework, introduced in
// iOS 17 / macOS 14 (2023). It replaces the older Combine-based approach
// (ObservableObject + @Published) with a simpler, more efficient system.
//
// KEY CONCEPTS:
//
// 1. @Observable MACRO
//    Macros are compile-time code transformations (new in Swift 5.9).
//    @Observable automatically generates the boilerplate needed to track
//    property access and notify observers when values change.
//
// 2. VALUE OBSERVATION
//    When a SwiftUI view reads a property from an @Observable object,
//    the framework automatically tracks that dependency. When the property
//    changes, ONLY views that actually read it will re-render.
//
//    This is more efficient than the old @Published approach, which would
//    notify ALL observers whenever ANY property changed.
//
// 3. REFERENCE TYPE (class)
//    @Observable requires a class (reference type), not a struct. This
//    allows the same instance to be shared across the app, with all
//    observers seeing the same state.
//
// =============================================================================
// BEST PRACTICES FOR APP STATE
// =============================================================================
//
// - Keep state classes focused and small
// - Use @Observable for shared mutable state
// - Use structs (value types) for immutable data models
// - Consider separating concerns: UI state vs. domain state
// - Mark classes as `final` when you don't need inheritance (performance)
//
// =============================================================================

import Foundation
import Observation  // Required for @Observable macro

// -----------------------------------------------------------------------------
// @Observable MACRO
// -----------------------------------------------------------------------------
// This macro transforms the class at compile time to add observation support.
// Behind the scenes, it:
// - Wraps each stored property with observation tracking
// - Generates a conformance to the Observable protocol
// - Adds methods for observers to register and receive updates
//
// You don't see this generated code, but it's what makes the "magic" work.
//
// COMPARISON TO OLD APPROACH:
// Old way (Combine-based):
//   class AppState: ObservableObject {
//       @Published var isRunning = false
//       @Published var kanataPID: Int?
//   }
//
// New way (Observation framework):
//   @Observable
//   class AppState {
//       var isRunning = false
//       var kanataPID: Int?
//   }
//
// The new approach is simpler and more performant.
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// FINAL KEYWORD
// -----------------------------------------------------------------------------
// `final` means this class cannot be subclassed. This is a BEST PRACTICE when
// you don't need inheritance because:
// - It communicates intent clearly
// - Enables compiler optimizations (static dispatch instead of dynamic)
// - Prevents accidental subclassing that could introduce bugs
// -----------------------------------------------------------------------------

@Observable
final class AppState {
    // -------------------------------------------------------------------------
    // STORED PROPERTIES
    // -------------------------------------------------------------------------
    // These are simple stored properties. The @Observable macro wraps them
    // to track when they're read and written.
    //
    // When you write `appState.isRunning = true`, the macro-generated code
    // notifies any SwiftUI views that are observing this property.
    // -------------------------------------------------------------------------

    /// Whether the kanata process is currently running.
    /// Used to:
    /// - Control menu bar icon opacity (full when running, dim when stopped)
    /// - Toggle button text between "Start" and "Stop"
    /// - Determine if cleanup is needed on app termination
    var isRunning: Bool = false

    /// The process ID (PID) of the running kanata process, or nil if not running.
    /// Used to:
    /// - Display the PID in the menu for debugging
    /// - Send signals (SIGTERM) to stop the process
    /// - Monitor if the process is still alive
    ///
    /// SWIFT OPTIONALS:
    /// The `?` makes this an Optional<Int>, meaning it can hold either an Int
    /// value OR nil (no value). This is Swift's way of handling the absence
    /// of a value safely, avoiding null pointer exceptions.
    ///
    /// To use an optional, you must unwrap it:
    /// - `if let pid = kanataPID { ... }` - conditional binding
    /// - `kanataPID ?? 0` - nil coalescing (provide default)
    /// - `kanataPID!` - force unwrap (crashes if nil - avoid!)
    var kanataPID: Int?
}
