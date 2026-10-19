import Foundation

final class CaptureEngine {
    let simulator: Simulator
    let controller: DeviceControlling
    let cancellation: Cancellation
    let settleSeconds: TimeInterval
    init(simulator: Simulator, controller: DeviceControlling, cancellation: Cancellation, settleSeconds: TimeInterval = 4) {
        self.simulator = simulator; self.controller = controller; self.cancellation = cancellation; self.settleSeconds = settleSeconds
    }

    func capture(device: Device, conditions: [Condition], label: String?, store: CaptureStore, environment: [String: String]) throws -> Int32 {
        var manifest = Manifest(captureID: store.captureID, createdAt: timestamp(), label: label, device: device,
                                environment: environment, results: conditions.enumerated().map { CaptureResult(index: $0.offset, requested: $0.element) })
        try store.save(manifest)
        let usesGUI = conditions.contains { !$0.isCurrent }
        if usesGUI {
            do { try controller.prepare(device, conditions: conditions) }
            catch {
                manifest.messages.append("GUI preparation failed: \(error)")
                manifest.results[0].progress = .finished
                manifest.results[0].messages.append("GUI preparation failed: \(error)")
                manifest.finishedAt = timestamp()
                try store.save(manifest)
                return 1
            }
        }

        var stopReason: String?
        for index in conditions.indices {
            if cancellation.cancelled { stopReason = "Interrupted; remaining conditions were not attempted."; break }
            var result = manifest.results[index]
            result.progress = .running
            manifest.results[index] = result
            try store.save(manifest)
            var operationFailed = false
            do {
                if usesGUI {
                    do { try controller.checkTarget(device); result.observations.guiTargetMatched = true }
                    catch { stopReason = "Target identity is no longer safe: \(error)"; throw error }
                }
                result.observations.beforeDisplays = try simulator.displays(device)
                if let posture = result.requested.posture {
                    do { try controller.click(posture.controlHelp, device: device) }
                    catch { stopReason = "GUI operation failed; no further GUI actions will be attempted: \(error)"; throw error }
                    result.observations.dispatchedControls.append(posture.controlHelp)
                    manifest.results[index] = result
                    try store.save(manifest)
                    try cancellation.sleep(seconds: settleSeconds)
                    result.messages.append("The posture button was dispatched. Device Hub did not expose a selected posture or hinge-angle readback; posture remains unverified.")
                }
                var displays = try simulator.displays(device)
                if let orientation = result.requested.orientation {
                    do { try controller.setOrientation(orientation, device: device) }
                    catch { stopReason = "GUI orientation command failed; no further GUI actions will be attempted: \(error)"; throw error }
                    result.observations.dispatchedControls.append("Orientation: " + orientation.uiValue)
                    manifest.results[index] = result
                    try store.save(manifest)
                    try cancellation.sleep(seconds: settleSeconds)
                    do { result.observations.guiOrientationBeforeCapture = try controller.readOrientation(device) }
                    catch { stopReason = "GUI orientation could not be read safely: \(error)"; throw error }
                    // Device Hub 27.1 may apply a named direction relative to the folded
                    // device frame. Correct from GUI readback, never from app pixels.
                    for _ in 0..<3 {
                        guard let observed = result.observations.guiOrientationBeforeCapture,
                              observed.menuTitle != orientation.uiValue,
                              [.portrait, .upsideDown, .landscapeLeft, .landscapeRight].contains(observed)
                        else { break }
                        do { try controller.rotateRight(device) }
                        catch { stopReason = "GUI orientation correction failed: \(error)"; throw error }
                        result.observations.dispatchedControls.append("Rotate Right")
                        manifest.results[index] = result
                        try store.save(manifest)
                        try cancellation.sleep(seconds: settleSeconds)
                        do { result.observations.guiOrientationBeforeCapture = try controller.readOrientation(device) }
                        catch { stopReason = "GUI orientation correction readback failed: \(error)"; throw error }
                    }
                    result.observations.deviceOrientationSource = "Device Hub > Device > Orientation menu checkmark"
                    guard result.observations.guiOrientationBeforeCapture?.menuTitle == orientation.uiValue else {
                        let observed = result.observations.guiOrientationBeforeCapture?.menuTitle ?? "unknown"
                        let message = "Could not establish requested orientation \(orientation.uiValue) (readback: \(observed)); no screenshot was taken for this condition."
                        stopReason = message
                        throw ToolError(message)
                    }
                    displays = try simulator.displays(device)
                    result.messages.append("Orientation was requested by name, then corrected with at most three right rotations if GUI readback differed. Menu readback describes Simulator orientation, not application rotation or independent motion-sensor state.")
                    if !displays.allSatisfy({ $0.uiOrientation == orientation.uiValue }) {
                        result.messages.append("simctl UI Orientation differs from the requested direction on one or more displays. The application may restrict rotation; display UI orientation does not drive additional rotations.")
                    }
                }
                if usesGUI {
                    do { try controller.checkTarget(device) }
                    catch { stopReason = "Target identity changed before capture: \(error)"; throw error }
                }
                result.observations.afterDisplays = displays
                if displays.count == 1 {
                    result.observations.activeDisplayID = displays[0].id
                    result.observations.displaySelectionReason = "Only one built-in display was enumerated. No inference from image content or power state was made."
                } else {
                    result.observations.displaySelectionReason = "Multiple built-in displays were enumerated; active display is unverified. All built-in displays are saved."
                    result.messages.append("Active display unverified; all built-in displays are retained without selecting by brightness or fixed screen ID.")
                }
                for display in displays {
                    try cancellation.check()
                    do {
                        let image = try store.image(index: index, display: display) { try simulator.screenshot(device, display: display, to: $0) }
                        result.images.append(image)
                    } catch {
                        operationFailed = true
                        result.messages.append("Display \(display.id) capture failed: \(error)")
                    }
                    // Persist after every image; partial results survive later failures.
                    manifest.results[index] = result
                    try store.save(manifest)
                }
                if usesGUI {
                    do { try controller.checkTarget(device) }
                    catch { stopReason = "Target identity changed during capture: \(error)"; throw error }
                }
                if result.requested.orientation != nil {
                    do { result.observations.guiOrientationAfterCapture = try controller.readOrientation(device) }
                    catch { stopReason = "GUI orientation readback failed after capture: \(error)"; throw error }
                    if result.observations.guiOrientationBeforeCapture == result.observations.guiOrientationAfterCapture {
                        result.observations.observedDeviceOrientation = result.observations.guiOrientationAfterCapture
                    } else {
                        result.messages.append("Device Hub orientation selection changed during capture; orientation is unverified.")
                    }
                }
                let finalDisplays = try simulator.displays(device)
                if finalDisplays != displays {
                    result.messages.append("Display inventory or UI Orientation changed during capture. The saved images may represent different instants.")
                    result.observations.activeDisplayID = nil
                    result.observations.afterDisplays = finalDisplays
                }
            } catch {
                operationFailed = true
                result.messages.append(String(describing: error))
                if cancellation.cancelled { stopReason = "Interrupted; remaining conditions were not attempted." }
            }
            result.outcome = Assessment.evaluate(result.requested, observations: result.observations, imageCount: result.images.count, failed: operationFailed)
            result.progress = .finished
            manifest.results[index] = result
            try store.save(manifest)
            print("\(index + 1)/\(conditions.count) \(result.requested.title): \(result.outcome.rawValue) (\(result.images.count) images)")
            if stopReason != nil { break }
        }
        if let stopReason { manifest.messages.append(stopReason) }
        manifest.complete = manifest.results.allSatisfy { $0.progress == .finished }
        manifest.finishedAt = timestamp()
        try store.save(manifest)
        return manifest.complete && manifest.results.allSatisfy { $0.outcome == .verified } ? 0 : 1
    }
}
