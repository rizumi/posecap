import XCTest
@testable import posecap

final class CaptureTests: XCTestCase {
    func testMatrixDefaultsAndFiltering() throws {
        let defaults = CapturePlan()
        XCTAssertEqual(try defaults.conditions(for: device()).map(\.title), [
            "closed / portrait", "closed / landscape", "half-open / portrait", "half-open / landscape", "open / portrait", "open / landscape",
        ])
        XCTAssertEqual(try CapturePlan(orientation: .portrait).conditions(for: device()).count, 3)
        XCTAssertEqual(try CapturePlan(posture: .closed, orientation: .landscape).conditions(for: device()).count, 1)
        let phone = device(model: "iPhone 18 Pro")
        XCTAssertEqual(try defaults.conditions(for: phone).count, 2)
        XCTAssertThrowsError(try CapturePlan(posture: .open).conditions(for: phone))
    }

    func testCaptureSucceedsWithoutReadbackButRejectsKnownMismatch() {
        var evidence = Observations()
        evidence.activeDisplayID = "17"
        evidence.guiTargetMatched = true
        evidence.dispatchedControls = ["Open"]
        evidence.guiPostureSelection = "Open"
        let condition = Condition(posture: .open, orientation: .portrait)
        XCTAssertEqual(Assessment.evaluate(condition, observations: evidence, imageCount: 1, failed: false), .captured)
        XCTAssertEqual(Assessment.evaluate(condition, observations: evidence, imageCount: 0, failed: false), .failed)
        evidence.observedPosture = .closed
        XCTAssertEqual(Assessment.evaluate(condition, observations: evidence, imageCount: 1, failed: false), .mismatched)
        evidence.observedPosture = .open
        evidence.observedDeviceOrientation = .portrait
        XCTAssertEqual(Assessment.evaluate(condition, observations: evidence, imageCount: 1, failed: false), .captured)
        XCTAssertEqual(Assessment.evaluate(condition, observations: evidence, imageCount: 1, failed: true), .failed)
        XCTAssertEqual(Assessment.evaluate(Condition(), observations: Observations(), imageCount: 2, failed: false), .captured)
    }

