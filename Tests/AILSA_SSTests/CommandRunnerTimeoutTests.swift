import XCTest
@testable import AILSA_SS

final class CommandRunnerTimeoutTests: XCTestCase {
    func testRunDrainsStdoutAndStderrLargerThanObservedPsOutput() throws {
        // A production `ps -ax -o pid=,command=` returned 271,140 bytes.
        // Each stream below is larger than that and both run concurrently.
        let streamBytes = 300_000
        let result = try CommandRunner.run(
            "/bin/sh",
            arguments: [
                "-c",
                "yes x | head -c \(streamBytes) & yes y | head -c \(streamBytes) >&2 & wait"
            ],
            timeout: 5
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.utf8.count, streamBytes)
        XCTAssertEqual(result.stderr.utf8.count, streamBytes)
    }

    func testRunTimeoutThrowsAndReturnsPromptly() {
        let start = Date()

        XCTAssertThrowsError(
            try CommandRunner.run(
                "/bin/sh",
                arguments: ["-c", "sleep 5"],
                timeout: 1
            )
        ) { error in
            guard case let AppError.io(message) = error else {
                return XCTFail("Expected AppError.io, got: \(error)")
            }
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(message.contains("sleep 5"))
        }

        XCTAssertLessThan(Date().timeIntervalSince(start), 4.0)
    }
}
