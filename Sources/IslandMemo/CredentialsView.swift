import SwiftUI

/// 密钥页：账号、密码和 API Key 的安全存储（密码本体只进 Keychain）。
/// 对应 TO-DO-Panel 的密钥模块。
struct CredentialsView: View {
    @ObservedObject var store: CredentialsStore
    @ObservedObject var settings: AppSettingsStore
    @State private var service = ""
    @State private var account = ""
    @State private var password = ""
    @State private var query = ""
    @State private var showsAddForm = false
    @State private var revealedID: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.5))
                TextField("搜索服务或账号", text: $query)
                    .textFieldStyle(.plain)
                Button { withAnimation(.easeOut(duration: 0.15)) { showsAddForm.toggle() } } label: {
                    Image(systemName: showsAddForm ? "xmark" : "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .clipShape(Circle())
                .help("添加密钥")
            }
            .inputStyle()

            if showsAddForm { addForm }

            let rows = store.filtered(query: query)
            if rows.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "key")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.25))
                    Text(query.isEmpty ? "保存的密钥会出现在这里" : "没有匹配的密钥")
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(rows) { credential in
                            credentialRow(credential)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("提示", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var addForm: some View {
        VStack(spacing: 9) {
            TextField("服务（如 GitHub）", text: $service)
                .textFieldStyle(.plain)
            Divider().overlay(.white.opacity(0.1))
            TextField("账号", text: $account)
                .textFieldStyle(.plain)
            Divider().overlay(.white.opacity(0.1))
            SecureField("密码 / API Key", text: $password)
                .textFieldStyle(.plain)
            HStack {
                Spacer()
                Button("保存") {
                    store.add(service: service, account: account, password: password)
                    service = ""
                    account = ""
                    password = ""
                    showsAddForm = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(service.trimmingCharacters(in: .whitespaces).isEmpty
                          || account.trimmingCharacters(in: .whitespaces).isEmpty
                          || password.isEmpty)
            }
        }
        .font(.callout)
        .padding(12)
        .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: IslandTheme.radiusTile))
    }

    private func credentialRow(_ credential: Credential) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .foregroundStyle(.yellow.opacity(0.8))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(credential.service)
                    .font(.callout.weight(.medium))
                Text(credential.account)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            Button { store.copyAccount(credential) } label: {
                Image(systemName: "person.crop.circle")
            }
            .buttonStyle(.borderless)
            .help("复制账号")

            Button { store.copyPassword(credential) } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制密码")

            if settings.credentialsAllowReveal {
                Button {
                    revealedID = revealedID == credential.id ? nil : credential.id
                } label: {
                    Image(systemName: revealedID == credential.id ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help("显示/隐藏密码")
            }

            Button(role: .destructive) { store.delete(credential) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .listRowStyle()
        .overlay(alignment: .bottom) {
            if settings.credentialsAllowReveal,
               revealedID == credential.id, let text = store.password(for: credential) {
                Text(text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.75))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                    .offset(y: 30)
                    .zIndex(1)
            }
        }
    }
}
