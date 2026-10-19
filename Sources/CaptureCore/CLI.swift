import Foundation

public enum CLI {
    static let version = "0.1.0"
    public static let help = """
    posecap — Capture iOS Simulator screenshots.

    Usage: posecap <command> [options]

    Commands:
      devices    List Simulators
      capture    Capture the prepared app screen
      report     Generate an HTML report

    Options:
      -h, --help    Show help
      --version     Show version

    Run posecap <command> --help for command options.
    """

    static func help(for command: Options.Command?) -> String {
        switch command {
        case .capture:
            return """
            Usage: posecap capture [options]

            Options:
              --model NAME          Exact Simulator model name
              --udid UUID           Simulator UUID (instead of --model)
              --current             Capture without GUI changes
              --posture POSTURE     closed | half-open | open (iPhone Duo only)
              --orientation DIR     portrait | landscape (landscape-left)
              --label TEXT          Screen name in the report
              --output PATH         Output directory (default: ./output)
              -h, --help            Show help

            Defaults to all postures/orientations: six for Duo, two for other models.
            Requires a booted Simulator; select one if several are booted.
            --current cannot be combined with posture or orientation filters.
            GUI changes require Device Hub 27.1 and Accessibility/Automation access.
            Final posture/orientation is left in place. Unverified captures exit 1.
            """
        case .report:
            return """
            Usage: posecap report --input PATH [options]

            Options:
              --input PATH          Directory containing capture runs (required)
              --title TEXT          Report heading
              --language en|ja      Report language (default: en)
              --details             Include capture diagnostics
              -h, --help            Show help

            Writes index.html in the input directory. Images and manifests are kept.
            """
        case .devices:
            return """
            Usage: posecap devices

            List iPhone/iPad Simulators with UUID, model, name, OS, and state.
            """
        default:
            return help
        }
    }

    public static func run(arguments: [String]) -> Int32 {
        let cancellation = Cancellation()
        cancellation.installSignalHandlers()
        do {
            let options = try Options.parse(arguments)
            switch options.command {
            case .help: print(help(for: options.helpTopic)); return 0
            case .version: print("posecap \(version)"); return 0
            case .report:
                print(try Report.generate(input: options.input!, language: options.language, details: options.details, title: options.title).path)
                return 0
            case .devices, .capture: break
            }
            let runner = ProcessRunner(cancellation: cancellation)
            let simulator = Simulator(runner: runner)
            let inventory = try simulator.inventory()
            if options.command == .devices {
                print("UDID  MODEL  DISPLAY NAME  OS  STATE")
                for device in inventory.devices where device.isMobile { print(device.summary) }
                return 0
            }
            let device = try inventory.select(udid: options.udid, model: options.model)
            let conditions = try options.conditions(for: device)
            if !options.current { try inventory.verifyGUIIdentity(device) }
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
            if code != 0 { error("Capture contains unverified, mismatched, failed, or unattempted conditions. See the manifest or report.") }
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
