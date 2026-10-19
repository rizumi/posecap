import Foundation
import ImageIO

struct CaptureStore {
    let directory: URL
    let captureID: String
    init(root: String) throws {
        let rootURL = try SafeFiles.directory(root, create: true)
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = TimeZone(secondsFromGMT: 0)
        date.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        captureID = date.string(from: Date()) + "-" + UUID().uuidString.lowercased()
        directory = rootURL.appendingPathComponent(captureID, isDirectory: true)
        // Never reuse an existing run, even in the unlikely event of an ID collision.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }
    func save(_ manifest: Manifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try SafeFiles.atomicWrite(encoder.encode(manifest), to: directory.appendingPathComponent("manifest.json"))
    }
    func image(index: Int, display: Display, capture: (URL) throws -> Void) throws -> ImageRecord {
        guard display.id.allSatisfy(\.isNumber), !display.id.isEmpty else { throw ToolError("Unsafe display identifier.") }
        let name = String(format: "%02d", index + 1) + "-display-\(display.id).png"
        let final = directory.appendingPathComponent(name)
        let temporary = directory.appendingPathComponent(".partial-\(UUID().uuidString).png")
        try SafeFiles.rejectSymlinks(in: directory)
        guard !FileManager.default.fileExists(atPath: final.path) else { throw ToolError("Refusing to overwrite an existing screenshot.") }
        defer { try? FileManager.default.removeItem(at: temporary) }
        try capture(temporary)
        try SafeFiles.regularFile(temporary)
        guard let source = CGImageSourceCreateWithURL(temporary as CFURL, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0, image.height > 0 else {
            throw ToolError("Screenshot output is not a decodable PNG.")
        }
        try FileManager.default.moveItem(at: temporary, to: final)
        return ImageRecord(displayID: display.id, path: name, width: image.width, height: image.height)
    }
}
