import Foundation
import ImageIO

struct CaptureStore {
    let directory: URL
    let captureID: String
    init(root: String = "./output", direct: Bool = false, now: Date = Date()) throws {
        let rootURL = try SafeFiles.directory(root, create: true)
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = TimeZone(secondsFromGMT: 0)
        date.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        if direct {
            directory = rootURL
            captureID = rootURL.lastPathComponent
        } else {
            let base = date.string(from: now)
            var suffix = 0
            while true {
                let name = base + (suffix == 0 ? "" : "-\(suffix)")
                let candidate = rootURL.appendingPathComponent(name, isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
                    directory = candidate
                    captureID = name
                    break
                } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                    suffix += 1
                }
            }
        }
    }

    func save(_ manifest: Manifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try SafeFiles.atomicWrite(encoder.encode(manifest), to: directory.appendingPathComponent("manifest.json"))
    }
    func image(condition: Condition, display: Display, capture: (URL) throws -> Void) throws -> ImageRecord {
        guard display.id.allSatisfy(\.isNumber), !display.id.isEmpty else { throw ToolError("Unsafe display identifier.") }
        let stem = [condition.posture?.rawValue, condition.orientation?.rawValue].compactMap { $0 }.joined(separator: "-")
        let name = (stem.isEmpty ? "current" : stem) + "-display-\(display.id).png"
        let final = directory.appendingPathComponent(name)
        let temporary = directory.appendingPathComponent(".partial-\(UUID().uuidString).png")
        try SafeFiles.rejectSymlinks(in: final)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try capture(temporary)
        try SafeFiles.regularFile(temporary)
        guard let source = CGImageSourceCreateWithURL(temporary as CFURL, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0, image.height > 0 else {
            throw ToolError("Screenshot output is not a decodable PNG.")
        }
        try SafeFiles.atomicWrite(Data(contentsOf: temporary), to: final)
        return ImageRecord(displayID: display.id, path: name, width: image.width, height: image.height)
    }
}
