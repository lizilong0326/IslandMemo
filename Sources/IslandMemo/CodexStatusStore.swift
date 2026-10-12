import Foundation

@MainActor
final class CodexStatusStore: ObservableObject {
    private struct Cache: Codable {
        let quota: CodexQuotaSnapshot?
        let tasks: [CodexTaskSummary]
    }

    @Published private(set) var quota: CodexQuotaSnapshot?
    @Published private(set) var tasks: [CodexTaskSummary] = []
    @Published private(set) var quotaError: String?
    @Published private(set) var taskError: String?
    @Published private(set) var isRefreshing = false

    private static let cacheKey = "islandmemo-codex-status-cache-v1"
    private let client: IslandCodexAppServerClient
    private let runtimeIndex: IslandCodexTaskRuntimeIndex
    private var quotaLoop: Task<Void, Never>?
    private var taskLoop: Task<Void, Never>?
    private var eventRefreshTask: Task<Void, Never>?
    @Published private(set) var isStarted = false
    private var lifecycleTask: Task<Void, Never>?
    private var generation = 0

    init(
        client: IslandCodexAppServerClient = IslandCodexAppServerClient(),
        runtimeIndex: IslandCodexTaskRuntimeIndex = IslandCodexTaskRuntimeIndex()
    ) {
        self.client = client
        self.runtimeIndex = runtimeIndex
        restoreCache()
    }

    var preferredQuota: CodexQuotaWindow? { quota?.preferredWindow }

    var displayQuotaWindows: [CodexQuotaWindow] {
        Array((quota?.visibleWindows ?? []).prefix(2))
    }

    var workingTasks: [CodexTaskSummary] {
        tasks.filter { $0.state == .working }
    }

    var isConnected: Bool {
        isStarted && quota != nil && quotaError == nil
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        generation += 1
        let token = generation
        let previous = lifecycleTask
        lifecycleTask = Task { [weak self] in
            _ = await previous?.value
            guard let self, self.isStarted, self.generation == token else { return }
            await client.setRateLimitUpdatedHandler { [weak self] in
                Task { @MainActor in self?.scheduleEventRefresh() }
            }
            await refreshAll()
            guard self.isStarted, self.generation == token else { return }
            startLoops()
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        generation += 1
        quotaLoop?.cancel()
        taskLoop?.cancel()
        eventRefreshTask?.cancel()
        quotaLoop = nil
        taskLoop = nil
        eventRefreshTask = nil
        let previous = lifecycleTask
        let client = client
        lifecycleTask = Task {
            _ = await previous?.value
            await client.setRateLimitUpdatedHandler(nil)
            await client.stop()
        }
    }

    func shutdown() async {
        stop()
        await lifecycleTask?.value
    }

    func refreshNow() {
        guard isStarted else { taskError = "Codex 状态读取已关闭，请在 AI 任务设置中开启。"; return }
        Task { [weak self] in await self?.refreshAll() }
    }

    private func refreshAll() async {
        guard isStarted, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshQuota()
        await refreshTasks()
    }

    private func refreshQuota() async {
        guard isStarted else { return }
        let token = generation
        do {
            let fetched = try await client.readQuota()
            guard isStarted, generation == token else { return }
            quota = fetched
            quotaError = nil
            persistCache()
        } catch {
            guard isStarted, generation == token else { return }
            quotaError = error.localizedDescription
            if var cached = quota {
                cached.freshness = .stale
                quota = cached
            }
        }
    }

    private func refreshTasks() async {
        guard isStarted else { return }
        let token = generation
        do {
            let fetched = try await client.readRecentTasks(limit: 8)
            let states = try? await runtimeIndex.latestStates(for: fetched.map(\.id))
            guard isStarted, generation == token else { return }
            if let states {
                tasks = fetched.map { task in
                    guard let runtime = states[task.id] else { return task }
                    return task.withState(runtime.taskState())
                }
            } else {
                tasks = fetched
            }
            taskError = nil
            persistCache()
        } catch {
            guard isStarted, generation == token else { return }
            taskError = error.localizedDescription
        }
    }

    private func startLoops() {
        quotaLoop?.cancel()
        taskLoop?.cancel()

        quotaLoop = Task { [weak self] in
            while let self, self.isStarted, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard self.isStarted, !Task.isCancelled else { break }
                await self.refreshQuota()
            }
        }

        taskLoop = Task { [weak self] in
            while let self, self.isStarted, !Task.isCancelled {
                let interval: UInt64 = self.workingTasks.isEmpty ? 15 : 2
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                guard self.isStarted, !Task.isCancelled else { break }
                await self.refreshTasks()
            }
        }
    }

    private func scheduleEventRefresh() {
        guard isStarted else { return }
        eventRefreshTask?.cancel()
        eventRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.refreshQuota()
        }
    }

    private func restoreCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else {
            return
        }
        if var cachedQuota = cache.quota {
            cachedQuota.freshness = .stale
            quota = cachedQuota
        }
        tasks = cache.tasks
    }

    private func persistCache() {
        let cache = Cache(quota: quota, tasks: tasks)
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }
}
