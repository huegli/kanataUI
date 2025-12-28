// AppStateTests.swift
// Unit tests for the AppState class.
//
// =============================================================================
// SWIFT TESTING FRAMEWORK
// =============================================================================
//
// This file uses Swift Testing, Apple's modern testing framework (2024+).
// It replaces XCTest with a more concise, expressive syntax.
//
// KEY DIFFERENCES FROM XCTEST:
//
// | XCTest                          | Swift Testing               |
// |---------------------------------|-----------------------------|
// | class SomeTests: XCTestCase     | struct SomeTests            |
// | func testSomething()            | @Test func something()      |
// | XCTAssertEqual(a, b)            | #expect(a == b)             |
// | XCTAssertTrue(condition)        | #expect(condition)          |
// | XCTAssertThrows                 | #expect(throws:)            |
//
// Swift Testing advantages:
// - Struct-based (no class inheritance needed)
// - Cleaner syntax with @Test and #expect macros
// - Better error messages
// - Parameterized tests with @Test(arguments:)
// - Test organization with @Suite
//
// =============================================================================
// TEST ORGANIZATION
// =============================================================================
//
// NAMING CONVENTION:
// Tests are typically named to describe what they verify:
// - "AppState initializes with inactive state"
// - "AppState can transition to running"
//
// The @Suite attribute groups related tests and provides a display name.
//
// =============================================================================

import Testing
@testable import KanataUI

// -----------------------------------------------------------------------------
// @Suite - TEST GROUPING
// -----------------------------------------------------------------------------
// @Suite groups related tests together. The string parameter is a display
// name shown in test results. Suites can be nested for organization.
//
// Using a struct (not class) is the Swift Testing convention. Structs are
// simpler and tests don't need shared mutable state.
// -----------------------------------------------------------------------------

@Suite("AppState Tests")
struct AppStateTests {

    // -------------------------------------------------------------------------
    // @Test - INDIVIDUAL TEST CASES
    // -------------------------------------------------------------------------
    // @Test marks a function as a test. The string parameter is a description
    // shown in test results (more readable than the function name).
    //
    // Tests should be:
    // - FAST: No slow operations (network, disk)
    // - ISOLATED: No dependencies on other tests
    // - REPEATABLE: Same result every time
    // - SELF-VALIDATING: Clear pass/fail (via #expect)
    // -------------------------------------------------------------------------

    @Test("AppState initializes with inactive state")
    func initialState() {
        // ARRANGE: Create the object under test
        let state = AppState()

        // ASSERT: Verify initial state
        // #expect is a macro that checks a boolean condition
        // If false, the test fails with a helpful error message
        #expect(!state.isRunning)  // Should NOT be running
        #expect(state.kanataPID == nil)  // Should have no PID
    }

    @Test("AppState can transition to running")
    func transitionToRunning() {
        // ARRANGE
        let state = AppState()

        // ACT: Modify the state
        state.isRunning = true
        state.kanataPID = 12345

        // ASSERT: Verify the new state
        #expect(state.isRunning)
        #expect(state.kanataPID == 12345)
    }

    @Test("AppState can transition back to stopped")
    func transitionToStopped() {
        // ARRANGE: Start with a running state
        let state = AppState()
        state.isRunning = true
        state.kanataPID = 12345

        // ACT: Transition back to stopped
        state.isRunning = false
        state.kanataPID = nil

        // ASSERT
        #expect(!state.isRunning)
        #expect(state.kanataPID == nil)
    }
}
