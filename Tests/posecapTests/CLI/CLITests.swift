import XCTest
@testable import posecap

final class CLITests: XCTestCase {
    func testHelpSelectsCommandWithoutRequiringArguments() throws {
        for command in ["devices", "capture", "report"] {
            for flag in ["--help", "-h"] {
                XCTAssertEqual(CLI.run(arguments: [command, flag]), 0)
            }
        }
        XCTAssertEqual(CLI.run(arguments: []), 0)
        XCTAssertEqual(CLI.run(arguments: ["--version"]), 0)
        XCTAssertFalse(PosecapCommand.helpMessage().contains("--posture"))
        XCTAssertFalse(ReportCommand.helpMessage().contains("--posture"))
        XCTAssertThrowsError(try PosecapCommand.parseAsRoot(["report"]))
    }

    func testCommandValidationAndArgumentParserSyntax() throws {
        let capture = try XCTUnwrap(PosecapCommand.parseAsRoot([
            "capture", "--model=iPhone Duo", "--label", "Home",
        ]) as? CaptureCommand)
        XCTAssertEqual(capture.model, "iPhone Duo")
        XCTAssertEqual(capture.label, "Home")
        XCTAssertEqual(capture.output, "./output")
        let id = "abcdefab-0000-0000-0000-000000000001"
        XCTAssertEqual(try CaptureCommand.parse(["--udid", id]).udid, id.uppercased())
        for args in [
            ["capture", "--udid", "invalid"], ["capture", "--model", ""],
            ["capture", "--label", "bad\0label"], ["capture", "--output", ""],
            ["capture", "--current"],
            ["capture", "--current", "--orientation", "portrait"],
            ["capture", "--posture", "invalid"], ["capture", "--orientation", "invalid"],
            ["capture", "--model"], ["report", "--input", ""],
            ["report", "--input", "output", "--title", ""],
            ["devices", "--current"],
        ] {
            XCTAssertEqual(CLI.run(arguments: args), 2, "Arguments: \(args)")
        }
        XCTAssertEqual(try CaptureCommand.parse(["--label", "First", "--label", "Last"]).label, "Last")
        XCTAssertEqual(CLI.run(arguments: ["help", "capture"]), 0)
    }

    func testCommandSpecificOptions() throws {
        XCTAssertThrowsError(try CaptureCommand.parse(["--current", "--posture", "closed"]))
        XCTAssertThrowsError(try CaptureCommand.parse(["--udid", device().udid, "--model", "iPhone Duo"]))
        XCTAssertThrowsError(try PosecapCommand.parseAsRoot(["boot"]))
        XCTAssertThrowsError(try CaptureCommand.parse(["--all"]))
        XCTAssertEqual(try ReportCommand.parse(["--input", "output"]).language, .en)
        XCTAssertEqual(try ReportCommand.parse(["--input", "output", "--language", "ja"]).language, .ja)
        XCTAssertThrowsError(try ReportCommand.parse(["--input", "output", "--language", "fr"]))
        XCTAssertThrowsError(try CaptureCommand.parse(["--language", "ja"]))
        XCTAssertFalse(try ReportCommand.parse(["--input", "output"]).details)
        XCTAssertTrue(try ReportCommand.parse(["--input", "output", "--details"]).details)
        XCTAssertThrowsError(try CaptureCommand.parse(["--details"]))
        XCTAssertTrue(try ReportCommand.parse(["--input", "output", "--details", "--details"]).details)
        XCTAssertEqual(try ReportCommand.parse(["--input", "output", "--title", "My App"]).title, "My App")
        XCTAssertThrowsError(try CaptureCommand.parse(["--title", "My App"]))
    }
}
