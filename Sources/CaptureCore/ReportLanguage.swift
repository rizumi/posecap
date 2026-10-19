import Foundation

enum ReportLanguage: String { case en, ja }

struct ReportText {
    let language: ReportLanguage
    func callAsFunction(_ en: String, _ ja: String) -> String { language == .ja ? ja : en }
    func posture(_ value: Posture?) -> String {
        guard let value else { return self("unknown", "未確認") }
        switch value {
        case .closed: return "Closed"
        case .halfOpen: return "Partially folded"
        case .open: return "Fully open"
        }
    }
    func orientation(_ value: DeviceOrientation?) -> String {
        guard let value else { return self("unknown", "未確認") }
        switch value {
        case .portrait: return "Portrait"
        case .upsideDown: return "Portrait Upside Down"
        case .landscapeLeft: return "Landscape Left"
        case .landscapeRight: return "Landscape Right"
        case .faceUp: return self("face up", "画面が上向き")
        case .faceDown: return self("face down", "画面が下向き")
        }
    }
    func condition(_ value: Condition) -> String {
        if value.isCurrent { return self("Current", "現在の画面") }
        var parts: [String] = []
        if let p = value.posture { parts.append(posture(p)) }
        if let o = value.orientation { parts.append(o == .portrait ? "Portrait" : "Landscape") }
        return parts.joined(separator: " / ")
    }
    func status(_ result: CaptureResult) -> String {
        switch result.progress {
        case .pending: return self("Not attempted", "未撮影")
        case .running: return self("Interrupted / incomplete", "中断・未完了")
        case .finished:
            switch result.outcome {
            case .verified: return self("verified", "指定条件を確認済み")
            case .unverified: return self("unverified", "確認できていない項目あり")
            case .mismatched: return self("mismatched", "指定条件と不一致")
            case .failed: return self("failed", "撮影処理に失敗")
            }
        }
    }
    func mismatch(_ result: CaptureResult) -> String {
        var reasons: [String] = []
        if let expected = result.requested.orientation,
           let actual = result.observations.observedDeviceOrientation,
           expected.uiValue != actual.menuTitle {
            let wanted = orientation(expected == .portrait ? .portrait : .landscapeLeft)
            reasons.append(self("Requested orientation: \(wanted); Device Hub reported: \(orientation(actual)).",
                                "指定した向きは「\(wanted)」、Device Hubから読み取った向きは「\(orientation(actual))」です。"))
        }
        if let expected = result.requested.posture, let actual = result.observations.observedPosture, expected != actual {
            reasons.append(self("Requested posture: \(posture(expected)); observed: \(posture(actual)).",
                                "指定した姿勢は「\(posture(expected))」、読み取った姿勢は「\(posture(actual))」です。"))
        }
        return reasons.joined(separator: " ")
    }
}
