import Foundation

public enum CLI {
    static let version = "0.1.0"
    public static let help = """
    posecap — Capture the currently displayed iOS Simulator screen.

    Usage:
      posecap devices
      posecap capture [--udid <uuid> | --model <model>] [--output <directory>]
                      [--label <text>]
                      [--current | [--posture <posture>] [--orientation <orientation>]]
      posecap report --input <directory> [--title <app name>] [--language en|ja] [--details]

    capture defaults to all conditions: six for iPhone Duo, two for other iPhone/iPad.
    --posture closed|half-open|open and --orientation portrait|landscape may be
    combined to narrow the matrix. Landscape means landscape-left.
    --current captures once without changing posture or orientation.
    --output defaults to ./output. Each invocation creates a new capture directory.
    --label is optional metadata, never a path or overwrite key.

    Only booted Simulators are eligible. No boot, app launch, or navigation is
    performed. --model matches the exact model name, not a custom display name.
    Without a selector, exactly one available iPhone/iPad must be booted.
    GUI changes require Device Hub 27.1 from the selected Xcode, an accessible
    single window, and macOS Accessibility/Automation permissions.
    The final posture is left in place. Do not interact with Device Hub during capture.

    Unverified conditions are saved and labeled. Multiple built-in displays are
    all saved if the active display is unknown. No condition is silently substituted.
    --language selects the report language (default: en).
    --details includes capture diagnostics in the report (hidden by default).
    --title sets the report heading, separately from screen labels.
    report includes all immediate capture directories and replaces only index.html.

    Exit codes: 0 complete; 1 incomplete/unverified/mismatched/failed capture;
                2 invalid arguments, selection, report, or setup error.
    Options: --help, --version
    """

    public static func run(arguments: [String]) -> Int32 {
        let cancellation = Cancellation()
        cancellation.installSignalHandlers()
        do {
            let options = try Options.parse(arguments)
            switch options.command {
            case .help: print(help); return 0
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
