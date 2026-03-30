import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: – ExportManager

/// Handles all export and sharing operations for sessions.
@MainActor
final class ExportManager {

    static let shared = ExportManager()

    // MARK: – Clipboard

    func copyToClipboard(session: Session, format: CopyFormat = .markdown) {
        let text: String
        switch format {
        case .markdown:
            text = session.summaryText()
        case .plainText:
            text = session.summaryText()
                .components(separatedBy: "\n")
                .map { line in
                    // Strip markdown headers
                    if line.hasPrefix("# ")  { return line.dropFirst(2).description }
                    if line.hasPrefix("## ") { return line.dropFirst(3).description }
                    if line.hasPrefix("- ")  { return "• " + line.dropFirst(2) }
                    return line
                }
                .joined(separator: "\n")
        case .transcript:
            text = session.transcriptText()
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    enum CopyFormat { case markdown, plainText, transcript }

    // MARK: – Share Sheet

    func shareSession(_ session: Session, relativeTo view: NSView? = nil) {
        let items: [Any] = buildShareItems(session: session)
        let picker = NSSharingServicePicker(items: items)
        if let view {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } else if let window = NSApp.keyWindow {
            picker.show(relativeTo: window.contentView?.bounds ?? .zero,
                        of: window.contentView ?? NSView(),
                        preferredEdge: .minY)
        }
    }

    private func buildShareItems(session: Session) -> [Any] {
        var items: [Any] = []
        if let summary = try? String(contentsOf: session.summaryURL, encoding: .utf8) {
            items.append(summary)
        }
        // Include the file itself so e.g. AirDrop works
        if session.hasSummary { items.append(session.summaryURL) }
        return items
    }

    // MARK: – Save panel (export to file)

    func exportToFile(session: Session, type: ExportType) async {
        let panel = NSSavePanel()
        panel.title = "Export \(session.title)"
        panel.nameFieldStringValue = safeFilename(session.title) + type.ext
        panel.allowedContentTypes = [type.utType]
        panel.canCreateDirectories = true

        guard let keyWindow = NSApp.keyWindow,
              await panel.beginSheetModal(for: keyWindow) == .OK,
              let url = panel.url else { return }

        do {
            switch type {
            case .markdown:
                try session.summaryText().write(to: url, atomically: true, encoding: .utf8)
            case .transcript:
                try session.transcriptText().write(to: url, atomically: true, encoding: .utf8)
            case .json:
                try exportJSON(session: session, to: url)
            case .pdf:
                try exportPDF(session: session, to: url)
            }
        } catch {
            showError("Export failed: \(error.localizedDescription)")
        }
    }

    enum ExportType {
        case markdown, transcript, json, pdf
        var ext: String {
            switch self { case .markdown: ".md"; case .transcript: ".txt"; case .json: ".json"; case .pdf: ".pdf" }
        }
        var utType: UTType {
            switch self { case .markdown, .transcript: .text; case .json: .json; case .pdf: .pdf }
        }
    }

    // MARK: – Private helpers

    private func safeFilename(_ title: String) -> String {
        title.components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: " -_")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
    }

    private func exportJSON(session: Session, to url: URL) throws {
        let dict: [String: Any] = [
            "title": session.title,
            "date": ISO8601DateFormatter().string(from: session.date),
            "template": session.template,
            "summary": session.summaryText(),
            "transcript": session.transcriptText(),
            "userNotes": session.userNotesText(),
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func exportPDF(session: Session, to url: URL) throws {
        let html = """
        <html><head><meta charset="utf-8">
        <style>body{font-family:-apple-system,sans-serif;max-width:800px;margin:40px auto;line-height:1.6}
        h1{border-bottom:1px solid #ddd;padding-bottom:8px}
        h2{color:#333;margin-top:24px}
        p,li{color:#555}</style></head>
        <body><h1>\(session.title)</h1>
        <p><em>\(DateFormatter.localizedString(from: session.date, dateStyle: .full, timeStyle: .short))</em></p>
        \(markdownToHTML(session.summaryText()))
        </body></html>
        """
        guard let data = html.data(using: .utf8) else { return }
        let printInfo = NSPrintInfo()
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey("NSPrintJobSavingURL")] = url
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        if let attrStr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
            view.textStorage?.setAttributedString(attrStr)
        }
        let op = NSPrintOperation(view: view, printInfo: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.run()
    }

    private func markdownToHTML(_ md: String) -> String {
        // Basic markdown → HTML (sufficient for meeting notes)
        var html = md
        // Headers
        html = html.replacingOccurrences(of: #"(?m)^## (.+)$"#, with: "<h2>$1</h2>", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?m)^# (.+)$"#, with: "<h1>$1</h1>", options: .regularExpression)
        // Bold
        html = html.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        // Bullets
        html = html.replacingOccurrences(of: #"(?m)^- (.+)$"#, with: "<li>$1</li>", options: .regularExpression)
        // Paragraphs
        html = html.components(separatedBy: "\n\n").map { "<p>\($0)</p>" }.joined(separator: "\n")
        return html
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Export Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
