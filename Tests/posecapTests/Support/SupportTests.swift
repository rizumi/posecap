import XCTest
@testable import posecap

final class SupportTests: XCTestCase {
    func testSubprocessTimeoutAndLargeOutputDoNotDeadlock() throws {
        let runner = ProcessRunner(cancellation: Cancellation())
        let started = Date()
        XCTAssertThrowsError(try runner.run("/bin/sleep", ["3"], timeout: 0.05))
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        let result = try runner.run("/usr/bin/head", ["-c", "200000", "/dev/zero"], timeout: 3)
        XCTAssertEqual(result.stdout.count, 200000)
    }
}
