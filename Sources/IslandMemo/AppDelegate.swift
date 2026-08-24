import AppKit
import SwiftUI
import QuartzCore
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TaskStore(repository: LocalTaskRepository())
    private var panel: IslandPanel!
    private var drawerView: NSView!
    private var statusItem: NSStatusItem!
    private var hoverTimer: Timer?
    private var globalHotKey: GlobalHotKey?
    private var isAnimatingIn = false
    private var isAnimatingOut = false
    private var isPinnedByHotKey = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        setupMenuBar()
        setupGlobalHotKey()
        store.load()
        startHoverTracking()
    }

    private func setupPanel() {
        panel = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 444, height: 524),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: IslandView(store: store))
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
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "灵岛备忘")

        let menu = NSMenu()
        menu.addItem(withTitle: "打开备忘录  ⇧⌘+", action: #selector(openFromMenu), keyEquivalent: "o")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let versionItem = menu.addItem(withTitle: "版本 \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出灵岛备忘", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func setupGlobalHotKey() {
        globalHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_Equal),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.toggleHotKeyPanel()
        }
    }

    private func startHoverTracking() {
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPointer() }
        }
    }

    private func checkPointer() {
        if isPinnedByHotKey { return }
        guard let screen = screenContainingMouse() ?? NSScreen.main else { return }
        let pointer = NSEvent.mouseLocation
        let centerX = screen.frame.midX
        // The pointer can sit slightly below the physical notch because macOS keeps
        // menu-bar hit testing out of the camera housing. Include that reachable band.
        let trigger = NSRect(x: centerX - 140, y: screen.frame.maxY - 86, width: 280, height: 86)
        // Date editing is presented in a separate popover window. Treat that popover
        // as part of the drawer so it remains usable while the main panel is open.
        let insidePanelOrPopover = NSApp.windows.contains {
            $0.isVisible && $0.frame.contains(pointer)
        }

        if trigger.contains(pointer) || insidePanelOrPopover {
            showPanel(on: screen)
        } else if panel.isVisible && !isAnimatingIn && !isAnimatingOut {
            hidePanel(on: screen)
        }
    }

    private func showPanel(on screen: NSScreen) {
        guard !panel.isVisible || isAnimatingOut else { return }
        isAnimatingIn = true
        isAnimatingOut = false
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        let expandedY = screen.frame.maxY - size.height
        if !panel.isVisible {
            // Keep the real window in its final position. Only its clipped content
            // moves, avoiding off-screen NSPanel frame constraints near the notch.
            panel.setFrameOrigin(NSPoint(x: x, y: expandedY))
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
            }
        }
    }

    private func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    @objc private func openFromMenu() {
        guard let screen = NSScreen.main else { return }
        isPinnedByHotKey = true
        showPanel(on: screen)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.requestAddFocus()
    }

    private func toggleHotKeyPanel() {
        guard let screen = screenContainingMouse() ?? NSScreen.main else { return }
        if panel.isVisible && isPinnedByHotKey {
            isPinnedByHotKey = false
            hidePanel(on: screen)
            return
        }

        isPinnedByHotKey = true
        showPanel(on: screen)
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
