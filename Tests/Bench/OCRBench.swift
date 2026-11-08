import AppKit
import AVFoundation
import Vision

/// A screenshot-like image: two paragraphs that wrap, a bulleted list and a small table.
func ocrSample() -> (CGImage, paragraphs: [String], listItems: [String], cells: [String]) {
    let p1 = "Совещание переносится на четверг, потому что заказчик не успел прислать техническое задание и правки к макетам."
    let p2 = "The release is planned for next week. Please check the build on your machine before Monday."
    let items = ["Проверить сборку", "Обновить документацию", "Send the report"]
    let cells = ["Name", "Status", "Login", "Done", "Search", "In progress"]
    let width = 900, height = 620
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let font = NSFont.systemFont(ofSize: 20)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    func draw(_ s: String, _ rect: NSRect) { (s as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attrs) }
    draw(p1, NSRect(x: 30, y: height - 110, width: 560, height: 90))
    draw(p2, NSRect(x: 30, y: height - 210, width: 560, height: 90))
    for (i, item) in items.enumerated() { draw("•  " + item, NSRect(x: 50, y: height - 270 - i * 34, width: 600, height: 30)) }
    for (i, cell) in cells.enumerated() {
        let row = i / 2, col = i % 2
        let rect = NSRect(x: 30 + col * 220, y: 140 - row * 44, width: 220, height: 44)
        NSColor.gray.setStroke(); NSBezierPath(rect: rect).stroke()
        draw(cell, rect.insetBy(dx: 10, dy: 8))
    }
    NSGraphicsContext.restoreGraphicsState()
    return (rep.cgImage!, [p1, p2], items, cells)
}

func normalized(_ s: String) -> String {
    s.lowercased().filter { $0.isLetter || $0.isNumber }
}

func runOCRBench() async -> String {
    let (image, paragraphs, items, cells) = ocrSample()
    var report = "## Text from the screen\n\n| Recognizer | Paragraphs kept whole | List items | Table cells | Time |\n|---|---|---|---|---|\n"

    // Current: VNRecognizeTextRequest lines joined by OCRParagraphs. Run once to load the models,
    // then timed over three runs: the first call pays a one-off load.
    func recognizeNow() -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { o in o.topCandidates(1).first.map { OCRParagraphs.Line(text: $0.string, box: o.boundingBox) } }
        return OCRParagraphs.join(lines)
    }
    var t = Date()
    _ = recognizeNow()
    let coldMs = Int(Date().timeIntervalSince(t) * 1000)
    t = Date()
    var current = ""
    for _ in 0..<3 { current = recognizeNow() }
    let currentMs = Int(Date().timeIntervalSince(t) * 1000 / 3)
    let currentBlocks = current.components(separatedBy: "\n").map(normalized)
    let keptCurrent = paragraphs.filter { p in currentBlocks.contains(normalized(p)) }.count
    let itemsCurrent = items.filter { i in current.lowercased().contains(i.lowercased()) }.count
    let cellsCurrent = cells.filter { c in current.contains(c) }.count
    report += "| VNRecognizeTextRequest + OCRParagraphs (now) | \(keptCurrent)/\(paragraphs.count) | \(itemsCurrent)/\(items.count) found as text | \(cellsCurrent)/\(cells.count) as text, no table structure | \(currentMs) ms (first \(coldMs) ms) |\n"

    // Candidate: RecognizeDocumentsRequest (macOS 26) gives the document's structure.
    do {
        t = Date()
        _ = try await RecognizeDocumentsRequest().perform(on: image)
        let cold = Int(Date().timeIntervalSince(t) * 1000)
        t = Date()
        var observations: [DocumentObservation] = []
        for _ in 0..<3 { observations = try await RecognizeDocumentsRequest().perform(on: image) }
        let ms = Int(Date().timeIntervalSince(t) * 1000 / 3)
        _ = cold
        guard let document = observations.first?.document else {
            report += "| RecognizeDocumentsRequest | no document | | | \(ms) ms |\n"
            return report
        }
        let docParagraphs = document.paragraphs.map { normalized($0.transcript) }
        let kept = paragraphs.filter { p in docParagraphs.contains(normalized(p)) }.count
        let listItems = document.lists.flatMap { $0.items.map { $0.itemString } }
        let itemsFound = items.filter { i in listItems.contains { $0.lowercased().contains(i.lowercased()) } }.count
        let tableCells = document.tables.flatMap { $0.rows.flatMap { $0.map { $0.content.text.transcript } } }
        let cellsFound = cells.filter { c in tableCells.contains { $0.contains(c) } }.count
        report += "| RecognizeDocumentsRequest (macOS 26) | \(kept)/\(paragraphs.count) | \(itemsFound)/\(items.count) as list items (\(document.lists.count) lists) | \(cellsFound)/\(cells.count) in \(document.tables.count) table(s) | \(ms) ms (first \(cold) ms) |\n"
    } catch {
        report += "| RecognizeDocumentsRequest | failed: \(error.localizedDescription) | | | |\n"
    }
    // What BindAll now hands to translation: each item and cell once, in reading order.
    let rendered = (try? await OCRService.recognizeDocument(image)) ?? ""
    func count(_ needle: String) -> Int { rendered.components(separatedBy: needle).count - 1 }
    let once = (items + cells).filter { count($0) == 1 }.count
    report += "\nBindAll's text from the document (each list item and cell exactly once: \(once)/\(items.count + cells.count)):\n\n```\n\(rendered)\n```\n"
    return report + "\n"
}

func runSpeechBench() -> String {
    let voices = AVSpeechSynthesisVoice.speechVoices()
    func summary(_ code: String) -> String {
        let v = voices.filter { $0.language.hasPrefix(code) }
        let quality = Dictionary(grouping: v, by: { $0.quality }).map { q, list in
            "\(q == .premium ? "premium" : q == .enhanced ? "enhanced" : "default") \(list.count)"
        }.sorted().joined(separator: ", ")
        return "\(v.count) voices (\(quality)): " + v.prefix(4).map(\.name).joined(separator: ", ")
    }
    return "## Reading aloud (AVSpeechSynthesizer)\n\n- ru: \(summary("ru"))\n- en: \(summary("en"))\n\n"
}
