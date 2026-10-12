import Foundation

/// One queue per file: later snapshots cannot overtake an earlier, slower write.
@MainActor
final class OrderedFileWriter {
    private var pending: Task<Bool, Never>?
    private(set) var lastError: String?

    func enqueue<T: Encodable & Sendable>(_ snapshot: T, to url: URL,
                                        onResult: @escaping @MainActor (String?) -> Void) {
        let previous = pending
        pending = Task {
            _ = await previous?.value
            let failure = await Task.detached(priority: .utility) { () -> String? in
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(snapshot).write(to: url, options: .atomic)
                    return nil
                } catch { return error.localizedDescription }
            }.value
            self.lastError = failure
            onResult(failure)
            return failure == nil
        }
    }

    func flush() async -> Bool { await pending?.value ?? true }
}
