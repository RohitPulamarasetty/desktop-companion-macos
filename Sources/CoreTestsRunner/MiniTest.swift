import Foundation

/// A minimal, dependency-free test harness. This project's build machine has
/// only the Xcode Command Line Tools installed (no Xcode.app), and both
/// XCTest and swift-testing require Xcode.app's platform SDKs — neither
/// module is available here. Rather than pull in a multi-GB Xcode install
/// just to run unit tests, this tiny runner provides the same assertion
/// vocabulary and reports PASS/FAIL per test plus a summary, exiting
/// non-zero on any failure so it composes into any future CI step.
struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

final class TestRunner {
    private(set) var passed = 0
    private(set) var failed = 0

    func run(_ name: String, _ block: () throws -> Void) {
        do {
            try block()
            passed += 1
            print("PASS  \(name)")
        } catch {
            failed += 1
            print("FAIL  \(name): \(error)")
        }
    }

    /// Prints the final tally and returns true iff everything passed.
    func summarize() -> Bool {
        print(String(repeating: "-", count: 40))
        print("\(passed) passed, \(failed) failed")
        return failed == 0
    }
}

func expectTrue(_ condition: Bool, _ message: String = "expected true", file: String = #file, line: Int = #line) throws {
    if !condition { throw TestFailure(message: "\(message) [\(file):\(line)]") }
}

func expectFalse(_ condition: Bool, _ message: String = "expected false", file: String = #file, line: Int = #line) throws {
    if condition { throw TestFailure(message: "\(message) [\(file):\(line)]") }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) throws {
    if a != b { throw TestFailure(message: "expected \(a) == \(b) [\(file):\(line)]") }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) throws {
    if a != b { throw TestFailure(message: "\(message): expected \(a) == \(b) [\(file):\(line)]") }
}

func expectNotNil<T>(_ value: T?, file: String = #file, line: Int = #line) throws {
    if value == nil { throw TestFailure(message: "expected non-nil value [\(file):\(line)]") }
}

func expectNil<T>(_ value: T?, file: String = #file, line: Int = #line) throws {
    if value != nil { throw TestFailure(message: "expected nil, got \(String(describing: value)) [\(file):\(line)]") }
}

func expectNotEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) throws {
    if a == b { throw TestFailure(message: "expected \(a) != \(b) [\(file):\(line)]") }
}

func expectNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) throws {
    if a == b { throw TestFailure(message: "\(message): expected \(a) != \(b) [\(file):\(line)]") }
}

func fail(_ message: String, file: String = #file, line: Int = #line) throws -> Never {
    throw TestFailure(message: "\(message) [\(file):\(line)]")
}
