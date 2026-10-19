import XCTest
@testable import posecap

final class CaptureStoreTests: XCTestCase {
    func testTimestampCollisionCreatesSeparateDirectories() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 0)
        let first = try CaptureStore(root: root.path, now: now)
        let second = try CaptureStore(root: root.path, now: now)
        XCTAssertEqual(first.captureID, "19700101T000000Z")
        XCTAssertEqual(second.captureID, "19700101T000000Z-1")
        XCTAssertNotEqual(first.directory, second.directory)
    }

    func testDirectRecaptureReplacesManifestAndOnlyReportsCurrentImages() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Home #1")
        let store = try CaptureStore(root: folder.path, direct: true)
        XCTAssertEqual(store.directory.standardizedFileURL, folder.standardizedFileURL)
        let runner = FakeRunner()
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: FakeController(), cancellation: Cancellation(), settleSeconds: 0)
        let first = Condition(posture: .closed, orientation: .portrait)
        let second = Condition(posture: .open, orientation: .portrait)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [first, second], label: "Old", store: store, environment: [:]), 0)
        let keep = folder.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: keep)
        let image = folder.appendingPathComponent("closed-portrait-display-17.png")
        try Data("old content".utf8).write(to: image)
        let again = try CaptureStore(root: folder.path, direct: true)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [first], label: "New", store: again, environment: [:]), 0)
        XCTAssertNotEqual(try Data(contentsOf: image), Data("old content".utf8))
        XCTAssertEqual(try readManifest(again).results.count, 1)
        XCTAssertEqual(try String(contentsOf: keep, encoding: .utf8), "keep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("open-portrait-display-17.png").path))
        let html = try String(contentsOf: Report.generate(input: folder.path), encoding: .utf8)
        XCTAssertTrue(html.contains("src=\"closed-portrait-display-17.png\""))
        XCTAssertFalse(html.contains("open-portrait-display-17.png"))
        XCTAssertFalse(html.contains("<h2>Old</h2>"))
        let parentHTML = try String(contentsOf: Report.generate(input: root.path), encoding: .utf8)
        XCTAssertTrue(parentHTML.contains("Home%20%231/closed-portrait-display-17.png"))

        runner.failScreenshot = runner.screenshotCount + 1
        XCTAssertEqual(try engine.capture(device: device(), conditions: [first], label: "Failed", store: again, environment: [:]), 1)
        let failedHTML = try String(contentsOf: Report.generate(input: folder.path), encoding: .utf8)
        XCTAssertFalse(failedHTML.contains("src=\"closed-portrait-display-17.png\""))
    }

    func testInvalidImageAndSymlinkDoNotReplaceExistingData() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path, direct: true)
        let condition = Condition(orientation: .portrait)
        let file = root.appendingPathComponent("portrait-display-42.png")
        let original = Data("original".utf8)
        try original.write(to: file)
        XCTAssertThrowsError(try store.image(condition: condition, display: reportDisplays()[0]) { try Data("invalid PNG".utf8).write(to: $0) })
        XCTAssertEqual(try Data(contentsOf: file), original)
        try FileManager.default.removeItem(at: file)
        let target = root.appendingPathComponent("target")
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        XCTAssertThrowsError(try store.image(condition: condition, display: reportDisplays()[0]) { _ in XCTFail("Must reject symlink before capture") })
        XCTAssertEqual(try Data(contentsOf: target), original)
    }
}
