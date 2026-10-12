import AppKit
import Foundation

struct Credential: Identifiable, Equatable, Sendable {
    let id: String
    var service: String
    var account: String
    var createdAt: Date
}

/// 密钥库：服务/账号元数据存本地 JSON，密码本体只进 Keychain。
/// 对应 TO-DO-Panel 的密钥模块（Electron safeStorage → macOS Keychain）。
@MainActor
final class CredentialsStore: ObservableObject {
    private struct Metadata: Codable, Sendable {
        let id: String
        var service: String
        var account: String
        var createdAt: Date
    }

    @Published private(set) var credentials: [Credential] = []
    @Published var errorMessage: String?

    @Published var persistenceError: String?
    private let fileWriter = OrderedFileWriter()

    private let fileURL: URL

    init(dataDirectory: URL? = nil) {
        let base = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IslandMemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("credentials.json")
        load()
    }

    func add(service: String, account: String, password: String) {
        let cleanedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedService.isEmpty, !cleanedAccount.isEmpty, !password.isEmpty else { return }
        let id = "credential-\(UUID().uuidString)"
        guard KeychainHelper.save(key: id, value: password) else {
            errorMessage = "密码写入钥匙串失败"
            return
        }
        credentials.insert(Credential(
            id: id,
            service: String(cleanedService.prefix(80)),
            account: String(cleanedAccount.prefix(320)),
            createdAt: .now
        ), at: 0)
        persist()
    }

    func password(for credential: Credential) -> String? {
        KeychainHelper.read(key: credential.id)
    }

    func copyAccount(_ credential: Credential) {
        writeToPasteboard(credential.account)
    }

    func copyPassword(_ credential: Credential) {
        guard let password = password(for: credential) else { return }
        writeToPasteboard(password)
    }

    func delete(_ credential: Credential) {
        KeychainHelper.delete(key: credential.id)
        credentials.removeAll { $0.id == credential.id }
        persist()
    }

    func filtered(query: String) -> [Credential] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return credentials }
        return credentials.filter {
            "\($0.service)\n\($0.account)".lowercased().contains(keyword)
        }
    }

    private func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = (try? decoder.decode([Metadata].self, from: data)) ?? []
        credentials = rows
            .map { Credential(id: $0.id, service: $0.service, account: $0.account, createdAt: $0.createdAt) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func flushPendingSave(retry: Bool = false) async -> Bool {
        if retry, fileWriter.lastError != nil { persist() }
        return await fileWriter.flush()
    }

    private func persist() {
        let snapshot = credentials.map {
            Metadata(id: $0.id, service: $0.service, account: $0.account, createdAt: $0.createdAt)
        }
        fileWriter.enqueue(snapshot, to: fileURL) { [weak self] error in
            self?.persistenceError = error.map { "保存密钥列表失败：\($0)；修改保留在当前会话，请重试。" }
        }
    }
}
