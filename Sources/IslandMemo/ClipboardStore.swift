import AppKit
import CryptoKit
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    private let pasteboard = NSPasteboard.general
    private let metadataURL: URL
    private let imageFolderURL: URL
    private let diagnosticsURL: URL
    private var lastChangeCount: Int
    private var monitorTimer: Timer?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IslandMemo", isDirectory: true)
        imageFolderURL = base.appendingPathComponent("ClipboardImages", isDirectory: true)
        metadataURL = base.appendingPathComponent("clipboard-history.json")
        diagnosticsURL = base.appendingPathComponent("clipboard-types.log")
        lastChangeCount = pasteboard.changeCount

        try? FileManager.default.createDirectory(at: imageFolderURL, withIntermediateDirectories: true)
        load()
    }

    func startMonitoring() {
        guard monitorTimer == nil else { return }
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPasteboard() }
        }
    }

    func copy(_ entry: ClipboardEntry) {
        pasteboard.clearContents()
        switch entry.kind {
        case .text:
            pasteboard.setString(entry.text ?? "", forType: .string)
        case .image:
            guard let fileName = entry.imageFileName,
                  let data = try? Data(contentsOf: imageFolderURL.appendingPathComponent(fileName)) else { return }
            pasteboard.setData(data, forType: .png)
        }
        lastChangeCount = pasteboard.changeCount
        moveToFront(entry.id)
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard let fileName = entry.imageFileName else { return nil }
        return NSImage(contentsOf: imageFolderURL.appendingPathComponent(fileName))
    }

    private func pollPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        let source = NSWorkspace.shared.frontmostApplication?.localizedName

        let defaults = UserDefaults.standard
        let capturesText = defaults.object(forKey: "clipboard-capture-text") as? Bool ?? true
        let capturesImages = defaults.object(forKey: "clipboard-capture-images") as? Bool ?? true

        // Finder supplies both the actual file URL and a TIFF document-icon preview.
        // Resolve the file first so the history stores the real photo, not its icon.
        if capturesImages, let imageData = imageFileDataFromPasteboard() {
            recordImage(imageData, source: source)
        } else if capturesImages, let imageData = imageDataFromAvailableTypes() {
            recordImage(imageData, source: source)
        } else if capturesImages, let imageURL = imageURLFromMarkup() {
            Task { [weak self] in
                guard let self,
                      let (data, _) = try? await URLSession.shared.data(from: imageURL),
                      let png = self.pngData(from: data) else {
                    self?.writeUnhandledTypeDiagnostics(source: source)
                    return
                }
                self.recordImage(png, source: source)
            }
        } else if capturesText, let text = pasteboard.string(forType: .string), !text.isEmpty {
            recordText(text, source: source)
        } else {
            writeUnhandledTypeDiagnostics(source: source)
        }
    }

    private func recordText(_ text: String, source: String?) {
        let fingerprint = digest(Data(text.utf8))
        if let existing = entries.first(where: { $0.fingerprint == fingerprint }) {
            moveToFront(existing.id, copiedAt: .now, source: source)
            return
        }
        entries.insert(ClipboardEntry(
            id: UUID(), kind: .text, fingerprint: fingerprint, text: text,
            imageFileName: nil, copiedAt: .now, sourceApplication: source
        ), at: 0)
        trimAndSave()
    }

    private func recordImage(_ data: Data, source: String?) {
        let fingerprint = digest(data)
        if let existing = entries.first(where: { $0.fingerprint == fingerprint }) {
            moveToFront(existing.id, copiedAt: .now, source: source)
            return
        }
        let id = UUID()
        let fileName = "\(id.uuidString).png"
        do {
            try data.write(to: imageFolderURL.appendingPathComponent(fileName), options: .atomic)
            entries.insert(ClipboardEntry(
                id: id, kind: .image, fingerprint: fingerprint, text: nil,
                imageFileName: fileName, copiedAt: .now, sourceApplication: source
            ), at: 0)
            trimAndSave()
        } catch { }
    }

    private func imageDataFromAvailableTypes() -> Data? {
        for type in pasteboard.types ?? [] {
            guard type != .fileURL,
                  let data = pasteboard.data(forType: type),
                  data.count <= 30_000_000 else { continue }
            if let png = pngData(from: data) { return png }
            if let embedded = embeddedImageData(in: data) { return embedded }
            if let webArchiveImage = imageDataFromPropertyList(data) { return webArchiveImage }
        }
        return nil
    }

    private func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }

    private func embeddedImageData(in data: Data) -> Data? {
        guard let markup = String(data: data, encoding: .utf8) else { return nil }
        let pattern = #"data:image/[^;]+;base64,([^\"'\s<>]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: markup, range: NSRange(markup.startIndex..., in: markup)),
              let range = Range(match.range(at: 1), in: markup),
              let decoded = Data(base64Encoded: String(markup[range]), options: .ignoreUnknownCharacters) else { return nil }
        return pngData(from: decoded)
    }

    private func imageDataFromPropertyList(_ data: Data) -> Data? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        return firstImageData(in: root)
    }

    private func firstImageData(in value: Any) -> Data? {
        if let data = value as? Data, let png = pngData(from: data) { return png }
        if let values = value as? [Any] {
            for child in values { if let data = firstImageData(in: child) { return data } }
        }
        if let values = value as? [String: Any] {
            for child in values.values { if let data = firstImageData(in: child) { return data } }
        }
        return nil
    }

    private func imageURLFromMarkup() -> URL? {
        for type in pasteboard.types ?? [] {
            guard let data = pasteboard.data(forType: type), data.count <= 5_000_000,
                  let markup = String(data: data, encoding: .utf8) else { continue }
            // Match the real `src` attribute, not Feishu's later `data-src`.
            // A greedy prefix previously skipped the public temporary image URL
            // and selected Feishu's authenticated internal endpoint instead.
            let pattern = #"<img\b[^>]*?\s+src\s*=\s*[\"'](https?://[^\"']+)[\"']"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: markup, range: NSRange(markup.startIndex..., in: markup)),
                  let range = Range(match.range(at: 1), in: markup) else { continue }
            let urlText = String(markup[range]).replacingOccurrences(of: "&amp;", with: "&")
            if let url = URL(string: urlText) { return url }
        }
        return nil
    }

    private func imageFileDataFromPasteboard() -> Data? {
        var candidateURLs: [URL] = []

        if let urlText = pasteboard.string(forType: .fileURL),
           let url = URL(string: urlText), url.isFileURL {
            candidateURLs.append(url)
        }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            candidateURLs.append(contentsOf: urls)
        }

        // Some apps expose a copied file as a plain path in addition to the filename URL.
        if let path = pasteboard.string(forType: .string), path.hasPrefix("/"),
           FileManager.default.fileExists(atPath: path) {
            candidateURLs.append(URL(fileURLWithPath: path))
        }

        for url in candidateURLs {
            guard let image = NSImage(contentsOf: url),
                  let tiff = image.tiffRepresentation,
                  let representation = NSBitmapImageRep(data: tiff),
                  let png = representation.representation(using: .png, properties: [:]) else { continue }
            return png
        }
        return nil
    }

    private func writeUnhandledTypeDiagnostics(source: String?) {
        let typeSummary = (pasteboard.types ?? []).map { type in
            "\(type.rawValue)=\(pasteboard.data(forType: type)?.count ?? 0)"
        }.joined(separator: ", ")
        let line = "[\(Date().formatted(.iso8601))] source=\(source ?? "unknown") types: \(typeSummary)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: diagnosticsURL.path),
           let handle = try? FileHandle(forWritingTo: diagnosticsURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: diagnosticsURL, options: .atomic)
        }
    }

    private func moveToFront(_ id: UUID, copiedAt: Date? = nil, source: String? = nil) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        if let copiedAt { entry.copiedAt = copiedAt }
        if let source { entry.sourceApplication = source }
        entries.insert(entry, at: 0)
        save()
    }

    private func trimAndSave() {
        let savedLimit = UserDefaults.standard.integer(forKey: "clipboard-max-items")
        let limit = savedLimit > 0 ? min(max(savedLimit, 5), 100) : 20
        while entries.count > limit {
            let removed = entries.removeLast()
            deleteCachedImage(for: removed)
        }
        save()
    }

    private func deleteCachedImage(for entry: ClipboardEntry) {
        guard let fileName = entry.imageFileName else { return }
        try? FileManager.default.removeItem(at: imageFolderURL.appendingPathComponent(fileName))
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = ((try? decoder.decode([ClipboardEntry].self, from: data)) ?? []).filter { entry in
            guard entry.kind == .image, let fileName = entry.imageFileName else { return true }
            return FileManager.default.fileExists(atPath: imageFolderURL.appendingPathComponent(fileName).path)
        }
        trimAndSave()
    }

    func applyPreferences() {
        trimAndSave()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
