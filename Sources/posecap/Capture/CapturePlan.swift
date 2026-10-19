struct Condition: Codable, Equatable {
    var posture: Posture?
    var orientation: Orientation?
    var isCurrent: Bool { posture == nil && orientation == nil }
    var title: String {
        isCurrent ? "Current" : [posture?.rawValue, orientation?.rawValue].compactMap { $0 }.joined(separator: " / ")
    }
}

struct CapturePlan {
    var current = false
    var posture: Posture?
    var orientation: Orientation?

    func conditions(for device: Device) throws -> [Condition] {
        guard device.isMobile else { throw ToolError("Cannot establish iPhone/iPad capture capabilities for this device.") }
        if current { return [Condition()] }
        if posture != nil && !device.isDuo { throw ToolError("This model has no implemented posture controller; the requested posture will not be substituted.") }
        let orientations = orientation.map { [$0] } ?? Orientation.allCases
        let postures: [Posture?] = device.isDuo ? (posture.map { [$0] } ?? Posture.allCases).map { Optional($0) } : [nil]
        return postures.flatMap { p in orientations.map { Condition(posture: p, orientation: $0) } }
    }
}
