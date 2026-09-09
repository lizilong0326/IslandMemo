import AppKit
import SwiftUI

@MainActor
final class MemoCaptureController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isProcessing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var reviewReason: String?
    @Published private(set) var savedID: UUID?
    @Published private(set) var hasDraft = false
    @Published private(set) var processingMessage = "正在提炼任务和截止时间…"
    @Published private(set) var isInferring = false
    @Published private(set) var canInfer = false
    @Published private(set) var usesOriginalText = false
    @Published var title = ""
    @Published var hasDueDate = false
    @Published var dueDate = Date()
    @Published var priority: TaskPriority = .blue
    let settings: AppSettingsStore
    private let store: TaskStore
    private let openSettings: () -> Void
    private var window: NSWindow?
    private var operation: Task<Void, Never>?
    private var requestID = UUID()
    private let configuration: () -> MemoAIConfiguration

    init(store: TaskStore, settings: AppSettingsStore? = nil,
         configuration: @escaping () -> MemoAIConfiguration = MemoAIConfiguration.load,
         openSettings: @escaping () -> Void) {
        self.store = store
        self.settings = settings ?? AppSettingsStore()
        self.configuration = configuration
        self.openSettings = openSettings
    }

    func begin(text: String, source: String) {
        // Preserve an in-flight request or an unconfirmed draft when another entry is clicked.
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        title = text
        hasDraft = true
        hasDueDate = false
        dueDate = Date().addingTimeInterval(3600)
        savedID = nil
        reviewReason = nil
        errorMessage = nil
        isInferring = false
        usesOriginalText = true
        priority = .blue
        refreshModelAvailability()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 420, height: 300)
        window.title = "生成备忘录 · \(source)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: MemoCaptureView(controller: self, settings: settings))
        // The window owns its size. Draft content scrolls above a fixed footer, so SwiftUI
        // cannot expand the hosted content past the bottom of the window when options change.
        hosting.sizingOptions = []
        window.contentView = hosting
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func generate() {
        guard hasDraft, !isProcessing, savedID == nil else { return }
        let configuration = configuration()
        guard configuration.isReadyForProcessing else {
            refreshModelAvailability()
            return
        }
        let text = title
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请先填写任务内容。"
            return
        }
        operation?.cancel()
        requestID = UUID()
        let id = requestID
        isInferring = true
        isProcessing = true
        processingMessage = "正在提炼任务和截止时间…"
        errorMessage = nil
        operation = Task { [weak self] in
            do {
                let draft = try await MemoAIService().extract(text: text, configuration: configuration)
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.title = draft.title
                self.hasDueDate = draft.dueDate != nil
                self.dueDate = draft.dueDate ?? Date().addingTimeInterval(3600)
                self.reviewReason = draft.reviewReason
                self.hasDraft = true
                self.usesOriginalText = false
                self.isInferring = false
                self.isProcessing = false
            } catch {
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.isInferring = false
                self.isProcessing = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func save() {
        guard hasDraft, !isProcessing, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorMessage = nil
        if let savedID {
            store.updateMemo(id: savedID, title: title, dueDate: hasDueDate ? dueDate : nil, priority: priority, preserveWhitespace: usesOriginalText)
        } else {
            savedID = store.add(title: title, dueDate: hasDueDate ? dueDate : nil, priority: priority, preserveWhitespace: usesOriginalText)
        }
        isProcessing = true
        processingMessage = "正在保存备忘录…"
        let id = requestID
        operation = Task { [weak self] in
            guard let self else { return }
            let success = await self.store.awaitPendingSave()
            guard !Task.isCancelled, self.requestID == id else { return }
            self.isProcessing = false
            if success {
                self.hasDraft = false
                self.close()
            } else {
                self.errorMessage = self.store.errorMessage ?? "保存失败，请重试。"
            }
        }
    }

    func cancelInference() {
        guard isInferring else { return }
        operation?.cancel()
        operation = nil
        requestID = UUID()
        isInferring = false
        isProcessing = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Keep storage errors visible until the write finishes; inference can be cancelled.
        !isProcessing || isInferring
    }

    func configure() { openSettings() }
    func close() { window?.close() }

    func refreshModelAvailability() {
        canInfer = configuration().isReadyForProcessing
        if !canInfer { cancelInference() }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshModelAvailability()
    }

    func windowWillClose(_ notification: Notification) {
        operation?.cancel()
        operation = nil
        requestID = UUID()
        isProcessing = false
        isInferring = false
        window = nil
    }
}

private struct MemoCaptureView: View {
    @ObservedObject var controller: MemoCaptureController
    @ObservedObject var settings: AppSettingsStore
    @State private var showsDateEditor = false
    @State private var showsPriorityEditor = false
    @State private var draftDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(.white.opacity(0.08))
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .memoAIConfigurationChanged)) { _ in
            controller.refreshModelAvailability()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("任务内容").font(.headline)
                Spacer(minLength: 0)
                Button("模型设置") { controller.configure() }
                    .buttonStyle(.link)
                if controller.canInfer {
                    Button(controller.isInferring ? "取消推理" : "推理") {
                        if controller.isInferring { controller.cancelInference() }
                        else { controller.generate() }
                    }
                    .disabled((controller.isProcessing && !controller.isInferring) ||
                              controller.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              controller.savedID != nil)
                }
            }
            if controller.isProcessing {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(controller.processingMessage).font(.caption)
                }
            } else {
                Text(controller.usesOriginalText
                     ? (controller.canInfer ? "点击「推理」处理当前内容并回填；直接添加会保存当前内容。" : "直接保存当前内容；配置大模型后可使用「推理」。")
                     : "已完成推理，可修改内容、级别和时间后直接添加。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = controller.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            if let reason = controller.reviewReason {
                Text(reason).font(.caption).foregroundStyle(.orange)
            }
            TextEditor(text: $controller.title)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(height: 96)
                .padding(6)
                .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.15)))
                .accessibilityLabel("任务内容")
                .disabled(controller.isProcessing)
            taskOptions.disabled(controller.isProcessing)
        }
    }

    private var taskOptions: some View {
        HStack(spacing: 14) {
            if settings.memoDueDatesEnabled || controller.hasDueDate {
                Button {
                    draftDate = controller.hasDueDate ? controller.dueDate : .now.addingTimeInterval(3600)
                    showsPriorityEditor = false
                    showsDateEditor = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: controller.hasDueDate ? "clock.fill" : "clock")
                        Text(controller.hasDueDate
                             ? controller.dueDate.formatted(.dateTime.month().day().hour().minute())
                             : "结束时间")
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .foregroundStyle(controller.hasDueDate ? Color.blue : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("设置结束时间")
                .accessibilityLabel("设置结束时间")
                .popover(isPresented: $showsDateEditor, arrowEdge: .bottom) {
                    DueDatePickerPopover(
                        selection: $draftDate,
                        showsClear: controller.hasDueDate,
                        onClear: {
                            controller.hasDueDate = false
                            showsDateEditor = false
                        },
                        onSave: {
                            controller.dueDate = draftDate
                            controller.hasDueDate = true
                            showsDateEditor = false
                        }
                    )
                }
            }
            if settings.memoPrioritiesEnabled {
                Button {
                    showsDateEditor = false
                    showsPriorityEditor = true
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(settings.priorityColor(for: controller.priority)).frame(width: 11, height: 11)
                        Text(settings.priorityName(for: controller.priority))
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("任务等级")
                .accessibilityLabel("任务等级")
                .popover(isPresented: $showsPriorityEditor, arrowEdge: .bottom) {
                    PriorityPickerPopover(selection: $controller.priority, settings: settings) {
                        showsPriorityEditor = false
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("取消") { controller.close() }
                .disabled(controller.isProcessing && !controller.isInferring)
            Spacer(minLength: 6)
            Button(controller.savedID == nil ? "添加任务" : "重试保存") { controller.save() }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isProcessing || controller.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
