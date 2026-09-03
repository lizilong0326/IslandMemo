import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        Group {
            if store.entries.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 30)).foregroundStyle(.white.opacity(0.25))
                    Text("复制内容后会出现在这里")
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 10) {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(store.entries.enumerated()).filter { $0.offset.isMultiple(of: 2) }, id: \.element.id) { _, entry in
                                clipboardRow(entry)
                            }
                        }
                        LazyVStack(spacing: 10) {
                            ForEach(Array(store.entries.enumerated()).filter { !$0.offset.isMultiple(of: 2) }, id: \.element.id) { _, entry in
                                clipboardRow(entry)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func clipboardRow(_ entry: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            switch entry.kind {
            case .text:
                Text(entry.text ?? "")
                    .font(.callout)
                    .lineLimit(settings.clipboardPreviewLines)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            case .image:
                if let image = store.image(for: entry) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 130, alignment: .leading)
                }
            }

            HStack(spacing: 8) {
                Text(entry.copiedAt.formatted(.dateTime.year().month().day().hour().minute().second()))
                    .font(.caption2).foregroundStyle(.white.opacity(0.42))
                if settings.clipboardShowSource,
                   let source = entry.sourceApplication, !source.isEmpty {
                    Text("· \(source)")
                        .font(.caption2).foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }
                Spacer()
                Button { store.copy(entry) } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(11)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
