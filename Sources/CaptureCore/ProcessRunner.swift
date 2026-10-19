import Foundation
import Darwin

final class Cancellation {
    private let lock = NSLock()
    private var flag = false
    private var sources: [DispatchSourceSignal] = []
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
    func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            source.setEventHandler { [weak self] in self?.cancel() }
            source.resume()
            sources.append(source)
        }
    }
    func check() throws { if cancelled { throw ToolError("Interrupted; saved results have been retained.") } }
    func sleep(seconds: TimeInterval) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        repeat {
            try check()
            Thread.sleep(forTimeInterval: min(0.1, max(0, deadline - ProcessInfo.processInfo.systemUptime)))
        } while ProcessInfo.processInfo.systemUptime < deadline
    }
}

struct CommandOutput {
    let stdout: Data
    let stderr: String
    var text: String { String(decoding: stdout, as: UTF8.self) }
}

protocol CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandOutput
}

final class ProcessRunner: CommandRunning {
    let cancellation: Cancellation
    init(cancellation: Cancellation) { self.cancellation = cancellation }

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) throws -> CommandOutput {
        try cancellation.check()
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("capture-process-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("stdout")
        let errURL = directory.appendingPathComponent("stderr")
        guard fm.createFile(atPath: outURL.path, contents: nil), fm.createFile(atPath: errURL.path, contents: nil) else { throw ToolError("Cannot create subprocess output files.") }
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)
        defer { try? outHandle.close(); try? errHandle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outHandle
        process.standardError = errHandle
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var interruption: String?
        while process.isRunning {
            if cancellation.cancelled { interruption = "Interrupted"; break }
            if ProcessInfo.processInfo.systemUptime >= deadline { interruption = "Command timed out after \(Int(timeout)) seconds"; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if let interruption {
            if process.isRunning { process.terminate() }
            let grace = ProcessInfo.processInfo.systemUptime + 0.5
            while process.isRunning && ProcessInfo.processInfo.systemUptime < grace { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw ToolError("\(interruption): \(URL(fileURLWithPath: executable).lastPathComponent). GUI action completion may be unknown.")
        }
        process.waitUntilExit()
        let errData = try readBounded(errURL, limit: 1_000_000)
        let stderr = String(decoding: errData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ToolError("\(URL(fileURLWithPath: executable).lastPathComponent) exited \(process.terminationStatus): \(stderr.prefix(4000))")
        }
        return CommandOutput(stdout: try readBounded(outURL, limit: 16_000_000), stderr: stderr)
    }
}

func readBounded(_ url: URL, limit: Int) throws -> Data {
    let h = try FileHandle(forReadingFrom: url)
    defer { try? h.close() }
    let data = try h.read(upToCount: limit + 1) ?? Data()
    guard data.count <= limit else { throw ToolError("File exceeds the supported size limit: \(url.lastPathComponent).") }
    return data
}
