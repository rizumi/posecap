import XCTest
import ApplicationServices
@testable import posecap

private final class AXNode {
    var values: [String: String]
    var flags: [String: Bool] = [:]
    var collections: [String: [AXNode]]
    init(_ role: String, _ children: [AXNode] = [], title: String? = nil) {
        values = [kAXRoleAttribute: role]
        values[kAXTitleAttribute] = title
        collections = [kAXChildrenAttribute: children]
    }
}

private final class FakeHubAX: HubAXAccess {
    let application = AXNode(kAXApplicationRole)
    let row = AXNode(kAXRowRole)
    let window = AXNode(kAXWindowRole, title: "ExampleApp – iOS 27.1")
    let outline = AXNode(kAXOutlineRole)
    let button = AXNode(kAXButtonRole)
    let controls = AXNode(kAXMenuRole)
    let orientations = AXNode(kAXMenuRole)
    var foreground = false
    var pressed: [AXNode] = []
    var onPress: ((AXNode) -> Void)?
    var onString: ((AXNode, String) throws -> Void)?
    var failure = false
    init() {
        let labels = ["ExampleApp", "27.1", "Simulator"].map { value -> AXNode in
            let label = AXNode(kAXStaticTextRole); label.values[kAXValueAttribute] = value; return label
        }
        row.collections[kAXChildrenAttribute] = [AXNode(kAXCellRole, labels)]
        row.flags[kAXSelectedAttribute] = true
        outline.collections[kAXChildrenAttribute] = [row]
        button.values[kAXHelpAttribute] = "Open"; button.flags[kAXEnabledAttribute] = true
        let inner = AXNode(kAXSplitGroupRole, [AXNode(kAXGroupRole, [AXNode(kAXScrollAreaRole, [outline])]), AXNode(kAXGroupRole), AXNode(kAXGroupRole, [button])])
        window.collections[kAXChildrenAttribute] = [AXNode(kAXGroupRole, [AXNode(kAXSplitGroupRole, [AXNode(kAXGroupRole, [inner])])])]
        application.collections[kAXWindowsAttribute] = [window]
        orientations.collections[kAXChildrenAttribute] = DeviceOrientation.allCases.map {
            let item = AXNode(kAXMenuItemRole, title: $0.menuTitle); item.flags[kAXEnabledAttribute] = true; return item
        }
        orientations.collections[kAXChildrenAttribute]![0].values["AXMenuItemMarkChar"] = "✓"
        controls.collections[kAXChildrenAttribute] = RotationDirection.allCases.map {
            let item = AXNode(kAXMenuItemRole, title: $0.menuTitle); item.flags[kAXEnabledAttribute] = true; return item
        }
        let device = AXNode(kAXMenuBarItemRole, [AXNode(kAXMenuRole, [AXNode(kAXMenuItemRole, [orientations], title: "Orientation")])], title: "Device")
        application.collections[kAXMenuBarAttribute] = [AXNode(kAXMenuBarRole, [device, AXNode(kAXMenuBarItemRole, [controls], title: "Controls")])]
    }
    func elements(_ element: AXNode, _ attribute: String) throws -> [AXNode] {
        if failure { throw ToolError("AX failure") }
        return element.collections[attribute] ?? []
    }
    func string(_ element: AXNode, _ attribute: String) throws -> String? {
        try onString?(element, attribute)
        return element.values[attribute]
    }
    func bool(_ element: AXNode, _ attribute: String) throws -> Bool { element.flags[attribute] ?? false }
    func same(_ lhs: AXNode, _ rhs: AXNode) -> Bool { lhs === rhs }
    func select(_ row: AXNode) throws { row.flags[kAXSelectedAttribute] = true }
    func press(_ element: AXNode) throws { pressed.append(element); onPress?(element) }
    func activate() throws { foreground = true }
    func requireForeground() throws { if !foreground { throw ToolError("Foreground lost") } }
    func pause() throws {}
    func run(_ operation: String, _ control: String = "") throws -> String {
        try DeviceHubAX(access: self).run(device: device(), operation: operation, control: control)
    }
}

