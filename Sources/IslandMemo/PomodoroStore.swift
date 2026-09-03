import Foundation
import UserNotifications

/// 番茄钟：面板内计时，结束后发系统通知。
/// Ported from TO-DO-Panel app.js 番茄钟模块（隐藏组件后仍继续计时和提醒的语义保留：
/// 计时状态由本 Store 持有，与界面是否可见无关）。
@MainActor
final class PomodoroStore: ObservableObject {
    enum Phase: String, Codable, Sendable {
        case idle
        case running
        case paused
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remainingSeconds: Int = 0
    @Published var durationMinutes: Int {
        didSet { UserDefaults.standard.set(durationMinutes, forKey: Self.durationDefaultsKey) }
    }

    private static let durationDefaultsKey = "pomodoro-duration-minutes"
    private var endDate: Date?
    private var timer: Timer?

    init() {
        let saved = UserDefaults.standard.integer(forKey: Self.durationDefaultsKey)
        durationMinutes = saved > 0 ? min(saved, 180) : 25
        remainingSeconds = durationMinutes * 60
    }

    var displayText: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var progress: Double {
        let total = Double(max(durationMinutes * 60, 1))
        return 1 - Double(remainingSeconds) / total
    }

    func start() {
        switch phase {
        case .idle:
            remainingSeconds = durationMinutes * 60
            endDate = .now.addingTimeInterval(TimeInterval(remainingSeconds))
        case .paused:
            endDate = .now.addingTimeInterval(TimeInterval(remainingSeconds))
        case .running:
            return
        }
        phase = .running
        startTimer()
    }

    func pause() {
        guard phase == .running else { return }
        tick()
        phase = .paused
        stopTimer()
    }

    func reset() {
        phase = .idle
        stopTimer()
        remainingSeconds = durationMinutes * 60
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard phase == .running, let endDate else { return }
        let remaining = Int(endDate.timeIntervalSinceNow.rounded())
        if remaining > 0 {
            remainingSeconds = remaining
            return
        }
        phase = .idle
        stopTimer()
        remainingSeconds = durationMinutes * 60
        sendCompletionNotification()
    }

    private func sendCompletionNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "丫丫灵动"
        content.subtitle = "番茄钟"
        content.body = "\(durationMinutes) 分钟专注结束，休息一下吧"
        content.sound = .default
        center.add(UNNotificationRequest(
            identifier: "pomodoro-\(UUID().uuidString)",
            content: content,
            trigger: nil
        ))
    }
}
