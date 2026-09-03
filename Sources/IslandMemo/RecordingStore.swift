import AppKit
import AVFoundation
import Foundation

struct RecordingEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var createdAt: Date
    var durationMs: Int
    var audioFileName: String
    var transcript: String

    init(id: UUID = UUID(), title: String, createdAt: Date = .now, durationMs: Int = 0, audioFileName: String, transcript: String = "") {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationMs = durationMs
        self.audioFileName = audioFileName
        self.transcript = transcript
    }
}

/// 百炼 qwen3-asr-flash-realtime 配置。
/// API Key 存 Keychain，其余存 UserDefaults。协议细节移植自 TO-DO-Panel main.js。
struct TranscriptionConfig: Equatable, Sendable {
    var region: String // "beijing" | "singapore"
    var workspaceId: String

    private static let regionKey = "transcription-region"
    private static let workspaceKey = "transcription-workspace-id"
    static let apiKeychainKey = "dashscope-api-key"

    static func load() -> TranscriptionConfig {
        let defaults = UserDefaults.standard
        return TranscriptionConfig(
            region: defaults.string(forKey: regionKey) == "singapore" ? "singapore" : "beijing",
            workspaceId: defaults.string(forKey: workspaceKey) ?? ""
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(region, forKey: Self.regionKey)
        defaults.set(workspaceId, forKey: Self.workspaceKey)
    }

    var apiKey: String? {
        let key = KeychainHelper.read(key: Self.apiKeychainKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false ? key : nil
    }

    var websocketURL: URL? {
        let host: String
        if !workspaceId.isEmpty {
            host = region == "singapore"
                ? "\(workspaceId).ap-southeast-1.maas.aliyuncs.com"
                : "\(workspaceId).cn-beijing.maas.aliyuncs.com"
        } else {
            host = region == "singapore" ? "dashscope-intl.aliyuncs.com" : "dashscope.aliyuncs.com"
        }
        return URL(string: "wss://\(host)/api-ws/v1/realtime?model=qwen3-asr-flash-realtime&heartbeat=true")
    }
}

/// 实时转写会话：OpenAI realtime 兼容协议 over WebSocket。
actor TranscriptionSession {
    enum Event: Sendable {
        case connected
        case transcript(final: String, interim: String)
        case failure(String)
        case finished(final: String)
    }

    private var task: URLSessionWebSocketTask?
    private var finalSegments: [String] = []
    private var interim = ""
    private var closed = false
    nonisolated let eventStream: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    init() {
        var captured: AsyncStream<Event>.Continuation!
        eventStream = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start(config: TranscriptionConfig) async throws {
        guard let apiKey = config.apiKey, let url = config.websocketURL else {
            throw NSError(domain: "Transcription", code: 1, userInfo: [NSLocalizedDescriptionKey: "未配置 API Key"])
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        if !config.workspaceId.isEmpty {
            request.setValue(config.workspaceId, forHTTPHeaderField: "X-DashScope-WorkSpace")
        }
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()

        let update: [String: Any] = [
            "event_id": Self.eventID(),
            "type": "session.update",
            "session": [
                "input_audio_format": "pcm",
                "sample_rate": 16000,
                "input_audio_transcription": ["language": "zh"],
                "turn_detection": ["type": "server_vad", "threshold": 0, "silence_duration_ms": 400],
            ],
        ]
        try await task.send(.string(Self.jsonString(update)))
        continuation.yield(.connected)
        listen()
    }

    func send(pcm16LE data: Data) async {
        guard !closed, !data.isEmpty, data.count <= 512 * 1024 else { return }
        let message: [String: Any] = [
            "event_id": Self.eventID(),
            "type": "input_audio_buffer.append",
            "audio": data.base64EncodedString(),
        ]
        try? await task?.send(.string(Self.jsonString(message)))
    }

    func finish() async {
        guard !closed else { return }
        let message: [String: Any] = ["event_id": Self.eventID(), "type": "session.finish"]
        try? await task?.send(.string(Self.jsonString(message)))
        // Give the server a moment to flush the last transcript, then close locally.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        closeLocally()
    }

    func cancel() {
        closeLocally()
    }

    private func closeLocally() {
        guard !closed else { return }
        closed = true
        task?.cancel(with: .normalClosure, reason: nil)
        let final = finalSegments.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        continuation.yield(.finished(final: final))
        continuation.finish()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { await self.handle(result) }
        }
    }

    private func handle(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .failure(let error):
            guard !closed else { return }
            continuation.yield(.failure(error.localizedDescription))
            closeLocally()
        case .success(let message):
            guard case .string(let raw) = message,
                  let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                if !closed { listen() }
                return
            }
            switch type {
            case "session.created", "session.updated":
                break
            case "conversation.item.input_audio_transcription.text":
                let text = (object["text"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let stash = (object["stash"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                interim = text + stash
                continuation.yield(.transcript(
                    final: finalSegments.joined(separator: " ").trimmingCharacters(in: .whitespaces),
                    interim: interim
                ))
            case "conversation.item.input_audio_transcription.completed":
                let transcript = (object["transcript"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                if !transcript.isEmpty, finalSegments.last != transcript {
                    finalSegments.append(transcript)
                }
                interim = ""
                continuation.yield(.transcript(
                    final: finalSegments.joined(separator: " ").trimmingCharacters(in: .whitespaces),
                    interim: ""
                ))
            case "error", "conversation.item.input_audio_transcription.failed":
                let detail = (object["error"] as? [String: Any])?["message"] as? String ?? "实时转写服务返回错误"
                continuation.yield(.failure(detail))
            case "session.finished":
                closeLocally()
                return
            default:
                break
            }
            if !closed { listen() }
        }
    }

    private static func eventID() -> String {
        "event_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    private static func jsonString(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// 录音资料库：AVAudioEngine 采集 → 16kHz 单声道 WAV 写盘；
/// 配置了 API Key 时同步把 PCM16 流送进实时转写。
/// 对应 TO-DO-Panel 的录制模块 + 百炼实时转写。
@MainActor
final class RecordingStore: ObservableObject {
    enum State: Equatable {
        case idle
        case recording(startedAt: Date)
    }

    @Published private(set) var recordings: [RecordingEntry] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var liveTranscript = ""
    @Published private(set) var liveInterim = ""
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var playingID: UUID?
    @Published var errorMessage: String?
    @Published var transcriptionEnabled: Bool {
        didSet { UserDefaults.standard.set(transcriptionEnabled, forKey: "recording-transcription-enabled") }
    }

    private let recordingsDir: URL
    private let metadataURL: URL
    private var engine: AVAudioEngine?
    private var wavWriter: WAVFileWriter?
    private var session: TranscriptionSession?
    private var sessionTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var meterTimer: Timer?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IslandMemo", isDirectory: true)
        recordingsDir = base.appendingPathComponent("Recordings", isDirectory: true)
        metadataURL = base.appendingPathComponent("recordings.json")
        transcriptionEnabled = UserDefaults.standard.object(forKey: "recording-transcription-enabled") as? Bool ?? false
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        load()
    }

    var elapsedText: String {
        guard case .recording(let startedAt) = state else { return "00:00" }
        let total = max(0, Int(Date().timeIntervalSince(startedAt)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// 供音频 tap 线程回写电平（audioLevel 对外的 setter 保持私有）。
    func updateAudioLevel(_ level: Float) {
        audioLevel = level
    }

    func toggleRecording() {
        switch state {
        case .idle: startRecording()
        case .recording: stopRecording()
        }
    }

    func startRecording() {
        guard state == .idle else { return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                guard granted else {
                    self.errorMessage = "没有麦克风权限，请在系统设置 → 隐私与安全性 → 麦克风 中允许"
                    return
                }
                self.beginCapture()
            }
        }
    }

    private func beginCapture() {
        let id = UUID()
        let fileName = "\(id.uuidString).wav"
        let fileURL = recordingsDir.appendingPathComponent(fileName)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)
        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            errorMessage = "没有可用的麦克风设备"
            return
        }

        guard let writer = WAVFileWriter(url: fileURL) else {
            errorMessage = "无法创建录音文件"
            return
        }
        wavWriter = writer

        let wantsTranscription = transcriptionEnabled && TranscriptionConfig.load().apiKey != nil
        if wantsTranscription {
            let session = TranscriptionSession()
            self.session = session
            liveTranscript = ""
            liveInterim = ""
            sessionTask = Task { [weak self] in
                do {
                    try await session.start(config: TranscriptionConfig.load())
                } catch {
                    await MainActor.run { self?.errorMessage = "转写连接失败：\(error.localizedDescription)" }
                    return
                }
                for await event in session.eventStream {
                    await MainActor.run {
                        guard let self else { return }
                        switch event {
                        case .connected:
                            break
                        case .transcript(let final, let interim):
                            self.liveTranscript = final
                            self.liveInterim = interim
                        case .failure(let message):
                            self.errorMessage = "转写失败：\(message)"
                        case .finished:
                            break
                        }
                    }
                }
            }
        }

        let processor = TapProcessor(writer: writer, session: self.session, store: self)
        input.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: nativeFormat,
            block: Self.makeTapBlock(processor: processor, format: nativeFormat)
        )

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = "录音启动失败：\(error.localizedDescription)"
            return
        }
        self.engine = engine
        state = .recording(startedAt: .now)
        startMeterRefresh()
    }

    /// 在 nonisolated 上下文中生成 tap 闭包：闭包若在 @MainActor 上下文里创建会继承
    /// MainActor 隔离，AVAudioEngine 在音频实时线程回调时触发 swift_task_checkIsolatedSwift
    /// 断言直接崩溃（已在 19:59 的崩溃报告中确认）。
    private nonisolated static func makeTapBlock(
        processor: TapProcessor,
        format: AVAudioFormat
    ) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            processor.process(buffer, format: format)
        }
    }

    func stopRecording() {
        guard case .recording(let startedAt) = state else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        stopMeterRefresh()
        audioLevel = 0

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let id = UUID(uuidString: wavWriter?.url.deletingPathExtension().lastPathComponent ?? "") ?? UUID()
        wavWriter?.finalize()
        let fileName = wavWriter?.url.lastPathComponent ?? ""
        wavWriter = nil

        let session = self.session
        self.session = nil
        state = .idle

        let finalizeEntry: (String) -> Void = { [weak self] transcript in
            guard let self else { return }
            let title = Self.defaultTitle(for: startedAt)
            self.recordings.insert(RecordingEntry(
                id: id,
                title: title,
                createdAt: startedAt,
                durationMs: durationMs,
                audioFileName: fileName,
                transcript: transcript
            ), at: 0)
            self.liveTranscript = ""
            self.liveInterim = ""
            self.persist()
        }

        if let session {
            sessionTask = Task {
                await session.finish()
                var final = ""
                for await event in session.eventStream {
                    if case .finished(let text) = event { final = text }
                }
                await MainActor.run { finalizeEntry(final) }
            }
        } else {
            finalizeEntry("")
        }
    }

    // MARK: - Playback & management

    func togglePlayback(_ entry: RecordingEntry) {
        if playingID == entry.id {
            player?.stop()
            player = nil
            playingID = nil
            return
        }
        let url = recordingsDir.appendingPathComponent(entry.audioFileName)
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            errorMessage = "无法播放该录音"
            return
        }
        self.player = player
        playingID = entry.id
        player.play()
        // Reset state when playback finishes.
        Task { [weak self, weak player] in
            while let player, player.isPlaying {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            await MainActor.run {
                if self?.playingID == entry.id {
                    self?.playingID = nil
                    self?.player = nil
                }
            }
        }
    }

    func delete(_ entry: RecordingEntry) {
        if playingID == entry.id { togglePlayback(entry) }
        try? FileManager.default.removeItem(at: recordingsDir.appendingPathComponent(entry.audioFileName))
        recordings.removeAll { $0.id == entry.id }
        persist()
    }

    func reveal(_ entry: RecordingEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([recordingsDir.appendingPathComponent(entry.audioFileName)])
    }

    func audioURL(for entry: RecordingEntry) -> URL {
        recordingsDir.appendingPathComponent(entry.audioFileName)
    }

    private func startMeterRefresh() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMeterRefresh() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = (try? decoder.decode([RecordingEntry].self, from: data)) ?? []
        recordings = rows.filter {
            FileManager.default.fileExists(atPath: recordingsDir.appendingPathComponent($0.audioFileName).path)
        }
    }

    private func persist() {
        let snapshot = recordings
        let url = metadataURL
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// 音频 tap 处理器：在音频实时线程上运行，只做线程安全的写盘/转发，
/// UI 状态（电平）通过 Task 跳回 MainActor。
private final class TapProcessor: @unchecked Sendable {
    let writer: WAVFileWriter
    let session: TranscriptionSession?
    weak var store: RecordingStore?

    init(writer: WAVFileWriter, session: TranscriptionSession?, store: RecordingStore) {
        self.writer = writer
        self.session = session
        self.store = store
    }

    func process(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        // Mix down to mono Float32.
        var mono = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            var sum: Float = 0
            for channel in 0..<channels {
                sum += channelData[channel][frame]
            }
            mono[frame] = sum / Float(channels)
        }
        let pcm16 = PCMResampler.resampleTo16k(mono: mono, inputRate: format.sampleRate)
        let data = Data(bytes: pcm16, count: pcm16.count * 2)
        writer.append(data)
        let level = PCMResampler.rms(mono)
        Task { @MainActor [weak store] in store?.updateAudioLevel(level) }
        if let session {
            Task { await session.send(pcm16LE: data) }
        }
    }
}

/// Float32 → 16kHz PCM16 重采样，移植自 TO-DO-Panel domain.js resampleFloat32ToPcm16。
enum PCMResampler {
    static func resampleTo16k(mono: [Float], inputRate: Double, outputRate: Double = 16000) -> [Int16] {
        guard !mono.isEmpty else { return [] }
        let ratio = inputRate / outputRate
        let outputLength = max(1, Int((Double(mono.count) / ratio).rounded()))
        var output = [Int16](repeating: 0, count: outputLength)
        for index in 0..<outputLength {
            let start = Int(Double(index) * ratio)
            let end = max(start + 1, min(mono.count, Int(Double(index + 1) * ratio)))
            var sum: Float = 0
            for sourceIndex in start..<end { sum += mono[sourceIndex] }
            let sample = max(-1, min(1, sum / Float(end - start)))
            output[index] = sample < 0 ? Int16(sample * 0x8000) : Int16(sample * 0x7fff)
        }
        return output
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumSquares: Float = 0
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            sumSquares += clamped * clamped
        }
        return (sumSquares / Float(samples.count)).squareRoot()
    }
}

/// 最小 WAV（PCM16 LE 单声道 16kHz）写入器。
final class WAVFileWriter: @unchecked Sendable {
    let url: URL
    private let handle: FileHandle
    private var dataLength: UInt32 = 0
    private let lock = NSLock()

    init?(url: URL) {
        self.url = url
        let header = WAVFileWriter.buildHeader(dataLength: 0)
        guard FileManager.default.createFile(atPath: url.path, contents: header),
              let handle = try? FileHandle(forWritingTo: url) else { return nil }
        self.handle = handle
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        dataLength += UInt32(data.count)
    }

    func finalize() {
        lock.lock()
        defer { lock.unlock() }
        let header = WAVFileWriter.buildHeader(dataLength: dataLength)
        try? handle.seek(toOffset: 0)
        try? handle.write(contentsOf: header)
        try? handle.close()
    }

    private static func buildHeader(dataLength: UInt32) -> Data {
        let sampleRate: UInt32 = 16000
        let byteRate = sampleRate * 2
        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        header.appendLE(36 + dataLength)
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt␣
        header.appendLE(UInt32(16))          // fmt chunk size
        header.appendLE(UInt16(1))           // PCM
        header.appendLE(UInt16(1))           // mono
        header.appendLE(sampleRate)
        header.appendLE(byteRate)
        header.appendLE(UInt16(2))           // block align
        header.appendLE(UInt16(16))          // bits per sample
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        header.appendLE(dataLength)
        return header
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
