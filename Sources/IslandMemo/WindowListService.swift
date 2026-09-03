import AppKit
import ApplicationServices
import Foundation

struct WindowInfo: Identifiable, Equatable, Sendable {
    let id: String
    let pid: pid_t
    let windowNumber: Int
    let appName: String
    let title: String
    let appPath: String
}

/// 当前窗口枚举与聚焦，移植自 TO-DO-Panel 的当前窗口模块。
/// 窗口标题需要「屏幕录制」权限；聚焦窗口需要「辅助功能」权限。
@MainActor
final class WindowListService: ObservableObject {
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var needsScreenRecording = false
    @Published private(set) var hasDetailedWindowTitles = true
    @Published private(set) var screenRecordingRestartRequired = false
    @Published private(set) var needsAccessibility = !AXIsProcessTrusted()

    func refresh() {
        let hasScreenRecordingAccess = CGPreflightScreenCaptureAccess()
        needsAccessibility = !AXIsProcessTrusted()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            windows = []
            needsScreenRecording = !hasScreenRecordingAccess
            return
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var rows: [WindowInfo] = []
        var seen = Set<String>()
        var detailedTitleCount = 0

        for entry in list {
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  pid != ownPID,
                  let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let appName = entry[kCGWindowOwnerName as String] as? String, !appName.isEmpty else { continue }
            guard let runningApp = NSRunningApplication(processIdentifier: pid),
                  runningApp.activationPolicy == .regular else { continue }
            let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat]
            let width = bounds?["Width"] ?? 0
            let height = bounds?["Height"] ?? 0
            guard width >= 100, height >= 100 else { continue }

            let title = (entry[kCGWindowName as String] as? String ?? "")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { detailedTitleCount += 1 }
            // 同进程同标题只保留最靠前的一条（CGWindowList 按前后序返回）。
            let windowNumber = entry[kCGWindowNumber as String] as? Int ?? 0
            let dedupeKey = title.isEmpty ? "\(pid)-\(windowNumber)" : "\(pid)-\(title)"
            guard seen.insert(dedupeKey).inserted else { continue }

            let appPath = runningApp.bundleURL?.path ?? ""
            rows.append(WindowInfo(
                id: "window-\(pid)-\(windowNumber)",
                pid: pid,
                windowNumber: windowNumber,
                appName: appName,
                title: title.isEmpty ? "应用窗口" : String(title.prefix(240)),
                appPath: appPath.hasSuffix(".app") ? appPath : ""
            ))
        }

        // macOS 新版本中，手动加入“录屏与系统录音”的应用偶尔会让预检结果
        // 落后于真实权限。实际已经拿到窗口标题时，以真实结果为准，不能提前拦截。
        hasDetailedWindowTitles = detailedTitleCount > 0
        needsScreenRecording = rows.isEmpty && !hasScreenRecordingAccess
        if !rows.isEmpty { screenRecordingRestartRequired = false }
        windows = rows
    }

    func icon(for window: WindowInfo) -> NSImage? {
        guard !window.appPath.isEmpty else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: window.appPath)
        icon.size = NSSize(width: 20, height: 20)
        return icon
    }

    /// 聚焦窗口：优先 AXRaise 精确到窗口，失败时退化为激活整个应用。
    @discardableResult
    func focus(_ window: WindowInfo) -> Bool {
        var raised = false
        if AXIsProcessTrusted() {
            let appElement = AXUIElementCreateApplication(window.pid)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
               let axWindows = value as? [AXUIElement] {
                for axWindow in axWindows {
                    var titleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
                    let axTitle = (titleValue as? String ?? "")
                    if axTitle == window.title || window.title.hasPrefix(axTitle) || axTitle.hasPrefix(window.title) {
                        raised = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString) == .success
                        break
                    }
                }
            }
        }
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return raised }
        let activated = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        return raised || activated
    }

    func requestScreenRecording() {
        let granted = CGRequestScreenCaptureAccess()
        needsScreenRecording = !granted
        screenRecordingRestartRequired = granted
        if granted {
            refresh()
        } else {
            Self.openScreenRecordingSettings()
        }
    }

    static func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    static func promptAccessibilityIfNeeded() {
        // kAXTrustedCheckOptionPrompt 的值就是该字符串；直接写字面量避开 Swift 6 并发检查。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func requestAccessibility() {
        Self.promptAccessibilityIfNeeded()
        needsAccessibility = !AXIsProcessTrusted()
    }
}
