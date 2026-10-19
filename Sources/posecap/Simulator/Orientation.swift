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
