import AppKit
import SwiftUI
import QuartzCore
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TaskStore(repository: LocalTaskRepository())
    private let clipboardStore = ClipboardStore()
    private lazy var reminderScheduler = TaskReminderScheduler { [weak self] in
        self?.store.tasks ?? []
    }
    private var panel: IslandPanel!
    private var drawerView: NSView!
    private var statusItem: NSStatusItem!
    private var openMenuItem: NSMenuItem?
    private var shortcutConfiguration = ShortcutConfiguration.load()
    private var pointerTrackingTimer: Timer?
    private var globalHotKey: GlobalHotKey?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isAnimatingIn = false
    private var isAnimatingOut = false
    private var isPinnedByHotKey = false
    private var hasPointerEnteredAfterHotKey = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        setupMenuBar()
        setupGlobalHotKey()
        setupDismissMonitors()
        store.load()
        reminderScheduler.start()
        clipboardStore.startMonitoring()
        startPointerTracking()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pointerTrackingTimer?.invalidate()
        reminderScheduler.stop()
        globalHotKey?.invalidate()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    }

    private func setupPanel() {
        panel = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 444, height: 524),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: IslandView(store: store, clipboardStore: clipboardStore))
        hostingView.wantsLayer = true
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        drawerView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "丫丫灵动")

        let menu = NSMenu()
        openMenuItem = menu.addItem(
            withTitle: "打开备忘录  \(shortcutConfiguration.displayText)",
            action: #selector(openFromMenu),
            keyEquivalent: "o"
        )
        menu.addItem(withTitle: "修改快捷键…", action: #selector(editShortcut), keyEquivalent: "")
        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let versionItem = menu.addItem(withTitle: "版本 \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出丫丫灵动", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func setupGlobalHotKey() {
        globalHotKey = GlobalHotKey(
            keyCode: shortcutConfiguration.keyCode,
            modifiers: shortcutConfiguration.modifiers
        ) { [weak self] in
            self?.toggleHotKeyPanel()
        }
    }

    private func setupDismissMonitors() {
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            Task { @MainActor in self?.handleMouseDown(event) }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            MainActor.assumeIsolated { self?.handleLocalMouseDown(event) }
            return event
        }
    }

    private func startPointerTracking() {
        pointerTrackingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPointer() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        pointerTrackingTimer = timer
        checkPointer()
    }

    private func checkPointer() {
        // Pointer movement may only keep an already-open panel visible or hide it.
        // Opening is exclusively handled by click, shortcut, or menu actions.
        guard panel.isVisible else { return }
        guard let screen = screenContainingMouse() ?? NSScreen.main else { return }
        let pointer = NSEvent.mouseLocation
        // Date editing is presented in a separate popover window. Treat that popover
        // as part of the drawer so it remains usable while the main panel is open.
        let insidePanelOrPopover = isInsideDrawerOrPopover(pointer)

        if isPinnedByHotKey {
            if insidePanelOrPopover {
                hasPointerEnteredAfterHotKey = true
            } else if hasPointerEnteredAfterHotKey && panel.isVisible && !isAnimatingIn && !isAnimatingOut {
                isPinnedByHotKey = false
                hasPointerEnteredAfterHotKey = false
                hidePanel(on: screen)
            }
            return
        }

        if !insidePanelOrPopover && !isAnimatingIn && !isAnimatingOut {
            hidePanel(on: screen)
        }
    }

    private func showPanel(on screen: NSScreen) {
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        let expandedY = screen.frame.maxY - size.height
        let targetOrigin = NSPoint(x: x, y: expandedY)

        // If the pointer reaches the notch on another display while the drawer is
        // already visible, move it to that display instead of leaving it behind.
        if panel.isVisible && !isAnimatingOut {
            if abs(panel.frame.origin.x - targetOrigin.x) > 0.5
                || abs(panel.frame.origin.y - targetOrigin.y) > 0.5 {
                panel.setFrameOrigin(targetOrigin)
            }
            return
        }

        isAnimatingIn = true
        isAnimatingOut = false
        if !panel.isVisible {
            // Keep the real window in its final position. Only its clipped content
            // moves, avoiding off-screen NSPanel frame constraints near the notch.
            panel.setFrameOrigin(targetOrigin)
            drawerView.frame = NSRect(origin: NSPoint(x: 0, y: size.height - 42), size: size)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.drawerView.animator().setFrameOrigin(.zero)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isAnimatingOut else { return }
                self.isAnimatingIn = false
                self.checkPointer()
            }
        }
    }

    private func hidePanel(on screen: NSScreen) {
        isAnimatingIn = false
        isAnimatingOut = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.drawerView.animator().setFrameOrigin(
                NSPoint(x: 0, y: self.panel.frame.height - 42)
            )
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.isAnimatingOut else { return }
                self.panel.orderOut(nil)
                self.isAnimatingOut = false
                self.store.requestMemoListReset()
            }
        }
    }

    private func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func notchTrigger(on screen: NSScreen) -> NSRect {
        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea,
           !leftArea.isEmpty,
           !rightArea.isEmpty,
           rightArea.minX > leftArea.maxX {
            // The gap between the two unobscured menu-bar areas is the physical notch.
            // A 3pt horizontal allowance prevents precision issues without occupying
            // any of the usable content directly below it.
            let menuBarHeight = max(
                screen.safeAreaInsets.top,
                screen.frame.maxY - screen.visibleFrame.maxY
            )
            let height = min(max(menuBarHeight + 8, 36), 54)
            return NSRect(
                x: leftArea.maxX - 3,
                y: screen.frame.maxY - height,
                width: rightArea.minX - leftArea.maxX + 6,
                height: height
            )
        }

        // Displays without a notch get a compact top-center trigger only.
        return NSRect(
            x: screen.frame.midX - 90,
            y: screen.frame.maxY - 30,
            width: 180,
            height: 30
        )
    }

    private func isInsideDrawerOrPopover(_ point: NSPoint) -> Bool {
        if let button = statusItem.button,
           let window = button.window {
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonFrame.contains(point) { return true }
        }
        return NSApp.windows.contains { $0.isVisible && $0.frame.contains(point) }
    }

    private func handleLocalMouseDown(_ event: NSEvent) {
        // Capture this synchronously, before a SwiftUI popover's Save action closes
        // and destroys its window. The pointer can then remain outside the drawer
        // without being mistaken for a leave event.
        if isPinnedByHotKey,
           panel.isVisible,
           let eventWindow = event.window,
           eventWindow !== panel {
            hasPointerEnteredAfterHotKey = false
            return
        }
        handleMouseDown(event)
    }

    private func handleMouseDown(_ event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        guard let screen = screenContainingMouse() ?? NSScreen.main else { return }

        if event.type == .leftMouseDown,
           (!panel.isVisible || isAnimatingOut),
           notchTrigger(on: screen).contains(pointer) {
            isPinnedByHotKey = true
            hasPointerEnteredAfterHotKey = false
            showPanel(on: screen)
            hasPointerEnteredAfterHotKey = isInsideDrawerOrPopover(pointer)
            return
        }

        dismissHotKeyPanelIfClickedOutside()
    }

    private func dismissHotKeyPanelIfClickedOutside() {
        guard isPinnedByHotKey, panel.isVisible else { return }
        let pointer = NSEvent.mouseLocation
        guard !isInsideDrawerOrPopover(pointer),
              let screen = screenContainingMouse() ?? NSScreen.main else {
            hasPointerEnteredAfterHotKey = true
            return
        }

        isPinnedByHotKey = false
        hasPointerEnteredAfterHotKey = false
        hidePanel(on: screen)
    }

    @objc private func openFromMenu() {
        guard let screen = NSScreen.main else { return }
        isPinnedByHotKey = true
        showPanel(on: screen)
        hasPointerEnteredAfterHotKey = isInsideDrawerOrPopover(NSEvent.mouseLocation)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.requestAddFocus()
    }

    @objc private func editShortcut() {
        let recorder = ShortcutRecorderView(initial: shortcutConfiguration)
        let alert = NSAlert()
        alert.messageText = "修改快捷键"
        alert.informativeText = "点击下方区域，然后按下新的组合键。快捷键必须包含 Command、Option 或 Control。"
        alert.accessoryView = recorder
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { alert.window.makeFirstResponder(recorder) }

        guard alert.runModal() == .alertFirstButtonReturn,
              let configuration = recorder.capturedConfiguration else { return }
        guard configuration != shortcutConfiguration else { return }

        let previousConfiguration = shortcutConfiguration
        globalHotKey?.invalidate()
        globalHotKey = nil
        let candidate = makeGlobalHotKey(configuration)
        guard candidate.isRegistered else {
            candidate.invalidate()
            globalHotKey = makeGlobalHotKey(previousConfiguration)
            let errorAlert = NSAlert()
            errorAlert.messageText = "快捷键无法使用"
            errorAlert.informativeText = "这个组合键可能已被其他应用占用，请换一个再试。"
            errorAlert.runModal()
            return
        }

        globalHotKey = candidate
        shortcutConfiguration = configuration
        shortcutConfiguration.save()
        openMenuItem?.title = "打开备忘录  \(configuration.displayText)"
    }

    private func makeGlobalHotKey(_ configuration: ShortcutConfiguration) -> GlobalHotKey {
        GlobalHotKey(keyCode: configuration.keyCode, modifiers: configuration.modifiers) { [weak self] in
            self?.toggleHotKeyPanel()
        }
    }

    private func toggleHotKeyPanel() {
        guard let screen = screenContainingMouse() ?? NSScreen.main else { return }
        if panel.isVisible && isPinnedByHotKey {
            isPinnedByHotKey = false
            hasPointerEnteredAfterHotKey = false
            hidePanel(on: screen)
            return
        }

        isPinnedByHotKey = true
        showPanel(on: screen)
        hasPointerEnteredAfterHotKey = isInsideDrawerOrPopover(NSEvent.mouseLocation)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.store.requestAddFocus()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
