import Foundation

public struct ToolError: Error, CustomStringConvertible {
    public let description: String
    public init(_ message: String) { description = message }
}

enum Posture: String, Codable, CaseIterable {
    case closed, halfOpen = "half-open", open
    var controlHelp: String {
        switch self {
        case .closed: return "Closed"
        case .halfOpen: return "Partially Open"
        case .open: return "Open"
        }
    }
}

enum Orientation: String, Codable, CaseIterable {
    case portrait, landscape
    var uiValue: String { self == .portrait ? "Portrait" : "Landscape Left" }
}

enum RotationDirection: String, CaseIterable {
    case left, right
    var menuTitle: String { self == .left ? "Rotate Left" : "Rotate Right" }
}

enum DeviceOrientation: String, Codable, CaseIterable {
    case portrait, upsideDown = "portrait-upside-down", landscapeLeft = "landscape-left"
    case landscapeRight = "landscape-right", faceUp = "face-up", faceDown = "face-down"
    var menuTitle: String {
        switch self {
        case .portrait: return "Portrait"
        case .upsideDown: return "Portrait Upside Down"
        case .landscapeLeft: return "Landscape Left"
        case .landscapeRight: return "Landscape Right"
        case .faceUp: return "Face Up"
        case .faceDown: return "Face Down"
        }
    }

    // Device Hub Controls-menu rotation order, verified using menu readback.
    private static let clockwise: [DeviceOrientation] = [.portrait, .landscapeRight, .upsideDown, .landscapeLeft]

    func rotations(to target: Orientation) -> [RotationDirection]? {
        guard let start = Self.clockwise.firstIndex(of: self) else { return nil }
        let end = target == .portrait ? 0 : 3
        switch (end - start + 4) % 4 {
        case 0: return []
        case 1: return [.right]
        case 2: return [.right, .right]
        default: return [.left]
        }
    }

    func rotated(_ direction: RotationDirection) -> DeviceOrientation? {
        guard let index = Self.clockwise.firstIndex(of: self) else { return nil }
        return Self.clockwise[(index + (direction == .right ? 1 : 3)) % 4]
    }
}

struct Condition: Codable, Equatable {
    var posture: Posture?
    var orientation: Orientation?
    var isCurrent: Bool { posture == nil && orientation == nil }
    var title: String {
        isCurrent ? "Current" : [posture?.rawValue, orientation?.rawValue].compactMap { $0 }.joined(separator: " / ")
    }
}

enum Outcome: String, Codable { case captured, verified, unverified, mismatched, failed }
enum Progress: String, Codable { case pending, running, finished }

struct Device: Codable, Equatable {
    let udid: String
    let name: String
    let model: String?
    let deviceTypeIdentifier: String
    let family: String?
    let runtimeIdentifier: String
    let runtimeVersion: String
    let state: String
    let available: Bool
    var isMobile: Bool { family == "iPhone" || family == "iPad" }
    var isDuo: Bool { deviceTypeIdentifier == "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo" }
    var summary: String { "\(udid)  \(model ?? "Unknown model")  name=\(name)  OS=\(runtimeVersion)  \(state)\(available ? "" : " (unavailable)")" }
}

struct Display: Codable, Equatable {
    let id: String
    let name: String
    let deviceName: String?
    let type: String
    let uiOrientation: String?
    let nativeWidth: Int?
    let nativeHeight: Int?
}

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
