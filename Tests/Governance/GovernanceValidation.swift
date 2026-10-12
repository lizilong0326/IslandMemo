import AppKit
import Foundation

private actor FixtureTaskRepository: TaskRepository {
    var saved: [TaskItem] = []
    var failures = 0
    func load() async throws -> [TaskItem] { saved }
    func failNext(_ count: Int) { failures = count }
    func save(_ tasks: [TaskItem]) async throws {
        if failures > 0 { failures -= 1; throw CocoaError(.fileWriteNoPermission) }
        saved = tasks
    }
}

private final class AuthorizationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: [@Sendable (Bool) -> Void] = []
    func request(_ callback: @escaping @Sendable (Bool) -> Void) { lock.lock(); callbacks.append(callback); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return callbacks.count }
    func resolve(_ result: Bool) { lock.lock(); let callback = callbacks.removeFirst(); lock.unlock(); callback(result) }
}

private struct DelayedSnapshot: Encodable, Sendable {
    let value: Int
    let delay: Double
    func encode(to encoder: any Encoder) throws {
        Thread.sleep(forTimeInterval: delay)
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

@main
struct GovernanceValidation {
    @MainActor static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }

    @MainActor static func resetDefaults(_ fixture: [String: Any] = [:]) {
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        precondition(domain == "com.islandmemo.governance-validation")
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        for (key, value) in fixture { UserDefaults.standard.set(value, forKey: key) }
    }

    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await validate()
                print("PASS: deterministic migration/defaults, category transactions, save failures, ordered persistence, recording preparation, background services, window ownership and layout")
                resetDefaults()
                NSApplication.shared.terminate(nil)
            } catch { FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8)); exit(1) }
        }
        NSApplication.shared.run()
    }

    @MainActor static func validate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IslandMemo-Governance-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        resetDefaults()
        let defaults = UserDefaults.standard
        let fresh = AppSettingsStore()
        let defaultHome = Set<AppSettingsStore.HomeModule>([.music, .pomodoro, .recorder, .windows, .clock, .calendar])
        require(fresh.enabledHomeModules == defaultHome, "Fresh Home must be deterministic")
        require(fresh.enabledFeatures.intersection(Set(AppSettingsStore.Feature.movableCases)).count == 9, "Fresh defaults retain all 15 primary functions")
        let reload = AppSettingsStore()
        require(reload.enabledHomeModules == fresh.enabledHomeModules && reload.enabledFeatures == fresh.enabledFeatures, "Reload must preserve placements")
        fresh.setWorkspacePlacement(.memo, placement: .hidden)
        fresh.resetWorkspaceLayout()
        require(fresh.enabledHomeModules == reload.enabledHomeModules && fresh.enabledFeatures == reload.enabledFeatures, "Reset uses installation defaults")
        fresh.undoLastLayoutReset()
        require(fresh.workspacePlacement(for: .memo) == .hidden, "Reset undo must restore previous placement")
        require(defaults.integer(forKey: "workspace-layout-version") == 2, "Migration version must be persisted")

        let legacyOrder: [AppSettingsStore.HomeModule] = [.calendar, .clock, .commands, .note, .mirror, .windows, .recorder, .pomodoro, .music, .completions]
        resetDefaults(["feature-order": ["链接", "备忘录"], "home-module-order": legacyOrder.map(\.rawValue)])
        let migrated = AppSettingsStore()
        require(Array(migrated.featureOrder.prefix(2)) == [.links, .memo], "Partial saved tab order must survive new feature additions")
        require(migrated.enabledHomeModules == Set(legacyOrder.prefix(6)), "Overflow keeps first six in saved Home order")
        require(legacyOrder.dropFirst(6).allSatisfy { migrated.workspacePlacement(for: $0.feature) == .tab }, "Overflow is still reachable as tabs")
        let migratedAgain = AppSettingsStore()
        require(migratedAgain.homeModuleOrder == migrated.homeModuleOrder && migratedAgain.enabledHomeModules == migrated.enabledHomeModules, "Legacy migration must not shuffle on restart")
        migrated.canDisableHomeModule = { _ in false }
        let protectedFeatures = migrated.enabledFeatures
        migrated.resetWorkspaceLayout()
        require(migrated.enabledFeatures == protectedFeatures && migrated.settingsError != nil, "Reset must honor recording lifecycle guard")

        resetDefaults()
        let settings = AppSettingsStore()
        settings.setWorkspacePlacement(.music, placement: .tab)
        settings.setWorkspacePlacement(.memo, placement: .home)
        settings.setMemoFloatingEnabled(true)
        settings.resetWorkspaceLayout()
        require(settings.workspacePlacement(for: .memo) == .tab && settings.memoFloatingEnabled,
                "Reset to a visible top placement retains desktop entry")
        settings.undoLastLayoutReset()
        require(settings.canEnableMemoFloating && settings.memoFloatingEnabled, "Undo restores valid previous Home opt-in")
        let homeOrder = settings.homeModuleOrder
        settings.moveWorkspaceFeatures(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        require(settings.homeModuleOrder == homeOrder, "Tab order must not alter Home arrangement")
        let preferences = settings.homeModuleSizes
        settings.setHomeModuleSize(.memo, size: .large)
        require(settings.homeModuleSizes.filter { $0.key != .memo } == preferences.filter { $0.key != .memo }, "Fitting cannot rewrite siblings' size preferences")
        for count in 1...6 {
            let modules = Array(AppSettingsStore.HomeModule.allCases.prefix(count))
            let layout = settings.resolvedHomeLayout(for: modules)
            require(HomeLayoutEngine.validate(layout, expectedCount: count), "Final layout must completely cover grid for \(count) modules")
        }
        let modules = settings.orderedVisibleModules(includeCompletions: true)
        let placements = settings.resolvedHomeLayout(for: modules)
        for (index, module) in modules.enumerated() { require(settings.actualHomeModuleSpan(module) == placements[index].span, "Settings and runtime must share final spans") }

        // Active, completed and deleted tasks retain their identities/content/subtasks.
        let repository = FixtureTaskRepository()
        let tasks = TaskStore(repository: repository)
        let category = settings.memoCategories[1]
        let taskIDs = (0..<3).map { tasks.add(title: "任务 \($0)", dueDate: .now, categoryID: category.id)! }
        tasks.addSubtask(to: tasks.tasks[0], title: "子任务")
        tasks.toggle(tasks.tasks[1])
        tasks.delete(tasks.tasks[2])
        _ = await tasks.awaitPendingSave()
        let originalTasks = tasks.tasks
        await repository.failNext(2)
        await settings.removeMemoCategory(category, tasks: tasks)
        require(settings.memoCategories.contains(category), "Failed task save must retain category definition")
        require(tasks.tasks == originalTasks, "Failed migration restores only category edits without losing task data")
        await settings.removeMemoCategory(category, tasks: tasks)
        require(!settings.memoCategories.contains(where: { $0.id == category.id }), "Retry must commit category deletion")
        require(tasks.tasks.map(\.id) == taskIDs, "Task IDs/order must survive category migration")
        require(tasks.tasks[1].isCompleted && tasks.tasks[2].deletedAt != nil && tasks.tasks[0].subtasks?.count == 1, "Migration retains completion/trash/subtasks")
        require(tasks.tasks.allSatisfy { $0.categoryID == settings.memoCategories.first?.id }, "All task states migrate to remaining first category")
        require(settings.resolvedMemoCategoryID("obsolete-id") == settings.memoCategories.first?.id, "Invalid legacy reference must remain visible")
        // Make room for a custom category and reset it without deleting its tasks.
        settings.addMemoCategory()
        let custom = settings.memoCategories.last!
        let customID = tasks.add(title: "自定义分类任务", dueDate: nil, categoryID: custom.id)!
        await settings.resetMemoCategories(tasks: tasks)
        require(tasks.tasks.count == 4 && tasks.tasks.first(where: { $0.id == customID })?.categoryID == settings.memoCategories.first?.id, "Category reset migrates custom references")
        let durableTasks = await repository.saved
        require(durableTasks == tasks.tasks, "Category commit waits for durable task snapshot")

        var reminderRequests = 0
        tasks.onReminderConfigured = { reminderRequests += 1 }
        _ = tasks.add(title: "无日期不申请通知", dueDate: nil)
        let reminderID = tasks.add(title: "设置将来时间才申请通知", dueDate: .now.addingTimeInterval(3600))!
        require(reminderRequests == 1, "Notification authorization must follow an explicit future deadline action")
        let reminderTask = tasks.tasks.first { $0.id == reminderID }!
        tasks.updateDueDate(reminderTask, dueDate: reminderTask.dueDate)
        require(reminderRequests == 1, "Unchanged deadline must not request again")
        _ = await tasks.awaitPendingSave()

        // Inject key-write failure without reading or writing any real keychain item.
        let oldConfig = TranscriptionConfig(region: "beijing", workspaceId: "old-workspace")
        oldConfig.save()
        let newConfig = TranscriptionConfig(region: "singapore", workspaceId: "new-workspace")
        var attemptedKey = ""
        let rejected = newConfig.saveReplacingKey(" replacement ") { attemptedKey = $0; return false }
        require(!rejected && attemptedKey == "replacement" && TranscriptionConfig.load() == oldConfig, "Failed secret write must retain ordinary fields and old configuration")
        require(newConfig.saveReplacingKey("replacement") { _ in true } && TranscriptionConfig.load() == newConfig, "Fields commit only after secret write success")
        require(oldConfig.saveReplacingKey("") { _ in require(false, "Blank key must not overwrite existing secret"); return false }, "Blank replacement preserves key")

        // Slow first serialization must never overwrite a later snapshot.
        let writer = OrderedFileWriter()
        let file = directory.appendingPathComponent("ordered.json")
        var lastError: String?
        writer.enqueue(DelayedSnapshot(value: 1, delay: 0.08), to: file) { lastError = $0 }
        writer.enqueue(DelayedSnapshot(value: 2, delay: 0), to: file) { lastError = $0 }
        let orderedSaved = await writer.flush()
        let orderedText = try String(contentsOf: file, encoding: .utf8)
        require(orderedSaved && lastError == nil && orderedText == "2", "Last queued snapshot wins after slower predecessor")
        writer.enqueue([3], to: file.appendingPathComponent("cannot-write.json")) { lastError = $0 }
        let failed = await writer.flush()
        let textAfterFailure = try String(contentsOf: file, encoding: .utf8)
        require(!failed && lastError != nil && textAfterFailure == "2", "Write failure is observable and preserves existing file")
        writer.enqueue([4], to: file) { lastError = $0 }
        let recovered = await writer.flush()
        require(recovered && lastError == nil, "Writer can recover after failure")
        let commands = CommandsStore(dataDirectory: directory)
        for index in 0..<30 { commands.add(text: "指令 \(index)") }
        let commandsSaved = await commands.flushPendingSave()
        let savedCommands = try JSONDecoder.islandDecoder.decode([QuickCommand].self, from: Data(contentsOf: directory.appendingPathComponent("commands.json")))
        require(commandsSaved && savedCommands.map(\.id) == commands.commands.map(\.id) && savedCommands.map(\.text) == commands.commands.map(\.text) && savedCommands.count == 30, "Real store queue must drain final snapshot")

        let probe = AuthorizationProbe()
        let recordings = RecordingStore(dataDirectory: directory, requestAudioAccess: { probe.request($0) })
        recordings.startRecording(); recordings.startRecording(); recordings.toggleRecording()
        require(recordings.state == .preparing && !recordings.canToggleRecording && probe.count == 1, "Preparing blocks duplicate permission/capture attempts")
        await recordings.shutdown()
        probe.resolve(true) // Stale success after shutdown must not start the real microphone.
        try? await Task.sleep(nanoseconds: 50_000_000)
        require(recordings.state == .idle && recordings.recordings.isEmpty, "Shutdown invalidates delayed authorization result")
        recordings.startRecording(); probe.resolve(false)
        try? await Task.sleep(nanoseconds: 50_000_000)
        require(recordings.state == .idle && recordings.errorMessage != nil, "Denied authorization returns to recoverable idle")
        let wavURL = directory.appendingPathComponent("fixture.wav")
        let wav = WAVFileWriter(url: wavURL)!
        wav.append(Data(repeating: 0, count: 16)); wav.finalize(); wav.append(Data(repeating: 0, count: 32)); wav.finalize()
        let wavData = try Data(contentsOf: wavURL)
        require(wavData.count == 60, "Finalized recording rejects late audio tap writes")

        let closingSession = TranscriptionSession()
        let finishStarted = Date()
        let closedText = await closingSession.finish()
        require(closedText.isEmpty && Date().timeIntervalSince(finishStarted) < 4, "Transcription finalization without a socket must complete within deadline")

        // Services are explicitly controlled, independent of feature placement.
        defaults.set(false, forKey: "clipboard-monitoring-enabled")
        let clipboard = ClipboardStore(dataDirectory: directory)
        clipboard.startMonitoring()
        require(!clipboard.isMonitoring, "Disabled capture must not start a timer")
        defaults.set(true, forKey: "clipboard-monitoring-enabled")
        clipboard.startMonitoring()
        require(clipboard.isMonitoring, "Explicit capture enable starts monitoring")
        clipboard.stopMonitoring() // Stop before the first poll; never read real clipboard contents.
        require(!clipboard.isMonitoring, "Capture stop releases its timer")
        let server = AgentNotifyServer(port: 0)
        server.start()
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard let port = server.listeningPort else { throw CocoaError(.fileReadUnknown) }
        var unknownSourceRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/notify/unknown")!)
        unknownSourceRequest.httpMethod = "POST"
        unknownSourceRequest.httpBody = Data("{}".utf8)
        let (_, response) = try await URLSession.shared.data(for: unknownSourceRequest)
        require((response as? HTTPURLResponse)?.statusCode == 404 && server.recentCompletions.isEmpty, "Loopback server preserves source allowlist without emitting a notification")
        server.stop(); server.start(); server.stop()
        try? await Task.sleep(nanoseconds: 50_000_000)
        require(!server.isRunning && server.listeningPort == nil, "Late listener callbacks cannot revive a stopped service")
        let codex = CodexStatusStore(client: IslandCodexAppServerClient(executableURL: nil),
                                    runtimeIndex: IslandCodexTaskRuntimeIndex(codexHomeURL: directory))
        codex.start(); codex.stop(); codex.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        require(codex.isStarted, "Latest Codex enable must win over queued stop")
        await codex.shutdown()
        codex.refreshNow()
        require(!codex.isStarted && codex.taskError?.contains("已关闭") == true, "Disabled manual refresh must not relaunch Codex")

        // Window ownership: independent windows must not keep the main drawer alive.
        let main = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        let child = NSPanel(contentRect: NSRect(x: 250, y: 150, width: 150, height: 150), styleMask: .borderless, backing: .buffered, defer: false)
        let other = NSPanel(contentRect: NSRect(x: 500, y: 100, width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        main.identifier = WindowInteractionPolicy.drawer
        other.identifier = WindowInteractionPolicy.memo
        main.addChildWindow(child, ordered: .above)
        main.orderFrontRegardless(); child.orderFrontRegardless(); other.orderFrontRegardless()
        defer { main.removeChildWindow(child); main.orderOut(nil); child.orderOut(nil); other.orderOut(nil) }
        require(WindowInteractionPolicy.isRelated(child, to: main), "Owned editor popup belongs to drawer")
        require(!WindowInteractionPolicy.isRelated(other, to: main), "Memo desktop window is independent of drawer")
        require(WindowInteractionPolicy.contains(NSPoint(x: 380, y: 200), in: main), "Owned popup remains within interaction boundary")
        require(!WindowInteractionPolicy.contains(NSPoint(x: 600, y: 200), in: main), "Independent window cannot keep drawer open")
        print("Validated 15 modules, 1–6 card layouts, category failure/retry and 30 ordered store writes; no real audio, external network or credentials used.")
    }
}

private extension JSONDecoder {
    static var islandDecoder: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}
