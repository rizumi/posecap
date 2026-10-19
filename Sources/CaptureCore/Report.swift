import Foundation
import CryptoKit

enum Report {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func generate(input: String, language: ReportLanguage = .en, details: Bool = false, title: String? = nil) throws -> URL {
        let t = ReportText(language: language)
        let root = try SafeFiles.directory(input, create: false)
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        var runs: [(Manifest, URL)] = []
        for entry in entries {
            if try SafeFiles.isSymlink(entry) { throw ToolError("Symbolic links are not allowed in report input: \(entry.lastPathComponent).") }
            guard try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
            let metadata = entry.appendingPathComponent("manifest.json")
            // Reject dangling symlinks before checking existence.
            try SafeFiles.rejectSymlinks(in: metadata)
            guard FileManager.default.fileExists(atPath: metadata.path) else { continue }
            try SafeFiles.regularFile(metadata)
            let data = try readBounded(metadata, limit: 8_000_000)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["schemaVersion"] as? Int == 1 else {
                throw ToolError("Unsupported metadata schema in \(entry.lastPathComponent); existing report was not replaced.")
            }
            let manifest = try JSONDecoder().decode(Manifest.self, from: data)
            guard manifest.captureID == entry.lastPathComponent else { throw ToolError("Capture directory and metadata ID differ.") }
            guard Set(manifest.results.map(\.index)).count == manifest.results.count,
                  Set(manifest.results.map { $0.requested.title }).count == manifest.results.count else { throw ToolError("Duplicate capture conditions in metadata.") }
            runs.append((manifest, entry))
        }
        guard !runs.isEmpty else { throw ToolError("No capture manifests found directly beneath the input directory.") }
        runs.sort { ($0.0.createdAt, $0.0.captureID) < ($1.0.createdAt, $1.0.captureID) }
        let heading = title ?? t("Capture report", "撮影レポート")
        let labels = Array(Set(runs.map { $0.0.label ?? $0.0.captureID })).sorted()
        let screenOptions = labels.enumerated().map { index, label in
            "<option value=\"\(index)\">\(escape(label))</option>"
        }.joined()
        let hasCurrent = runs.contains { $0.0.results.contains { $0.requested.isCurrent } }
        let currentOption = hasCurrent ? "<option value=\"current\">\(t("Current / unspecified", "現在の画面・向き未指定"))</option>" : ""
        let scriptHash = Data(SHA256.hash(data: Data(filterScript.utf8))).base64EncodedString()
        var sections = ""
        for (manifest, directory) in runs {
            let screenID = labels.firstIndex(of: manifest.label ?? manifest.captureID)!
            sections += "<section data-screen=\"\(screenID)\"><h2>\(escape(manifest.label ?? manifest.captureID))</h2>"
            if details { sections += "<p><code>\(escape(manifest.captureID))</code> · \(escape(manifest.createdAt))</p>" }
            sections += "<p>\(escape(manifest.device.model ?? t("Unknown model", "機種不明"))) · \(escape(manifest.device.name)) · OS \(escape(manifest.device.runtimeVersion))</p>"
            if !manifest.complete { sections += "<p class=failed>\(t("Incomplete run. Pending or interrupted conditions are not successful captures.", "撮影は未完了です。未撮影・中断した条件が含まれています。"))</p>" }
            if details || !manifest.complete { sections += messages(manifest.messages) }
            if manifest.results.contains(where: { $0.requested.isCurrent }) {
                for result in manifest.results { sections += try cell(result, device: manifest.device, directory: directory, text: t, details: details) }
            } else {
                sections += "<div class=grid>"
                let postures: [Posture?] = manifest.results.contains { $0.requested.posture != nil } ? Posture.allCases.map { $0 } : [nil]
                for posture in postures where manifest.results.contains(where: { $0.requested.posture == posture }) {
                    for orientation in Orientation.allCases {
                        if let result = manifest.results.first(where: { $0.requested.posture == posture && $0.requested.orientation == orientation }) {
                            sections += try cell(result, device: manifest.device, directory: directory, text: t, details: details)
                        } else {
                            let title = t.condition(Condition(posture: posture, orientation: orientation))
                            sections += "<article data-orientation=\"\(orientation.rawValue)\"><h3>\(escape(title))</h3><p class=muted>\(t("Not requested", "指定なし"))</p></article>"
                        }
                    }
                }
                sections += "</div>"
            }
            sections += "</section>"
        }
        let html = """
        <!doctype html><html lang="\(language.rawValue)"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self' file:; style-src 'unsafe-inline'; script-src 'sha256-\(scriptHash)'; base-uri 'none'; form-action 'none'">
        <title>\(escape(heading))</title><style>
        [hidden]{display:none!important}.filters{display:flex;flex-wrap:wrap;gap:1rem;margin:1.5rem 0}.filters label{display:flex;align-items:center;gap:.6rem}select{font:inherit;padding:.4rem .7rem;max-width:100%;border:1px solid #bcc7d1;border-radius:6px;background:white;color:inherit}select:focus-visible{outline:2px solid #087d98;outline-offset:2px}footer{margin:2rem 0;color:#526170;font-size:.8rem}:root{color-scheme:light;font-family:system-ui,sans-serif}*{box-sizing:border-box}body{max-width:1500px;margin:2rem auto;padding:0 2rem;line-height:1.6;background:#f3f5f7;color:#1f2937}h1{margin-bottom:.3rem}h2{margin:0 0 .5rem}h3{margin:0;font-size:1rem}section{margin:2.5rem 0}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:20px}article{background:white;border:1px solid #dce2e8;border-radius:12px;padding:16px;min-width:0}figure{margin:1rem 0}img{width:100%;height:460px;object-fit:contain;background:#e9edf1;border-radius:6px;display:block}figcaption{font-size:.85rem;color:#526170;overflow-wrap:anywhere}code{overflow-wrap:anywhere}.status{font-size:.85rem}.verified{color:#147d44}.unverified,.muted{color:#526170}.mismatched,.failed{color:#a52222;font-weight:600}li{overflow-wrap:anywhere}details{margin:.7rem 0;font-size:.85rem}summary{cursor:pointer}pre{white-space:pre-wrap;overflow-wrap:anywhere}a{color:#087d98}.intro{color:#526170}@media(max-width:650px){body{padding:0 1rem}.grid{grid-template-columns:1fr}img{height:380px}}
        </style></head><body><h1>\(escape(heading))</h1>
        <p class=intro>\(t("Compare layouts by screen and orientation. Click an image for full size.", "画面・向きを選んでレイアウトを比較できます。画像をクリックすると原寸で開きます。"))</p>
        <div class=filters hidden>
        <label for=screen-filter>\(t("Screen", "画面")) <select id=screen-filter><option value=all>\(t("All", "すべて"))</option>\(screenOptions)</select></label>
        <label for=orientation-filter>\(t("Orientation", "向き")) <select id=orientation-filter><option value=all>\(t("All", "すべて"))</option><option value=portrait>Portrait</option><option value=landscape>Landscape</option>\(currentOption)</select></label>
        </div>
        <p id=filter-empty role=status hidden>\(t("No captures match these filters.", "この条件に該当する撮影結果はありません。"))</p>
        \(sections)<footer>Generated by posecap</footer><script>\(filterScript)</script></body></html>
        """
        let output = root.appendingPathComponent("index.html")
        try SafeFiles.atomicWrite(Data(html.utf8), to: output)
        return output
    }

