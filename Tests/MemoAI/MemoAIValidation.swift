import AppKit
import Foundation
import SwiftUI

@MainActor
private final class EditingShortcutProbe: NSView {
    var lastAction = ""
    override var acceptsFirstResponder: Bool { true }
    @objc func paste(_ sender: Any?) { lastAction = "paste" }
    @objc func copy(_ sender: Any?) { lastAction = "copy" }
    @objc func cut(_ sender: Any?) { lastAction = "cut" }
    override func selectAll(_ sender: Any?) { lastAction = "selectAll" }
    @objc func undo(_ sender: Any?) { lastAction = "undo" }
    @objc func redo(_ sender: Any?) { lastAction = "redo" }
}

actor MemoryRepository: TaskRepository {
    var items: [TaskItem] = []
    var shouldFail = false
    func load() async throws -> [TaskItem] { items }
    func save(_ tasks: [TaskItem]) async throws {
        if shouldFail { throw MemoAIError.message("模拟磁盘写入失败") }
        items = tasks
    }
    func fail(_ value: Bool) { shouldFail = value }
}

@main
struct MemoAIValidation {
    @MainActor private static var previewController: MemoCaptureController?
    @MainActor private static var previewCloseObserver: NSObjectProtocol?
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        ApplicationMenus.install()
        Task { @MainActor in
            do {
                try MemoAICredentialValidation.run()
                try await run()
                try validateEditingShortcuts()
                print("备忘录验证通过：无模型原文添加、保留换行和长文本、时间校验、接口响应、手动推理、取消、一次保存、保存重试、防重复创建")
                if CommandLine.arguments.contains("--inspect") {
                    showInteractivePreview()
                    return
                }
                if CommandLine.arguments.contains("--inspect-settings") {
                    showSettingsPreview()
                    return
                }
                app.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("验证失败：\(error)\n".utf8))
                exit(1)
            }
        }
        app.run()
    }

    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw MemoAIError.message(message) }
    }

    @MainActor private static func validateEditingShortcuts() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let responder = EditingShortcutProbe()
        window.contentView = responder
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(responder)
        defer { window.close() }
        let shortcuts: [(String, NSEvent.ModifierFlags, String)] = [
            ("v", .command, "paste"), ("c", .command, "copy"),
            ("x", .command, "cut"), ("a", .command, "selectAll"),
            ("z", .command, "undo"), ("z", [.command, .shift], "redo")
        ]
        for (key, modifiers, expected) in shortcuts {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                        characters: modifiers.contains(.shift) ? key.uppercased() : key,
                                        charactersIgnoringModifiers: modifiers.contains(.shift) ? key.uppercased() : key,
                                        isARepeat: false, keyCode: 0)!
            try require(NSApp.mainMenu?.performKeyEquivalent(with: event) == true, "编辑快捷键未被处理：\(expected)")
            try require(responder.lastAction == expected, "编辑快捷键未发送给当前输入框：\(expected)")
        }
        print("编辑快捷键验证通过：粘贴、复制、剪切、全选、撤销、重做；未访问系统剪贴板")
    }

    @MainActor private static func showSettingsPreview() {
        // This executable has its own defaults domain; never write production credentials.
        UserDefaults.standard.set(true, forKey: "memo-ai-enabled")
        UserDefaults.standard.set("", forKey: "memo-ai-endpoint")
        UserDefaults.standard.set("", forKey: "memo-ai-model")
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 460),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "模型设置粘贴验证（测试数据）"
        window.contentView = NSHostingView(rootView: MemoAISettingsView().padding(20))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                                      object: window, queue: .main) { _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    @MainActor static func settle(_ controller: MemoCaptureController) async throws {
        for _ in 0..<150 {
            if !controller.isProcessing { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw MemoAIError.message("等待生成超时")
    }

    static func requestCount() async throws -> Int {
        let url = URL(string: "http://127.0.0.1:\(CommandLine.arguments[1])/requests")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Int.self, from: data)
    }

    @MainActor static func run() async throws {
        let raw = "  明天下午三点前发送设计稿。\n保留第二行 🌍 和原始空格。  \n"
        let rawConfigurations = [
            MemoAIConfiguration(endpoint: "", model: "", apiKey: ""),
            MemoAIConfiguration(endpoint: "", model: "model", apiKey: "key"),
            MemoAIConfiguration(endpoint: "http://127.0.0.1:\(CommandLine.arguments[1])/chat/completions", model: "test-model", apiKey: "test-only", useModel: false)
        ]
        for (index, config) in rawConfigurations.enumerated() {
            let repository = MemoryRepository()
            let store = TaskStore(repository: repository)
            let controller = MemoCaptureController(store: store, configuration: { config }, openSettings: {})
            controller.begin(text: raw, source: "原文添加测试")
            controller.begin(text: raw, source: "重复点击")
            try await settle(controller)
            try require(controller.errorMessage == nil && controller.usesOriginalText, "无模型时不应要求配置或调用接口")
            try require(!controller.canInfer, "未配置或未启用模型时不应显示推理按钮")
            try require(await repository.items.isEmpty, "打开弹窗不应保存任务")
            try require(controller.title == raw && !controller.hasDueDate, "原文或时间被自动改写")
            if index == 0 { captureWindow(named: "生成备忘录 · 原文添加测试", file: "memo-original-text.png") }
            if index == 0 {
                controller.hasDueDate = true
                controller.dueDate = Date(timeIntervalSince1970: 2_000_000_000)
                controller.priority = .red
                NSApp.windows.first(where: { $0.title == "生成备忘录 · 原文添加测试" })?
                    .setContentSize(NSSize(width: 420, height: 300))
                try await Task.sleep(for: .milliseconds(100))
                captureWindow(named: "生成备忘录 · 原文添加测试", file: "memo-compact-with-date.png")
            }
            controller.save()
            controller.save()
            try await settle(controller)
            try require(await repository.items.count == 1, "一次添加未保存或发生重复")
            try require(await repository.items.first?.title == raw, "原文或换行空格被改写")
            try require(!controller.hasDraft, "成功保存后仍要求确认")
            if index == 0 {
                try require(await repository.items.first?.priority == .red, "任务等级未保存")
                try require(await repository.items.first?.dueDate == Date(timeIntervalSince1970: 2_000_000_000), "时间和级别未一起保存")
            } else {
                try require(await repository.items.first?.dueDate == nil, "无模型时不应解释时间")
            }
            let longText = String(repeating: "原文🌍\n", count: 3001)
            controller.begin(text: longText, source: "长原文测试")
            try await settle(controller)
            try require(controller.priority == .blue, "新任务继承了上一条的等级")
            controller.save()
            try await settle(controller)
            try require(await repository.items.last?.title == longText, "原文添加错误地应用了模型长度限制")
            controller.close()
            controller.begin(text: "  \n  ", source: "空选区测试")
            try await settle(controller)
            controller.save()
            try require(store.tasks.count == 2, "空选区不应生成任务")
            controller.close()
        }
        let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 500),
                                      styleMask: [.titled], backing: .buffered, defer: false)
        settingsWindow.title = "模型设置测试"
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.contentView = NSHostingView(rootView: MemoAISettingsView()
            .padding(20).frame(width: 390).background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark))
        settingsWindow.orderFront(nil)
        try await Task.sleep(for: .milliseconds(150))
        captureWindow(named: "模型设置测试", file: "memo-settings.png")
        settingsWindow.close()
        let now = ISO8601DateFormatter().date(from: "2026-09-09T10:00:00+08:00")!
        let source = "2030年9月10日15点前整理并发送首页设计稿"
        let exact = MemoAIExtraction(title: "交付设计稿", dueAt: "2030-09-10T15:00:00+08:00",
                                     timeEvidence: "2030年9月10日15点", needsReview: false, reviewReason: nil)
        let draft = try exact.validated(source: source, now: now)
        try require(draft.dueDate == ISO8601DateFormatter().date(from: "2030-09-10T07:00:00Z"), "时区转换错误")
        try require(draft.reviewReason == nil, "明确时间应允许自动创建")
        let hallucinated = try exact.validated(source: "交付设计稿", now: now)
        try require(hallucinated.dueDate == nil && hallucinated.reviewReason != nil, "原文无时间证据时不能自动创建日期")
        let past = try exact.validated(source: source, now: Date(timeIntervalSince1970: 2_100_000_000))
        try require(past.reviewReason != nil, "过去时间必须确认")
        let invalid = try MemoAIExtraction(title: "交付", dueAt: "tomorrow", timeEvidence: "明天", needsReview: false, reviewReason: nil)
            .validated(source: "明天交付", now: now)
        try require(invalid.dueDate == nil && invalid.reviewReason != nil, "错误时间格式必须确认")
        let absent = try MemoAIExtraction(title: "交付", dueAt: nil, timeEvidence: nil, needsReview: false, reviewReason: nil)
            .validated(source: "交付", now: now)
        try require(absent.dueDate == nil && absent.reviewReason == nil, "无时间不应补日期")
        let dateOnly = try MemoAIExtraction(title: "交付", dueAt: "2030-09-10T23:59:00+08:00", timeEvidence: "2030年9月10日", needsReview: true, reviewReason: "使用当日结束时间")
            .validated(source: "2030年9月10日交付", now: now)
        try require(dateOnly.reviewReason != nil, "只有日期需要确认")
        let config = MemoAIConfiguration(endpoint: "http://127.0.0.1:\(CommandLine.arguments[1])/chat/completions", model: "test-model", apiKey: "test-only")
        for endpoint in ["http://example.com/chat/completions", "https://example.com/v1", "https://name:pass@example.com/chat/completions", "https://example.com/chat/completions?key=bad"] {
            do {
                _ = try MemoAIConfiguration(endpoint: endpoint, model: "test", apiKey: "test").validatedURL()
                throw MemoAIError.message("接受了不合规地址：\(endpoint)")
            } catch let error as MemoAIError {
                if error.localizedDescription.hasPrefix("接受了") { throw error }
            }
        }
        let service = MemoAIService()
        let network = try await service.extract(text: source, configuration: config, now: now)
        try require(network.dueDate == draft.dueDate, "网络响应解析错误")
        for input in ["unauthorized", "malformed", "redirect", String(repeating: "字", count: 12001)] {
            do {
                _ = try await service.extract(text: input, configuration: config)
                throw MemoAIError.message("错误输入被当成成功：\(input.prefix(20))")
            } catch let error as MemoAIError {
                if error.localizedDescription.hasPrefix("错误输入") { throw error }
            }
        }
        let repo = MemoryRepository()
        let store = TaskStore(repository: repo)
        let controller = MemoCaptureController(store: store, configuration: { config }, openSettings: {})
        let requestsBeforeOpen = try await requestCount()
        controller.begin(text: source, source: "测试文本")
        controller.begin(text: "不应替换草稿", source: "重复点击")
        try await Task.sleep(for: .milliseconds(150))
        try require(try await requestCount() == requestsBeforeOpen, "打开弹窗自动调用了模型")
        try require(controller.title == source && store.tasks.isEmpty, "打开弹窗改写或保存了任务")
        try require(controller.canInfer, "已配置模型时没有推理入口")
        controller.generate()
        controller.generate()
        try await settle(controller)
        try require(try await requestCount() == requestsBeforeOpen + 1, "推理按钮重复发起请求")
        try require(controller.savedID == nil && store.tasks.isEmpty, "推理完成后不应自动创建任务")
        try require(controller.hasDueDate && controller.dueDate == draft.dueDate, "推理未填写截止时间")
        captureWindow(named: "生成备忘录 · 测试文本", file: "memo-inferred.png")
        controller.title = "修改后的任务"
        controller.priority = .red
        controller.save()
        controller.save()
        try await settle(controller)
        try require(await repo.items.count == 1 && controller.title == "修改后的任务", "一次点击未保存或重复保存")
        try require(!controller.hasDraft && !NSApp.windows.contains(where: { $0.isVisible && $0.title == "生成备忘录 · 测试文本" }), "添加后未关闭弹窗")
        controller.save()
        try require(store.tasks.count == 1, "关闭后仍可重复添加")
        controller.begin(text: "尽快交付", source: "含糊时间")
        controller.generate()
        try await settle(controller)
        try require(controller.savedID == nil && store.tasks.count == 1 && controller.reviewReason != nil, "含糊时间应保留草稿提示")
        captureWindow(named: "生成备忘录 · 含糊时间", file: "memo-review.png")
        controller.save()
        try await settle(controller)
        try require(await repo.items.count == 2 && !controller.hasDraft, "含糊时间点击添加后仍要求确认")
        controller.begin(text: "slow", source: "取消测试")
        controller.generate()
        controller.close()
        try await Task.sleep(for: .seconds(1))
        try require(store.tasks.count == 2, "取消后仍创建任务")
        controller.begin(text: "slow", source: "取消推理")
        controller.generate()
        controller.cancelInference()
        controller.title = "保留取消后的编辑"
        try await Task.sleep(for: .seconds(1))
        try require(controller.title == "保留取消后的编辑" && !controller.isProcessing, "取消后模型结果覆盖草稿")
        controller.close()
        controller.begin(text: "unauthorized", source: "推理失败")
        controller.generate()
        try await settle(controller)
        try require(controller.errorMessage != nil && controller.title == "unauthorized", "推理失败丢失原文")
        controller.save()
        try await settle(controller)
        try require(await repo.items.last?.title == "unauthorized" && !controller.hasDraft, "推理失败不能直接保存原文")
        await repo.fail(true)
        controller.begin(text: "普通任务", source: "存储失败")
        controller.save()
        try await settle(controller)
        try require(controller.errorMessage != nil && store.tasks.count == 4 && controller.hasDraft, "保存失败应留在弹窗重试")
        await repo.fail(false)
        controller.save()
        try await settle(controller)
        try require(controller.errorMessage == nil && store.tasks.count == 4 && !controller.hasDraft, "保存重试重复创建或未关闭")
        let disabledConfig = MemoAIConfiguration(endpoint: config.endpoint, model: config.model, apiKey: config.apiKey, useModel: false)
        let disabled = MemoCaptureController(store: store, configuration: { disabledConfig }, openSettings: {})
        let requestsBeforeDisabled = try await requestCount()
        disabled.begin(text: "关闭模型", source: "开关验证")
        disabled.generate()
        try await settle(disabled)
        try require(try await requestCount() == requestsBeforeDisabled, "模型开关关闭仍发起请求")
        disabled.close()
        var liveConfiguration = disabledConfig
        let live = MemoCaptureController(store: store, configuration: { liveConfiguration }, openSettings: {})
        live.begin(text: "slow", source: "配置刷新验证")
        try require(!live.canInfer, "模型关闭仍显示推理入口")
        liveConfiguration = config
        live.refreshModelAvailability()
        try require(live.canInfer && !live.isProcessing && live.title == "slow", "完成模型配置后应只显示入口，不自动推理")
        live.generate()
        liveConfiguration = disabledConfig
        live.refreshModelAvailability()
        try await Task.sleep(for: .seconds(1))
        try require(!live.canInfer && !live.isProcessing && live.title == "slow", "停用模型后未取消推理或草稿被覆盖")
        live.close()
        // Inference must use the currently edited draft, rather than the initial selection.
        controller.begin(text: "普通内容", source: "编辑后推理")
        controller.title = source
        controller.generate()
        try await settle(controller)
        try require(controller.hasDueDate && controller.dueDate == draft.dueDate, "推理没有使用当前编辑内容")
        controller.close()
        // Several immediate changes must reach disk in the same order as the UI.
        let first = store.add(title: "先添加", dueDate: nil)!
        store.updateMemo(id: first, title: "最终内容", dueDate: draft.dueDate)
        try require(await store.awaitPendingSave(), "连续写入失败")
        try require(await repo.items.last?.title == "最终内容", "旧快照覆盖了新数据")

    }

    @MainActor private static func showInteractivePreview() {
        let repository = MemoryRepository()
        let controller = MemoCaptureController(store: TaskStore(repository: repository),
            configuration: { MemoAIConfiguration(endpoint: "http://127.0.0.1:\(CommandLine.arguments[1])/chat/completions", model: "test-model", apiKey: "test-only") }, openSettings: {})
        UserDefaults.standard.set(true, forKey: "memo-ai-enabled")
        previewController = controller
        controller.begin(text: "明天下午三点前发出设计稿。\n保留原文，在下方选择级别和结束时间。", source: "布局验证")
        guard let window = NSApp.windows.first(where: { $0.title == "生成备忘录 · 布局验证" }) else { return }
        window.setContentSize(NSSize(width: 420, height: 300))
        previewCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
        print("交互预览已打开；关闭布局验证窗口将结束验证程序。")
    }

    @MainActor private static func captureView(_ view: NSView, file: String) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent(file))
        }
    }

    @MainActor static func captureWindow(named title: String, file: String) {
        guard let view = NSApp.windows.first(where: { $0.title == title })?.contentView else { return }
        captureView(view, file: file)
    }
}
