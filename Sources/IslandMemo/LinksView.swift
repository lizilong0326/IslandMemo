import SwiftUI

/// 链接页：保存公开网址，后台补全标题与图标，按规则自动分组。
/// 对应 TO-DO-Panel 的链接模块。
struct LinksView: View {
    @ObservedObject var store: LinksStore
    @ObservedObject var settings: AppSettingsStore
    @State private var newURL = ""
    @State private var isHoveredID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link.circle.fill").foregroundStyle(.blue)
                TextField("粘贴网址，回车保存", text: $newURL)
                    .textFieldStyle(.plain)
                    .onSubmit(addLink)
                Button(action: addLink) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .clipShape(Circle())
                .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("保存链接")
            }
            .inputStyle()

            if store.groups.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "link")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("保存的链接会出现在这里")
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(store.groups) { group in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(group.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.46))
                                    .padding(.leading, 4)
                                ForEach(group.links) { link in
                                    linkRow(link)
                                }
                            }
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

    private func linkRow(_ link: SavedLink) -> some View {
        HStack(spacing: 10) {
            if let data = link.faviconData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "globe")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .font(.callout)
                    .lineLimit(1)
                if settings.linksShowURL {
                    Text(link.url)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if isHoveredID == link.id {
                Button { store.open(link) } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("在浏览器打开")
                Button(role: .destructive) { store.delete(link) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除链接")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: IslandTheme.radiusSquircle)
            .fill(isHoveredID == link.id ? IslandTheme.surface2 : IslandTheme.surface1))
        .contentShape(RoundedRectangle(cornerRadius: IslandTheme.radiusSquircle))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHoveredID = hovering ? link.id : nil }
        }
        .onTapGesture { store.open(link) }
    }

    private func addLink() {
        store.add(rawURL: newURL)
        newURL = ""
    }
}
