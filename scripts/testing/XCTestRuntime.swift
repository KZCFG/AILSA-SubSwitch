// Minimal *executing* XCTest replacement for Command Line Tools-only machines.
// Assertions record failures; `run_offline_tests.sh` generates a main that
// instantiates each `XCTestCase` subclass and calls its `test*` methods.
// Not a substitute for `xcodebuild test`; it exists so the offline unit tests
// can actually run (not just type-check) without Xcode.
@_exported import Foundation

public enum XCTRuntime {
    nonisolated(unsafe) public static var currentTest = ""
    nonisolated(unsafe) public static var failures: [String] = []
    nonisolated(unsafe) public static var failedTests: Set<String> = []
    nonisolated(unsafe) public static var passed = 0
    nonisolated(unsafe) public static var skipped: [String] = []
    private static let lock = NSLock()

    public static func record(_ message: String, file: StaticString, line: UInt) {
        lock.lock(); defer { lock.unlock() }
        let text = "\(file):\(line): \(currentTest): \(message)"
        failures.append(text)
        failedTests.insert(currentTest)
        FileHandle.standardError.write(("  FAIL " + text + "\n").data(using: .utf8)!)
    }

    @MainActor
    public static func run(_ name: String, _ body: @MainActor () async throws -> Void) async {
        currentTest = name
        let before = failedTests.count
        if let filter = CommandLine.arguments.dropFirst().first, !filter.isEmpty, !name.contains(filter) { return }
        fflush(stdout)
        FileHandle.standardError.write(("RUN  " + name + "\n").data(using: .utf8)!)
        do { try await body() }
        catch let skip as XCTSkip { skipped.append(name + ": " + skip.message); print("SKIP \(name)"); return }
        catch { record("threw \(error)", file: #filePath, line: #line) }
        if failedTests.count == before { passed += 1 }
    }

    public static func summary() -> Int32 {
        print("\nSUMMARY \(passed) passed, \(failedTests.count) failed, \(skipped.count) skipped")
        for failure in failures { print("  " + failure) }
        for skip in skipped { print("  SKIP " + skip) }
        return failedTests.isEmpty ? 0 : 1
    }
}

open class XCTestCase {
    public init() {}
    open func setUp() {}
    open func setUpWithError() throws {}
    open func setUp() async throws {}
    open func tearDown() {}
    open func tearDownWithError() throws {}
    open func tearDown() async throws {}
    public var continueAfterFailure: Bool = true
    nonisolated(unsafe) private var teardownBlocks: [() async throws -> Void] = []

    public func expectation(description: String) -> XCTestExpectation { XCTestExpectation(description: description) }

    public func wait(for expectations: [XCTestExpectation], timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if expectations.allSatisfy(\.isSatisfied) { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        for expectation in expectations where !expectation.isSatisfied && !expectation.isInverted {
            XCTRuntime.record("expectation not fulfilled: \(expectation.expectationDescription)", file: file, line: line)
        }
        for expectation in expectations where expectation.isInverted && expectation.fulfillCount > 0 {
            XCTRuntime.record("inverted expectation fulfilled: \(expectation.expectationDescription)", file: file, line: line)
        }
    }

    public func fulfillment(of expectations: [XCTestExpectation], timeout: TimeInterval = 60, enforceOrder: Bool = false, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !expectations.allSatisfy(\.isSatisfied) {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        for expectation in expectations where !expectation.isSatisfied && !expectation.isInverted {
            XCTRuntime.record("expectation not fulfilled: \(expectation.expectationDescription)", file: file, line: line)
        }
    }

    public func addTeardownBlock(_ block: @escaping () -> Void) { teardownBlocks.append { block() } }
    public func addTeardownBlock(_ block: @Sendable @escaping () async throws -> Void) { teardownBlocks.append(block) }
    public func runTeardownBlocks() async {
        for block in teardownBlocks.reversed() { try? await block() }
        teardownBlocks.removeAll()
    }
    public func measure(_ block: () -> Void) { block() }
}

public final class XCTestExpectation: @unchecked Sendable {
    public let expectationDescription: String
    public var assertForOverFulfill = false
    public var isInverted = false
    public var expectedFulfillmentCount = 1
    private let lock = NSLock()
    private var count = 0
    public init(description: String) { expectationDescription = description }
    public func fulfill() { lock.lock(); count += 1; lock.unlock() }
    public var fulfillCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    public var isSatisfied: Bool { isInverted ? fulfillCount == 0 : fulfillCount >= expectedFulfillmentCount }
}

public struct XCTestError: Error {
    public enum Code { case timeoutWhileWaiting, failureWhileWaiting }
    public let code: Code
    public init(_ code: Code = .failureWhileWaiting) { self.code = code }
}

public struct XCTSkip: Error {
    public let message: String
    public init(_ message: String = "") { self.message = message }
}

private func evaluate<T>(_ expression: () throws -> T, file: StaticString, line: UInt) -> T? {
    do { return try expression() } catch { XCTRuntime.record("threw \(error)", file: file, line: line); return nil }
}
private func text(_ m: () -> String) -> String { let value = m(); return value.isEmpty ? "" : " - " + value }

public func XCTAssert(_ e: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(try e(), m(), file: file, line: line) }
public func XCTAssertTrue(_ e: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    if let v = evaluate(e, file: file, line: line), !v { XCTRuntime.record("XCTAssertTrue failed" + text(m), file: file, line: line) }
}
public func XCTAssertFalse(_ e: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    if let v = evaluate(e, file: file, line: line), v { XCTRuntime.record("XCTAssertFalse failed" + text(m), file: file, line: line) }
}
public func XCTAssertNil(_ e: @autoclosure () throws -> Any?, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    if let v = evaluate(e, file: file, line: line), let inner = v { XCTRuntime.record("XCTAssertNil failed: \(inner)" + text(m), file: file, line: line) }
}
public func XCTAssertNotNil(_ e: @autoclosure () throws -> Any?, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    if let v = evaluate(e, file: file, line: line), v == nil { XCTRuntime.record("XCTAssertNotNil failed" + text(m), file: file, line: line) }
}
public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let x = evaluate(a, file: file, line: line), let y = evaluate(b, file: file, line: line) else { return }
    if x != y { XCTRuntime.record("XCTAssertEqual failed: (\(x)) is not equal to (\(y))" + text(m), file: file, line: line) }
}
public func XCTAssertEqual<T: FloatingPoint>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, accuracy: T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let x = evaluate(a, file: file, line: line), let y = evaluate(b, file: file, line: line) else { return }
    if abs(x - y) > accuracy { XCTRuntime.record("XCTAssertEqual failed: (\(x)) is not equal to (\(y)) +/- \(accuracy)" + text(m), file: file, line: line) }
}
public func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let x = evaluate(a, file: file, line: line), let y = evaluate(b, file: file, line: line) else { return }
    if x == y { XCTRuntime.record("XCTAssertNotEqual failed: (\(x)) is equal to (\(y))" + text(m), file: file, line: line) }
}
public func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let x = evaluate(a, file: file, line: line), let y = evaluate(b, file: file, line: line) else { return }
    if !(x > y) { XCTRuntime.record("XCTAssertGreaterThan failed: (\(x)) is not greater than (\(y))" + text(m), file: file, line: line) }
}
public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let x = evaluate(a, file: file, line: line), let y = evaluate(b, file: file, line: line) else { return }
    if !(x >= y) { XCTRuntime.record("XCTAssertGreaterThanOrEqual failed: (\(x)) < (\(y))" + text(m), file: file, line: line) }
}
public func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let x = evaluate(a, file: file, line: line), let y = evaluate(b, file: file, line: line) else { return }
    if !(x < y) { XCTRuntime.record("XCTAssertLessThan failed: (\(x)) is not less than (\(y))" + text(m), file: file, line: line) }
}
public func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let x = evaluate(a, file: file, line: line), let y = evaluate(b, file: file, line: line) else { return }
    if !(x <= y) { XCTRuntime.record("XCTAssertLessThanOrEqual failed: (\(x)) > (\(y))" + text(m), file: file, line: line) }
}
public func XCTAssertThrowsError<T>(_ e: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {
    do { _ = try e(); XCTRuntime.record("XCTAssertThrowsError failed: did not throw" + text(m), file: file, line: line) } catch { handler(error) }
}
public func XCTAssertNoThrow<T>(_ e: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try e() } catch { XCTRuntime.record("XCTAssertNoThrow failed: threw \(error)" + text(m), file: file, line: line) }
}
public func XCTFail(_ m: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTRuntime.record("XCTFail" + (m.isEmpty ? "" : " - " + m), file: file, line: line) }
public func XCTUnwrap<T>(_ e: @autoclosure () throws -> T?, _ m: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) throws -> T {
    if let v = try e() { return v }
    XCTRuntime.record("XCTUnwrap failed: nil" + text(m), file: file, line: line)
    throw XCTestError()
}
