import Foundation

struct Options {
    enum Command: String { case devices, capture, report, help, version }
    var command: Command
    var udid: String?
    var model: String?
    var label: String?
    var output = "./output"
    var input: String?
    var posture: Posture?
    var orientation: Orientation?
    var current = false
    var language: ReportLanguage = .en
    var details = false
    var title: String?

    static func parse(_ args: [String]) throws -> Options {
        guard let first = args.first else { return Options(command: .help) }
        if first == "--help" || first == "-h" { return Options(command: .help) }
        if first == "--version" { return Options(command: .version) }
        guard let command = Command(rawValue: first), command != .version else { throw ToolError("Unknown command: \(first). Use posecap --help.") }
        if args.dropFirst().contains("--help") || args.dropFirst().contains("-h") { return Options(command: .help) }
        var options = Options(command: command)
        var seen = Set<String>()
        var i = 1
        while i < args.count {
            let key = args[i]
            guard seen.insert(key).inserted else { throw ToolError("Repeated option: \(key).") }
            if key == "--current" && command == .capture { options.current = true; i += 1; continue }
            if key == "--details" && command == .report { options.details = true; i += 1; continue }
            let allowed: Set<String> = command == .capture
                ? ["--udid", "--model", "--label", "--output", "--posture", "--orientation"]
                : command == .report ? ["--input", "--language", "--title"] : []
            guard allowed.contains(key) else { throw ToolError("Unknown option for \(command.rawValue): \(key).") }
            guard i + 1 < args.count, !args[i + 1].hasPrefix("--") else { throw ToolError("Missing value for \(key).") }
            let value = args[i + 1]
            guard !value.isEmpty, !value.contains("\0") else { throw ToolError("Empty or invalid value for \(key).") }
            switch key {
            case "--udid":
                guard UUID(uuidString: value) != nil else { throw ToolError("--udid requires a Simulator UUID.") }
                options.udid = value.uppercased()
            case "--model": options.model = value
            case "--label": options.label = value
            case "--output": options.output = value
            case "--input": options.input = value
            case "--title": options.title = value
            case "--language":
                guard let language = ReportLanguage(rawValue: value) else { throw ToolError("--language must be en or ja.") }
                options.language = language
            case "--posture":
                guard let v = Posture(rawValue: value) else { throw ToolError("Posture must be closed, half-open, or open.") }
                options.posture = v
            case "--orientation":
                guard let v = Orientation(rawValue: value) else { throw ToolError("Orientation must be portrait or landscape (landscape-left).") }
                options.orientation = v
            default: break
            }
            i += 2
        }
        guard options.udid == nil || options.model == nil else { throw ToolError("Use only one of --udid and --model.") }
        guard !options.current || (options.posture == nil && options.orientation == nil) else { throw ToolError("--current cannot be combined with --posture or --orientation.") }
        if command == .report && options.input == nil { throw ToolError("report requires --input <directory>.") }
        return options
    }

    func conditions(for device: Device) throws -> [Condition] {
        guard device.isMobile else { throw ToolError("Cannot establish iPhone/iPad capture capabilities for this device.") }
        if current { return [Condition()] }
        if posture != nil && !device.isDuo { throw ToolError("This model has no implemented posture controller; the requested posture will not be substituted.") }
        let orientations = orientation.map { [$0] } ?? Orientation.allCases
        let postures: [Posture?] = device.isDuo ? (posture.map { [$0] } ?? Posture.allCases).map { Optional($0) } : [nil]
        return postures.flatMap { p in orientations.map { Condition(posture: p, orientation: $0) } }
    }
}
