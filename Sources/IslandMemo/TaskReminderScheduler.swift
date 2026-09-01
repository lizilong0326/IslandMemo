import Foundation
import UserNotifications

@MainActor
final class TaskReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    private struct ReminderState: Codable {
        var dueTimestamp: TimeInterval
        var notifiedCheckpoints: Set<Int>
    }

    private struct ReminderCandidate {
        let key: String
        let title: String
        let dueDate: Date
    }

    private struct Checkpoint {
        let seconds: Int
        let label: String
    }

    private let checkpoints = [
        Checkpoint(seconds: 24 * 60 * 60, label: "24小时"),
        Checkpoint(seconds: 12 * 60 * 60, label: "12小时"),
        Checkpoint(seconds: 6 * 60 * 60, label: "6小时"),
        Checkpoint(seconds: 3 * 60 * 60, label: "3小时"),
        Checkpoint(seconds: 60 * 60, label: "1小时"),
        Checkpoint(seconds: 10 * 60, label: "10分钟")
    ]
    private let stateDefaultsKey = "task-reminder-checkpoints-v1"
    private let tasksProvider: @MainActor () -> [TaskItem]
    private var states: [String: ReminderState] = [:]
    private var timer: Timer?

    init(tasksProvider: @escaping @MainActor () -> [TaskItem]) {
        self.tasksProvider = tasksProvider
        super.init()
        loadState()
    }

    func start() {
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        timer?.invalidate()
        let timer = Timer(timeInterval: 10 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkReminders() }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Give the local task repository time to finish loading before establishing
        // the initial checkpoint state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.checkReminders()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func checkReminders(now: Date = .now) {
        let candidates = reminderCandidates()
        let activeKeys = Set(candidates.map(\.key))
        states = states.filter { activeKeys.contains($0.key) }
        var didChange = false

        for candidate in candidates {
            let remaining = candidate.dueDate.timeIntervalSince(now)
            guard remaining > 0 else { continue }

            if let state = states[candidate.key],
               abs(state.dueTimestamp - candidate.dueDate.timeIntervalSince1970) < 1 {
                let crossed = checkpoints.filter {
                    remaining <= Double($0.seconds)
                        && !state.notifiedCheckpoints.contains($0.seconds)
                }
                guard !crossed.isEmpty else { continue }

                // If sleep or shutdown skipped several checks, send only the nearest
                // useful reminder and mark the older crossed checkpoints as handled.
                let reminder = crossed.min { $0.seconds < $1.seconds }!
                states[candidate.key]?.notifiedCheckpoints.formUnion(crossed.map(\.seconds))
                sendNotification(for: candidate, checkpoint: reminder)
                didChange = true
            } else {
                // On first observation, checkpoints already in the past are recorded
                // without producing a burst of retrospective notifications.
                let alreadyCrossed = Set(checkpoints.filter {
                    remaining <= Double($0.seconds)
                }.map(\.seconds))
                states[candidate.key] = ReminderState(
                    dueTimestamp: candidate.dueDate.timeIntervalSince1970,
                    notifiedCheckpoints: alreadyCrossed
                )
                didChange = true
            }
        }

        if didChange { saveState() }
    }

    private func reminderCandidates() -> [ReminderCandidate] {
        tasksProvider().flatMap { task -> [ReminderCandidate] in
            guard task.deletedAt == nil, !task.isCompleted else { return [] }
            var candidates: [ReminderCandidate] = []
            if let dueDate = task.dueDate {
                candidates.append(ReminderCandidate(
                    key: "task-\(task.id.uuidString)",
                    title: task.title,
                    dueDate: dueDate
                ))
            }
            for subtask in task.subtasks ?? [] where !subtask.isCompleted {
                guard let dueDate = subtask.dueDate else { continue }
                candidates.append(ReminderCandidate(
                    key: "subtask-\(task.id.uuidString)-\(subtask.id.uuidString)",
                    title: subtask.title,
                    dueDate: dueDate
                ))
            }
            return candidates
        }
    }

    private func sendNotification(for candidate: ReminderCandidate, checkpoint: Checkpoint) {
        let content = UNMutableNotificationContent()
        content.title = "丫丫灵动"
        content.subtitle = candidate.title
        content.body = "有任务还剩\(checkpoint.label)就要超时了"
        content.sound = .default
        let identifier = "\(candidate.key)-\(Int(candidate.dueDate.timeIntervalSince1970))-\(checkpoint.seconds)"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        )
    }

    private func loadState() {
        guard let data = UserDefaults.standard.data(forKey: stateDefaultsKey) else { return }
        states = (try? JSONDecoder().decode([String: ReminderState].self, from: data)) ?? [:]
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(states) else { return }
        UserDefaults.standard.set(data, forKey: stateDefaultsKey)
    }
}
