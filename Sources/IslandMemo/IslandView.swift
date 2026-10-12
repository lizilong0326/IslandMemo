import SwiftUI

private enum AppTab: String, CaseIterable, Identifiable {
    case memo = "备忘录"
    case clipboard = "复制记录"
    case home = "首页"
    case links = "链接"
    case recordings = "录制"
    case credentials = "密钥"
    case music = "音乐"
    case pomodoro = "番茄钟"
    case recorder = "快速录音"
    case windows = "当前窗口"
    case mirror = "镜子"
    case note = "随笔记"
    case commands = "常用指令"
    case clock = "时钟"
    case calendar = "日历"
    case completions = "AI 任务"
    case settings = "设置"
    var id: Self { self }

    var systemImage: String {
        switch self {
        case .memo: return "checklist"
        case .clipboard: return "doc.on.clipboard"
        case .home: return "square.grid.2x2"
        case .links: return "link"
        case .recordings: return "waveform"
        case .credentials: return "key"
        case .music: return "music.note"
        case .pomodoro: return "timer"
        case .recorder: return "record.circle"
        case .windows: return "macwindow"
        case .mirror: return "camera"
        case .note: return "pencil.line"
        case .commands: return "command"
        case .clock: return "clock"
        case .calendar: return "calendar"
        case .completions: return "sparkles"
        case .settings: return "gearshape"
        }
    }

    var feature: AppSettingsStore.Feature {
        switch self {
        case .memo: return .memo
        case .clipboard: return .clipboard
        case .home: return .home
        case .links: return .links
        case .recordings: return .recordings
        case .credentials: return .credentials
        case .music: return .music
        case .pomodoro: return .pomodoro
        case .recorder: return .recorder
        case .windows: return .windows
        case .mirror: return .mirror
        case .note: return .note
        case .commands: return .commands
        case .clock: return .clock
        case .calendar: return .calendar
        case .completions: return .completions
        case .settings: return .settings
        }
    }

    init(feature: AppSettingsStore.Feature) {
        switch feature {
        case .memo: self = .memo
        case .clipboard: self = .clipboard
        case .home: self = .home
        case .links: self = .links
        case .recordings: self = .recordings
        case .credentials: self = .credentials
        case .music: self = .music
        case .pomodoro: self = .pomodoro
        case .recorder: self = .recorder
        case .windows: self = .windows
        case .mirror: self = .mirror
        case .note: self = .note
        case .commands: self = .commands
        case .clock: self = .clock
        case .calendar: self = .calendar
        case .completions: self = .completions
        case .settings: self = .settings
        }
    }
}

