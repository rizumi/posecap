import Foundation
import AppKit

// The only replaceable control boundary needed by this MVP.
protocol DeviceControlling {
    func prepare(_ device: Device, conditions: [Condition]) throws
    func checkTarget(_ device: Device) throws
    func click(_ help: String, device: Device) throws
    // Returns false when the requested menu item is already selected.
    func setOrientation(_ orientation: Orientation, device: Device) throws -> Bool
    func readOrientation(_ device: Device) throws -> DeviceOrientation?
    func rotate(_ direction: RotationDirection, device: Device) throws
}

final class DeviceHubController: DeviceControlling {
    private let simulator: Simulator
    private let runner: CommandRunning
    private var expectedBundle: URL?
    private let cancellation: Cancellation
    init(simulator: Simulator, runner: CommandRunning, cancellation: Cancellation) {
        self.simulator = simulator; self.runner = runner; self.cancellation = cancellation
    }

    func prepare(_ device: Device, conditions: [Condition]) throws {
        let developer = try runner.run("/usr/bin/xcode-select", ["-p"], timeout: 30).text.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = URL(fileURLWithPath: developer).deletingLastPathComponent().appendingPathComponent("Applications/DeviceHub.app")
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "com.apple.dt.Devices",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == "27.1" else {
            throw ToolError("GUI control is implemented only for Device Hub 27.1. Select a matching Xcode.")
        }
        expectedBundle = app.resolvingSymlinksInPath()
        try validateProcess()
        try simulator.inventory().verifyGUIIdentity(device)
        try call(device, operation: "prepare", expected: "target-confirmed")
        let controls = Set(conditions.compactMap { $0.posture?.controlHelp })
        for help in controls.sorted() {
            try call(device, operation: "probe", control: help, expected: "control-confirmed")
        }
        if conditions.contains(where: { $0.orientation != nil }) {
            for direction in RotationDirection.allCases {
                try call(device, operation: "probe-rotation", control: direction.menuTitle, expected: "control-confirmed")
            }
        }
        for title in Set(conditions.compactMap { $0.orientation?.uiValue }).sorted() {
            try call(device, operation: "probe-orientation", control: title, expected: "control-confirmed")
        }
    }

    @discardableResult
    private func validateProcess() throws -> NSRunningApplication {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Devices")
        guard apps.count == 1, let actual = apps.first?.bundleURL?.resolvingSymlinksInPath(), actual == expectedBundle else {
            throw ToolError("Open exactly one Device Hub from the selected Xcode before GUI capture.")
        }
        return apps[0]
    }

    private func validateTargetEnvironment(_ device: Device) throws {
        try validateProcess()
        try simulator.inventory().verifyGUIIdentity(device)
    }

    func checkTarget(_ device: Device) throws {
        try validateTargetEnvironment(device)
        try call(device, operation: "check", expected: "target-confirmed")
    }

    func click(_ help: String, device: Device) throws {
        try validateTargetEnvironment(device)
        try call(device, operation: "click", control: help, expected: "dispatched")
    }

    func setOrientation(_ orientation: Orientation, device: Device) throws -> Bool {
        try validateTargetEnvironment(device)
        let value = try response(device, operation: "set-orientation", control: orientation.uiValue)
        switch value {
        case "dispatched": return true
        case "unchanged": return false
        default: throw ToolError("Unexpected Device Hub adapter response; stopping GUI operations.")
        }
    }

    func rotate(_ direction: RotationDirection, device: Device) throws {
        try validateTargetEnvironment(device)
        try call(device, operation: "rotate", control: direction.menuTitle, expected: "dispatched")
    }

    func readOrientation(_ device: Device) throws -> DeviceOrientation? {
        // Each fresh AX session checks selection/title within the operation.
        try validateTargetEnvironment(device)
        let value = try response(device, operation: "read-orientation", control: "")
        if value == "unknown" { return nil }
        guard let orientation = DeviceOrientation.allCases.first(where: { $0.menuTitle == value }) else {
            throw ToolError("Unexpected Device Hub orientation readback; stopping GUI operations.")
        }
        return orientation
    }

    private func call(_ device: Device, operation: String, control: String = "", expected: String) throws {
        guard try response(device, operation: operation, control: control) == expected else { throw ToolError("Unexpected Device Hub adapter response; stopping GUI operations.") }
    }

    private func response(_ device: Device, operation: String, control: String) throws -> String {
        let started = ProcessInfo.processInfo.systemUptime
        defer {
            if ProcessInfo.processInfo.environment["POSECAP_TRACE_TIMING"] == "1" {
                let elapsed = String(format: "%.3f", ProcessInfo.processInfo.systemUptime - started)
                let suffix = control.isEmpty ? "" : " " + control
                FileHandle.standardError.write(Data("[timing] \(elapsed)s Device Hub AX \(operation)\(suffix)\n".utf8))
            }
        }
        let access = try NativeHubAX(app: validateProcess(), cancellation: cancellation)
        return try DeviceHubAX(access: access).run(device: device, operation: operation, control: control)
    }
}
