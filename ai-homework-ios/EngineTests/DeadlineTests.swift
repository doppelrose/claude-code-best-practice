import XCTest
@testable import HomeworkEngine

final class DeadlineTests: XCTestCase {
    func testFastSyncWorkReturnsValue() async {
        let value = await Deadline.compute(seconds: 2) { 21 * 2 }
        XCTAssertEqual(value, 42)
    }

    func testStuckSyncWorkIsAbandoned() async {
        let started = Date()
        let value: Int? = await Deadline.compute(seconds: 0.3) {
            // Имитация зависшего решателя.
            Thread.sleep(forTimeInterval: 3)
            return 1
        }
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testSlowAsyncOperationThrows() async {
        let started = Date()
        do {
            _ = try await Deadline.run(seconds: 0.3) { () async throws -> Int in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertTrue(error is Deadline.Exceeded)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testFastAsyncOperationReturns() async throws {
        let value = try await Deadline.run(seconds: 2) { () async throws -> String in "ok" }
        XCTAssertEqual(value, "ok")
    }
}
