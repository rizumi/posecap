import Foundation
import CoreGraphics
import ImageIO
@testable import posecap

func device(id: String = "00000000-0000-0000-0000-000000000001", name: String = "ExampleApp", model: String = "iPhone Duo", state: String = "Booted") -> Device {
    Device(udid: id, name: name, model: model, deviceTypeIdentifier: model == "iPhone Duo" ? "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo" : "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro", family: "iPhone", runtimeIdentifier: "example-runtime", runtimeVersion: "27.1", state: state, available: true)
}

func temporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("capture-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
}

func readManifest(_ store: CaptureStore) throws -> Manifest {
    try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: store.directory.appendingPathComponent("manifest.json")))
}

func enumeration(ids: [String], deviceNames: [String: String] = [:]) -> String {
    "Port:\n    Connected Screens:\n" + ids.map { id in
        """
            (\(id)) LCD:
                Screen ID: \(id)
                Name: LCD
                Device Name: \(deviceNames[id] ?? "example-\(id)")
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

final class FakeRunner: CommandRunning {
    var ids = ["17"]
    var deviceNames: [String: String] = [:]
    var enumerationReadbacks: [String] = []
    var screenshotCount = 0
    var screenshotDisplayIDs: [String] = []
    var enumerationCount = 0
    var failScreenshot: Int?
    var afterScreenshot: (() -> Void)?
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandOutput {
        if arguments.contains("enumerate") {
            enumerationCount += 1
            let text = enumerationReadbacks.isEmpty ? enumeration(ids: ids, deviceNames: deviceNames) : enumerationReadbacks.removeFirst()
            return CommandOutput(stdout: Data(text.utf8), stderr: "")
        }
        if arguments.contains("screenshot") {
            screenshotCount += 1
            screenshotDisplayIDs.append(String(arguments.first { $0.hasPrefix("--display=") }!.dropFirst("--display=".count)))
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

final class FakeController: DeviceControlling {
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

func reportDisplays() -> [Display] {
    [Display(id: "42", name: "LCD", deviceName: "primary", type: "Integrated", uiOrientation: "Portrait", nativeWidth: 2, nativeHeight: 3),
     Display(id: "17", name: "LCD-1", deviceName: "primary-1", type: "Integrated", uiOrientation: "Portrait", nativeWidth: 3, nativeHeight: 4)]
}
