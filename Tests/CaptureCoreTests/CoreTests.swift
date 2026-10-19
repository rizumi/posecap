import XCTest
import CoreGraphics
import ImageIO
@testable import CaptureCore

final class CoreTests: XCTestCase {
    func testHelpSelectsCommandWithoutRequiringArguments() throws {
        XCTAssertNil(try Options.parse(["--help"]).helpTopic)
        for command in [Options.Command.devices, .capture, .report] {
            for flag in ["--help", "-h"] {
                let options = try Options.parse([command.rawValue, flag])
                XCTAssertEqual(options.command, .help)
                XCTAssertEqual(options.helpTopic, command)
                XCTAssertTrue(CLI.help(for: options.helpTopic).contains("Usage: posecap " + command.rawValue))
            }
        }
        XCTAssertFalse(CLI.help.contains("--posture"))
        XCTAssertFalse(CLI.help(for: .report).contains("--posture"))
        XCTAssertThrowsError(try Options.parse(["report"]))
    }

    func testBundledDeviceHubAdapterIsAvailable() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "DeviceHub", withExtension: "applescript"))
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("on run argv"))
    }

    func testDuplicateRuntimeBuildsAreAllowedButConflictingVersionsFail() throws {
        let json = #"{"devicetypes":[{"identifier":"phone","name":"iPhone Duo","productFamily":"iPhone"}],"runtimes":[{"identifier":"runtime","version":"27.1","buildversion":"example-a"},{"identifier":"runtime","version":"27.1","buildversion":"example-b"}],"devices":{"runtime":[{"udid":"00000000-0000-0000-0000-000000000001","name":"Home","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"phone"}]}}"#
        XCTAssertEqual(try Inventory(data: Data(json.utf8)).devices[0].runtimeVersion, "27.1")
        XCTAssertThrowsError(try Inventory(data: Data(json.replacingOccurrences(of: #""version":"27.1","buildversion":"example-b""#, with: #""version":"27.2","buildversion":"example-b""#).utf8)))
    }

    func testDeviceSelectionUsesModelNotDisplayNameAndRejectsAmbiguity() throws {
        let a = device(name: "ExampleApp", model: "iPhone Duo")
        let b = device(id: "00000000-0000-0000-0000-000000000002", name: "iPhone Duo", model: "iPhone 18 Pro")
        XCTAssertEqual(try Inventory(devices: [a, b]).select(udid: nil, model: "iPhone Duo"), a)
        XCTAssertThrowsError(try Inventory(devices: [a, b]).select(udid: nil, model: nil))
        XCTAssertThrowsError(try Inventory(devices: [a, device(id: b.udid)]).select(udid: nil, model: "iPhone Duo"))
        XCTAssertThrowsError(try Inventory(devices: [device(state: "Shutdown")]).select(udid: a.udid, model: nil))
    }

    func testGUIIdentityIncludesShutdownDuplicates() {
        let a = device()
        let duplicate = device(id: "00000000-0000-0000-0000-000000000002", state: "Shutdown")
        XCTAssertThrowsError(try Inventory(devices: [a, duplicate]).verifyGUIIdentity(a))
    }

    func testMatrixDefaultsFilteringAndCurrent() throws {
        let defaults = try Options.parse(["capture"])
        XCTAssertEqual(try defaults.conditions(for: device()).map(\.title), [
            "closed / portrait", "closed / landscape", "half-open / portrait", "half-open / landscape", "open / portrait", "open / landscape",
        ])
        XCTAssertEqual(try Options.parse(["capture", "--orientation", "portrait"]).conditions(for: device()).count, 3)
        XCTAssertEqual(try Options.parse(["capture", "--posture", "closed", "--orientation", "landscape"]).conditions(for: device()).count, 1)
        XCTAssertTrue(try Options.parse(["capture", "--current"]).conditions(for: device())[0].isCurrent)
        XCTAssertThrowsError(try Options.parse(["capture", "--current", "--posture", "closed"]))
        XCTAssertThrowsError(try Options.parse(["capture", "--udid", device().udid, "--model", "iPhone Duo"]))
        XCTAssertThrowsError(try Options.parse(["boot"]))
        XCTAssertThrowsError(try Options.parse(["capture", "--all"]))
        let phone = device(model: "iPhone 18 Pro")
        XCTAssertEqual(try defaults.conditions(for: phone).count, 2)
        XCTAssertThrowsError(try Options.parse(["capture", "--posture", "open"]).conditions(for: phone))
    }

    func testEnumerationUsesDiscoveredIDsAndOnlyBuiltInScreens() throws {
        let displays = try DisplayParser.parse(enumeration(ids: ["17", "42"]))
        XCTAssertEqual(displays.map(\.id), ["17", "42"])
        XCTAssertEqual(displays.map(\.uiOrientation), ["Portrait", "Portrait"])
        XCTAssertThrowsError(try DisplayParser.parse("Power state: On"))
        XCTAssertThrowsError(try DisplayParser.parse(enumeration(ids: ["17", "17"])))
        XCTAssertThrowsError(try DisplayParser.parse(enumeration(ids: ["17"]).replacingOccurrences(of: "Screen ID: 17", with: "Screen ID: 99")))
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

    func testCurrentCaptureSavesBlackPNGWithoutGUI() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner()
        let controller = FakeController()
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition()], label: nil, store: store, environment: [:]), 0)
        let manifest = try readManifest(store)
        XCTAssertEqual(manifest.results[0].images.count, 1)
        XCTAssertEqual(manifest.results[0].images[0].width, 2)
        XCTAssertEqual(controller.prepareCount, 0)
        XCTAssertEqual(controller.checkCount, 0)
    }

    func testMultiDisplayCurrentSucceedsAndSavesBoth() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner(); runner.ids = ["17", "42"]
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: FakeController(), cancellation: Cancellation(), settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition()], label: "Home", store: store, environment: [:]), 0)
        let result = try readManifest(store).results[0]
        XCTAssertEqual(result.outcome, .captured)
        XCTAssertEqual(result.images.map(\.displayID), ["17", "42"])
        XCTAssertNil(result.observations.activeDisplayID)
        XCTAssertEqual(runner.enumerationCount, 2)
    }

    func testConsecutiveConditionsReusePostureAndKeepBothDisplays() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner(); runner.ids = ["17", "42"]
        let controller = FakeController(); controller.orientationReadback = nil
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        let conditions = try Options.parse(["capture"]).conditions(for: device())
        XCTAssertEqual(try engine.capture(device: device(), conditions: conditions, label: nil, store: store, environment: [:]), 0)
        let manifest = try readManifest(store)
        XCTAssertEqual(controller.clickedControls, ["Closed", "Partially Open", "Open"])
        XCTAssertEqual(manifest.results.map { $0.images.count }, Array(repeating: 2, count: 6))
        XCTAssertFalse(manifest.results[1].observations.dispatchedControls.contains("Closed"))
        XCTAssertTrue(manifest.results[1].messages.contains { $0.contains("preceding successful condition") })
        XCTAssertEqual(runner.enumerationCount, 18)
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

    func testReportLanguageOptionsAndLocalizedMismatch() throws {
        XCTAssertEqual(ReportText(language: .ja).condition(Condition(posture: .closed, orientation: .landscape)), "Closed / Landscape")
        XCTAssertEqual(ReportText(language: .ja).condition(Condition(orientation: .portrait)), "Portrait")
        XCTAssertEqual(ReportText(language: .ja).orientation(.landscapeLeft), "Landscape Left")
        XCTAssertEqual(try Options.parse(["report", "--input", "output"]).language, .en)
        XCTAssertEqual(try Options.parse(["report", "--input", "output", "--language", "ja"]).language, .ja)
        XCTAssertThrowsError(try Options.parse(["report", "--input", "output", "--language", "fr"]))
        XCTAssertThrowsError(try Options.parse(["capture", "--language", "ja"]))
        XCTAssertFalse(try Options.parse(["report", "--input", "output"]).details)
        XCTAssertTrue(try Options.parse(["report", "--input", "output", "--details"]).details)
        XCTAssertThrowsError(try Options.parse(["capture", "--details"]))
        XCTAssertThrowsError(try Options.parse(["report", "--input", "output", "--details", "--details"]))
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let controller = FakeController(); controller.orientationReadback = .portrait
        let engine = CaptureEngine(simulator: Simulator(runner: FakeRunner()), controller: controller, cancellation: Cancellation(), settleSeconds: 0)
        _ = try engine.capture(device: device(), conditions: [Condition(orientation: .portrait)], label: "<日本語 & English>", store: store, environment: [:])
        // Older manifests can contain mismatches; both languages must explain them.
        var historical = try readManifest(store)
        historical.results[0].outcome = .mismatched
        historical.results[0].observations.observedDeviceOrientation = .landscapeRight
        try store.save(historical)
        let manifestBefore = try Data(contentsOf: store.directory.appendingPathComponent("manifest.json"))
        let output = try Report.generate(input: root.path, language: .ja)
        let ja = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(ja.contains("lang=\"ja\""))
        XCTAssertTrue(ja.contains("指定した向きは「Portrait」"))
        XCTAssertTrue(ja.contains("読み取った向きは「Landscape Right」"))
        XCTAssertTrue(ja.contains("&lt;日本語 &amp; English&gt;"))
        XCTAssertFalse(ja.contains("<日本語"))
        _ = try Report.generate(input: root.path, language: .en)
        let en = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(en.contains("lang=\"en\""))
        XCTAssertTrue(en.contains("Requested orientation: Portrait; Device Hub reported: Landscape Right."))
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("manifest.json")), manifestBefore)
    }

    func testReportTitleIsSeparateFromScreenLabelAndEscaped() throws {
        XCTAssertEqual(try Options.parse(["report", "--input", "output", "--title", "My App"]).title, "My App")
        XCTAssertThrowsError(try Options.parse(["capture", "--title", "My App"]))
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let engine = CaptureEngine(simulator: Simulator(runner: FakeRunner()), controller: FakeController(), cancellation: Cancellation(), settleSeconds: 0)
        _ = try engine.capture(device: device(), conditions: [Condition(orientation: .portrait)], label: "Screen A", store: store, environment: [:])
        let before = try Data(contentsOf: store.directory.appendingPathComponent("manifest.json"))
        let output = try Report.generate(input: root.path, title: "<App & Name>")
        let html = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(html.contains("<h1>&lt;App &amp; Name&gt;</h1>"))
        XCTAssertTrue(html.contains("<title>&lt;App &amp; Name&gt;</title>"))
        XCTAssertTrue(html.contains("<h2>Screen A</h2>"))
        XCTAssertTrue(html.contains("data-orientation=\"portrait\""))
        XCTAssertTrue(html.contains("<div class=filters hidden>"))
        XCTAssertFalse(html.contains("Saved Simulator captures"))
        XCTAssertTrue(html.contains("Generated by posecap"))
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("manifest.json")), before)
    }

    func testReportDisplayDefaultsUseRolesRatherThanFixedIDs() {
        for posture in Posture.allCases {
            var result = CaptureResult(index: 0, requested: Condition(posture: posture, orientation: .portrait))
            result.observations.afterDisplays = reportDisplays()
            result.images = [ImageRecord(displayID: "42", path: "outer.png", width: 2, height: 3),
                             ImageRecord(displayID: "17", path: "inner.png", width: 3, height: 4)]
            XCTAssertEqual(Report.preferredDisplayID(for: result, device: device()), posture == .closed ? "42" : "17")
            XCTAssertNil(result.observations.activeDisplayID)
            XCTAssertEqual(Assessment.evaluate(result.requested, observations: result.observations, imageCount: 2, failed: false), .captured)
            XCTAssertNil(Report.preferredDisplayID(for: result, device: device(model: "iPhone 18 Pro")))
        }
    }

    func testReportDisplayDefaultsFallBackWhenUnknownOrMissing() {
        var result = CaptureResult(index: 0, requested: Condition(posture: .open))
        result.images = [ImageRecord(displayID: "42", path: "outer.png", width: 2, height: 3)]
        result.observations.afterDisplays = reportDisplays()
        XCTAssertNil(Report.preferredDisplayID(for: result, device: device())) // missing inner image
        result.images.append(ImageRecord(displayID: "17", path: "inner.png", width: 3, height: 4))
        result.observations.beforeDisplays = reportDisplays().reversed()
        XCTAssertEqual(Report.preferredDisplayID(for: result, device: device()), "17")
        result.observations.beforeDisplays = [reportDisplays()[0]]
        XCTAssertNil(Report.preferredDisplayID(for: result, device: device())) // inventory changed
        result.observations.beforeDisplays = []
        result.observations.afterDisplays = [reportDisplays()[0], reportDisplays()[0]]
        XCTAssertNil(Report.preferredDisplayID(for: result, device: device())) // ambiguous roles
        result.observations.afterDisplays = []
        XCTAssertNil(Report.preferredDisplayID(for: result, device: device())) // old manifest without roles
        var current = CaptureResult(index: 0, requested: Condition())
        current.observations.afterDisplays = reportDisplays()
        current.images = result.images
        XCTAssertNil(Report.preferredDisplayID(for: current, device: device()))
    }

    func testReportHidesAlternateDisplayAndMakesDetailsOptional() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let runner = FakeRunner(); runner.ids = ["42", "17"]
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: FakeController(), cancellation: Cancellation(), settleSeconds: 0)
        _ = try engine.capture(device: device(), conditions: [Condition(posture: .closed, orientation: .portrait)], label: "Example", store: store, environment: [:])
        var manifest = try readManifest(store)
        manifest.results[0].observations.beforeDisplays = reportDisplays()
        manifest.results[0].observations.afterDisplays = reportDisplays()
        try store.save(manifest)
        let original = try Data(contentsOf: store.directory.appendingPathComponent("manifest.json"))
        let output = try Report.generate(input: root.path)
        let html = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(html.contains("01-display-42.png"))
        XCTAssertFalse(html.contains("01-display-17.png"))
        XCTAssertFalse(html.contains("<details>"))
        _ = try Report.generate(input: root.path, details: true)
        let detailed = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(detailed.contains("Capture details · captured"))
        XCTAssertFalse(detailed.contains("01-display-17.png"))
        _ = try Report.generate(input: root.path)
        XCTAssertEqual(try Data(contentsOf: store.directory.appendingPathComponent("manifest.json")), original)
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent("01-display-17.png"))
        XCTAssertThrowsError(try Report.generate(input: root.path))
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), html)
    }

    func testReportEscapesLabelsRetainsDuplicateLabelsAndRejectsTraversal() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let label = "<script>alert('Home')</script>"
        var first: CaptureStore?
        for _ in 0..<2 {
            let store = try CaptureStore(root: root.path); first = first ?? store
            let engine = CaptureEngine(simulator: Simulator(runner: FakeRunner()), controller: FakeController(), cancellation: Cancellation(), settleSeconds: 0)
            _ = try engine.capture(device: device(), conditions: [Condition()], label: label, store: store, environment: [:])
        }
        let output = try Report.generate(input: root.path)
        let html = try String(contentsOf: output, encoding: .utf8)
        XCTAssertFalse(html.contains("<script>alert("))
        XCTAssertEqual(html.components(separatedBy: "<script>").count - 1, 1)
        XCTAssertTrue(html.contains("script-src 'sha256-"))
        XCTAssertEqual(html.components(separatedBy: "<option value=\"0\">&lt;script&gt;").count - 1, 1)
        XCTAssertTrue(html.contains("data-orientation=\"current\""))
        XCTAssertEqual(html.components(separatedBy: "<h2>&lt;script&gt;").count - 1, 2)
        let store = first!
        var manifest = try readManifest(store)
        manifest.results[0].images = [ImageRecord(displayID: "17", path: "../outside.png", width: 2, height: 3)]
        try store.save(manifest)
        XCTAssertThrowsError(try Report.generate(input: root.path))
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), html)
    }

    func testSymlinkPathsAndUnsupportedSchemaAreRejected() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertThrowsError(try CaptureStore(root: link.path))
        try FileManager.default.removeItem(at: link)
        let store = try CaptureStore(root: real.path)
        try Data("{\"schemaVersion\":999}".utf8).write(to: store.directory.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try Report.generate(input: real.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: real.appendingPathComponent("index.html").path))
    }

    func testCancellationKeepsPendingManifest() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let cancellation = Cancellation(); cancellation.cancel()
        let runner = FakeRunner()
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: FakeController(), cancellation: cancellation, settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition()], label: nil, store: store, environment: [:]), 1)
        XCTAssertEqual(try readManifest(store).results[0].progress, .pending)
        XCTAssertEqual(runner.screenshotCount, 0)
    }

    func testCancellationAfterAnImageRetainsThatImageAndCheckpoint() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root.path)
        let cancellation = Cancellation()
        let runner = FakeRunner(); runner.ids = ["17", "42"]; runner.afterScreenshot = { cancellation.cancel() }
        let engine = CaptureEngine(simulator: Simulator(runner: runner), controller: FakeController(), cancellation: cancellation, settleSeconds: 0)
        XCTAssertEqual(try engine.capture(device: device(), conditions: [Condition()], label: nil, store: store, environment: [:]), 1)
        let manifest = try readManifest(store)
        XCTAssertEqual(manifest.results[0].images.count, 1)
        XCTAssertEqual(manifest.results[0].outcome, .failed)
        XCTAssertEqual(runner.screenshotCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(manifest.results[0].images[0].path).path))
    }

    func testSubprocessTimeoutAndLargeOutputDoNotDeadlock() throws {
        let runner = ProcessRunner(cancellation: Cancellation())
        let started = Date()
        XCTAssertThrowsError(try runner.run("/bin/sleep", ["3"], timeout: 0.05))
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        let result = try runner.run("/usr/bin/head", ["-c", "200000", "/dev/zero"], timeout: 3)
        XCTAssertEqual(result.stdout.count, 200000)
    }
}

