import Darwin

@main
enum Posecap {
    static func main() {
        setbuf(stdout, nil)
        exit(CLI.run(arguments: Array(CommandLine.arguments.dropFirst())))
    }
}
