import AppKit
import ApplicationServices

// A fresh session is used for each operation. AX references never cross an
// operation boundary (in particular, dynamic menu references cannot be cached).
protocol HubAXAccess {
    associatedtype Element
    var application: Element { get }
    func elements(_ element: Element, _ attribute: String) throws -> [Element]
    func string(_ element: Element, _ attribute: String) throws -> String?
    func bool(_ element: Element, _ attribute: String) throws -> Bool
    func same(_ lhs: Element, _ rhs: Element) -> Bool
    func select(_ row: Element) throws
    func press(_ element: Element) throws
    func activate() throws
    func requireForeground() throws
    func pause() throws
}

struct DeviceHubAX<Access: HubAXAccess> {
    let access: Access

    private func unique(_ elements: [Access.Element], _ description: String) throws -> Access.Element {
        guard elements.count == 1, let element = elements.first else {
            throw ToolError("Cannot uniquely identify Device Hub \(description).")
        }
        return element
    }

    private func children(_ element: Access.Element, role: String) throws -> [Access.Element] {
        try access.elements(element, kAXChildrenAttribute).filter { try access.string($0, kAXRoleAttribute) == role }
    }

    // Match the known 27.1 hierarchy, retaining semantic matching for controls.
    private func child(_ element: Access.Element, role: String, index: Int = 0) throws -> Access.Element {
        let matches = try children(element, role: role)
        guard matches.indices.contains(index) else { throw ToolError("Unexpected Device Hub \(role) hierarchy.") }
        return matches[index]
    }

    private func content(_ window: Access.Element) throws -> Access.Element {
        let group = try child(window, role: kAXGroupRole)
        let split = try child(group, role: kAXSplitGroupRole)
        let inner = try child(split, role: kAXGroupRole)
        return try child(inner, role: kAXSplitGroupRole)
    }

    private func labels(_ row: Access.Element) throws -> [String] {
        let cell = try unique(access.elements(row, kAXChildrenAttribute), "sidebar cell")
        return try children(cell, role: kAXStaticTextRole).map {
            guard let value = try access.string($0, kAXValueAttribute) else { throw ToolError("Missing sidebar label.") }
            return value
        }
    }

    private func matches(_ row: Access.Element, device: Device) throws -> Bool {
        let values = try labels(row)
        return values.count == 3 && values.contains(device.name) && values.contains(device.runtimeVersion) && values.contains("Simulator")
    }

    private func assertTarget(_ window: Access.Element, row: Access.Element, device: Device) throws {
        let current = try unique(access.elements(access.application, kAXWindowsAttribute), "window")
        guard access.same(current, window), try access.bool(row, kAXSelectedAttribute), try matches(row, device: device),
              let title = try access.string(current, kAXTitleAttribute),
              ["\(device.name) – iOS \(device.runtimeVersion)", "\(device.name) – iPadOS \(device.runtimeVersion)"].contains(title) else {
            throw ToolError("Device Hub target selection or window changed; stopping GUI operations.")
        }
    }

    private func named(_ parent: Access.Element, role: String, attribute: String, value: String) throws -> Access.Element {
        try unique(children(parent, role: role).filter { try access.string($0, attribute) == value }, value)
    }

    private func enabled(_ element: Access.Element) throws {
        guard try access.bool(element, kAXEnabledAttribute) else { throw ToolError("Requested Device Hub control is disabled.") }
    }

    func run(device: Device, operation: String, control: String) throws -> String {
        guard ["prepare", "check", "probe", "click", "probe-orientation", "set-orientation", "read-orientation", "probe-rotation", "rotate"].contains(operation) else {
            throw ToolError("Unknown GUI operation.")
        }
        let window = try unique(access.elements(access.application, kAXWindowsAttribute), "window")
        let split = try content(window)
        let sidebar = try child(split, role: kAXGroupRole)
        let scroll = try child(sidebar, role: kAXScrollAreaRole)
        let outline = try child(scroll, role: kAXOutlineRole)
        let row = try unique(children(outline, role: kAXRowRole).filter { try matches($0, device: device) }, "Simulator row")

        if operation == "prepare" {
            if try !access.bool(row, kAXSelectedAttribute) { try access.select(row) }
            // Only the title/selection transition is retried; no control mutation.
            for attempt in 0..<20 {
                do { try assertTarget(window, row: row, device: device); return "target-confirmed" }
                catch { if attempt == 19 { throw error }; try access.pause() }
            }
        }
        try assertTarget(window, row: row, device: device)
        if operation == "check" { return "target-confirmed" }

        if ["probe", "click"].contains(operation) {
            guard ["Closed", "Partially Open", "Open", "Rotate Right"].contains(control) else { throw ToolError("Unknown posture control.") }
            let controls = try child(split, role: kAXGroupRole, index: 2)
            let button = try named(controls, role: kAXButtonRole, attribute: kAXHelpAttribute, value: control)
            try enabled(button)
            if operation == "probe" { return "control-confirmed" }
            try assertTarget(window, row: row, device: device)
            try access.press(button)
            try assertTarget(window, row: row, device: device)
            return "dispatched"
        }

        // Device Hub removes dynamic orientation/rotation menus in the background.
        try access.activate()
        try access.requireForeground()
        try assertTarget(window, row: row, device: device)
        let bar = try unique(access.elements(access.application, kAXMenuBarAttribute), "menu bar")
        let rotation = ["probe-rotation", "rotate"].contains(operation)
        let barItem = try named(bar, role: kAXMenuBarItemRole, attribute: kAXTitleAttribute, value: rotation ? "Controls" : "Device")
        if rotation {
            guard RotationDirection.allCases.map(\.menuTitle).contains(control) else { throw ToolError("Unknown rotation direction.") }
            if operation == "rotate" {
                try access.requireForeground()
                try access.press(barItem)
            }
            let menu = try unique(children(barItem, role: kAXMenuRole), "Controls menu")
            let item = try named(menu, role: kAXMenuItemRole, attribute: kAXTitleAttribute, value: control)
            try enabled(item)
            try assertTarget(window, row: row, device: device)
            try access.requireForeground()
            if operation == "probe-rotation" { return "control-confirmed" }
            try access.press(item)
            try assertTarget(window, row: row, device: device)
            return "dispatched"
        }

        let menu = try unique(children(barItem, role: kAXMenuRole), "Device menu")
        let orientation = try named(menu, role: kAXMenuItemRole, attribute: kAXTitleAttribute, value: "Orientation")
        let submenu = try unique(children(orientation, role: kAXMenuRole), "Orientation menu")
        if operation == "read-orientation" {
            var marked: [String] = []
            for direction in DeviceOrientation.allCases {
                let item = try named(submenu, role: kAXMenuItemRole, attribute: kAXTitleAttribute, value: direction.menuTitle)
                if try access.string(item, "AXMenuItemMarkChar") == "✓" { marked.append(direction.menuTitle) }
            }
            try assertTarget(window, row: row, device: device)
            try access.requireForeground()
            return marked.count == 1 ? marked[0] : "unknown"
        }
        guard Orientation.allCases.map(\.uiValue).contains(control) else { throw ToolError("Unknown orientation preset.") }
        let item = try named(submenu, role: kAXMenuItemRole, attribute: kAXTitleAttribute, value: control)
        try enabled(item)
        let alreadySelected = try access.string(item, "AXMenuItemMarkChar") == "✓"
        try assertTarget(window, row: row, device: device)
        try access.requireForeground()
        if operation == "probe-orientation" { return "control-confirmed" }
        if alreadySelected { return "unchanged" }
        try access.press(item)
        try assertTarget(window, row: row, device: device)
        return "dispatched"
    }
}

