import AppKit
import SwiftUI

private actor FixtureRepository: TaskRepository {
    func load() async throws -> [TaskItem] { [] }
    func save(_ tasks: [TaskItem]) async throws {}
}

@main
struct MemoFloatingValidation {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await run()
                print("PASS: memo floating lifecycle, placement, shared data and layout")
                app.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
                exit(1)
            }
        }
        app.run()
    }

    @MainActor static func run() async throws {
        // The standalone validation executable has its own preferences domain.
        // Override initial reads so the fixture is independent of local settings.
        var fixtureDefaults: [String: Any] = [
            "workspace-placement-备忘录": "tab",
            "workspace-placement-复制记录": "tab",
            "workspace-placement-时钟": "home",
            "memo-categories-enabled": true,
            "memo-subtasks-enabled": true,
            "memo-completed-enabled": true,
            "memo-trash-enabled": true,
            "memo-floating-enabled": false
        ]
        for feature in AppSettingsStore.Feature.movableCases
            where feature != .memo && feature != .clipboard && feature != .clock {
            fixtureDefaults["workspace-placement-\(feature.rawValue)"] = "hidden"
        }
        UserDefaults.standard.setVolatileDomain(fixtureDefaults, forName: UserDefaults.argumentDomain)
        precondition(Bundle.main.bundleIdentifier != "com.local.islandmemo")
        defer { UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName) }
        let suiteName = "MemoFloatingValidation-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettingsStore()
        let store = TaskStore(repository: FixtureRepository())
        let controller = MemoFloatingController(store: store, settings: settings, defaults: defaults)
        defer { controller.stop() }
        controller.start()
        await settle()
        precondition(settings.canEnableMemoFloating && !settings.memoFloatingEnabled)
        precondition(controller.orbPanel == nil, "Default-off setting must not create a desktop entry")
        settings.setWorkspacePlacement(.memo, placement: .home)
        await settle()
        precondition(settings.canEnableMemoFloating && !settings.memoFloatingEnabled)
        precondition(controller.orbPanel == nil, "Home placement alone must not enable the orb")
        settings.setMemoFloatingEnabled(true)
        await settle()
        guard let orb = controller.orbPanel, let memo = controller.memoPanel else {
            throw failure("Panels were not installed for an enabled memo")
        }
        precondition(orb.isVisible && !memo.isVisible)
        // AppKit rounds a 44.8pt frame to the display's backing pixel grid.
        precondition(abs(orb.frame.width - MemoFloatingMetrics.orbSide) < 1)
        precondition(memo.contentView != nil)
        let content = memo.contentView

        // Exercise the actual click handler of the transparent native orb button.
        orb.contentView?.layoutSubtreeIfNeeded()
        guard let button = descendants(orb.contentView!).compactMap({ $0 as? NSButton }).first else {
            throw failure("Orb has no native click/drag control")
        }
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 20),
                                       modifierFlags: [], timestamp: 0, windowNumber: orb.windowNumber,
                                       context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        button.mouseDown(with: event)
        precondition(orb.isVisible, "Mouse down alone must not activate during a drag")
        button.mouseUp(with: event)
        await settle()
        precondition(!orb.isVisible && memo.isVisible)
        precondition(screenContains(memo.frame))

        // Keep a draft when the desktop window is collapsed and reopened.
        guard let field = descendants(memo.contentView!).compactMap({ $0 as? NSTextField })
            .first(where: { $0.placeholderString == "新建任务" }) else {
            throw failure("Expanded memo has no task composer")
        }
        field.stringValue = "收起后保留的草稿"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        memo.cancelOperation(nil)
        precondition(orb.isVisible && !memo.isVisible)
        controller.expand()
        await settle()
        precondition(memo.contentView === content, "Collapse must preserve the editor")
        precondition(field.stringValue == "收起后保留的草稿")

        // A real store mutation must update the orb count without separate storage.
        let id = store.add(title: "悬浮窗口与主面板共用的任务", dueDate: .now.addingTimeInterval(3600))!
        await settle()
        precondition(button.accessibilityLabel() == "备忘录，1 个未完成任务")
        let task = store.tasks.first(where: { $0.id == id })!
        store.toggle(task)
        await settle()
        precondition(button.accessibilityLabel() == "备忘录，0 个未完成任务")
        store.delete(store.tasks[0])
        precondition(store.deletedTasks.count == 1)
        store.restore(store.tasks[0])
        precondition(store.deletedTasks.isEmpty)

        // Screen-edge, negative-coordinate display and changed-resolution cases.
        for area in [NSRect(x: 0, y: 0, width: 1440, height: 900),
                     NSRect(x: -1280, y: 40, width: 1280, height: 680),
                     NSRect(x: 0, y: 0, width: 360, height: 400)] {
            for origin in [NSPoint(x: area.minX - 500, y: area.minY - 1000),
                           NSPoint(x: area.maxX + 500, y: area.maxY + 1000)] {
                let result = MemoFloatingController.clamped(
                    NSRect(origin: origin, size: MemoFloatingMetrics.windowSize), to: area)
                precondition(area.contains(result), "Window is outside the visible display")
            }
        }
        memo.setFrameOrigin(NSPoint(x: memo.frame.minX - 40, y: memo.frame.minY + 15))
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: memo))
        controller.collapse()
        let savedFrame = orb.frame

        // Explicit opt-out hides both windows while retaining the home module.
        controller.expand()
        settings.setMemoFloatingEnabled(false)
        await settle()
        precondition(!orb.isVisible && !memo.isVisible && settings.canEnableMemoFloating)
        settings.setMemoFloatingEnabled(true)
        await settle()
        precondition(orb.isVisible && !memo.isVisible)

        // Both visible placements retain the opt-in and the expanded editor.
        controller.expand()
        settings.setWorkspacePlacement(.memo, placement: .tab)
        await settle()
        precondition(settings.canEnableMemoFloating && settings.memoFloatingEnabled && memo.isVisible)
        settings.setMemoFloatingEnabled(false)
        await settle()
        precondition(!orb.isVisible && !memo.isVisible)
        settings.setMemoFloatingEnabled(true)
        await settle()
        precondition(settings.memoFloatingEnabled && orb.isVisible && !memo.isVisible,
                     "Top-tab memo must support explicit opt-in")
        controller.expand()
        settings.setWorkspacePlacement(.memo, placement: .home)
        await settle()
        precondition(settings.memoFloatingEnabled && memo.isVisible,
                     "Moving between visible placements must preserve the expanded editor")

        // Hiding memo closes both windows and clears the opt-in.
        settings.setWorkspacePlacement(.memo, placement: .hidden)
        await settle()
        precondition(!settings.canEnableMemoFloating && !settings.memoFloatingEnabled
                     && !orb.isVisible && !memo.isVisible)
        settings.setMemoFloatingEnabled(true)
        precondition(!settings.memoFloatingEnabled, "Hidden memo cannot enable the orb")
        settings.setWorkspacePlacement(.memo, placement: .tab)
        await settle()
        precondition(settings.canEnableMemoFloating && !settings.memoFloatingEnabled && !orb.isVisible,
                     "Moving back to the top must require a new opt-in")
        settings.setMemoFloatingEnabled(true)
        await settle()
        controller.expand()
        settings.setWorkspacePlacement(.memo, placement: .hidden)
        await settle()
        precondition(!settings.memoFloatingEnabled && !orb.isVisible && !memo.isVisible)
        settings.setWorkspacePlacement(.memo, placement: .home)
        await settle()
        precondition(settings.workspacePlacement(for: .memo) == .home)
        precondition(!orb.isVisible && !memo.isVisible, "Moving back home must require a new opt-in")
        settings.setMemoFloatingEnabled(true)
        await settle()
        precondition(orb.isVisible && !memo.isVisible)
        controller.expand()
        settings.setWorkspacePlacement(.memo, placement: .hidden)
        await settle()
        precondition(!orb.isVisible && !memo.isVisible)
        controller.expand()
        precondition(!memo.isVisible, "Disabled memo cannot be expanded")

        controller.stop()
        settings.setWorkspacePlacement(.memo, placement: .home)
        settings.setMemoFloatingEnabled(true)
        fixtureDefaults["workspace-placement-备忘录"] = "home"
        fixtureDefaults.removeValue(forKey: "memo-floating-enabled")
        UserDefaults.standard.setVolatileDomain(fixtureDefaults, forName: UserDefaults.argumentDomain)
        let reloadedSettings = AppSettingsStore()
        precondition(reloadedSettings.memoFloatingEnabled, "Explicit opt-in must persist across launches")
        let restored = MemoFloatingController(store: store, settings: reloadedSettings, defaults: defaults)
        defer { restored.stop() }
        restored.start()
        await settle()
        precondition(restored.orbPanel!.frame == savedFrame, "Orb position was not restored")
        reloadedSettings.setWorkspacePlacement(.clipboard, placement: .hidden)
        reloadedSettings.setWorkspacePlacement(.clock, placement: .hidden)
        reloadedSettings.setWorkspacePlacement(.memo, placement: .hidden)
        await settle()
        precondition(reloadedSettings.canEnableMemoFloating && reloadedSettings.memoFloatingEnabled
                     && restored.orbPanel?.isVisible == true,
                     "A rejected parent change must retain the existing valid orb setting")
        reloadedSettings.settingsError = nil

        // Stress the shared compact list and render actual AppKit views for visual QA.
        for index in 0..<30 {
            let id = store.add(title: "待办 \(index + 1)：检查小窗口布局和长标题显示，支持滚动查看所有任务", dueDate: nil)!
            if index == 0 { store.addSubtask(to: store.tasks.first(where: { $0.id == id })!, title: "子任务") }
        }
        restored.expand()
        await settle()
        let host = restored.memoPanel!.contentView!
        host.layoutSubtreeIfNeeded()
        let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
        precondition(scrolls.count == 1, "Compact categories must share a single scroll view")
        let scroll = scrolls[0]
        precondition(scroll.documentView!.bounds.height > scroll.contentView.bounds.height)
        let maximum = scroll.documentView!.bounds.height - scroll.contentView.bounds.height
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        precondition(abs(scroll.contentView.bounds.minY - maximum) < 1)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        try render(host, name: "memo-window")
        for width in [360.0, 440.0] {
            restored.memoPanel!.setContentSize(NSSize(width: width, height: 480))
            await settle()
            host.layoutSubtreeIfNeeded()
            try render(host, name: "memo-window-\(Int(width))")
        }
        restored.collapse()
        for style in [NSAppearance.Name.aqua, .darkAqua] {
            restored.orbPanel!.appearance = NSAppearance(named: style)
            await settle()
            try render(restored.orbPanel!.contentView!, name: "orb-\(style.rawValue)")
        }
        let drawer = NSHostingView(rootView: MemoWorkspaceView(
            store: store, appSettings: settings, section: .constant(.tasks))
            .padding(24).background(Color.black).preferredColorScheme(.dark))
        let drawerWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 868, height: 365),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
        drawerWindow.isReleasedWhenClosed = false
        drawerWindow.appearance = NSAppearance(named: .darkAqua)
        drawerWindow.contentView = drawer
        drawerWindow.orderFront(nil)
        defer { drawerWindow.close() }
        await settle()
        try render(drawer, name: "drawer-memo")
        reloadedSettings.resetWorkspaceLayout()
        await settle()
        precondition(reloadedSettings.workspacePlacement(for: .memo) == .tab
                     && reloadedSettings.memoFloatingEnabled && restored.orbPanel?.isVisible == true,
                     "Resetting to a visible placement must retain the orb opt-in")
        UserDefaults.standard.set(true, forKey: "memo-floating-enabled")
        fixtureDefaults["workspace-placement-备忘录"] = "tab"
        UserDefaults.standard.setVolatileDomain(fixtureDefaults, forName: UserDefaults.argumentDomain)
        let savedTopSettings = AppSettingsStore()
        precondition(savedTopSettings.canEnableMemoFloating && savedTopSettings.memoFloatingEnabled,
                     "Top-tab opt-in must persist across launches")
        fixtureDefaults["workspace-placement-备忘录"] = "hidden"
        UserDefaults.standard.setVolatileDomain(fixtureDefaults, forName: UserDefaults.argumentDomain)
        let invalidSavedSettings = AppSettingsStore()
        precondition(!invalidSavedSettings.memoFloatingEnabled
                     && !UserDefaults.standard.bool(forKey: "memo-floating-enabled"),
                     "An invalid saved opt-in must be cleared at startup")
    }

    @MainActor static func settle() async { try? await Task.sleep(for: .milliseconds(100)) }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "MemoFloatingValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    @MainActor static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    @MainActor static func screenContains(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.contains(frame) }
    }
    @MainActor static func render(_ view: NSView, name: String) throws {
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let url = URL(fileURLWithPath: ".build/memo-floating-validation/\(name).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        print("rendered \(url.path)")
    }
}
