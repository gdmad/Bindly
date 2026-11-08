import AppKit
import Vision

/// Captures a user-selected screen region and recognizes text in it with the Vision framework.
enum OCRService {
    enum OCRError: LocalizedError {
        case cancelled
        case noImage
        case noText
        var errorDescription: String? {
            switch self {
            case .cancelled: return "Screen selection was cancelled."
            case .noImage: return "Could not capture the selected area."
            case .noText: return "No readable text was found in the selection."
            }
        }
    }

    /// Interactively asks the user to drag-select a screen region, then reads its text: as a
    /// document (paragraphs, lists, tables kept apart) where Vision can, as joined lines otherwise.
    static func captureAndRecognize() async throws -> String {
        let image = try await Task.detached(priority: .userInitiated) { try capture() }.value
        if let text = try? await recognizeDocument(image), !text.isEmpty { return text }
        return try await Task.detached(priority: .userInitiated) { try recognizeLines(image) }.value
    }

    private static func capture() throws -> CGImage {
        let tmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("bindly_ocr_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        // Interactive region capture via the system tool (no app-level Screen Recording prompt needed).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", tmp] // -i interactive, -x no sound
        try process.run()
        process.waitUntilExit()

        guard FileManager.default.fileExists(atPath: tmp),
              let image = NSImage(contentsOfFile: tmp) else {
            throw OCRError.cancelled // user pressed Esc → no file written
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.noImage
        }
        return cgImage
    }

    /// `RecognizeDocumentsRequest` (macOS 26): the structure comes with the text, so a list or a
    /// table is not flattened into run-on lines before it is translated.
    static func recognizeDocument(_ image: CGImage) async throws -> String {
        guard let document = try await RecognizeDocumentsRequest().perform(on: image).first?.document else { return "" }
        var blocks: [DocumentLayout.Block] = []
        blocks += document.paragraphs.map {
            DocumentLayout.Block(content: .paragraph($0.transcript), box: $0.boundingRegion.boundingBox.cgRect)
        }
        blocks += document.lists.map {
            DocumentLayout.Block(content: .list($0.items.map(\.itemString)), box: $0.boundingRegion.boundingBox.cgRect)
        }
        blocks += document.tables.map { table in
            DocumentLayout.Block(content: .table(table.rows.map { $0.map { $0.content.text.transcript } }),
                                 box: table.boundingRegion.boundingBox.cgRect)
        }
        return DocumentLayout.render(blocks).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The earlier path, kept for when the document request fails or finds nothing.
    static func recognizeLines(_ cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { OCRParagraphs.Line(text: $0.string, box: observation.boundingBox) }
        }
        let text = OCRParagraphs.join(lines).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OCRError.noText }
        return text
    }
}