final class DeviceHubAXTests: XCTestCase {
    func testPrepareSelectsAndReadDoesNotDispatch() throws {
        let ax = FakeHubAX(); ax.row.flags[kAXSelectedAttribute] = false
        XCTAssertEqual(try ax.run("prepare"), "target-confirmed")
        XCTAssertEqual(try ax.run("read-orientation"), "Portrait")
        XCTAssertEqual(try ax.run("set-orientation", "Portrait"), "unchanged")
        XCTAssertTrue(ax.pressed.isEmpty)
        XCTAssertTrue(ax.foreground)
    }
    func testAmbiguousIdentityAndWindowFailBeforePress() {
        for kind in 0..<3 {
            let ax = FakeHubAX()
            if kind == 0 { ax.outline.collections[kAXChildrenAttribute]!.append(ax.row) }
            if kind == 1 { ax.application.collections[kAXWindowsAttribute]!.append(ax.window) }
            if kind == 2 { ax.window.values[kAXTitleAttribute] = "Other device" }
            XCTAssertThrowsError(try ax.run("click", "Open"))
            XCTAssertTrue(ax.pressed.isEmpty)
        }
    }
    func testControlMustBeUniqueAndEnabled() {
        let ax = FakeHubAX(); ax.button.flags[kAXEnabledAttribute] = false
        XCTAssertThrowsError(try ax.run("click", "Open"))
        ax.orientations.collections[kAXChildrenAttribute]!.append(ax.orientations.collections[kAXChildrenAttribute]![0])
        XCTAssertThrowsError(try ax.run("set-orientation", "Portrait"))
        XCTAssertTrue(ax.pressed.isEmpty)
    }
    func testSelectionChangeBeforeAndAfterPressIsRejected() {
        let before = FakeHubAX()
        before.onString = { element, attribute in
            if element === before.button && attribute == kAXHelpAttribute { before.row.flags[kAXSelectedAttribute] = false }
        }
        XCTAssertThrowsError(try before.run("click", "Open"))
        XCTAssertTrue(before.pressed.isEmpty)
        let after = FakeHubAX(); after.onPress = { _ in after.row.flags[kAXSelectedAttribute] = false }
        XCTAssertThrowsError(try after.run("click", "Open"))
        XCTAssertEqual(after.pressed.count, 1)
    }
    func testRotationOpensMenuAndStopsOnForegroundLoss() throws {
        let ax = FakeHubAX()
        XCTAssertEqual(try ax.run("rotate", "Rotate Left"), "dispatched")
        XCTAssertEqual(ax.pressed.map { $0.values[kAXTitleAttribute] }, ["Controls", "Rotate Left"])
        let lost = FakeHubAX(); lost.onPress = { _ in lost.foreground = false }
        XCTAssertThrowsError(try lost.run("rotate", "Rotate Left"))
        XCTAssertEqual(lost.pressed.count, 1)
    }
    func testReadbackRequiresCompleteFreshMenuAndPropagatesAXFailure() throws {
        let ax = FakeHubAX()
        XCTAssertEqual(try ax.run("read-orientation"), "Portrait")
        ax.orientations.collections[kAXChildrenAttribute]![0].values.removeValue(forKey: "AXMenuItemMarkChar")
        XCTAssertEqual(try ax.run("read-orientation"), "unknown")
        ax.orientations.collections[kAXChildrenAttribute]!.removeLast()
        XCTAssertThrowsError(try ax.run("read-orientation"))
        let failed = FakeHubAX()
        failed.onString = { _, attribute in if attribute == "AXMenuItemMarkChar" { throw ToolError("AX transport error") } }
        XCTAssertThrowsError(try failed.run("read-orientation"))
        XCTAssertTrue(failed.pressed.isEmpty)
    }
}