private func device(id: String = "00000000-0000-0000-0000-000000000001", name: String = "ExampleApp", model: String = "iPhone Duo", state: String = "Booted") -> Device {
    Device(udid: id, name: name, model: model, deviceTypeIdentifier: model == "iPhone Duo" ? "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo" : "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro", family: "iPhone", runtimeIdentifier: "example-runtime", runtimeVersion: "27.1", state: state, available: true)
}

private func temporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("capture-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
}

private func readManifest(_ store: CaptureStore) throws -> Manifest {
    try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: store.directory.appendingPathComponent("manifest.json")))
}

private func enumeration(ids: [String]) -> String {
    "Port:\n    Connected Screens:\n" + ids.map { id in
        """
            (\(id)) LCD:
                Screen ID: \(id)
                Name: LCD
                Device Name: example-\(id)
                Screen Type: Integrated
                Pixel Size: {2, 3}
                UI Orientation: Portrait

        """
    }.joined() + """
        (99) TVOut:
            Screen ID: 99
            Screen Type: TVOut

    Port:
        Class: Audio
    """
}

private final class FakeRunner: CommandRunning {
    var ids = ["17"]
    var screenshotCount = 0
    var enumerationCount = 0
    var failScreenshot: Int?
    var afterScreenshot: (() -> Void)?
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandOutput {
        if arguments.contains("enumerate") {
            enumerationCount += 1
            return CommandOutput(stdout: Data(enumeration(ids: ids).utf8), stderr: "")
        }
        if arguments.contains("screenshot") {
            screenshotCount += 1
            if screenshotCount == failScreenshot { throw ToolError("Synthetic screenshot failure.") }
            let context = CGContext(data: nil, width: 2, height: 3, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
            let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments.last!) as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            guard CGImageDestinationFinalize(destination) else { throw ToolError("Cannot create test PNG.") }
            afterScreenshot?()
            return CommandOutput(stdout: Data(), stderr: "")
        }
        throw ToolError("Unexpected mock command.")
    }
}

