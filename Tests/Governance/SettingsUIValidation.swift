import AppKit
import SwiftUI

private actor UITaskRepository: TaskRepository {
    func load() async throws -> [TaskItem] { [] }
    func save(_ tasks: [TaskItem]) async throws {}
}

@main
struct SettingsUIValidation {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await validate()
                print("PASS: rendered all 12 settings panes and Home memo fixture with orb disabled")
                NSApplication.shared.terminate(nil)
            } catch { FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8)); exit(1) }
        }
        NSApplication.shared.run()
    }

    @MainActor static func validate() async throws {
        let domain = Bundle.main.bundleIdentifier!
        precondition(domain == "com.islandmemo.settings-ui-validation")
        UserDefaults.standard.removePersistentDomain(forName: domain)
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IslandMemo-SettingsQA-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = URL(fileURLWithPath: ".build/settings-ui-validation/screenshots")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let settings = AppSettingsStore()
        settings.setWorkspacePlacement(.music, placement: .tab)
        settings.setWorkspacePlacement(.memo, placement: .home)
        let tasks = TaskStore(repository: UITaskRepository())
        tasks.add(title: "检查设置保存结果", dueDate: nil)
        tasks.add(title: "分类调整后任务仍然可见", dueDate: nil)
        let pomodoro = PomodoroStore()
        let recordings = RecordingStore(dataDirectory: directory, requestAudioAccess: { $0(false) })
        let notifications = AgentNotifyServer()
        let music = MusicService()
        let applications = AIApplicationDetector(scanImmediately: false)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        for pane in SettingsPane.allCases {
            let view = NSHostingView(rootView: DisplaySettingsView(settings: settings, tasks: tasks,
                pomodoro: pomodoro, recordings: recordings, notifyServer: notifications,
                aiApplications: applications, music: music, onEditShortcut: {}, initialPane: pane,
                transcriptionHasAPIKey: { false }))
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 120_000_000)
            try render(view, to: output.appendingPathComponent("settings-\(pane.rawValue).png"))
            precondition(view.bounds.width == 1100 && view.bounds.height == 680)
        }
        settings.setMemoFloatingEnabled(true)
        for trigger in AppSettingsStore.MemoFloatingTrigger.allCases {
            settings.memoFloatingTrigger = trigger
            let view = NSHostingView(rootView: DisplaySettingsView(settings: settings, tasks: tasks,
                pomodoro: pomodoro, recordings: recordings, notifyServer: notifications,
                aiApplications: applications, music: music, onEditShortcut: {}, initialPane: .memo,
                transcriptionHasAPIKey: { false }))
            window.contentView = view
            try? await Task.sleep(nanoseconds: 120_000_000)
            try render(view, to: output.appendingPathComponent("settings-memo-\(trigger.rawValue).png"))
        }
        settings.setMemoFloatingEnabled(false)
        let home = NSHostingView(rootView: IslandView(store: tasks,
            clipboardStore: ClipboardStore(dataDirectory: directory), linksStore: LinksStore(dataDirectory: directory),
            commandsStore: CommandsStore(dataDirectory: directory), pomodoroStore: pomodoro,
            recordingsStore: recordings, credentialsStore: CredentialsStore(dataDirectory: directory), musicService: music,
            windowListService: WindowListService(enumeratesSystemWindows: false), notifyServer: notifications,
            codexStatusStore: CodexStatusStore(client: IslandCodexAppServerClient(executableURL: nil)),
            appSettings: settings, panelMetrics: PanelMetrics(), onOpenDisplaySettings: {}, onGenerateMemo: { _, _ in }))
        window.setContentSize(NSSize(width: 868, height: 413))
        window.contentView = home
        try? await Task.sleep(nanoseconds: 100_000_000)
        tasks.requestAddFocus() // Actual root routes Home-placed memo to its Home entry.
        try? await Task.sleep(nanoseconds: 150_000_000)
        try render(home, to: output.appendingPathComponent("home-memo-manager.png"))
        if ProcessInfo.processInfo.arguments.contains("--preview-home") {
            print("READY: Actual IslandView Home fixture, orb disabled")
            try? await Task.sleep(nanoseconds: 45_000_000_000)
        }
        precondition(!settings.memoFloatingEnabled, "Full manager must remain reachable with orb disabled")
    }

    @MainActor static func render(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
