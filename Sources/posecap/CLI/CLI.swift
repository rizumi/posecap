import ArgumentParser
import Foundation

enum CLI {
    static let version = "0.1.3"

    static func run(arguments: [String]) -> Int32 {
        var command: any ParsableCommand
        do {
            command = try PosecapCommand.parseAsRoot(arguments.isEmpty ? ["--help"] : arguments)
        } catch {
            let code = PosecapCommand.exitCode(for: error).rawValue
            let message = PosecapCommand.fullMessage(for: error)
            if code == 0 {
                print(message)
            } else {
                FileHandle.standardError.write(Data((message + "\n").utf8))
            }
            return code == 0 ? 0 : 2
        }
        do {
            try command.run()
            return 0
        } catch let code as ExitCode {
            return code.rawValue
        } catch {
            if PosecapCommand.exitCode(for: error).rawValue == 0 {
                print(PosecapCommand.fullMessage(for: error))
                return 0
            }
            Self.error(String(describing: error))
            return 2
        }
    }

    static func capture(options: CaptureCommand) -> Int32 {
        let cancellation = Cancellation()
        cancellation.installSignalHandlers()
        do {
            let runner = ProcessRunner(cancellation: cancellation)
            let simulator = Simulator(runner: runner)
            let inventory = try simulator.inventory()
            let device = try inventory.select(udid: options.udid, model: options.model)
            let plan = CapturePlan(posture: options.posture, orientation: options.orientation)
            let conditions = try plan.conditions(for: device)
            try inventory.verifyGUIIdentity(device)
            let environment = [
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "xcode": try runner.run("/usr/bin/xcodebuild", ["-version"], timeout: 30).text.trimmingCharacters(in: .whitespacesAndNewlines),
                "tool": version,
            ]
            let store = try CaptureStore(root: options.output)
            print("Capture: \(store.directory.path)")
            let controller = DeviceHubController(simulator: simulator, runner: runner)
            let engine = CaptureEngine(simulator: simulator, controller: controller, cancellation: cancellation)
            let code: Int32
            do {
                code = try engine.capture(device: device, conditions: conditions, label: options.label, store: store, environment: environment)
            } catch {
                Self.error("Capture stopped: \(error). Existing files are retained in \(store.directory.path).")
                return 1
            }
            print("Saved: \(store.directory.appendingPathComponent("manifest.json").path)")
            if code != 0 { error("Capture contains mismatched, failed, or unattempted conditions. See the manifest or report.") }
            return code
        } catch {
            Self.error(String(describing: error))
            return cancellation.cancelled ? 1 : 2
        }
    }

    private static func error(_ message: String) {
        FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    }
}
