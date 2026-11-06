import Foundation
import NotchClipCore
import OSLog
import Vision

/// Reads the text in image clips with Apple's on-device Vision OCR (free, offline).
/// Runs off the main thread and stores the result on the clip.
@MainActor
final class TextReader {
    private let store: ClipStore
    private var inFlight: Set<UUID> = []
    private let queue = DispatchQueue(label: "NotchClip.TextReader", qos: .utility)

    init(store: ClipStore) {
        self.store = store
    }

    /// Reads every image clip that hasn't been read yet (new screenshots and older history).
    func readPending() {
        store.items
            .filter { $0.kind == .image && $0.ocrText == nil && !inFlight.contains($0.id) }
            .forEach(read)
    }

    private func read(_ item: ClipItem) {
        guard let url = store.imageURL(for: item) else { return }
        inFlight.insert(item.id)
        let id = item.id
        queue.async { [weak self] in
            let text = Self.recognize(at: url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.inFlight.remove(id)
                    // An empty string marks "read, no text" so it isn't retried.
                    self.store.setOCRText(text ?? "", id: id)
                }
            }
        }
    }

    nonisolated private static func recognize(at url: URL) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(url: url)
        do {
            try handler.perform([request])
        } catch {
            Logger(subsystem: "com.minutechbuilds.notchclip", category: "ocr")
                .error("Text recognition failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
