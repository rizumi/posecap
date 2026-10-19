struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}