struct IslandView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var clipboardStore: ClipboardStore
    @ObservedObject var linksStore: LinksStore
    @ObservedObject var commandsStore: CommandsStore
    @ObservedObject var pomodoroStore: PomodoroStore
    @ObservedObject var recordingsStore: RecordingStore
    @ObservedObject var credentialsStore: CredentialsStore
    @ObservedObject var musicService: MusicService
    @ObservedObject var windowListService: WindowListService
    @ObservedObject var notifyServer: AgentNotifyServer
    @ObservedObject var codexStatusStore: CodexStatusStore
    @ObservedObject var appSettings: AppSettingsStore
    @ObservedObject var panelMetrics: PanelMetrics
    let onOpenDisplaySettings: () -> Void
    let onGenerateMemo: (String, String) -> Void
    var shouldPresentTaskError: () -> Bool = { true }
    @State private var section: MemoSection = .tasks
    @State private var selectedTab: AppTab = .memo
    @State private var homeDetail: AppTab?
    @State private var homeMemoDraft = ""
    private var currentTab: AppTab { homeDetail ?? selectedTab }

    var body: some View {
        ZStack(alignment: .top) {
            BottomRoundedRectangle(radius: IslandTheme.radiusPanel)
                .fill(IslandTheme.background)
            // 底沿渐变描边，对齐参考项目的标志性边缘光。
            BottomRoundedRectangle(radius: IslandTheme.radiusPanel)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.35),
                            IslandTheme.accentBlue.opacity(0.22),
                            IslandTheme.accentGreen.opacity(0.28),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )

            VStack(spacing: IslandTheme.s3) {
                topbar
                    .frame(height: IslandTheme.topbarHeight)
                if let message = pendingStorageError {
                    HStack(spacing: 8) {
                        Text(message).font(.caption2).foregroundStyle(IslandTheme.accentOrange).lineLimit(2)
                        Spacer()
                        Button("重试保存") {
                            Task {
                                _ = await clipboardStore.flushPendingSave(retry: true)
                                _ = await commandsStore.flushPendingSave(retry: true)
                                _ = await linksStore.flushPendingSave(retry: true)
                                _ = await credentialsStore.flushPendingSave(retry: true)
                                _ = await recordingsStore.flushPendingSave(retry: true)
                            }
                        }.buttonStyle(.borderless).font(.caption)
                    }.padding(8).background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: 8))
                }

                ZStack {
                    // Keep the editor mounted so changing tabs preserves its draft.
                    MemoWorkspaceView(store: store, appSettings: appSettings, section: $section,
                                      isActive: currentTab == .memo)
                        .opacity(currentTab == .memo ? 1 : 0)
                        .allowsHitTesting(currentTab == .memo)
                        .accessibilityHidden(currentTab != .memo)
                    switch currentTab {
                    case .memo:
                        EmptyView()
                    case .clipboard:
                        ClipboardHistoryView(store: clipboardStore, settings: appSettings, onGenerateMemo: onGenerateMemo)
                    case .home:
                        HomeView(
                            tasks: store,
                            clipboard: clipboardStore,
                            links: linksStore,
                            credentials: credentialsStore,
                            pomodoro: pomodoroStore,
                            music: musicService,
                            windows: windowListService,
                            commands: commandsStore,
                            recordings: recordingsStore,
                            notifyServer: notifyServer,
                            codexStatus: codexStatusStore,
                            panelMetrics: panelMetrics,
                            settings: appSettings,
                            onGenerateMemo: onGenerateMemo,
                            memoDraft: $homeMemoDraft,
                            onOpenModule: { module in homeDetail = AppTab(feature: module.feature) }
                        )
                    case .links:
                        LinksView(store: linksStore, settings: appSettings)
                    case .recordings:
                        RecordingsView(store: recordingsStore)
                    case .credentials:
                        CredentialsView(store: credentialsStore, settings: appSettings)
                    case .music: standaloneModule(.music)
                    case .pomodoro: standaloneModule(.pomodoro)
                    case .recorder: standaloneModule(.recorder)
                    case .windows: standaloneModule(.windows)
                    case .mirror: standaloneModule(.mirror)
                    case .note: standaloneModule(.note)
                    case .commands: standaloneModule(.commands)
                    case .clock: standaloneModule(.clock)
                    case .calendar: standaloneModule(.calendar)
                    case .completions: standaloneModule(.completions)
                    case .settings:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, IslandTheme.s6)
            .padding(.top, panelMetrics.topInset)
            .padding(.bottom, IslandTheme.s4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .tint(IslandTheme.accentBlue)
        .onAppear {
            if !visibleTabs.contains(selectedTab), let first = visibleTabs.first {
                selectedTab = first
            }
        }
        .onChange(of: store.focusAddRequest) { _ in
            homeDetail = nil
            if appSettings.workspacePlacement(for: .memo) == .tab {
                selectedTab = .memo
                section = .tasks
            } else if appSettings.workspacePlacement(for: .memo) == .home {
                selectedTab = .home
            } else if let first = visibleTabs.first {
                selectedTab = first
            }
        }
        .onChange(of: appSettings.enabledFeatures) { _ in
            homeDetail = nil
            if !visibleTabs.contains(selectedTab), let first = visibleTabs.first { selectedTab = first }
        }
        .onChange(of: appSettings.featureOrder) { _ in
            if !visibleTabs.contains(selectedTab), let first = visibleTabs.first { selectedTab = first }
        }
        .onChange(of: appSettings.memoTrashEnabled) { enabled in
            if !enabled { section = .tasks }
        }
        .alert("提示", isPresented: Binding(
            get: { store.errorMessage != nil && shouldPresentTaskError() },
            set: { if !$0 { store.errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var pendingStorageError: String? {
        [clipboardStore.errorMessage, commandsStore.errorMessage, linksStore.errorMessage,
         credentialsStore.persistenceError, recordingsStore.persistenceError,
         currentTab == .recordings ? nil : recordingsStore.errorMessage,
         currentTab == .credentials ? nil : credentialsStore.errorMessage].compactMap { $0 }.first
    }

    private func standaloneModule(_ module: AppSettingsStore.HomeModule) -> some View {
        HomeView(
            tasks: store,
            clipboard: clipboardStore,
            links: linksStore,
            credentials: credentialsStore,
            pomodoro: pomodoroStore,
            music: musicService,
            windows: windowListService,
            commands: commandsStore,
            recordings: recordingsStore,
            notifyServer: notifyServer,
            codexStatus: codexStatusStore,
            panelMetrics: panelMetrics,
            settings: appSettings,
            onGenerateMemo: onGenerateMemo,
            memoDraft: $homeMemoDraft,
            standaloneModule: module
        )
    }

    // MARK: - 顶栏（对齐参考项目：左侧胶囊 Tabs，中央留刘海安全区，右侧图标按钮）

    private var topbar: some View {
        HStack(spacing: IslandTheme.s3) {
            capsuleTabs
            if homeDetail != nil {
                Button { homeDetail = nil } label: { Label("返回首页", systemImage: "chevron.left") }
                    .buttonStyle(.borderless).font(.caption)
            }
            if currentTab == .memo {
                memoSectionButtons
            }
            utilityIcon(systemImage: "gearshape", active: false, help: "打开设置") {
                onOpenDisplaySettings()
            }
        }
    }

    private var capsuleTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: IslandTheme.s1) {
                ForEach(visibleTabs) { tab in
                    capsuleTabButton(tab)
                }
            }
            .padding(3)
        }
        .scrollIndicators(.never)
        .background(IslandTheme.surface1, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func capsuleTabButton(_ tab: AppTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { homeDetail = nil; selectedTab = tab }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 12))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selectedTab == tab ? IslandTheme.text1 : IslandTheme.text3)
            .background(selectedTab == tab ? IslandTheme.surface2 : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var memoSectionButtons: some View {
        HStack(spacing: 6) {
            utilityIcon(systemImage: "checklist", active: section == .tasks, help: "任务列表") {
                section = .tasks
            }
            if appSettings.memoTrashEnabled {
                utilityIcon(systemImage: "trash", active: section == .trash, help: "回收站") {
                    section = .trash
                }
            }
        }
    }

    private func utilityIcon(systemImage: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(active ? IslandTheme.text1 : IslandTheme.text3)
                .frame(width: 30, height: 30)
                .background(active ? IslandTheme.surface2 : IslandTheme.surface1)
                .clipShape(RoundedRectangle(cornerRadius: IslandTheme.radiusInput))
                .overlay(
                    RoundedRectangle(cornerRadius: IslandTheme.radiusInput)
                        .stroke(IslandTheme.hairlineSoft, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var visibleTabs: [AppTab] {
        appSettings.orderedVisibleFeatures
            .filter { $0 != .settings }
            .map { AppTab(feature: $0) }
    }

}

struct BottomRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
