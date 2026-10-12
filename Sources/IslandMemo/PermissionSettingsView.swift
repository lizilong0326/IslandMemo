import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI
import UserNotifications

enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case microphone = "麦克风", camera = "摄像头", screen = "屏幕录制"
    case accessibility = "辅助功能", automation = "自动化", notifications = "通知"
    var id: Self { self }
    var pane: String {
        switch self {
        case .microphone: return "Privacy_Microphone"
        case .camera: return "Privacy_Camera"
        case .screen: return "Privacy_ScreenCapture"
        case .accessibility: return "Privacy_Accessibility"
        case .automation: return "Privacy_Automation"
        case .notifications: return "Notifications"
        }
    }
}

/// Read status on return to the app. Only an explicit button can request authorization.
struct PermissionSettingsView: View {
    let kinds: [PermissionKind]
    @State private var notificationStatus = "正在检查"
    @State private var refreshID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("系统权限").font(.caption.weight(.semibold)).foregroundStyle(IslandTheme.text3)
            ForEach(kinds) { kind in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.rawValue).foregroundStyle(IslandTheme.text1)
                        Text(status(kind)).font(.caption2).foregroundStyle(IslandTheme.text3)
                    }
                    Spacer(minLength: 4)
                    Button(actionTitle(kind)) { act(kind) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Text("从系统设置返回后自动复查；若系统提示需重启应用，请重启后重试。")
                .font(.caption2).foregroundStyle(IslandTheme.text4)
        }
        .padding(.vertical, 10)
        .task(id: refreshID) {
            guard kinds.contains(.notifications) else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: notificationStatus = "已允许"
            case .denied: notificationStatus = "未允许，任务与计时仍保留"
            case .notDetermined: notificationStatus = "尚未授权"
            @unknown default: notificationStatus = "状态未知"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshID += 1 }
    }

    private func status(_ kind: PermissionKind) -> String {
        switch kind {
        case .microphone: return captureStatus(.audio)
        case .camera: return captureStatus(.video)
        case .screen: return CGPreflightScreenCaptureAccess() ? "已允许" : "未允许；窗口信息可能不完整"
        case .accessibility: return AXIsProcessTrusted() ? "已允许" : "未允许；部分窗口与播放器控制不可用"
        case .automation: return "按播放器分别授权，执行播放控制时检查"
        case .notifications: return notificationStatus
        }
    }

    private func captureStatus(_ media: AVMediaType) -> String {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return "已允许"
        case .notDetermined: return "尚未授权"
        case .denied: return "未允许，请在系统设置中开启"
        case .restricted: return "受系统限制"
        @unknown default: return "状态未知"
        }
    }

    private func actionTitle(_ kind: PermissionKind) -> String {
        if kind == .microphone, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { return "申请权限" }
        if kind == .camera, AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { return "申请权限" }
        if kind == .notifications, notificationStatus == "尚未授权" { return "申请权限" }
        return "系统设置"
    }

    private func act(_ kind: PermissionKind) {
        if kind == .microphone, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in Task { @MainActor in refreshID += 1 } }
        } else if kind == .camera, AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { _ in Task { @MainActor in refreshID += 1 } }
        } else if kind == .notifications, notificationStatus == "尚未授权" {
            Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]); refreshID += 1 }
        } else {
            let address = kind == .notifications ? "x-apple.systempreferences:com.apple.preference.notifications" : "x-apple.systempreferences:com.apple.preference.security?\(kind.pane)"
            if let url = URL(string: address) { NSWorkspace.shared.open(url) }
        }
    }
}
