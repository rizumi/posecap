import XCTest
@testable import posecap

final class SimulatorTests: XCTestCase {
    func testBundledDeviceHubAdapterIsAvailable() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "DeviceHub", withExtension: "applescript"))
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("on run argv"))
    }

    func testDuplicateRuntimeBuildsAreAllowedButConflictingVersionsFail() throws {
        let json = #"{"devicetypes":[{"identifier":"phone","name":"iPhone Duo","productFamily":"iPhone"}],"runtimes":[{"identifier":"runtime","version":"27.1","buildversion":"example-a"},{"identifier":"runtime","version":"27.1","buildversion":"example-b"}],"devices":{"runtime":[{"udid":"00000000-0000-0000-0000-000000000001","name":"Home","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"phone"}]}}"#
        XCTAssertEqual(try Inventory(data: Data(json.utf8)).devices[0].runtimeVersion, "27.1")
        XCTAssertThrowsError(try Inventory(data: Data(json.replacingOccurrences(of: #""version":"27.1","buildversion":"example-b""#, with: #""version":"27.2","buildversion":"example-b""#).utf8)))
    }

    func testDeviceSelectionUsesModelNotDisplayNameAndRejectsAmbiguity() throws {
        let a = device(name: "ExampleApp", model: "iPhone Duo")
        let b = device(id: "00000000-0000-0000-0000-000000000002", name: "iPhone Duo", model: "iPhone 18 Pro")
        XCTAssertEqual(try Inventory(devices: [a, b]).select(udid: nil, model: "iPhone Duo"), a)
        XCTAssertThrowsError(try Inventory(devices: [a, b]).select(udid: nil, model: nil))
        XCTAssertThrowsError(try Inventory(devices: [a, device(id: b.udid)]).select(udid: nil, model: "iPhone Duo"))
        XCTAssertThrowsError(try Inventory(devices: [device(state: "Shutdown")]).select(udid: a.udid, model: nil))
    }

    func testGUIIdentityIncludesShutdownDuplicates() {
        let a = device()
        let duplicate = device(id: "00000000-0000-0000-0000-000000000002", state: "Shutdown")
        XCTAssertThrowsError(try Inventory(devices: [a, duplicate]).verifyGUIIdentity(a))
    }

    func testEnumerationUsesDiscoveredIDsAndOnlyBuiltInScreens() throws {
        let displays = try DisplayParser.parse(enumeration(ids: ["17", "42"]))
        XCTAssertEqual(displays.map(\.id), ["17", "42"])
        XCTAssertEqual(displays.map(\.uiOrientation), ["Portrait", "Portrait"])
        XCTAssertThrowsError(try DisplayParser.parse("Power state: On"))
        XCTAssertThrowsError(try DisplayParser.parse(enumeration(ids: ["17", "17"])))
        XCTAssertThrowsError(try DisplayParser.parse(enumeration(ids: ["17"]).replacingOccurrences(of: "Screen ID: 17", with: "Screen ID: 99")))
    }
}
