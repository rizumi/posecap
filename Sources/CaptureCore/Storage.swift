import Foundation
import ImageIO

enum SafeFiles {
    static func isSymlink(_ url: URL) throws -> Bool {
        // lstat-style resource values also detect dangling symlinks.
        (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true
    }

    static func rejectSymlinks(in url: URL) throws {
        var part = url.absoluteURL
        while part.path != "/" {
            // attributesOfItem uses lstat and detects dangling links as well.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: part.path), attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                // Foundation can spell the OS-owned /private/var and /private/tmp
                // aliases as /var and /tmp. These fixed system aliases are safe;
                // user-created symlinks in or above a result directory are not.
                if ["/var", "/tmp"].contains(part.path),
                   (try? FileManager.default.destinationOfSymbolicLink(atPath: part.path)) == "private" + part.path {
                    part.deleteLastPathComponent()
                    continue
                }
                throw ToolError("Symbolic links are not allowed in result paths: \(part.lastPathComponent).")
            }
            part.deleteLastPathComponent()
        }
    }

    static func directory(_ path: String, create: Bool) throws -> URL {
        let url = URL(fileURLWithPath: path, isDirectory: true).absoluteURL
        try rejectSymlinks(in: url)
        if create { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw ToolError("Expected a directory: \(url.lastPathComponent).") }
        return url
    }

    static func regularFile(_ url: URL) throws {
        try rejectSymlinks(in: url)
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw ToolError("Expected a regular file: \(url.lastPathComponent).") }
    }

    static func imageURL(_ relativePath: String, in directory: URL) throws -> URL {
        guard !relativePath.isEmpty, relativePath != ".", relativePath != "..",
              !relativePath.contains("/"), !relativePath.contains("\\"),
              !relativePath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              relativePath.lowercased().hasSuffix(".png") else { throw ToolError("Unsafe image path in capture metadata.") }
        let url = directory.appendingPathComponent(relativePath)
        try regularFile(url)
        return url
    }

    static func atomicWrite(_ data: Data, to url: URL) throws {
        try rejectSymlinks(in: url)
        if FileManager.default.fileExists(atPath: url.path) { try regularFile(url) }
        try data.write(to: url, options: .atomic)
    }
}

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
