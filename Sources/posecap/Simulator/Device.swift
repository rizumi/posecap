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
