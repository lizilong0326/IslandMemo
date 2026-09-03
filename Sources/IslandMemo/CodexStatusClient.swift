import Foundation

// Adapted from CodexFloat's MIT-licensed CodexQuotaCore.
// See THIRD_PARTY_NOTICES.md for attribution.

enum IslandCodexClientError: Error, LocalizedError, Sendable {
    case codexNotFound
    case launchFailed(String)
    case disconnected
    case timeout(String)
    case rpc(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "未找到 Codex；请先安装或打开 ChatGPT/Codex"
        case .launchFailed(let message): return "Codex 服务启动失败：\(message)"
        case .disconnected: return "Codex 服务已断开"
        case .timeout(let method): return "Codex 请求超时：\(method)"
        case .rpc(let message): return "Codex 返回错误：\(message)"
        case .writeFailed(let message): return "无法写入 Codex 服务：\(message)"
        }
    }
}

enum IslandCodexExecutableLocator {
    static func locate(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser
        var candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            home.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent("codex")
            })
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

actor IslandCodexAppServerClient {
    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<Data, Error>
    }

    private let executableURL: URL?
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = Data()
    private var pending: [Int64: PendingRequest] = [:]
    private var nextID: Int64 = 1
    private var isInitialized = false
    private var rateLimitUpdatedHandler: (@Sendable () -> Void)?

    init(executableURL: URL? = IslandCodexExecutableLocator.locate()) {
        self.executableURL = executableURL
    }

    func setRateLimitUpdatedHandler(_ handler: (@Sendable () -> Void)?) {
        rateLimitUpdatedHandler = handler
    }

    func readQuota() async throws -> CodexQuotaSnapshot {
        do {
            try await ensureStarted()
            let response = try await send(method: "account/rateLimits/read", params: nil)
            return try CodexStatusDecoder.decodeQuota(response)
        } catch {
            if shouldRestart(after: error) { stop() }
            throw error
        }
    }

    func readRecentTasks(limit: Int) async throws -> [CodexTaskSummary] {
        do {
            try await ensureStarted()
            let response = try await send(
                method: "thread/list",
                params: [
                    "limit": min(50, max(1, limit)),
                    "sortKey": "recency_at",
                    "sortDirection": "desc",
                    "sourceKinds": ["appServer", "cli", "vscode"],
                    "archived": false,
                    "useStateDbOnly": true,
                ]
            )
            return try CodexStatusDecoder.decodeTasks(response)
        } catch {
            if shouldRestart(after: error) { stop() }
            throw error
        }
    }

    func stop() {
        guard let process else { return }
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        inputHandle?.closeFile()
        if process.isRunning { process.terminate() }
        self.process = nil
        inputHandle = nil
        isInitialized = false
        failPending(with: IslandCodexClientError.disconnected)
    }

    private func ensureStarted() async throws {
        if process?.isRunning == true, isInitialized { return }
        stop()
        guard let executableURL else { throw IslandCodexClientError.codexNotFound }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.receive(data) }
        }
        error.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            Task { await self?.didTerminate() }
        }

        do {
            try process.run()
        } catch {
            throw IslandCodexClientError.launchFailed(error.localizedDescription)
        }
        self.process = process
        inputHandle = input.fileHandleForWriting

        _ = try await send(method: "initialize", params: [
            "clientInfo": [
                "name": "island_memo",
                "title": "IslandMemo",
                "version": "1.0.0",
            ]
        ])
        try writeNotification(method: "initialized")
        isInitialized = true
    }

    private func send(method: String, params: [String: Any]?) async throws -> Data {
        guard process?.isRunning == true, let inputHandle else {
            throw IslandCodexClientError.disconnected
        }
        let id = nextID
        nextID += 1
        var object: [String: Any] = ["method": method, "id": id]
        if let params { object["params"] = params }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = PendingRequest(method: method, continuation: continuation)
            do {
                try inputHandle.write(contentsOf: data)
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: IslandCodexClientError.writeFailed(error.localizedDescription))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await self?.expire(id: id, method: method)
            }
        }
    }

    private func writeNotification(method: String) throws {
        guard let inputHandle else { throw IslandCodexClientError.disconnected }
        var data = try JSONSerialization.data(withJSONObject: ["method": method])
        data.append(0x0A)
        do {
            try inputHandle.write(contentsOf: data)
        } catch {
            throw IslandCodexClientError.writeFailed(error.localizedDescription)
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else {
            failPending(with: IslandCodexClientError.disconnected)
            return
        }
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = Data(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            handleLine(line)
        }
    }

    private func handleLine(_ line: Data) {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return
        }
        if let id = (object["id"] as? NSNumber)?.int64Value,
           let request = pending.removeValue(forKey: id) {
            if let error = object["error"] as? [String: Any] {
                request.continuation.resume(
                    throwing: IslandCodexClientError.rpc(error["message"] as? String ?? "未知错误")
                )
            } else {
                request.continuation.resume(returning: line)
            }
            return
        }
        if object["method"] as? String == "account/rateLimits/updated" {
            rateLimitUpdatedHandler?()
        }
    }

    private func expire(id: Int64, method: String) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.continuation.resume(throwing: IslandCodexClientError.timeout(method))
    }

    private func didTerminate() {
        process = nil
        inputHandle = nil
        isInitialized = false
        failPending(with: IslandCodexClientError.disconnected)
    }

    private func failPending(with error: Error) {
        let requests = pending.values
        pending.removeAll()
        for request in requests { request.continuation.resume(throwing: error) }
    }

    private func shouldRestart(after error: Error) -> Bool {
        guard let error = error as? IslandCodexClientError else { return false }
        switch error {
        case .disconnected, .timeout, .writeFailed, .launchFailed: return true
        case .codexNotFound, .rpc: return false
        }
    }
}