private final class FakeController: DeviceControlling {
    var prepareCount = 0
    var checkCount = 0
    var clickCount = 0
    var failClick: Int?
    var orientationReadback: DeviceOrientation? = .portrait
    var orientationSetCount = 0
    var orientationWasDispatched = true
    var failReadback = false
    var clickedControls: [String] = []
    var rotationCount = 0
    var rotations: [RotationDirection] = []
    var rotationReadbacks: [DeviceOrientation?] = []
    var failRotation = false
    var afterSet: (() -> Void)?
    func rotate(_ direction: RotationDirection, device: Device) throws {
        rotationCount += 1
        rotations.append(direction)
        if failRotation { throw ToolError("Synthetic rotation target loss.") }
        if !rotationReadbacks.isEmpty { orientationReadback = rotationReadbacks.removeFirst() }
    }
    func setOrientation(_ orientation: Orientation, device: Device) throws -> Bool {
        orientationSetCount += 1
        afterSet?()
        return orientationWasDispatched
    }
    func readOrientation(_ device: Device) throws -> DeviceOrientation? {
        if failReadback { throw ToolError("Synthetic readback target loss.") }
        return orientationReadback
    }
    func prepare(_ device: Device, conditions: [Condition]) throws { prepareCount += 1 }
    func checkTarget(_ device: Device) throws { checkCount += 1 }
    func click(_ help: String, device: Device) throws {
        clickCount += 1
        clickedControls.append(help)
        if clickCount == failClick { throw ToolError("Synthetic target identity failure.") }
    }
}

private func reportDisplays() -> [Display] {
    [Display(id: "42", name: "LCD", deviceName: "primary", type: "Integrated", uiOrientation: "Portrait", nativeWidth: 2, nativeHeight: 3),
     Display(id: "17", name: "LCD-1", deviceName: "primary-1", type: "Integrated", uiOrientation: "Portrait", nativeWidth: 3, nativeHeight: 4)]
}
