import AppKit
import SwiftUI

extension Notification.Name {
    static let openMemoAISettings = Notification.Name("IslandMemo.openMemoAISettings")
    static let memoAIConfigurationChanged = Notification.Name("IslandMemo.memoAIConfigurationChanged")
}

struct MemoAISettingsView: View {
    @State private var endpoint = UserDefaults.standard.string(forKey: "memo-ai-endpoint") ?? ""
    @State private var model = UserDefaults.standard.string(forKey: "memo-ai-model") ?? ""
    @State private var keyInput = ""
    @State private var status = ""
    @AppStorage("memo-ai-enabled") private var useModel = !(UserDefaults.standard.string(forKey: "memo-ai-model") ?? "").isEmpty

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("复制内容转备忘录", systemImage: "note.text.badge.plus").font(.headline)
            Text("从复制记录点击添加备忘录，可编辑原文；配置模型后可手动推理并回填。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("使用大模型提炼（可选）", isOn: $useModel)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: useModel) { _ in
                    NotificationCenter.default.post(name: .memoAIConfigurationChanged, object: nil)
                }
            Text(useModel ? "完成配置后，在添加弹窗点击「推理」才会提炼任务和截止时间；也可直接保存当前内容。" : "当前直接添加原文，不联网，不识别或改写时间。")
                .font(.caption).foregroundStyle(.secondary)
            if useModel {
                TextField("完整地址：https://…/v1/chat/completions", text: $endpoint)
                TextField("模型名称", text: $model)
                SecureField("API Key（留空保留本地已存密钥）", text: $keyInput)
                Text("旧版仅存在钥匙串中的密钥，请重新粘贴并保存一次。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("支持 Chat Completions 兼容接口。仅在弹窗点击「推理」时发送当前内容；API Key 保存在本机配置文件中。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("保存模型配置") { saveConfiguration() }
                    Spacer()
                }
                Text(status.isEmpty ? "模型配置需点击保存，其他开关自动保存。" : status)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .textFieldStyle(.roundedBorder)
    }

    private func saveConfiguration() {
        let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let credentials = MemoAICredentialStore()
            let resolvedKey = key.isEmpty ? (try credentials.read() ?? "") : key
            let configuration = MemoAIConfiguration(endpoint: endpoint, model: model, apiKey: resolvedKey)
            _ = try configuration.validatedURL()
            try credentials.save(resolvedKey)
            UserDefaults.standard.set(endpoint, forKey: "memo-ai-endpoint")
            UserDefaults.standard.set(model, forKey: "memo-ai-model")
            keyInput = ""
            NotificationCenter.default.post(name: .memoAIConfigurationChanged, object: nil)
            status = "已保存，可从复制记录生成一条备忘录进行验证。"
        } catch { status = error.localizedDescription }
    }
}
