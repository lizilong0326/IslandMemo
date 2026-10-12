import AppKit
import SwiftUI

enum MemoFloatingMetrics {
    // Match YaYaStatus's 0.7-scaled, 64pt orb window and 60pt face.
    static let orbSide: CGFloat = 44.8
    static let faceSide: CGFloat = 42
    static let windowSize = NSSize(width: 440, height: 480)
}

struct MemoOrbView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettingsStore
    let onActivate: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onInteractionStarted: () -> Void

    private var pendingCount: Int {
        store.activeTasks.filter { !$0.isCompleted }.count
    }

    var body: some View {
        MemoOrbFace(pendingCount: pendingCount)
            .overlay {
                MemoOrbDragControl(
                    label: "备忘录，\(pendingCount) 个未完成任务",
                    toolTip: settings.memoFloatingTrigger == .hover
                        ? "移入立即展开备忘录 · 移出工作区域自动收起" : "点击打开备忘录 · 拖动调整位置",
                    onActivate: onActivate,
                    onHoverChanged: onHoverChanged,
                    onInteractionStarted: onInteractionStarted
                )
            }
    }
}

/// Shared by the desktop orb and the read-only settings preview.
struct MemoOrbFace: View {
    let pendingCount: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle().fill(colorScheme == .dark
                ? Color.black.opacity(0.8)
                : Color(nsColor: .windowBackgroundColor).opacity(0.92))
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1)
            Circle()
                .stroke(pendingCount > 0 ? ring : AngularGradient(colors: [.gray.opacity(0.5)], center: .center),
                        lineWidth: 1.8)
                .padding(3.5)
            if pendingCount > 0 {
                Text(pendingCount > 9 ? "9+" : String(pendingCount))
                    .font(.custom("AvenirNext-DemiBold", size: pendingCount > 9 ? 11.2 : 15.4))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary)
            } else {
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: MemoFloatingMetrics.faceSide, height: MemoFloatingMetrics.faceSide)
        .frame(width: MemoFloatingMetrics.orbSide, height: MemoFloatingMetrics.orbSide)
    }

    private var ring: AngularGradient {
        AngularGradient(colors: [
            Color(red: 0.24, green: 0.30, blue: 0.61).opacity(0.35),
            Color(red: 0.62, green: 0.43, blue: 1),
            Color(red: 0.30, green: 0.62, blue: 1),
            Color(red: 0.67, green: 0.90, blue: 1),
            Color(red: 0.24, green: 0.30, blue: 0.61).opacity(0.35)
        ], center: .center)
    }
}

struct MemoFloatingView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettingsStore
    let isVisible: () -> Bool
    let onCollapse: () -> Void
    @State private var section: MemoSection = .tasks

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checklist").foregroundStyle(IslandTheme.accentBlue)
                Text("备忘录").font(.system(size: 14, weight: .semibold))
                Spacer()
                if settings.memoTrashEnabled {
                    Button {
                        section = section == .tasks ? .trash : .tasks
                    } label: {
                        Image(systemName: section == .tasks ? "trash" : "checklist")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(section == .tasks ? "回收站" : "返回任务")
                    .accessibilityLabel(section == .tasks ? "回收站" : "返回任务")
                }
                Button(action: onCollapse) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("收起为悬浮球（Esc）")
                .accessibilityLabel("收起为悬浮球")
            }
            MemoWorkspaceView(store: store, appSettings: settings, section: $section, compact: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IslandTheme.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(LinearGradient(colors: [.purple.opacity(0.4), IslandTheme.accentBlue.opacity(0.3)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
        .tint(IslandTheme.accentBlue)
        .alert("提示", isPresented: Binding(
            get: { store.errorMessage != nil && isVisible() },
            set: { if !$0 { store.errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

/// Let AppKit distinguish clicks from window dragging, as in YaYaStatus.
private struct MemoOrbDragControl: NSViewRepresentable {
    let label: String
    let toolTip: String
    let onActivate: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onInteractionStarted: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onActivate) }

    func makeNSView(context: Context) -> MemoOrbButton {
        let button = MemoOrbButton()
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.activate)
        return button
    }

    func updateNSView(_ button: MemoOrbButton, context: Context) {
        context.coordinator.onActivate = onActivate
        button.setAccessibilityLabel(label)
        button.toolTip = toolTip
        button.onHoverChanged = onHoverChanged
        button.onInteractionStarted = onInteractionStarted
    }

    final class Coordinator: NSObject {
        var onActivate: () -> Void
        init(_ onActivate: @escaping () -> Void) { self.onActivate = onActivate }
        @objc func activate() { onActivate() }
    }
}

private final class MemoOrbButton: NSButton {
    var onHoverChanged: ((Bool) -> Void)?
    var onInteractionStarted: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var originalMouseDown: NSEvent?
    private var startedWindowDrag = false
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

    override func mouseDown(with event: NSEvent) {
        onInteractionStarted?()
        originalMouseDown = event
        startedWindowDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !startedWindowDrag, let originalMouseDown else { return }
        let dx = event.locationInWindow.x - originalMouseDown.locationInWindow.x
        let dy = event.locationInWindow.y - originalMouseDown.locationInWindow.y
        guard dx * dx + dy * dy >= 16 else { return }
        startedWindowDrag = true
        window?.performDrag(with: originalMouseDown)
    }

    override func mouseUp(with event: NSEvent) {
        defer { originalMouseDown = nil; startedWindowDrag = false }
        if !startedWindowDrag, originalMouseDown != nil { performClick(nil) }
    }
}
