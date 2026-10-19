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
        guard !conditions.isEmpty, conditions.allSatisfy({ !$0.isCurrent }) else {
            throw ToolError("Capture requires an explicit posture or orientation; current-state capture is no longer supported.")
        }
        var manifest = Manifest(captureID: store.captureID, createdAt: timestamp(), label: label, device: device,
                                environment: environment, results: conditions.enumerated().map { CaptureResult(index: $0.offset, requested: $0.element) })
        try store.save(manifest)
        do { try controller.prepare(device, conditions: conditions) }
        catch {
            manifest.messages.append("GUI preparation failed: \(error)")
            manifest.results[0].progress = .finished
            manifest.results[0].messages.append("GUI preparation failed: \(error)")
            manifest.finishedAt = timestamp()
            try store.save(manifest)
            return 1
        }

        var stopReason: String?
        var previousPosture: Posture?
        for index in conditions.indices {
            if cancellation.cancelled { stopReason = "Interrupted; remaining conditions were not attempted."; break }
            var result = manifest.results[index]
            let started = ProcessInfo.processInfo.systemUptime
            let postureChanged = result.requested.posture != nil && result.requested.posture != previousPosture
            result.progress = .running
            manifest.results[index] = result
            try store.save(manifest)
            var operationFailed = false
            do {
                do { try controller.checkTarget(device); result.observations.guiTargetMatched = true }
                catch { stopReason = "Target identity is no longer safe: \(error)"; throw error }
                result.observations.beforeDisplays = try simulator.displays(device)
                if let posture = result.requested.posture, postureChanged {
                    do { try controller.click(posture.controlHelp, device: device) }
                    catch { stopReason = "GUI operation failed; no further GUI actions will be attempted: \(error)"; throw error }
                    result.observations.dispatchedControls.append(posture.controlHelp)
                    manifest.results[index] = result
                    try store.save(manifest)
                    try cancellation.sleep(seconds: settleSeconds)
                    result.messages.append("The posture button was dispatched.")
                } else if result.requested.posture != nil {
                    result.messages.append("The posture requested by the preceding successful condition was retained; no posture readback is available.")
                }
                if let orientation = result.requested.orientation {
                    do { result.observations.guiOrientationBeforeCapture = try controller.readOrientation(device) }
                    catch { stopReason = "GUI orientation could not be read safely: \(error)"; throw error }
                    result.messages.append("Initial Device Hub orientation: \(result.observations.guiOrientationBeforeCapture?.menuTitle ?? "unknown").")
                    // Immediately after folding, a relative turn can leave menu
                    // readback unchanged. Reconcile a differing direction once,
                    // then use fresh readback to choose the shortest correction.
                    let observed = result.observations.guiOrientationBeforeCapture
                    if observed?.rotations(to: orientation) == nil || (postureChanged && observed?.menuTitle != orientation.uiValue) {
                        let dispatched: Bool
                        do { dispatched = try controller.setOrientation(orientation, device: device) }
                        catch { stopReason = "GUI orientation command failed; no further GUI actions will be attempted: \(error)"; throw error }
                        if dispatched {
                            result.observations.dispatchedControls.append("Orientation: " + orientation.uiValue)
                            manifest.results[index] = result
                            try store.save(manifest)
                            try cancellation.sleep(seconds: settleSeconds)
                        }
                        do { result.observations.guiOrientationBeforeCapture = try controller.readOrientation(device) }
                        catch { stopReason = "GUI orientation could not be read safely: \(error)"; throw error }
                    }
                    let rotations = result.observations.guiOrientationBeforeCapture?.rotations(to: orientation) ?? []
                    for direction in rotations {
                        guard let before = result.observations.guiOrientationBeforeCapture,
                              before.menuTitle != orientation.uiValue,
                              let expected = before.rotated(direction) else { break }
                        do { try controller.rotate(direction, device: device) }
                        catch { stopReason = "GUI orientation rotation failed: \(error)"; throw error }
                        result.observations.dispatchedControls.append(direction.menuTitle)
                        manifest.results[index] = result
                        try store.save(manifest)
                        try cancellation.sleep(seconds: settleSeconds)
                        do { result.observations.guiOrientationBeforeCapture = try controller.readOrientation(device) }
                        catch { stopReason = "GUI orientation rotation readback failed: \(error)"; throw error }
                        let after = result.observations.guiOrientationBeforeCapture
                        result.messages.append("\(direction.menuTitle): \(before.menuTitle) → \(after?.menuTitle ?? "unknown").")
                        if let after, after != expected, after.menuTitle != orientation.uiValue {
                            let message = "Unexpected orientation after \(direction.menuTitle): expected \(expected.menuTitle), read \(after.menuTitle); no further rotations or screenshots were attempted."
                            stopReason = message
                            throw ToolError(message)
                        }
                    }
                    result.observations.deviceOrientationSource = "Device Hub > Device > Orientation menu checkmark"
                    if let actual = result.observations.guiOrientationBeforeCapture, actual.menuTitle != orientation.uiValue {
                        let observed = result.observations.guiOrientationBeforeCapture?.menuTitle ?? "unknown"
                        let message = "Could not establish requested orientation \(orientation.uiValue) (readback: \(observed)); no screenshot was taken for this condition."
                        stopReason = message
                        throw ToolError(message)
                    }
                    result.messages.append("Orientation used the shortest left/right rotation sequence from GUI readback (at most two turns). One named request reconciles a differing direction after a posture change or unknown/non-planar readback. Menu readback describes Simulator orientation, not application rotation or independent motion-sensor state.")
                }
                let displays = try simulator.displays(device)
                let preferredDisplay = DisplaySelection.preferredDisplay(device: device, posture: result.requested.posture,
                                                                         displays: displays, before: result.observations.beforeDisplays)
                let captureDisplays = preferredDisplay.map { [$0] } ?? displays
                if let orientation = result.requested.orientation {
                    if !captureDisplays.allSatisfy({ $0.uiOrientation == orientation.uiValue }) {
                        result.messages.append("simctl UI Orientation differs from the requested direction on one or more selected displays. The application may restrict rotation; display UI orientation does not drive additional rotations.")
                    }
                }
                do { try controller.checkTarget(device) }
                catch { stopReason = "Target identity changed before capture: \(error)"; throw error }
                result.observations.afterDisplays = displays
                if displays.count == 1 {
                    result.observations.activeDisplayID = displays[0].id
                    result.observations.displaySelectionReason = "Only one built-in display was enumerated. No inference from image content or power state was made."
                } else if let preferredDisplay {
                    let role = result.requested.posture == .closed ? "outer" : "inner"
                    result.observations.displaySelectionReason = "Only the \(role) display (\(preferredDisplay.id)) is saved, selected from the requested posture and enumerated display roles. This does not verify the active display."
                } else {
                    result.observations.displaySelectionReason = "No unambiguous posture-based display selection was available; all enumerated built-in displays are saved."
                }
                for display in captureDisplays {
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
                if result.requested.orientation != nil {
                    // readOrientation validates the target as part of the same operation.
                    do { result.observations.guiOrientationAfterCapture = try controller.readOrientation(device) }
                    catch { stopReason = "GUI orientation readback failed after capture: \(error)"; throw error }
                    if result.observations.guiOrientationBeforeCapture == result.observations.guiOrientationAfterCapture {
                        result.observations.observedDeviceOrientation = result.observations.guiOrientationAfterCapture
                    } else {
                        result.messages.append("Device Hub orientation selection changed during capture.")
                    }
                } else {
                    do { try controller.checkTarget(device) }
                    catch { stopReason = "Target identity changed during capture: \(error)"; throw error }
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
            previousPosture = result.outcome == .captured ? result.requested.posture : nil
            result.progress = .finished
            manifest.results[index] = result
            try store.save(manifest)
            let elapsed = String(format: "%.1f", ProcessInfo.processInfo.systemUptime - started)
            print("\(index + 1)/\(conditions.count) \(result.requested.title): \(result.outcome.rawValue) (\(result.images.count) images, \(elapsed)s)")
            if stopReason != nil { break }
        }
        if let stopReason { manifest.messages.append(stopReason) }
        manifest.complete = manifest.results.allSatisfy { $0.progress == .finished }
        manifest.finishedAt = timestamp()
        try store.save(manifest)
        return manifest.complete && manifest.results.allSatisfy { $0.outcome == .captured } ? 0 : 1
    }
}
