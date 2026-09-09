import Darwin
import Foundation

struct MemoAICredentialStore {
    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IslandMemo", isDirectory: true)
            .appendingPathComponent("memo-ai-credentials.json")
    }

    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    private struct Credentials: Codable {
        let apiKey: String
    }

    func read() throws -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Credentials.self, from: data).apiKey
    }

    func save(_ apiKey: String) throws {
        let folder = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Credentials(apiKey: apiKey))
        let temporary = folder.appendingPathComponent(".memo-ai-credentials-\(UUID().uuidString).tmp")
        // Create the staging file as owner-only before writing any secret bytes.
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        // A same-directory rename atomically replaces the old key and retains mode 0600.
        guard rename(temporary.path, fileURL.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

}
