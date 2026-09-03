import SwiftUI

/// 录制页：录音即创建实时记录，同步显示状态与转写。
/// 对应 TO-DO-Panel 的录制模块。
struct RecordingsView: View {
    @ObservedObject var store: RecordingStore
    @State private var expandedID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            recordControl

            if store.recordings.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "waveform")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.25))
                    Text("录音会保存在这里")
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.recordings) { entry in
                            recordingRow(entry)
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

    private var recordControl: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { store.toggleRecording() } label: {
                    Image(systemName: store.state == .idle ? "record.circle" : "stop.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(store.state == .idle ? .red : .white)
                }
                .buttonStyle(.plain)
                .help(store.state == .idle ? "开始录音" : "停止录音")

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.state == .idle ? "点击开始录音" : "录音中 \(store.elapsedText)")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                    if store.state != .idle {
                        // 电平条
                        GeometryReader { geometry in
                            Capsule()
                                .fill(.white.opacity(0.12))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(.green)
                                        .frame(width: geometry.size.width * CGFloat(min(store.audioLevel * 3, 1)))
                                }
                        }
                        .frame(height: 5)
                    } else {
                        Text(TranscriptionConfig.load().apiKey != nil ? "已配置实时转写" : "未配置转写 API（设置页可配置）")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                Spacer()
            }

            if store.state != .idle, !store.liveTranscript.isEmpty || !store.liveInterim.isEmpty {
                Text(store.liveTranscript + store.liveInterim)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
            }
        }
        .tileStyle()
    }

    private func recordingRow(_ entry: RecordingEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { store.togglePlayback(entry) } label: {
                    Image(systemName: store.playingID == entry.id ? "stop.circle.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help(store.playingID == entry.id ? "停止" : "播放")

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.callout)
                    Text("\(durationText(entry.durationMs)) · \(entry.createdAt.formatted(.dateTime.month().day().hour().minute()))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer(minLength: 8)

                if !entry.transcript.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            expandedID = expandedID == entry.id ? nil : entry.id
                        }
                    } label: {
                        Image(systemName: expandedID == entry.id ? "chevron.up" : "doc.text")
                    }
                    .buttonStyle(.borderless)
                    .help("查看转写")
                }
                Button { store.reveal(entry) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中显示")
                Button(role: .destructive) { store.delete(entry) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除录音")
            }

            if expandedID == entry.id, !entry.transcript.isEmpty {
                Text(entry.transcript)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 34)
            }
        }
        .listRowStyle()
    }

    private func durationText(_ ms: Int) -> String {
        let total = max(0, ms / 1000)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
