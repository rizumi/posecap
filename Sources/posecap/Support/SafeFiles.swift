import Foundation

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
