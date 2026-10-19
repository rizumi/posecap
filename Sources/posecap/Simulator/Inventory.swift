import Foundation

struct Inventory {
    struct Raw: Decodable {
        struct TypeInfo: Decodable { let identifier: String; let name: String; let productFamily: String? }
        struct Runtime: Decodable { let identifier: String; let version: String }
        struct Entry: Decodable { let udid: String; let name: String; let state: String; let isAvailable: Bool; let deviceTypeIdentifier: String? }
        let devicetypes: [TypeInfo]
        let runtimes: [Runtime]
        let devices: [String: [Entry]]
    }
    let devices: [Device]

    init(data: Data) throws {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        var types: [String: Raw.TypeInfo] = [:]
        for type in raw.devicetypes {
            if let existing = types[type.identifier], existing.name != type.name || existing.productFamily != type.productFamily {
                throw ToolError("Conflicting Simulator model information.")
            }
            types[type.identifier] = type
        }
        var runtimes: [String: String] = [:]
        // Xcode may list multiple runtime builds with the same ID and OS version.
        // Reconcile only the version; never invent a runtime build for the device.
        for runtime in raw.runtimes {
            if let existing = runtimes[runtime.identifier], existing != runtime.version {
                throw ToolError("Conflicting Simulator runtime versions.")
            }
            runtimes[runtime.identifier] = runtime.version
        }
        devices = raw.devices.flatMap { runtime, entries in entries.map { entry in
            let typeID = entry.deviceTypeIdentifier ?? ""
            let type = types[typeID]
            return Device(udid: entry.udid.uppercased(), name: entry.name, model: type?.name,
                          deviceTypeIdentifier: typeID, family: type?.productFamily,
                          runtimeIdentifier: runtime, runtimeVersion: runtimes[runtime] ?? "unknown",
                          state: entry.state, available: entry.isAvailable)
        }}.sorted { ($0.model ?? "", $0.runtimeVersion, $0.udid) < ($1.model ?? "", $1.runtimeVersion, $1.udid) }
        guard Set(devices.map(\.udid)).count == devices.count else { throw ToolError("Duplicate Simulator UDIDs in inventory.") }
    }

    init(devices: [Device]) { self.devices = devices }

    func select(udid: String?, model: String?) throws -> Device {
        let candidates: [Device]
        if let udid {
            candidates = devices.filter { $0.udid.caseInsensitiveCompare(udid) == .orderedSame }
        } else {
            candidates = devices.filter { $0.available && $0.state == "Booted" && $0.isMobile && (model == nil || $0.model == model) }
        }
        guard !candidates.isEmpty else {
            let matching = devices.filter { model == nil ? $0.isMobile : $0.model == model }
            throw ToolError("No matching booted Simulator. Start the desired Simulator and prepare its screen first.\n" + matching.map(\.summary).joined(separator: "\n"))
        }
        guard candidates.count == 1 else { throw ToolError("Multiple Simulators match; specify --udid.\n" + candidates.map(\.summary).joined(separator: "\n")) }
        let device = candidates[0]
        guard device.available, device.state == "Booted" else { throw ToolError("The selected Simulator must be available and booted. No automatic boot is performed.") }
        guard device.isMobile else { throw ToolError("Cannot establish iPhone/iPad capabilities for the selected device.") }
        return device
    }

    func verifyGUIIdentity(_ device: Device) throws {
        // Include shutdown and unavailable entries: they can also appear in Device Hub.
        let matches = devices.filter { $0.name == device.name && $0.runtimeVersion == device.runtimeVersion }
        guard matches.count == 1, matches[0].udid == device.udid else {
            throw ToolError("Device Hub cannot uniquely identify this Simulator by display name and OS version. Give it a unique display name before GUI capture.")
        }
        guard matches[0].state == "Booted", matches[0].available else { throw ToolError("The selected Simulator is no longer available and booted.") }
        guard device.runtimeVersion != "unknown", !device.name.contains("\n"), !device.name.contains("\r") else { throw ToolError("Device Hub identity cannot be established from this name/runtime.") }
    }
}