final class NativeHubAX: HubAXAccess {
    let application: AXUIElement
    private let app: NSRunningApplication
    private let cancellation: Cancellation
    private let deadline = ProcessInfo.processInfo.systemUptime + 25
    private let bundle: URL

    init(app: NSRunningApplication, cancellation: Cancellation) throws {
        guard AXIsProcessTrusted() else { throw ToolError("Allow Accessibility access for the launching app or posecap in System Settings.") }
        guard let bundle = app.bundleURL?.resolvingSymlinksInPath() else { throw ToolError("Device Hub has no application bundle.") }
        self.app = app; self.bundle = bundle; self.cancellation = cancellation
        application = AXUIElementCreateApplication(app.processIdentifier)
        guard AXUIElementSetMessagingTimeout(application, 1) == .success else { throw ToolError("Cannot set Device Hub Accessibility timeout.") }
    }

    private func check() throws {
        try cancellation.check()
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw ToolError("Device Hub Accessibility operation timed out; action completion may be unknown.") }
        guard !app.isTerminated, let current = NSRunningApplication(processIdentifier: app.processIdentifier),
              current.bundleURL?.resolvingSymlinksInPath() == bundle else { throw ToolError("Device Hub process changed.") }
    }

    private func value(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef? {
        try check()
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        try check()
        if status == .noValue || status == .attributeUnsupported { return nil }
        guard status == .success else { throw ToolError("Device Hub Accessibility read failed (\(attribute), \(status.rawValue)).") }
        return value
    }

    func elements(_ element: AXUIElement, _ attribute: String) throws -> [AXUIElement] {
        guard let value = try value(element, attribute) else { throw ToolError("Missing Device Hub \(attribute).") }
        if CFGetTypeID(value) == AXUIElementGetTypeID() { return [unsafeBitCast(value, to: AXUIElement.self)] }
        guard let array = value as? [AXUIElement], array.count <= 4096 else { throw ToolError("Unexpected Device Hub \(attribute) collection.") }
        return array
    }
    func string(_ element: AXUIElement, _ attribute: String) throws -> String? {
        guard let value = try value(element, attribute) else { return nil }
        guard let string = value as? String else { throw ToolError("Unexpected Device Hub \(attribute) text.") }
        return string
    }
    func bool(_ element: AXUIElement, _ attribute: String) throws -> Bool {
        guard let value = try value(element, attribute), CFGetTypeID(value) == CFBooleanGetTypeID(), let bool = value as? Bool else {
            throw ToolError("Missing or invalid Device Hub \(attribute) flag.")
        }
        return bool
    }
    func same(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool { CFEqual(lhs, rhs) }
    func select(_ row: AXUIElement) throws {
        try check()
        guard AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success else { throw ToolError("Cannot select Device Hub target.") }
        try check()
    }
    func press(_ element: AXUIElement) throws {
        try check()
        let status = AXUIElementPerformAction(element, kAXPressAction as CFString)
        try check()
        guard status == .success else { throw ToolError("Device Hub press failed (\(status.rawValue)); action completion may be unknown.") }
    }
    func activate() throws {
        try check()
        if try bool(application, kAXFrontmostAttribute) { return }
        guard app.activate(options: []) else { throw ToolError("Cannot activate Device Hub.") }
        try check()
        guard AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue) == .success else { throw ToolError("Cannot bring Device Hub to foreground.") }
        for _ in 0..<20 {
            try check()
            if try bool(application, kAXFrontmostAttribute) { return }
            try pause()
        }
        try requireForeground()
    }
    func requireForeground() throws {
        try check()
        guard try bool(application, kAXFrontmostAttribute) else { throw ToolError("Device Hub lost foreground; stopping GUI operations.") }
    }
    func pause() throws { try check(); try cancellation.sleep(seconds: 0.1); try check() }
}
