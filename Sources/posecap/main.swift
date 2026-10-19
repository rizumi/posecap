import CaptureCore
import Darwin

setbuf(stdout, nil)
exit(CLI.run(arguments: Array(CommandLine.arguments.dropFirst())))
