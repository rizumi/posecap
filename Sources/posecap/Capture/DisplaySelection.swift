enum DisplaySelection {
    // Observed iPhone Duo roles in Device Hub 27.1. This selects a capture
    // target from the requested posture; it does not verify the active panel.
    static func preferredDisplay(device: Device, posture: Posture?, displays: [Display], before: [Display]) -> Display? {
        guard device.isDuo, let posture,
              displays.count == 2,
              displays.allSatisfy({ $0.type == "Integrated" }),
              Set(displays.map(\.id)).count == 2,
              Set(displays.compactMap(\.deviceName)) == Set(["primary", "primary-1"])
        else { return nil }
        if !before.isEmpty {
            guard before.count == displays.count,
                  displays.allSatisfy({ after in
                      before.contains { $0.id == after.id && $0.deviceName == after.deviceName && $0.type == after.type }
                  }) else { return nil }
        }
        let role = posture == .closed ? "primary" : "primary-1"
        return displays.first { $0.deviceName == role }
    }
}
