import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case features = "功能与顺序"
    case memo = "备忘录"
    case clipboard = "复制记录"
    case home = "首页布局"
    case aiTasks = "AI 任务"
    case music = "音乐服务"
    case focus = "专注计时"
    case recording = "录制与转写"
    case links = "链接"
    case credentials = "密钥"
    case general = "通用"

    var id: Self { self }
    var icon: String {
        switch self {
        case .features: return "rectangle.3.group"
        case .memo: return "checklist"
        case .clipboard: return "doc.on.clipboard"
        case .home: return "square.grid.2x2"
        case .aiTasks: return "sparkles"
        case .music: return "music.note.list"
        case .focus: return "timer"
        case .recording: return "waveform"
        case .links: return "link"
        case .credentials: return "key"
        case .general: return "gearshape"
        }
    }
}

/// 完整设置中心：左侧调整设置，右侧同步展示不可操作的效果预览。
struct DisplaySettingsView: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var pomodoro: PomodoroStore
    @ObservedObject var recordings: RecordingStore
    @ObservedObject var notifyServer: AgentNotifyServer
    @ObservedObject var aiApplications: AIApplicationDetector
    @ObservedObject var music: MusicService
    let onEditShortcut: () -> Void
    @State private var pane: SettingsPane = .features
    @State private var region = TranscriptionConfig.load().region
    @State private var workspaceId = TranscriptionConfig.load().workspaceId
    @State private var apiKeyInput = ""
    @State private var transcriptionSaved = false
    @State private var showsAPIRequired = false
    @State private var draggedMemoCategoryID: String?

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider().overlay(IslandTheme.hairline)
            editor.frame(width: 390)
            Divider().overlay(IslandTheme.hairline)
            SettingsReadOnlyPreview(
                settings: settings,
                pane: pane,
                pomodoroMinutes: pomodoro.durationMinutes,
                notifyServerIsRunning: notifyServer.isRunning
            )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background(IslandTheme.background)
        .frame(minWidth: 1060, minHeight: 650)
        .preferredColorScheme(.dark)
        .tint(IslandTheme.accentBlue)
        .alert("提示", isPresented: Binding(
            get: { settings.settingsError != nil },
            set: { if !$0 { settings.settingsError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(settings.settingsError ?? "")
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("设置中心").font(.title3.weight(.semibold)).foregroundStyle(IslandTheme.text1)
                Text("所有修改会自动保存").font(.caption2).foregroundStyle(IslandTheme.text3)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)

            VStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { item in
                    Button { pane = item } label: {
                        HStack(spacing: 9) {
                            Image(systemName: item.icon).frame(width: 17)
                            Text(item.rawValue)
                            Spacer()
                        }
                        .font(.callout.weight(pane == item ? .semibold : .regular))
                        .foregroundStyle(pane == item ? IslandTheme.text1 : IslandTheme.text3)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(pane == item ? IslandTheme.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            Spacer()
        }
        .frame(width: 158)
        .background(IslandTheme.surface1.opacity(0.72))
    }

    @ViewBuilder private var editor: some View {
        switch pane {
        case .features: featureEditor
        case .memo: memoEditor
        case .clipboard: clipboardEditor
        case .home: homeEditor
        case .aiTasks: aiTasksEditor
        case .music: musicEditor
        case .focus: focusEditor
        case .recording: recordingEditor
        case .links: linksEditor
        case .credentials: credentialsEditor
        case .general: generalEditor
        }
    }

    private var featureEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            editorHeader("功能与顺序", detail: "每个功能可放在顶部、首页或隐藏；首页最多 6 个模块")
            List {
                ForEach(settings.orderedMovableFeatures) { feature in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(IslandTheme.text4)
                        Image(systemName: feature.systemImage).frame(width: 18).foregroundStyle(IslandTheme.text2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.rawValue).foregroundStyle(IslandTheme.text1)
                            Text(feature.detail).font(.caption2).foregroundStyle(IslandTheme.text3)
                        }
                        Spacer()
                        workspacePlacementControl(for: feature)
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(IslandTheme.surface1)
                }
                .onMove(perform: settings.moveWorkspaceFeatures)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            HStack(spacing: 10) {
                Text("一个功能只能选择一个位置。首页最多显示 6 个模块；设置固定在顶部右侧。")
                    .font(.caption2)
                    .foregroundStyle(IslandTheme.text4)
                Spacer()
                Button {
                    settings.resetWorkspaceLayout()
                } label: {
                    Label("重置功能", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .editorPadding()
    }

    private var memoEditor: some View {
        scrollEditor("备忘录", detail: "关闭细节功能只隐藏入口，原有任务数据会保留") {
            settingsCard {
                settingsToggle("任务分类", detail: "最多 4 个分类，可调整顺序和占位大小", value: $settings.memoCategoriesEnabled)
                settingsToggle("启用子任务", detail: "显示子任务列表和添加入口", value: $settings.memoSubtasksEnabled)
                settingsToggle("结束时间", detail: "允许任务和子任务设置时间", value: $settings.memoDueDatesEnabled)
                settingsToggle("任务等级", detail: "普通、一般、重要和紧急", value: $settings.memoPrioritiesEnabled)
                settingsToggle("已完成列表", detail: "显示未完成/已完成切换", value: $settings.memoCompletedEnabled)
                settingsToggle("回收站", detail: "显示恢复和彻底删除入口", value: $settings.memoTrashEnabled)
            }
            if settings.memoCategoriesEnabled && settings.memoSubtasksEnabled {
                Label {
                    Text("不建议同时开启任务分类和子任务。两层结构会压缩任务内容空间，影响日常查看与操作。")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption2)
                .foregroundStyle(IslandTheme.accentOrange)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(IslandTheme.accentOrange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            if settings.memoCategoriesEnabled {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("任务分类")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(IslandTheme.text3)
                        Text("\(settings.memoCategories.count)/4")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(IslandTheme.text4)
                        Spacer()
                        Button("恢复默认") { settings.resetMemoCategories() }
                            .buttonStyle(.borderless).font(.caption2)
                        Button {
                            settings.addMemoCategory()
                        } label: {
                            Label("添加", systemImage: "plus")
                        }
                        .buttonStyle(.borderless).font(.caption2)
                        .disabled(settings.memoCategories.count >= 4)
                    }
                    settingsCard {
                        ForEach(settings.memoCategories) { category in
                            memoCategorySettingRow(category)
                                .onDrag {
                                    draggedMemoCategoryID = category.id
                                    return NSItemProvider(object: category.id as NSString)
                                }
                                .onDrop(
                                    of: ["public.text"],
                                    delegate: MemoCategoryDropDelegate(
                                        currentID: category.id,
                                        draggedID: $draggedMemoCategoryID,
                                        settings: settings
                                    )
                                )
                                .settingDivider()
                        }
                    }
                    Text("拖动左侧把手调整位置；“放大”会占用主区域，其余分类自动补齐空位。")
                        .font(.caption2)
                        .foregroundStyle(IslandTheme.text4)
                }
            }
            if settings.memoPrioritiesEnabled {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("任务等级样式")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(IslandTheme.text3)
                        Spacer()
                        Button("恢复默认") { settings.resetPriorityAppearance() }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                    }
                    settingsCard {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            HStack(spacing: 14) {
                                ColorPicker("", selection: Binding(
                                    get: { settings.priorityColor(for: priority) },
                                    set: { settings.setPriorityColorHex(priority, hex: colorHex($0)) }
                                ), supportsOpacity: false)
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(width: 30)
                                TextField("等级名称", text: Binding(
                                    get: { settings.priorityNames[priority] ?? settings.priorityName(for: priority) },
                                    set: { settings.setPriorityName(priority, name: $0) }
                                ))
                                .textFieldStyle(.plain)
                                .foregroundStyle(IslandTheme.text1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 10)
                            .settingDivider()
                        }
                    }
                }
            }
        }
    }

    private func workspacePlacementControl(for feature: AppSettingsStore.Feature) -> some View {
        let selected = settings.workspacePlacement(for: feature)
        return HStack(spacing: 2) {
            ForEach(AppSettingsStore.WorkspacePlacement.allCases) { placement in
                Button {
                    settings.setWorkspacePlacement(feature, placement: placement)
                } label: {
                    Text(placement.compactLabel)
                        .font(.caption2.weight(selected == placement ? .semibold : .medium))
                        .foregroundStyle(selected == placement ? IslandTheme.text1 : IslandTheme.text3)
                        .frame(width: 42, height: 26)
                        .background(
                            selected == placement ? IslandTheme.accentBlue.opacity(0.2) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(
                                    selected == placement ? IslandTheme.accentBlue.opacity(0.65) : Color.clear,
                                    lineWidth: 1
                                )
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("放到\(placement.label)")
                .accessibilityLabel("\(feature.rawValue)放到\(placement.label)")
            }
        }
        .padding(2)
        .background(IslandTheme.surface2, in: RoundedRectangle(cornerRadius: 9))
        .animation(.easeOut(duration: 0.14), value: selected)
    }

    private var clipboardEditor: some View {
        scrollEditor("复制记录", detail: "设置记录类型、容量和卡片展示") {
            settingsCard {
                settingsToggle("记录文字", detail: "监听复制到剪贴板的文字", value: $settings.clipboardCaptureText)
                settingsToggle("记录图片", detail: "包含截图和复制的图片文件", value: $settings.clipboardCaptureImages)
                settingsToggle("显示来源应用", detail: "在记录时间后显示来源", value: $settings.clipboardShowSource)
                labeledStepper("最多保留", value: $settings.clipboardMaxItems, range: 5...100, suffix: "条")
                labeledStepper("文字预览", value: $settings.clipboardPreviewLines, range: 1...8, suffix: "行")
            }
        }
    }

    private var homeEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            editorHeader(
                "首页布局",
                detail: "已使用 \(settings.enabledHomeModules.count)/\(AppSettingsStore.maximumHomeModuleCount)；拖动调整顺序"
            )
            List {
                ForEach(settings.orderedVisibleModules(includeCompletions: true)) { module in
                    HStack(spacing: 9) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(IslandTheme.text4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.rawValue).foregroundStyle(IslandTheme.text1)
                            Text(module.detail).font(.caption2).foregroundStyle(IslandTheme.text3)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.homeModuleSizes[module] ?? .small },
                            set: { settings.setHomeModuleSize(module, size: $0) }
                        )) {
                            ForEach(settings.allowedHomeModuleSizes(for: module), id: \.self) { size in
                                Text(size.label).tag(size)
                            }
                        }
                        .labelsHidden().frame(width: 62).disabled(!settings.canResizeHomeModules)
                        Button {
                            settings.setWorkspacePlacement(module.feature, placement: .tab)
                        } label: {
                            Image(systemName: "rectangle.topthird.inset.filled")
                        }
                        .buttonStyle(.borderless)
                        .help("移到顶部 Tab")
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(IslandTheme.surface1)
                }
                .onMove(perform: settings.moveVisibleHomeModules)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("时钟样式").foregroundStyle(IslandTheme.text1)
                    Text("切换首页时钟的显示方式")
                        .font(.caption2)
                        .foregroundStyle(IslandTheme.text3)
                }
                Spacer(minLength: 12)
                Picker("", selection: $settings.clockStyle) {
                    ForEach(AppSettingsStore.ClockStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 126)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text("首页最多显示 6 个模块；空间不足时会自动调整尺寸")
                    .font(.caption2).foregroundStyle(IslandTheme.text4)
                Spacer()
                Button {
                    settings.resetHomeLayout()
                } label: {
                    Label("重置首页", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .editorPadding()
    }

    private var focusEditor: some View {
        scrollEditor("专注计时", detail: "修改后下一次开始计时生效") {
            settingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("默认专注时间")
                        Spacer()
                        Text("\(pomodoro.durationMinutes) 分钟").foregroundStyle(IslandTheme.text3)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(pomodoro.durationMinutes) },
                            set: { pomodoro.durationMinutes = Int($0.rounded()) }
                        ),
                        in: 1...180, step: 1
                    )
                    .disabled(pomodoro.phase == .running)
                    HStack(spacing: 7) {
                        ForEach([15, 25, 45, 60], id: \.self) { minutes in
                            Button("\(minutes)分钟") { pomodoro.durationMinutes = minutes }
                                .buttonStyle(.bordered).controlSize(.small)
                                .disabled(pomodoro.phase == .running)
                        }
                    }
                    if pomodoro.phase == .running {
                        Text("计时进行中，暂停或重置后可以修改")
                            .font(.caption2)
                            .foregroundStyle(IslandTheme.text4)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var aiTasksEditor: some View {
        scrollEditor("AI 任务", detail: "检测本机 AI 应用及任务完成通知接入状态") {
            settingsCard {
                infoRow("接收服务", value: notifyServer.isRunning ? "运行中" : "端口不可用")
                infoRow("本机地址", value: "127.0.0.1:43821")
                HStack(spacing: 8) {
                    Text("连接验证").foregroundStyle(IslandTheme.text1)
                    Spacer()
                    Button("发送测试") { notifyServer.sendTestCompletion() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("复制接入地址") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            "http://127.0.0.1:43821/notify/codex",
                            forType: .string
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 11)
                .settingDivider()
                if !notifyServer.recentCompletions.isEmpty {
                    HStack {
                        Text("历史记录").foregroundStyle(IslandTheme.text1)
                        Spacer()
                        Text("\(notifyServer.recentCompletions.count) 条")
                            .foregroundStyle(IslandTheme.text3)
                        Button("清空", role: .destructive) { notifyServer.clearHistory() }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 11)
                    .settingDivider()
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("本机 AI 应用")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(IslandTheme.text3)
                    Spacer()
                    Text("检测到 \(aiApplications.applications.count) 个")
                        .font(.caption2)
                        .foregroundStyle(IslandTheme.text4)
                    Button {
                        aiApplications.scan()
                    } label: {
                        Label("重新检测", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                }
                settingsCard {
                    if aiApplications.applications.isEmpty {
                        Text("暂未检测到常见 AI 应用")
                            .foregroundStyle(IslandTheme.text3)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(aiApplications.applications) { application in
                            aiApplicationRow(application)
                                .settingDivider()
                        }
                    }
                }
            }
            Text("检测依据是本机应用、命令行工具和公开的任务完成钩子配置。macOS 不允许一个应用读取其他应用的系统通知内容；标记为“仅应用通知”的工具仍可自行弹通知，但暂时不能把任务完成详情传给丫丫灵动。")
                .font(.caption2)
                .foregroundStyle(IslandTheme.text4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func aiApplicationRow(_ application: DetectedAIApplication) -> some View {
        HStack(spacing: 10) {
            Image(systemName: application.systemImage)
                .frame(width: 18)
                .foregroundStyle(IslandTheme.text2)
            VStack(alignment: .leading, spacing: 2) {
                Text(application.name)
                    .foregroundStyle(IslandTheme.text1)
                Text(application.detail)
                    .font(.caption2)
                    .foregroundStyle(IslandTheme.text3)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(application.integration.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(application.integration == .connected ? IslandTheme.accentGreen : (application.integration == .available ? IslandTheme.accentBlue : IslandTheme.text4))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(IslandTheme.surface2, in: Capsule())
        }
        .padding(.vertical, 10)
        .help(application.location)
    }

    private var musicEditor: some View {
        scrollEditor("音乐服务", detail: "分别启用播放器，并选择首页音乐卡默认控制哪一个") {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("播放器")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(IslandTheme.text3)
                    Spacer()
                    Button { music.refreshStatus() } label: {
                        Label("重新检测", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                }
                settingsCard {
                    ForEach(MusicService.Provider.allCases) { provider in
                        musicProviderRow(provider)
                            .settingDivider()
                    }
                }
            }

            if let error = music.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(IslandTheme.accentOrange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(IslandTheme.accentOrange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }

            Text("Apple Music 与 Spotify 使用播放器原生控制；汽水音乐使用桌面快捷键，需要在系统设置的“辅助功能”中允许丫丫灵动。首页音乐卡始终只控制标记为默认的服务。")
                .font(.caption2)
                .foregroundStyle(IslandTheme.text4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { music.refreshStatus() }
    }

    private func musicProviderRow(_ provider: MusicService.Provider) -> some View {
        HStack(spacing: 10) {
            Group {
                if let icon = music.icon(for: provider) {
                    Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                } else {
                    Image(systemName: "music.note")
                        .frame(width: 24, height: 24)
                        .foregroundStyle(IslandTheme.text4)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.name).foregroundStyle(IslandTheme.text1)
                    Text(music.isInstalled(provider) ? (music.isRunning(provider) ? "运行中" : "已安装") : "未安装")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(music.isInstalled(provider) ? IslandTheme.accentGreen : IslandTheme.text4)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(IslandTheme.surface2, in: Capsule())
                }
                Text(provider.controlDescription)
                    .font(.caption2)
                    .foregroundStyle(IslandTheme.text3)
            }
            Spacer(minLength: 8)
            if music.defaultProvider == provider && music.isEnabled(provider) {
                Text("默认")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(IslandTheme.accentBlue)
            } else {
                Button("设为默认") { music.setDefault(provider) }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .disabled(!music.isInstalled(provider) || !music.isEnabled(provider))
            }
            Toggle("", isOn: Binding(
                get: { music.isEnabled(provider) },
                set: { music.setEnabled(provider, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 10)
    }

    private var recordingEditor: some View {
        scrollEditor("录制与转写", detail: "转写关闭后仍会正常保存本地录音") {
            settingsCard {
                settingsToggle(
                    "实时转写",
                    detail: recordings.transcriptionEnabled ? "录音时同步生成文字" : "默认关闭，不影响本地录音",
                    value: Binding(
                        get: { recordings.transcriptionEnabled },
                        set: { enabled in
                            if enabled && TranscriptionConfig.load().apiKey == nil {
                                recordings.transcriptionEnabled = false
                                showsAPIRequired = true
                            } else {
                                recordings.transcriptionEnabled = enabled
                                showsAPIRequired = false
                            }
                        }
                    )
                )
                if showsAPIRequired {
                    Text("必须先填写并保存 API Key，才能开启实时转写")
                        .font(.caption2)
                        .foregroundStyle(IslandTheme.p0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 9)
                        .settingDivider()
                }
                infoRow("录音文件", value: "本地保存")
                HStack(spacing: 12) {
                    Text("转写区域")
                        .foregroundStyle(IslandTheme.text1)
                    Spacer(minLength: 12)
                    regionSelector
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .settingDivider()
                TextField("Workspace ID（可选）", text: $workspaceId)
                    .textFieldStyle(.roundedBorder)
                    .padding(.vertical, 9)
                    .settingDivider()
                SecureField("新的 API Key（留空则不修改）", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .padding(.vertical, 9)
                    .settingDivider()
                HStack {
                    Text(transcriptionSaved ? "已保存" : (TranscriptionConfig.load().apiKey == nil ? "未配置 API Key" : "API Key 已存入钥匙串"))
                        .font(.caption2)
                        .foregroundStyle(transcriptionSaved ? IslandTheme.accentGreen : IslandTheme.text3)
                    Spacer()
                    Button("保存转写配置", action: saveTranscription)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.vertical, 11)
            }
        }
    }

    private var linksEditor: some View {
        scrollEditor("链接", detail: "控制链接列表的信息密度和自动处理") {
            settingsCard {
                settingsToggle("显示完整网址", detail: "在标题下方显示网址", value: $settings.linksShowURL)
                settingsToggle("自动读取标题和图标", detail: "保存后联网补全公开网页信息", value: $settings.linksAutoMetadata)
            }
        }
    }

    private var credentialsEditor: some View {
        scrollEditor("密钥", detail: "密码正文始终只保存在 macOS 钥匙串") {
            settingsCard {
                settingsToggle("允许临时显示密钥", detail: "关闭后密钥页不显示眼睛按钮", value: $settings.credentialsAllowReveal)
                infoRow("密码存储", value: "macOS 钥匙串")
                infoRow("列表元数据", value: "仅保存在本机")
            }
        }
    }

    private var generalEditor: some View {
        scrollEditor("通用", detail: "应用启动与本地数据") {
            settingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("唤起快捷键").foregroundStyle(IslandTheme.text1)
                        Text(settings.shortcutDisplayText).font(.caption2).foregroundStyle(IslandTheme.text3)
                    }
                    Spacer()
                    Button("修改…", action: onEditShortcut).buttonStyle(.borderless)
                }
                .padding(.vertical, 11)
                .settingDivider()
                settingsToggle("开机自动启动", detail: "登录 macOS 后自动运行", value: $settings.autoLaunch)
                HStack(spacing: 12) {
                    Text("系统权限")
                        .foregroundStyle(IslandTheme.text1)
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        permissionButton("麦克风", pane: "Privacy_Microphone")
                        permissionButton("摄像头", pane: "Privacy_Camera")
                        permissionButton("屏幕录制", pane: "Privacy_ScreenCapture")
                    }
                }
                .padding(.vertical, 11)
                .settingDivider()
                infoRow("设置保存", value: settings.homeLayoutPersisted ? "已写入本机" : "仅本次会话")
                infoRow("数据位置", value: "Application Support/IslandMemo")
            }
        }
    }

    private func editorHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(IslandTheme.text1)
            Text(detail).font(.caption).foregroundStyle(IslandTheme.text3)
        }
    }

    private func scrollEditor<Content: View>(_ title: String, detail: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    editorHeader(title, detail: detail)
                    content()
                }
                .frame(width: max(0, geometry.size.width - 40), alignment: .leading)
                .padding(20)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: IslandTheme.radiusTile))
    }

    private func memoCategorySettingRow(_ category: MemoCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(IslandTheme.text4)
                .frame(width: 15)
            TextField("分类名称", text: Binding(
                get: { category.name },
                set: { settings.updateMemoCategory(category, name: $0) }
            ))
            .textFieldStyle(.plain)
            .foregroundStyle(IslandTheme.text1)
            .frame(maxWidth: .infinity)
            Picker("", selection: Binding(
                get: { category.size },
                set: { settings.setMemoCategorySize(category, size: $0) }
            )) {
                ForEach(MemoCategory.Size.allCases, id: \.self) { size in
                    Text(size.label).tag(size)
                }
            }
            .labelsHidden()
            .frame(width: 68)
            Button(role: .destructive) {
                settings.removeMemoCategory(category)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(settings.memoCategories.count <= 1)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func settingsToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(IslandTheme.text1)
                Text(detail).font(.caption2).foregroundStyle(IslandTheme.text3)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: value)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11)
        .settingDivider()
    }

    private func labeledStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack {
            Text(title).foregroundStyle(IslandTheme.text1)
            Spacer()
            Text("\(value.wrappedValue)\(suffix)").foregroundStyle(IslandTheme.text3)
            Stepper("", value: value, in: range).labelsHidden()
        }
        .padding(.vertical, 11).settingDivider()
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(IslandTheme.text1)
            Spacer()
            Text(value).foregroundStyle(IslandTheme.text3)
        }
        .padding(.vertical, 11).settingDivider()
    }

    private func permissionButton(_ title: String, pane: String) -> some View {
        Button(title) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var regionSelector: some View {
        HStack(spacing: 2) {
            regionButton("北京", value: "beijing")
            regionButton("新加坡", value: "singapore")
        }
        .padding(2)
        .background(IslandTheme.surface3, in: RoundedRectangle(cornerRadius: 7))
    }

    private func regionButton(_ title: String, value: String) -> some View {
        Button { region = value } label: {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(region == value ? IslandTheme.text1 : IslandTheme.text2)
                .frame(width: 66, height: 25)
                .background(
                    region == value ? IslandTheme.accentBlue : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
    }

    private func colorHex(_ color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "#0A84FF" }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }

    private func saveTranscription() {
        var config = TranscriptionConfig.load()
        config.region = region
        config.workspaceId = workspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
        config.save()
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            KeychainHelper.save(key: TranscriptionConfig.apiKeychainKey, value: key)
            apiKeyInput = ""
        }
        transcriptionSaved = true
        showsAPIRequired = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { transcriptionSaved = false }
    }
}

private struct SettingsReadOnlyPreview: View {
    @ObservedObject var settings: AppSettingsStore
    let pane: SettingsPane
    let pomodoroMinutes: Int
    let notifyServerIsRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("实时预览").font(.title3.weight(.semibold)).foregroundStyle(IslandTheme.text1)
                    Text("仅用于查看效果，不能在这里操作").font(.caption2).foregroundStyle(IslandTheme.text3)
                }
                Spacer()
                Label("只读", systemImage: "eye").font(.caption.weight(.medium)).foregroundStyle(IslandTheme.text3)
            }

            GeometryReader { geometry in
                let logicalWidth = IslandTheme.panelWidth
                let logicalHeight = IslandTheme.topbarHeight
                    + IslandTheme.s3
                    + IslandTheme.panelContentHeight
                    + IslandTheme.s4
                let scale = min(
                    geometry.size.width / logicalWidth,
                    geometry.size.height / logicalHeight
                )

                previewPanel
                    .frame(width: logicalWidth, height: logicalHeight)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: max(0, (geometry.size.width - logicalWidth * scale) / 2))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewPanel: some View {
        VStack(spacing: IslandTheme.s3) {
            previewTopbar
                .frame(height: IslandTheme.topbarHeight)
            Group {
                if pane == .home || pane == .focus { homePreview } else { detailPreview }
            }
            .frame(height: IslandTheme.panelContentHeight)
        }
        .padding(.horizontal, IslandTheme.s6)
        .padding(.bottom, IslandTheme.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(IslandTheme.hairline, lineWidth: 1))
    }

    private var previewTopbar: some View {
        HStack(spacing: 4) {
            ForEach(settings.orderedVisibleFeatures.filter { $0 != .settings }) { feature in
                HStack(spacing: 4) {
                    Image(systemName: feature.systemImage).font(.system(size: 12))
                    Text(feature.rawValue).font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(IslandTheme.text2)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(IslandTheme.surface2, in: Capsule())
            }
            Spacer(minLength: 0)
            Image(systemName: "gearshape")
                .font(.system(size: 12))
                .foregroundStyle(IslandTheme.text3)
                .padding(7)
                .background(IslandTheme.surface2, in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: IslandTheme.topbarHeight).clipped()
    }

    @ViewBuilder private var detailPreview: some View {
        switch pane {
        case .features, .memo: memoPreview
        case .clipboard: clipboardPreview
        case .focus: focusPreview
        case .aiTasks: genericPreview(
            "AI 任务接收服务",
            icon: "sparkles",
            subtitle: notifyServerIsRunning ? "运行中 · 等待完成通知" : "端口不可用"
        )
        case .music: genericPreview("音乐服务", icon: "music.note", subtitle: "独立启用 · 指定默认播放器")
        case .recording: genericPreview("快速录音", icon: "record.circle", subtitle: "点击开始 · 可控制实时转写")
        case .links: genericPreview("收藏的链接", icon: "link", subtitle: settings.linksShowURL ? "https://example.com" : "自动整理到分类")
        case .credentials: genericPreview("密钥保存在钥匙串", icon: "key", subtitle: settings.credentialsAllowReveal ? "允许临时显示" : "始终保持隐藏")
        case .general: genericPreview("丫丫灵动", icon: "gearshape", subtitle: "设置会自动保存在本机")
        case .home: EmptyView()
        }
    }

    private var memoPreview: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                if settings.memoCompletedEnabled {
                HStack(spacing: 22) {
                    Text("未完成").foregroundStyle(IslandTheme.text1)
                    Text("已完成").foregroundStyle(IslandTheme.text3)
                }
                .font(.caption.weight(.semibold))
                }
                Spacer()
                if settings.memoTrashEnabled {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(IslandTheme.text3)
                }
            }
            if settings.memoCategoriesEnabled {
                memoCategoryPreviewGrid
            } else {
                sampleTask("整理今天的工作", hasSubtasks: settings.memoSubtasksEnabled)
                sampleTask("联系快递", hasSubtasks: false)
                Spacer()
            }
        }
    }

    private var memoCategoryPreviewGrid: some View {
        GeometryReader { geometry in
            let categories = settings.memoCategories
            let placements = MemoCategoryLayoutEngine.resolve(categories: categories)
            let gap: CGFloat = 7
            let cellWidth = (geometry.size.width - gap * 11) / 12
            let cellHeight = (geometry.size.height - gap * 3) / 4

            ZStack(alignment: .topLeading) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    if placements.indices.contains(index) {
                        let placement = placements[index]
                        let width = cellWidth * CGFloat(placement.span.columns) + gap * CGFloat(placement.span.columns - 1)
                        let height = cellHeight * CGFloat(placement.span.rows) + gap * CGFloat(placement.span.rows - 1)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 6) {
                                Text(category.name).font(.caption2.weight(.semibold)).lineLimit(1)
                                Spacer()
                            }
                            Text(index == 0 ? "整理今天的工作" : "示例任务")
                                .font(.system(size: 9))
                                .foregroundStyle(IslandTheme.text2)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(IslandTheme.text1)
                        .padding(9)
                        .frame(width: width, height: height, alignment: .topLeading)
                        .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: 10))
                        .offset(
                            x: CGFloat(placement.column) * (cellWidth + gap),
                            y: CGFloat(placement.row) * (cellHeight + gap)
                        )
                    }
                }
            }
        }
    }

    private func sampleTask(_ title: String, hasSubtasks: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "circle").foregroundStyle(IslandTheme.text3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium)).foregroundStyle(IslandTheme.text1)
                if settings.memoDueDatesEnabled {
                    Label("今天 18:00", systemImage: "clock").font(.caption2).foregroundStyle(IslandTheme.text3)
                }
                if hasSubtasks { Text("子任务 1/3").font(.caption2).foregroundStyle(IslandTheme.text3) }
                if hasSubtasks {
                    HStack(spacing: 6) {
                        Image(systemName: "circle").font(.system(size: 9))
                        Text("整理会议记录").font(.caption2)
                    }
                    .foregroundStyle(IslandTheme.text3)
                    .padding(.top, 2)
                }
            }
            Spacer()
            if settings.memoPrioritiesEnabled {
                Circle().fill(settings.priorityColor(for: .blue)).frame(width: 8, height: 8)
                Text(settings.priorityName(for: .blue)).font(.caption2).foregroundStyle(IslandTheme.text3)
            }
        }
        .padding(11)
        .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private var clipboardPreview: some View {
        HStack(alignment: .top, spacing: 9) {
            ForEach(0..<2, id: \.self) { index in
                VStack(alignment: .leading, spacing: 7) {
                    Text(index == 0 ? "这是一段复制内容，用来查看文字卡片的显示行数和省略效果。" : "另一条复制记录会按照两列瀑布流显示。")
                        .font(.caption).foregroundStyle(IslandTheme.text2).lineLimit(settings.clipboardPreviewLines)
                    Text(settings.clipboardShowSource ? "2026/9/3  ·  访达" : "2026/9/3")
                        .font(.system(size: 8)).foregroundStyle(IslandTheme.text4)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: 11))
            }
            Spacer()
        }
    }

    private var focusPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("番茄钟", systemImage: "timer").font(.caption).foregroundStyle(IslandTheme.text3)
            Text(String(format: "%02d:00", pomodoroMinutes))
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(IslandTheme.text1)
            ProgressView(value: 0.22).tint(IslandTheme.accentBlue)
            Spacer()
        }
        .padding(16)
        .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: 16))
    }

    private func genericPreview(_ title: String, icon: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(IslandTheme.text3)
            Text(title).font(.headline).foregroundStyle(IslandTheme.text1)
            Text(subtitle).font(.caption).foregroundStyle(IslandTheme.text3)
            Spacer()
        }
        .padding(.top, 54).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var homePreview: some View {
        GeometryReader { geometry in
            let modules = settings.orderedVisibleModules(includeCompletions: true)
            let sizes = settings.normalizedHomeModuleSizes(for: modules)
            let spans = modules.map { module -> HomeGridSpan in
                let size = sizes[module] ?? .small
                return HomeGridSpan(columns: size.columns, rows: size.rows)
            }
            let placements = HomeLayoutEngine.resolve(spans: spans) ?? []
            let gap: CGFloat = 6
            let cellWidth = (geometry.size.width - gap * 11) / 12
            let cellHeight = (geometry.size.height - gap * 3) / 4

            ZStack(alignment: .topLeading) {
                ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                    if placements.indices.contains(index) {
                        let placement = placements[index]
                        let width = cellWidth * CGFloat(placement.span.columns) + gap * CGFloat(placement.span.columns - 1)
                        let height = cellHeight * CGFloat(placement.span.rows) + gap * CGFloat(placement.span.rows - 1)
                        VStack(alignment: .leading, spacing: 4) {
                            if module == .clock {
                                if settings.clockStyle == .analog {
                                    if placement.span.rows == 1 || placement.span.columns <= 2 {
                                        AnalogClockFace(date: .now)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    } else if placement.span.rows >= 4 && placement.span.columns <= 4 {
                                        VStack(spacing: 4) {
                                            AnalogClockFace(date: .now)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            Text("10:30  28")
                                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                                .monospacedDigit()
                                                .foregroundStyle(IslandTheme.text1)
                                        }
                                    } else {
                                        HStack(spacing: 6) {
                                            AnalogClockFace(date: .now)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("10:30")
                                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                                    .monospacedDigit()
                                                    .foregroundStyle(IslandTheme.text1)
                                                Text("9月3日")
                                                    .font(.system(size: 6))
                                                    .foregroundStyle(IslandTheme.text4)
                                            }
                                        }
                                    }
                                } else {
                                    Text("LOCAL TIME")
                                        .font(.system(size: 6, weight: .semibold))
                                        .tracking(1)
                                        .foregroundStyle(IslandTheme.text4)
                                    Spacer(minLength: 0)
                                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                                        Text("10:30")
                                            .font(.system(size: 18, weight: .medium, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(IslandTheme.text1)
                                        Text("28")
                                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(IslandTheme.accentBlue)
                                    }
                                    Spacer(minLength: 0)
                                }
                            } else {
                                Image(systemName: moduleIcon(module)).font(.caption)
                                Text(module.rawValue).font(.caption2.weight(.semibold)).lineLimit(1)
                                Text(modulePreviewText(module))
                                    .font(.system(size: 8))
                                    .foregroundStyle(IslandTheme.text4)
                                    .lineLimit(2)
                                Spacer()
                            }
                        }
                        .foregroundStyle(IslandTheme.text2).padding(8)
                        .frame(width: width, height: height, alignment: .topLeading)
                        .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: 10))
                        .offset(
                            x: CGFloat(placement.column) * (cellWidth + gap),
                            y: CGFloat(placement.row) * (cellHeight + gap)
                        )
                    }
                }
            }
        }
    }

    private func moduleIcon(_ module: AppSettingsStore.HomeModule) -> String {
        switch module {
        case .memo: return "checklist"
        case .clipboard: return "doc.on.clipboard"
        case .links: return "link"
        case .recordings: return "waveform"
        case .credentials: return "key"
        case .music: return "music.note"
        case .pomodoro: return "timer"
        case .recorder: return "mic"
        case .windows: return "macwindow"
        case .mirror: return "camera"
        case .note: return "pencil.line"
        case .commands: return "command"
        case .clock: return "clock"
        case .calendar: return "calendar"
        case .completions: return "sparkles"
        }
    }

    private func modulePreviewText(_ module: AppSettingsStore.HomeModule) -> String {
        switch module {
        case .memo: return "近期未完成任务"
        case .clipboard: return "最近复制内容"
        case .links: return "最近收藏链接"
        case .recordings: return "最近录音"
        case .credentials: return "密钥快速复制"
        case .music: return "播放控制"
        case .pomodoro: return String(format: "%02d:00", pomodoroMinutes)
        case .recorder: return "点击开始录音"
        case .windows: return "当前窗口列表"
        case .mirror: return "点击开启镜子"
        case .note: return "随手记录内容"
        case .commands: return "常用指令"
        case .clock: return "10:30:00"
        case .calendar: return "公历 · 农历"
        case .completions: return "最近完成任务"
        }
    }
}

private extension View {
    func editorPadding() -> some View { padding(20) }
    func settingDivider() -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(IslandTheme.hairlineSoft).frame(height: 1)
        }
    }
}

private struct MemoCategoryDropDelegate: DropDelegate {
    let currentID: String
    @Binding var draggedID: String?
    let settings: AppSettingsStore

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != currentID else { return }
        settings.moveMemoCategory(draggedID, before: currentID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