    func testCaptureRejectsCurrentAndEmptyPlansBeforeGUIOrScreenshots() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner()
        let controller = FakeController()
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        for conditions: [Condition] in [[], [Condition()], [Condition(orientation: .portrait), Condition()]] {
            XCTAssertThrowsError(try engine.capture(device: device(), conditions: conditions, label: nil, store: store, environment: [:]))
        }
        XCTAssertEqual(controller.prepareCount, 0)
        XCTAssertEqual(runner.screenshotCount, 0)
    }

    func testConsecutiveConditionsReusePostureAndCaptureOnlySelectedDisplay() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner(); runner.ids = ["17", "42"]
        runner.deviceNames = ["42": "primary", "17": "primary-1"]
        let controller = FakeController(); controller.orientationReadback = nil
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        let conditions = try CapturePlan().conditions(for: device())
        XCTAssertEqual(try engine.capture(device: device(), conditions: conditions, label: nil, store: store, environment: [:]), 0)
        let manifest = try readManifest(store)
        XCTAssertEqual(controller.clickedControls, ["Closed", "Partially Open", "Open"])
        XCTAssertEqual(manifest.results.map { $0.images.count }, Array(repeating: 1, count: 6))
        XCTAssertEqual(runner.screenshotDisplayIDs, ["42", "42", "17", "17", "17", "17"])
        XCTAssertEqual(runner.screenshotCount, 6)
        for result in manifest.results {
            XCTAssertEqual(result.observations.beforeDisplays.count, 2)
            XCTAssertEqual(result.observations.afterDisplays.count, 2)
            XCTAssertNil(result.observations.activeDisplayID)
            XCTAssertEqual(Report.preferredDisplayID(for: result, device: device()), result.images[0].displayID)
        }
        XCTAssertFalse(manifest.results[1].observations.dispatchedControls.contains("Closed"))
        XCTAssertTrue(manifest.results[1].messages.contains { $0.contains("preceding successful condition") })
        XCTAssertEqual(runner.enumerationCount, 18)
        let output = try Report.generate(input: root.path, details: true)
        let html = try String(contentsOf: output, encoding: .utf8)
        XCTAssertEqual(html.components(separatedBy: "<figure>").count - 1, 6)
        XCTAssertTrue(html.contains("Outer display"))
        XCTAssertTrue(html.contains("Inner display"))
        XCTAssertFalse(html.contains("No posture-based display default available"))
    }

    func testPostureCaptureKeepsBothWhenDisplayRolesAreUnknownOrAmbiguous() throws {
        for roles: [String: String] in [[:], ["17": "primary", "42": "primary"], ["17": "primary-1", "42": "unknown"]] {
            let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
            let store = try CaptureStore(root: root.path)
            let runner = FakeRunner(); runner.ids = ["17", "42"]; runner.deviceNames = roles
            let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: FakeController(), cancellation: Cancellation(), settleSeconds: 0)
            XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(posture: .closed)], label: nil, store: store, environment: [:]), 0)
            XCTAssertEqual(runner.screenshotDisplayIDs, ["17", "42"])
            XCTAssertEqual(try readManifest(store).results[0].images.count, 2)
        }
    }

    func testDisplayRoleChangeBeforeCaptureKeepsBothDisplays() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner(); runner.ids = ["17", "42"]
        runner.enumerationReadbacks = [enumeration(ids: runner.ids, deviceNames: ["42": "primary", "17": "primary-1"])]
        runner.deviceNames = ["17": "primary", "42": "primary-1"]
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: FakeController(), cancellation: Cancellation(), settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(posture: .closed)], label: nil, store: store, environment: [:]), 0)
        XCTAssertEqual(runner.screenshotDisplayIDs, ["17", "42"])
        let result = try readManifest(store).results[0]
        XCTAssertNil(Report.preferredDisplayID(for: result, device: device()))
        XCTAssertEqual(result.images.count, 2)
    }

    func testSelectedDisplayFailureDoesNotCaptureOtherPanel() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner(); runner.ids = ["17", "42"]
        runner.deviceNames = ["42": "primary", "17": "primary-1"]; runner.failScreenshot = 1
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: FakeController(), cancellation: Cancellation(), settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(posture: .closed)], label: nil, store: store, environment: [:]), 1)
        XCTAssertEqual(runner.screenshotDisplayIDs, ["42"])
        let result = try readManifest(store).results[0]
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.images.isEmpty)
    }

    func testPostureIsReappliedAfterFailedCondition() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner(); runner.failScreenshot = 1
        let controller = FakeController()
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        let condition = Condition(posture: .closed, orientation: .portrait)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [condition, condition], label: nil, store: store, environment: [:]), 1)
        XCTAssertEqual(controller.clickedControls, ["Closed", "Closed"])
        XCTAssertEqual(try readManifest(store).results.map(\.outcome), [.failed, .captured])
    }

    func testAlreadySelectedOrientationIsNotRecordedAsDispatched() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let controller = FakeController(); controller.orientationWasDispatched = false
        let engine = CaptureEngine(simulator: Simulator(runner: FakeRunner()), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(orientation: .portrait)], label: nil, store: store, environment: [:]), 0)
        let result = try readManifest(store).results[0]
        XCTAssertTrue(result.observations.dispatchedControls.isEmpty)
        XCTAssertEqual(result.observations.observedDeviceOrientation, .portrait)
        XCTAssertEqual(controller.rotationCount, 0)
    }

    func testReadbackFailureAfterScreenshotStopsBatchAndRetainsImage() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner()
        let controller = FakeController()
        runner.afterScreenshot = { controller.failReadback = true }
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        let condition = Condition(posture: .closed, orientation: .portrait)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [condition, condition], label: nil, store: store, environment: [:]), 1)
        let manifest = try readManifest(store)
        XCTAssertEqual(manifest.results.map(\.progress), [.finished, .pending])
        XCTAssertEqual(manifest.results[0].outcome, .failed)
        XCTAssertEqual(manifest.results[0].images.count, 1)
        XCTAssertEqual(controller.clickCount, 1)
    }

    func testScreenshotFailureRetainsOtherImagesAndContinuesConditions() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner(); runner.ids = ["17", "42"]; runner.failScreenshot = 1
        let controller = FakeController()
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        let conditions = [Condition(posture: .closed, orientation: .portrait), Condition(posture: .open, orientation: .portrait)]
        XCTAssertEqual(try engine.capture(device: device(), conditions: conditions, label: nil, store: store, environment: [:]), 1)
        let manifest = try readManifest(store)
        XCTAssertTrue(manifest.complete)
        XCTAssertEqual(manifest.results.map(\.outcome), [.failed, .captured])
        XCTAssertEqual(manifest.results.map { $0.images.count }, [1, 2])
        XCTAssertEqual(runner.screenshotCount, 4)
    }

    func testGUIFailureStopsRemainingConditionsAndRetainsEarlierImage() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner()
        let controller = FakeController(); controller.failClick = 2
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        let conditions = Posture.allCases.map { Condition(posture: $0, orientation: .portrait) }
        XCTAssertEqual(try engine.capture(device: device(), conditions: conditions, label: nil, store: store, environment: [:]), 1)
        let manifest = try readManifest(store)
        XCTAssertFalse(manifest.complete)
        XCTAssertEqual(manifest.results.map(\.progress), [.finished, .finished, .pending])
        XCTAssertEqual(manifest.results[0].images.count, 1)
        XCTAssertEqual(controller.clickCount, 2)
        XCTAssertEqual(runner.screenshotCount, 1)
    }

    func testDirectOrientationDoesNotRetryWhenDisplayUIStaysPortrait() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let controller = FakeController(); controller.orientationReadback = .landscapeLeft
        let engine = CaptureEngine(simulator: Simulator(runner: FakeRunner()), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(orientation: .landscape)], label: nil, store: store, environment: [:]), 0)
        XCTAssertEqual(controller.orientationSetCount, 0)
        XCTAssertEqual(controller.clickCount, 0)
        let result = try readManifest(store).results[0]
        XCTAssertEqual(result.outcome, .captured)
        XCTAssertEqual(result.observations.afterDisplays[0].uiOrientation, "Portrait")
        XCTAssertEqual(result.observations.observedDeviceOrientation, .landscapeLeft)
        XCTAssertNotNil(result.observations.deviceOrientationSource)
    }

    func testUnknownOrientationCapturesButKnownUncorrectedOrientationStops() throws {
        for readback in [nil, DeviceOrientation.landscapeRight] {
            let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
            let store = try CaptureStore(root: root.path)
            let controller = FakeController(); controller.orientationReadback = readback
            let engine = CaptureEngine(simulator: Simulator(runner: FakeRunner()), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
            XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(orientation: .landscape)], label: nil, store: store, environment: [:]), readback == nil ? 0 : 1)
            let result = try readManifest(store).results[0]
            XCTAssertEqual(result.outcome, readback == nil ? .captured : .failed)
            XCTAssertEqual(result.images.count, readback == nil ? 1 : 0)
            XCTAssertEqual(controller.orientationSetCount, readback == nil ? 1 : 0)
            XCTAssertEqual(controller.clickCount, 0)
        }
    }

    func testShortestRotationsFromEveryPlanarOrientation() throws {
        let cases: [(DeviceOrientation, Orientation, [RotationDirection], [DeviceOrientation?])] = [
            (.portrait, .portrait, [], []),
            (.portrait, .landscape, [.left], [.landscapeLeft]),
            (.landscapeRight, .portrait, [.left], [.portrait]),
            (.landscapeRight, .landscape, [.right, .right], [.upsideDown, .landscapeLeft]),
            (.upsideDown, .portrait, [.right, .right], [.landscapeLeft, .portrait]),
            (.upsideDown, .landscape, [.right], [.landscapeLeft]),
            (.landscapeLeft, .portrait, [.right], [.portrait]),
            (.landscapeLeft, .landscape, [], []),
        ]
        for (start, target, directions, readbacks) in cases {
            let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
            let store = try CaptureStore(root: root.path)
            let controller = FakeController()
            controller.orientationReadback = start
            controller.rotationReadbacks = readbacks
            let engine = CaptureEngine(simulator: Simulator(runner: FakeRunner()), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
            XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(orientation: target)], label: nil, store: store, environment: [:]), 0)
            XCTAssertEqual(controller.rotations, directions)
            XCTAssertEqual(controller.orientationSetCount, 0)
            let result = try readManifest(store).results[0]
            XCTAssertEqual(result.observations.observedDeviceOrientation?.menuTitle, target.uiValue)
            XCTAssertEqual(result.observations.dispatchedControls, directions.map(\.menuTitle))
        }
    }

    func testUnexpectedRotationStopsWithoutCirclingOrCapturing() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let controller = FakeController()
        controller.rotationReadbacks = [.landscapeRight]
        let runner = FakeRunner()
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        let conditions = [Condition(orientation: .landscape), Condition(orientation: .portrait)]
        XCTAssertEqual(try engine.capture(device: device(), conditions: conditions, label: nil, store: store, environment: [:]), 1)
        XCTAssertEqual(controller.rotations, [.left])
        XCTAssertEqual(runner.screenshotCount, 0)
        XCTAssertEqual(try readManifest(store).results.map(\.progress), [.finished, .pending])
    }

    func testPostureChangeReconcilesOrientationBeforeRelativeTurns() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let controller = FakeController(); controller.orientationReadback = .landscapeLeft
        controller.afterSet = { controller.orientationReadback = .portrait }
        controller.rotationReadbacks = [.landscapeLeft]
        let engine = CaptureEngine(simulator: Simulator(runner: FakeRunner()), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        let conditions = [Condition(posture: .closed, orientation: .portrait), Condition(posture: .closed, orientation: .landscape)]
        XCTAssertEqual(try engine.capture(device: device(), conditions: conditions, label: nil, store: store, environment: [:]), 0)
        XCTAssertEqual(controller.orientationSetCount, 1)
        XCTAssertEqual(controller.rotations, [.left])
        let results = try readManifest(store).results
        XCTAssertEqual(results[0].observations.dispatchedControls, ["Closed", "Orientation: Portrait"])
        XCTAssertEqual(results[1].observations.dispatchedControls, ["Rotate Left"])
    }

    func testNamedRequestAfterFoldUsesOneLeftCorrectionForQuarterTurnOffset() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let controller = FakeController(); controller.orientationReadback = .landscapeLeft
        controller.afterSet = { controller.orientationReadback = .landscapeRight }
        controller.rotationReadbacks = [.portrait]
        let engine = CaptureEngine(simulator: Simulator(runner: FakeRunner()), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(posture: .open, orientation: .portrait)], label: nil, store: store, environment: [:]), 0)
        XCTAssertEqual(controller.orientationSetCount, 1)
        XCTAssertEqual(controller.rotations, [.left])
        XCTAssertEqual(try readManifest(store).results[0].observations.observedDeviceOrientation, .portrait)
    }

    func testUnknownReadbackAfterRotationDoesNotTriggerBlindSecondTurn() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let controller = FakeController(); controller.orientationReadback = .upsideDown
        controller.rotationReadbacks = [nil]
        let engine = CaptureEngine(simulator: Simulator(runner: FakeRunner()), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(orientation: .portrait)], label: nil, store: store, environment: [:]), 0)
        XCTAssertEqual(controller.rotations, [.right])
        XCTAssertNil(try readManifest(store).results[0].observations.observedDeviceOrientation)
    }

    func testNonPlanarOrientationUsesNamedFallbackBeforePlanningRotations() throws {
        for start in [DeviceOrientation.faceUp, .faceDown] {
            let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
            let store = try CaptureStore(root: root.path)
            let controller = FakeController(); controller.orientationReadback = start
            controller.afterSet = { controller.orientationReadback = .portrait }
            controller.rotationReadbacks = [.landscapeLeft]
            let engine = CaptureEngine(simulator: Simulator(runner: FakeRunner()), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
            XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(orientation: .landscape)], label: nil, store: store, environment: [:]), 0)
            XCTAssertEqual(controller.orientationSetCount, 1)
            XCTAssertEqual(controller.rotations, [.left])
        }
    }

    func testOrientationChangeDuringScreenshotStillCaptures() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let controller = FakeController(); controller.orientationReadback = .portrait
        let runner = FakeRunner()
        runner.afterScreenshot = { controller.orientationReadback = .landscapeRight }
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(orientation: .portrait)], label: nil, store: store, environment: [:]), 0)
        let result = try readManifest(store).results[0]
        XCTAssertEqual(controller.rotationCount, 0)
        XCTAssertEqual(result.outcome, .captured)
        XCTAssertNil(result.observations.observedDeviceOrientation)
        XCTAssertEqual(result.images.count, 1)
    }

    func testOrientationCorrectionIsBoundedAndAllowsUnknownReadback() throws {
        for mode in 0..<3 {
            let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
            let store = try CaptureStore(root: root.path)
            let controller = FakeController()
            controller.orientationReadback = mode == 1 ? nil : .portrait
            controller.failRotation = mode == 2
            let runner = FakeRunner()
            let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
            XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(orientation: .landscape)], label: nil, store: store, environment: [:]), mode == 1 ? 0 : 1)
            XCTAssertEqual(controller.rotationCount, [1, 0, 1][mode])
            XCTAssertEqual(runner.screenshotCount, mode == 1 ? 1 : 0)
        }
    }

    func testCancellationKeepsPendingManifest() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let cancellation = Cancellation(); cancellation.cancel()
        let runner = FakeRunner()
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: FakeController(), cancellation: cancellation, settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(orientation: .portrait)], label: nil, store: store, environment: [:]), 1)
        XCTAssertEqual(try readManifest(store).results[0].progress, .pending)
        XCTAssertEqual(runner.screenshotCount, 0)
    }

    func testCancellationAfterAnImageRetainsThatImageAndCheckpoint() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let cancellation = Cancellation()
        let runner = FakeRunner(); runner.ids = ["17", "42"]; runner.afterScreenshot = { cancellation.cancel() }
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: FakeController(), cancellation: cancellation, settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition(orientation: .portrait)], label: nil, store: store, environment: [:]), 1)
        let manifest = try readManifest(store)
        XCTAssertEqual(manifest.results[0].images.count, 1)
        XCTAssertEqual(manifest.results[0].outcome, .failed)
        XCTAssertEqual(runner.screenshotCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(manifest.results[0].images[0].path).path))
    }
}
