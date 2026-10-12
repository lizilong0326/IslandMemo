import AppKit
import SwiftUI

extension Notification.Name {
    static let openMemoAISettings = Notification.Name("IslandMemo.openMemoAISettings")
    static let memoAIConfigurationChanged = Notification.Name("IslandMemo.memoAIConfigurationChanged")
}

@MainActor
final class MemoAISettingsDraft: ObservableObject {
    @Published var endpoint = UserDefaults.standard.string(forKey: "memo-ai-endpoint") ?? ""
    @Published var model = UserDefaults.standard.string(forKey: "memo-ai-model") ?? ""
    @Published var keyInput = ""
    @Published var status = ""
    private var savedEndpoint = UserDefaults.standard.string(forKey: "memo-ai-endpoint") ?? ""
    private var savedModel = UserDefaults.standard.string(forKey: "memo-ai-model") ?? ""
    var isDirty: Bool { endpoint != savedEndpoint || model != savedModel || !keyInput.isEmpty }

    func discard() {
        endpoint = savedEndpoint
        model = savedModel
        keyInput = ""
        status = "已还原为上次保存的配置"
    }

    func save() {
        let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let credentials = MemoAICredentialStore()
            let resolvedKey = key.isEmpty ? (try credentials.read() ?? "") : key
            _ = try MemoAIConfiguration(endpoint: endpoint, model: model, apiKey: resolvedKey).validatedURL()
            try credentials.save(resolvedKey)
            UserDefaults.standard.set(endpoint, forKey: "memo-ai-endpoint")
            UserDefaults.standard.set(model, forKey: "memo-ai-model")
            self.endpoint = endpoint
            self.model = model
            savedEndpoint = endpoint
            savedModel = model
            keyInput = ""
            status = "配置已保存，连接尚未验证；请从复制记录点击推理验证。"
            NotificationCenter.default.post(name: .memoAIConfigurationChanged, object: nil)
        } catch { status = "保存失败：\(error.localizedDescription)；输入已保留。" }
    }
}

struct MemoAISettingsView: View {
    @ObservedObject var draft: MemoAISettingsDraft
    @AppStorage("memo-ai-enabled") private var useModel = !(UserDefaults.standard.string(forKey: "memo-ai-model") ?? "").isEmpty

    init(draft: MemoAISettingsDraft = MemoAISettingsDraft()) { self.draft = draft }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("复制内容转备忘录", systemImage: "note.text.badge.plus").font(.headline)
            Text("从复制记录添加备忘录，可编辑原文；配置模型后可手动推理并回填。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("使用大模型提炼（可选）", isOn: $useModel)
                .toggleStyle(.switch).controlSize(.small)
                .onChange(of: useModel) { _ in
                    NotificationCenter.default.post(name: .memoAIConfigurationChanged, object: nil)
                }
            Text(useModel ? "点击「推理」才会联网；添加前仍可人工修改和确认。" : "直接添加原文，不识别或改写时间。")
                .font(.caption).foregroundStyle(.secondary)
            if useModel {
                TextField("完整地址：https://…/v1/chat/completions", text: $draft.endpoint)
                TextField("模型名称", text: $draft.model)
                SecureField("API Key（留空保留已存密钥）", text: $draft.keyInput)
                Text("支持 Chat Completions 兼容接口；密钥保存在本机配置文件中。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if useModel || draft.isDirty {
                HStack {
                    Button("保存模型配置") { draft.save() }
                    Button("还原未保存修改") { draft.discard() }.disabled(!draft.isDirty)
                }
                Text(draft.status.hasPrefix("保存失败") ? draft.status : (draft.isDirty ? "有未保存修改；切换设置页会保留草稿，退出应用后丢弃。" : (draft.status.isEmpty ? "连接配置需要点击保存；保存成功不代表连接可用。" : draft.status)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12).textFieldStyle(.roundedBorder)
    }
}