    private static let filterScript = """
    (() => {
      const screen = document.getElementById('screen-filter');
      const orientation = document.getElementById('orientation-filter');
      const sections = [...document.querySelectorAll('section[data-screen]')];
      function update() {
        let visible = 0;
        for (const section of sections) {
          let cards = 0;
          for (const card of section.querySelectorAll('article[data-orientation]')) {
            card.hidden = orientation.value !== 'all' && card.dataset.orientation !== orientation.value;
            if (!card.hidden) cards++;
          }
          section.hidden = (screen.value !== 'all' && section.dataset.screen !== screen.value) || cards === 0;
          if (!section.hidden) visible++;
        }
        document.getElementById('filter-empty').hidden = visible !== 0;
      }
      screen.addEventListener('change', update);
      orientation.addEventListener('change', update);
      document.querySelector('.filters').hidden = false;
      update();
    })();
    """

    private static func messages(_ items: [String]) -> String {
        items.isEmpty ? "" : "<ul>" + items.map { "<li>\(escape($0))</li>" }.joined() + "</ul>"
    }

    // A report presentation convention for the observed iPhone Duo display roles.
    // Never write this preference into activeDisplayID or upgrade capture evidence.
    static func preferredDisplayID(for result: CaptureResult, device: Device) -> String? {
        guard device.isDuo, let posture = result.requested.posture else { return nil }
        let displays = result.observations.afterDisplays
        guard displays.count == 2,
              displays.allSatisfy({ $0.type == "Integrated" }),
              Set(displays.map(\.id)).count == 2,
              Set(displays.compactMap(\.deviceName)) == Set(["primary", "primary-1"])
        else { return nil }
        // If both inventories exist, role identity must remain stable across capture.
        let before = result.observations.beforeDisplays
        if !before.isEmpty {
            guard before.count == displays.count,
                  displays.allSatisfy({ after in
                      before.contains { $0.id == after.id && $0.deviceName == after.deviceName && $0.type == after.type }
                  }) else { return nil }
        }
        let role = posture == .closed ? "primary" : "primary-1"
        guard let display = displays.first(where: { $0.deviceName == role }),
              result.images.filter({ $0.displayID == display.id }).count == 1
        else { return nil }
        return display.id
    }

