import AppKit
import Foundation

struct QuickCommand: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// 常用指令：保存高频 prompt / 命令片段，点击复制到剪贴板。
/// Ported from TO-DO-Panel workspace.js 常用指令模块。
@MainActor
final class CommandsStore: ObservableObject {
    @Published private(set) var commands: [QuickCommand] = []

    @Published var errorMessage: String?

    private let fileWriter = OrderedFileWriter()

    private let fileURL: URL

    init(dataDirectory: URL? = nil) {
        let base = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IslandMemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("commands.json")
        load()
    }

    func add(text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !commands.contains(where: { $0.text == cleaned }) else { return }
        commands.insert(QuickCommand(text: cleaned), at: 0)
        persist()
    }

    func delete(_ command: QuickCommand) {
        commands.removeAll { $0.id == command.id }
        persist()
    }

    func copy(_ command: QuickCommand) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command.text, forType: .string)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        commands = (try? decoder.decode([QuickCommand].self, from: data)) ?? []
    }

    func flushPendingSave(retry: Bool = false) async -> Bool {
        if retry, fileWriter.lastError != nil { persist() }
        return await fileWriter.flush()
    }

    private func persist() {
        let snapshot = commands
        fileWriter.enqueue(snapshot, to: fileURL) { [weak self] error in
            self?.errorMessage = error.map { "保存常用指令失败：\($0)；修改保留在当前会话，请重试。" }
        }
    }
}
