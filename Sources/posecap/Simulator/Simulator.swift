import Foundation

struct Simulator {
    let runner: CommandRunning
    func inventory() throws -> Inventory {
        try Inventory(data: runner.run("/usr/bin/xcrun", ["simctl", "list", "-j"], timeout: 30).stdout)
    }
    func displays(_ device: Device) throws -> [Display] {
        let output = try runner.run("/usr/bin/xcrun", ["simctl", "io", device.udid, "enumerate"], timeout: 30)
        return try DisplayParser.parse(output.text)
    }
    func screenshot(_ device: Device, display: Display, to file: URL) throws {
        _ = try runner.run("/usr/bin/xcrun", ["simctl", "io", device.udid, "screenshot", "--type=png", "--display=\(display.id)", file.path], timeout: 30)
    }
}

enum DisplayParser {
    static func parse(_ text: String) throws -> [Display] {
        guard let start = text.range(of: "    Connected Screens:") else { throw ToolError("Display enumeration format is unknown; cannot identify built-in screens.") }
        let section = String(text[start.upperBound...]).components(separatedBy: "\nPort:")[0]
        let expression = try NSRegularExpression(pattern: #"(?m)^    \(([0-9]+)\) ([^\n]+):\s*$"#)
        let ns = section as NSString
        let matches = expression.matches(in: section, range: NSRange(location: 0, length: ns.length))
        var displays: [Display] = []
        for (index, match) in matches.enumerated() {
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let block = ns.substring(with: NSRange(location: NSMaxRange(match.range), length: end - NSMaxRange(match.range)))
            var fields: [String: String] = [:]
            for line in block.components(separatedBy: .newlines) {
                let pieces = line.trimmingCharacters(in: .whitespaces).split(separator: ":", maxSplits: 1).map(String.init)
                if pieces.count == 2 { fields[pieces[0]] = pieces[1].trimmingCharacters(in: .whitespaces) }
            }
            guard fields["Screen Type"] == "Integrated" else { continue }
            let id = ns.substring(with: match.range(at: 1))
            guard fields["Screen ID"] == id else { throw ToolError("Inconsistent screen identifiers in enumeration.") }
            let sizes = (fields["Pixel Size"] ?? "").split { !$0.isNumber }.compactMap { Int($0) }
            displays.append(Display(id: id, name: fields["Name"] ?? ns.substring(with: match.range(at: 2)),
                                    deviceName: fields["Device Name"], type: "Integrated", uiOrientation: fields["UI Orientation"],
                                    nativeWidth: sizes.count == 2 ? sizes[0] : nil, nativeHeight: sizes.count == 2 ? sizes[1] : nil))
        }
        guard !displays.isEmpty, Set(displays.map(\.id)).count == displays.count else { throw ToolError("No unambiguous built-in display inventory is available.") }
        return displays.sorted { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
    }
}