    private static func cell(_ result: CaptureResult, device: Device, directory: URL, text t: ReportText, details: Bool) throws -> String {
        let status = t.status(result)
        let style = result.progress == .finished ? result.outcome.rawValue : "failed"
        var html = "<article data-orientation=\"\(result.requested.orientation?.rawValue ?? "current")\" data-posture=\"\(escape(result.requested.posture?.rawValue ?? ""))\"><h3>\(escape(t.condition(result.requested)))</h3>"
        if result.progress != .finished || result.outcome == .failed || result.outcome == .mismatched {
            html += "<p class=\"status \(style)\">\(escape(status))</p>"
        }
        if result.outcome == .mismatched {
            html += "<p class=mismatched>\(escape(t.mismatch(result)))</p>"
        }
        if result.images.isEmpty { html += "<p class=muted>\(t("No saved image", "保存された画像はありません"))</p>" }
        let preferred = preferredDisplayID(for: result, device: device)
        for image in result.images {
            let file = try SafeFiles.imageURL(image.path, in: directory)
            if let preferred, image.displayID != preferred { continue }
            let componentSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            let relative = [directory.lastPathComponent, file.lastPathComponent].map { $0.addingPercentEncoding(withAllowedCharacters: componentSet)! }.joined(separator: "/")
            let role = preferred == image.displayID ? (result.requested.posture == .closed ? t("Outer display · ", "外側の画面 · ") : t("Inner display · ", "内側の画面 · ")) : ""
            let caption = "\(role)\(t("Display", "画面")) \(image.displayID) · PNG \(image.width) × \(image.height)"
            let figure = "<figure><a href=\"\(escape(relative))\"><img loading=lazy src=\"\(escape(relative))\" alt=\"\(escape(caption))\"></a>" + (details || preferred == nil && result.images.count > 1 ? "<figcaption>\(escape(caption))</figcaption>" : "") + "</figure>"
            html += figure
        }
        if preferred == nil && result.images.count > 1 {
            html += "<p class=muted>\(t("No posture-based display default available; showing all saved displays.", "姿勢に応じた主画像を選べないため、保存した全画面を表示しています。"))</p>"
        }
        guard details else {
            if result.outcome == .failed { html += messages(result.messages) }
            return html + "</article>"
        }
        let evidence = result.observations
        html += "<details><summary>\(t("Capture details · ", "撮影詳細 · "))\(escape(status))</summary><p>\(t("Device posture: ", "読み取った姿勢："))\(escape(t.posture(evidence.observedPosture)))<br>\(t("Simulator orientation: ", "読み取った向き："))\(escape(t.orientation(evidence.observedDeviceOrientation)))<br>\(t("Orientation source: ", "向きの確認方法："))\(escape(evidence.deviceOrientationSource ?? t("unavailable", "取得できず")))<br>\(t("GUI orientation before/after capture: ", "撮影前／後の向き："))\(escape(t.orientation(evidence.guiOrientationBeforeCapture))) / \(escape(t.orientation(evidence.guiOrientationAfterCapture)))<br>\(t("GUI posture selection: ", "GUIの姿勢選択："))\(escape(evidence.guiPostureSelection ?? t("unavailable", "取得できず")))<br>\(t("GUI target matched: ", "GUIの対象一致："))\(evidence.guiTargetMatched.map { $0 ? t("yes", "一致") : t("no", "不一致") } ?? t("not checked", "未確認"))</p>"
        if preferred != nil {
            html += "<p>\(t("Main image follows the requested posture and recorded display roles. This presentation default does not verify the active display.", "主画像は指定した姿勢と記録された画面の対応から選んでいます。使用中の画面を検証した結果ではありません。"))</p>"
        }
        html += "<p>\(t("Original diagnostic messages", "診断メッセージ（原文）"))</p>"
        html += messages(result.messages)
        html += "<p>\(escape(evidence.displaySelectionReason ?? "No display selection evidence."))</p>"
        html += "<p>\(t("Dispatched controls: ", "実行した操作："))\(escape(evidence.dispatchedControls.joined(separator: ", ")))</p>"
        for display in evidence.afterDisplays {
            html += "<p>Display \(escape(display.id)) — simctl UI Orientation: \(escape(display.uiOrientation ?? "unknown"))</p>"
        }
        return html + "</details></article>"
    }
}
