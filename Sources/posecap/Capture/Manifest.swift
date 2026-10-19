import Foundation

enum Outcome: String, Codable { case captured, verified, unverified, mismatched, failed }
enum Progress: String, Codable { case pending, running, finished }

struct ImageRecord: Codable {
    let displayID: String
    let path: String
    let width: Int
    let height: Int
}

struct Observations: Codable {
    var guiTargetMatched: Bool?
    var dispatchedControls: [String] = []
    // Fold state has no readback in the current backend.
    var observedPosture: Posture?
    var observedDeviceOrientation: DeviceOrientation?
    var deviceOrientationSource: String?
    var guiOrientationBeforeCapture: DeviceOrientation?
    var guiOrientationAfterCapture: DeviceOrientation?
    var guiPostureSelection: String?
    var beforeDisplays: [Display] = []
    var afterDisplays: [Display] = []
    var activeDisplayID: String?
    var displaySelectionReason: String?
}

struct CaptureResult: Codable {
    let index: Int
    let requested: Condition
    var progress: Progress = .pending
    var outcome: Outcome = .failed
    var observations = Observations()
    var images: [ImageRecord] = []
    var messages: [String] = []
}

struct Manifest: Codable {
    var schemaVersion = 1
    let captureID: String
    let createdAt: String
    var finishedAt: String?
    let label: String?
    let device: Device
    let environment: [String: String]
    var results: [CaptureResult]
    var complete = false
    var messages: [String] = []
}

func timestamp(_ date: Date = Date()) -> String {
    ISO8601DateFormatter().string(from: date)
}

enum Assessment {
    static func evaluate(_ condition: Condition, observations: Observations, imageCount: Int, failed: Bool) -> Outcome {
        if failed || imageCount == 0 { return .failed }
        if let expected = condition.posture, let actual = observations.observedPosture, expected != actual { return .mismatched }
        if let expected = condition.orientation, let actual = observations.observedDeviceOrientation, expected.uiValue != actual.menuTitle { return .mismatched }
        return .captured
    }
}
