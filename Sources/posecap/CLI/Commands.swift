import ArgumentParser
import Foundation

extension Posture: ExpressibleByArgument {}
extension Orientation: ExpressibleByArgument {}
extension ReportLanguage: ExpressibleByArgument {}

struct PosecapCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "posecap",
        abstract: "Capture iOS Simulator screenshots.",
        version: "posecap \(CLI.version)",
        subcommands: [DevicesCommand.self, CaptureCommand.self, ReportCommand.self])
}

struct DevicesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devices", abstract: "List Simulators",
        discussion: "List iPhone/iPad Simulators with UUID, model, name, OS, and state.")

    mutating func run() throws {
        let cancellation = Cancellation()
        cancellation.installSignalHandlers()
        do {
            let inventory = try Simulator(runner: ProcessRunner(cancellation: cancellation)).inventory()
            print("UDID  MODEL  DISPLAY NAME  OS  STATE")
            for device in inventory.devices where device.isMobile { print(device.summary) }
        } catch {
            if cancellation.cancelled { throw ExitCode(1) }
            throw error
        }
    }
}

struct ReportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report", abstract: "Generate an HTML report",
        discussion: "Writes index.html in the input directory. Images and manifests are kept.")

    @Option(help: "Directory containing capture runs (required)")
    var input: String
    @Option(help: "Report heading")
    var title: String?
    @Option(help: "Report language")
    var language: ReportLanguage = .en
    @Flag(help: "Include capture diagnostics")
    var details = false

    mutating func validate() throws {
        try validateText(input, option: "--input")
        try validateText(title, option: "--title")
    }

    mutating func run() throws {
        print(try Report.generate(input: input, language: language, details: details, title: title).path)
    }
}

private func validateText(_ value: String?, option: String) throws {
    if let value, value.isEmpty || value.contains("\0") {
        throw ValidationError("Empty or invalid value for \(option).")
    }
}

struct CaptureCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture", abstract: "Capture the prepared app screen",
        discussion: """
        Defaults to all postures/orientations: six for Duo, two for other models.
        Requires a booted Simulator; select one if several are booted.
        --current cannot be combined with posture or orientation filters.
        GUI changes require Device Hub 27.1 and Accessibility/Automation access.
        Final posture/orientation is left in place. Completed captures exit 0.
        """)

    @Option(help: "Simulator UUID (instead of --model)")
    var udid: String?
    @Option(help: "Exact Simulator model name")
    var model: String?
    @Option(help: "Screen name in the report")
    var label: String?
    @Option(help: "Output directory")
    var output = "./output"
    @Option(help: "Device posture (iPhone Duo only)")
    var posture: Posture?
    @Option(help: "Device orientation (landscape uses landscape-left)")
    var orientation: Orientation?
    @Flag(help: "Capture without GUI changes")
    var current = false

    mutating func validate() throws {
        for (value, name) in [(model, "--model"), (label, "--label"), (Optional(output), "--output")] {
            try validateText(value, option: name)
        }
        if let udid {
            guard UUID(uuidString: udid) != nil else {
                throw ValidationError("--udid requires a Simulator UUID.")
            }
            self.udid = udid.uppercased()
        }
        guard udid == nil || model == nil else {
            throw ValidationError("Use only one of --udid and --model.")
        }
        guard !current || (posture == nil && orientation == nil) else {
            throw ValidationError("--current cannot be combined with --posture or --orientation.")
        }
    }

    mutating func run() throws {
        let code = CLI.capture(options: self)
        if code != 0 { throw ExitCode(code) }
    }
}
