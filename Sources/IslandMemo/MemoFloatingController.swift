import AppKit
import Combine
import SwiftUI

/// Independent desktop entry point; both windows use AppDelegate's TaskStore.
@MainActor
final class MemoFloatingController: NSObject, NSWindowDelegate {
    private let store: TaskStore
    private let settings: AppSettingsStore
    private let defaults: UserDefaults
    private(set) var orbPanel: NSPanel?
    private(set) var memoPanel: NSPanel?
    private var settingsObservation: AnyCancellable?
    private var screenObservation: NSObjectProtocol?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isPositioning = false
    private var isStarted = false
    private static let positionKey = "memo-floating-orb-frame-v1"

    init(store: TaskStore, settings: AppSettingsStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.settings = settings
        self.defaults = defaults
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        settingsObservation = Publishers.CombineLatest3(settings.$enabledFeatures, settings.$enabledHomeModules,
                                                        settings.$memoFloatingEnabled)
            .sink { [weak self] _ in
                // @Published emits before assignment; inspect the committed placement
                // after both the tab and home-module sets have been updated.
                Task { @MainActor in self?.syncVisibility() }
            }
        screenObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.fitToScreen() }
        }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor in self?.collapse() }
        }
        // Independent app windows close this popup; its menus and editors remain usable.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            if let window = event.window,
               let role = WindowInteractionPolicy.rootRole(of: window),
               role != WindowInteractionPolicy.memo && role != WindowInteractionPolicy.orb {
                self?.collapse()
            }
            return event
        }
        syncVisibility()
    }

    func stop() {
        isStarted = false
        settingsObservation = nil
        if let screenObservation { NotificationCenter.default.removeObserver(screenObservation) }
        screenObservation = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        globalMouseMonitor = nil
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        localMouseMonitor = nil
        orbPanel?.orderOut(nil)
        memoPanel?.orderOut(nil)
    }

    private var isEnabled: Bool { settings.canEnableMemoFloating && settings.memoFloatingEnabled }

    private func syncVisibility() {
        guard isStarted else { return }
        guard isEnabled else {
            orbPanel?.orderOut(nil)
            memoPanel?.orderOut(nil)
            return
        }
        installPanelsIfNeeded()
        if memoPanel?.isVisible != true { orbPanel?.orderFrontRegardless() }
    }

    func expand() {
        guard isStarted, isEnabled else { return }
        installPanelsIfNeeded()
        guard let orbPanel, let memoPanel else { return }
        let area = screen(for: orbPanel.frame).visibleFrame
        let size = NSSize(width: min(MemoFloatingMetrics.windowSize.width, area.width - 16),
                          height: min(MemoFloatingMetrics.windowSize.height, area.height - 16))
        let target = NSRect(x: orbPanel.frame.maxX - size.width, y: orbPanel.frame.maxY - size.height,
                            width: size.width, height: size.height)
        position(memoPanel, frame: Self.clamped(target, to: area))
        orbPanel.orderOut(nil)
        memoPanel.makeKeyAndOrderFront(nil)
    }

    func collapse() {
        guard isStarted, let memoPanel, memoPanel.isVisible, let orbPanel else { return }
        let side = MemoFloatingMetrics.orbSide
        let target = NSRect(x: memoPanel.frame.maxX - side, y: memoPanel.frame.maxY - side,
                            width: side, height: side)
        position(orbPanel, frame: Self.clamped(target, to: screen(for: memoPanel.frame).visibleFrame))
        savePosition()
        memoPanel.orderOut(nil)
        if isEnabled { orbPanel.orderFrontRegardless() }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isPositioning, let window = notification.object as? NSWindow else { return }
        if window === orbPanel {
            let area = screen(for: window.frame).visibleFrame
            position(window, frame: Self.clamped(window.frame, to: area))
            savePosition()
        } else if window === memoPanel, let orbPanel {
            let side = MemoFloatingMetrics.orbSide
            let anchor = NSRect(x: window.frame.maxX - side, y: window.frame.maxY - side,
                                width: side, height: side)
            position(orbPanel, frame: Self.clamped(anchor, to: screen(for: window.frame).visibleFrame))
            savePosition()
        }
    }

    private func installPanelsIfNeeded() {
        guard orbPanel == nil else { return }
        let area = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let side = MemoFloatingMetrics.orbSide
        let initial = NSRect(x: area.maxX - side - 24, y: area.midY - side / 2, width: side, height: side)
        let saved = defaults.string(forKey: Self.positionKey).map(NSRectFromString)
        let restored = saved.flatMap { frame -> NSRect? in
            guard frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width > 0, frame.height > 0 else { return nil }
            return NSRect(origin: frame.origin, size: initial.size)
        } ?? initial
        let orb = makePanel(title: "备忘录悬浮球")
        orb.identifier = WindowInteractionPolicy.orb
        orb.contentView = NSHostingView(rootView: MemoOrbView(store: store) { [weak self] in self?.expand() })
        orbPanel = orb
        position(orb, frame: Self.clamped(restored, to: screen(for: restored).visibleFrame))

        let memo = makePanel(title: "备忘录小窗口")
        memo.identifier = WindowInteractionPolicy.memo
        memo.isMovableByWindowBackground = true
        memo.onEscape = { [weak self] in self?.collapse() }
        memo.contentView = NSHostingView(rootView: MemoFloatingView(store: store, settings: settings,
            isVisible: { [weak self] in self?.memoPanel?.isVisible == true }) { [weak self] in
            self?.collapse()
        })
        memoPanel = memo
    }

    private func makePanel(title: String) -> MemoFloatingPanel {
        let panel = MemoFloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.delegate = self
        return panel
    }

    private func position(_ window: NSWindow, frame: NSRect) {
        isPositioning = true
        window.setFrame(frame, display: window.isVisible)
        isPositioning = false
    }

    private func savePosition() {
        guard let orbPanel else { return }
        defaults.set(NSStringFromRect(orbPanel.frame), forKey: Self.positionKey)
    }

    private func screen(for frame: NSRect) -> NSScreen {
        let intersecting = NSScreen.screens.filter { $0.visibleFrame.intersects(frame) }
        return intersecting.max { left, right in
            let l = left.visibleFrame.intersection(frame)
            let r = right.visibleFrame.intersection(frame)
            return l.width * l.height < r.width * r.height
        } ?? NSScreen.main!
    }

    private func fitToScreen() {
        guard isStarted, let orbPanel else { return }
        if let memoPanel, memoPanel.isVisible {
            position(memoPanel, frame: Self.clamped(memoPanel.frame, to: screen(for: memoPanel.frame).visibleFrame))
            windowDidMove(Notification(name: NSWindow.didMoveNotification, object: memoPanel))
        } else {
            position(orbPanel, frame: Self.clamped(orbPanel.frame, to: screen(for: orbPanel.frame).visibleFrame))
            savePosition()
        }
    }

    static func clamped(_ frame: NSRect, to area: NSRect) -> NSRect {
        let width = min(frame.width, max(1, area.width - 16))
        let height = min(frame.height, max(1, area.height - 16))
        return NSRect(x: min(max(frame.minX, area.minX + 8), area.maxX - width - 8),
                      y: min(max(frame.minY, area.minY + 8), area.maxY - height - 8),
                      width: width, height: height)
    }
}

private final class MemoFloatingPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
