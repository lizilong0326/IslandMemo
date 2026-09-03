import Foundation
import ServiceManagement

struct MemoCategory: Identifiable, Codable, Equatable, Sendable {
    enum Size: String, Codable, CaseIterable, Sendable {
        case standard
        case expanded

        var label: String { self == .standard ? "标准" : "放大" }
    }

    let id: String
    var name: String
    var colorHex: String
    var size: Size

    init(id: String = UUID().uuidString, name: String, colorHex: String, size: Size = .standard) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.size = size
    }
}

/// 面板设置：功能开关 + 开机启动 + 转写配置。
/// 对应 TO-DO-Panel 的设置页（数据目录迁移不移植，IslandMemo 已有固定本地目录）。
@MainActor
final class AppSettingsStore: ObservableObject {
    static let maximumHomeModuleCount = 6
    enum ClockStyle: String, CaseIterable, Identifiable, Sendable {
        case digital
        case analog

        var id: Self { self }
        var label: String { self == .digital ? "数字" : "钟表" }
    }

    enum Feature: String, CaseIterable, Identifiable, Sendable {
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

        var defaultsKey: String { "feature-\(self)" }

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

        var detail: String {
            switch self {
            case .memo: return "任务、子任务与回收站"
            case .clipboard: return "本地剪贴板历史"
            case .home: return "可自由排布的工作台"
            case .links: return "链接收藏与自动分组"
            case .recordings: return "录音与实时转写"
            case .credentials: return "本地密钥管理"
            case .music: return "播放状态与控制"
            case .pomodoro: return "专注计时"
            case .recorder: return "快速开始录音"
            case .windows: return "窗口快速切换"
            case .mirror: return "摄像头预览"
            case .note: return "快速记录文字"
            case .commands: return "提示词快捷入口"
            case .clock: return "时间与日期"
            case .calendar: return "公历月历与农历信息"
            case .completions: return "本机 Agent 完成提醒"
            case .settings: return "应用设置入口"
            }
        }

        var homeModule: HomeModule? {
            switch self {
            case .memo: return .memo
            case .clipboard: return .clipboard
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
            case .home, .settings: return nil
            }
        }

        static var movableCases: [Feature] {
            allCases.filter { $0 != .home && $0 != .settings }
        }
    }

    enum HomeModule: String, CaseIterable, Identifiable, Sendable {
        case memo = "备忘录"
        case clipboard = "复制记录"
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

        var id: Self { self }

        var defaultsKey: String { "home-module-\(self)" }

        var detail: String {
            switch self {
            case .memo: return "待办摘要与快速完成"
            case .clipboard: return "最近复制内容"
            case .links: return "最近收藏的链接"
            case .recordings: return "录音历史摘要"
            case .credentials: return "密钥名称与快速复制"
            case .clock: return "时间与日期"
            case .calendar: return "公历月份与农历日期"
            case .music: return "播放状态与控制"
            case .pomodoro: return "专注计时"
            case .recorder: return "录音与转写"
            case .windows: return "窗口快速切换"
            case .mirror: return "摄像头预览"
            case .note: return "首页快速记录"
            case .commands: return "提示词快捷入口"
            case .completions: return "本机 Agent 完成提醒"
            }
        }

        var feature: Feature {
            switch self {
            case .memo: return .memo
            case .clipboard: return .clipboard
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
            }
        }
    }

    enum WorkspacePlacement: String, CaseIterable, Identifiable, Sendable {
        case tab
        case home
        case hidden

        var id: Self { self }
        var label: String {
            switch self {
            case .tab: return "顶部 Tab"
            case .home: return "首页模块"
            case .hidden: return "隐藏"
            }
        }

        var compactLabel: String {
            switch self {
            case .tab: return "顶部"
            case .home: return "首页"
            case .hidden: return "隐藏"
            }
        }
    }

    enum HomeModuleSize: String, CaseIterable, Sendable {
        case mini
        case small
        case medium
        case large

        var label: String {
            switch self {
            case .mini: return "迷你"
            case .small: return "小"
            case .medium: return "中"
            case .large: return "大"
            }
        }

        var columns: Int {
            switch self {
            case .mini, .small: return 2
            case .medium, .large: return 4
            }
        }

        var rows: Int {
            switch self {
            case .mini: return 1
            case .small, .medium: return 2
            case .large: return 4
            }
        }

        var area: Int { columns * rows }

        var next: HomeModuleSize {
            switch self {
            case .mini: return .small
            case .small: return .medium
            case .medium: return .large
            case .large: return .mini
            }
        }

        var larger: HomeModuleSize? {
            switch self {
            case .mini: return .small
            case .small: return .medium
            case .medium: return .large
            case .large: return nil
            }
        }

        var smaller: HomeModuleSize? {
            switch self {
            case .mini: return nil
            case .small: return .mini
            case .medium: return .small
            case .large: return .medium
            }
        }
    }

    @Published private(set) var enabledFeatures: Set<Feature>
    @Published private(set) var featureOrder: [Feature]
    @Published private(set) var enabledHomeModules: Set<HomeModule>
    @Published private(set) var homeModuleSizes: [HomeModule: HomeModuleSize]
    @Published private(set) var homeModuleOrder: [HomeModule]
    @Published private(set) var homeLayoutReadOnly = false
    @Published private(set) var homeLayoutPersisted = true
    @Published private(set) var shortcutDisplayText: String
    var canDisableHomeModule: ((HomeModule) -> Bool)?
    var onClipboardConfigurationChanged: (() -> Void)?

    @Published var memoSubtasksEnabled: Bool {
        didSet { UserDefaults.standard.set(memoSubtasksEnabled, forKey: "memo-subtasks-enabled") }
    }
    @Published var memoDueDatesEnabled: Bool {
        didSet { UserDefaults.standard.set(memoDueDatesEnabled, forKey: "memo-due-dates-enabled") }
    }
    @Published var memoPrioritiesEnabled: Bool {
        didSet { UserDefaults.standard.set(memoPrioritiesEnabled, forKey: "memo-priorities-enabled") }
    }
    @Published var memoCompletedEnabled: Bool {
        didSet { UserDefaults.standard.set(memoCompletedEnabled, forKey: "memo-completed-enabled") }
    }
    @Published var memoTrashEnabled: Bool {
        didSet { UserDefaults.standard.set(memoTrashEnabled, forKey: "memo-trash-enabled") }
    }
    @Published var memoCategoriesEnabled: Bool {
        didSet { UserDefaults.standard.set(memoCategoriesEnabled, forKey: "memo-categories-enabled") }
    }
    @Published private(set) var memoCategories: [MemoCategory]
    @Published var clockStyle: ClockStyle {
        didSet { UserDefaults.standard.set(clockStyle.rawValue, forKey: "home-clock-style") }
    }
    @Published var clipboardCaptureText: Bool {
        didSet { UserDefaults.standard.set(clipboardCaptureText, forKey: "clipboard-capture-text"); onClipboardConfigurationChanged?() }
    }
    @Published var clipboardCaptureImages: Bool {
        didSet { UserDefaults.standard.set(clipboardCaptureImages, forKey: "clipboard-capture-images"); onClipboardConfigurationChanged?() }
    }
    @Published var clipboardShowSource: Bool {
        didSet { UserDefaults.standard.set(clipboardShowSource, forKey: "clipboard-show-source") }
    }
    @Published var clipboardMaxItems: Int {
        didSet {
            UserDefaults.standard.set(clipboardMaxItems, forKey: "clipboard-max-items")
            onClipboardConfigurationChanged?()
        }
    }
    @Published var clipboardPreviewLines: Int {
        didSet {
            UserDefaults.standard.set(clipboardPreviewLines, forKey: "clipboard-preview-lines")
        }
    }
    @Published var linksShowURL: Bool {
        didSet { UserDefaults.standard.set(linksShowURL, forKey: "links-show-url") }
    }
    @Published var linksAutoMetadata: Bool {
        didSet { UserDefaults.standard.set(linksAutoMetadata, forKey: "links-auto-metadata") }
    }
    @Published var credentialsAllowReveal: Bool {
        didSet { UserDefaults.standard.set(credentialsAllowReveal, forKey: "credentials-allow-reveal") }
    }
    @Published private(set) var priorityNames: [TaskPriority: String]
    @Published private(set) var priorityColorHexes: [TaskPriority: String]
    @Published var autoLaunch: Bool {
        didSet { applyAutoLaunch() }
    }
    @Published var settingsError: String?

    init() {
        let defaults = UserDefaults.standard
        let legacyTopFeatures: [Feature] = [.memo, .clipboard, .home, .links, .recordings, .credentials, .settings]
        var features = Set<Feature>()
        for feature in legacyTopFeatures {
            // 新功能默认开启；用户显式关闭后尊重选择。
            if defaults.object(forKey: feature.defaultsKey) as? Bool ?? true {
                features.insert(feature)
            }
        }
        // 设置中心是所有功能恢复与配置的唯一入口，始终保留。
        features.insert(.settings)
        enabledFeatures = features

        let defaultFeatureOrder = Feature.allCases
        let savedFeatureOrder = (defaults.array(forKey: "feature-order") as? [String])?
            .compactMap(Feature.init(rawValue:))
        if let savedFeatureOrder,
           savedFeatureOrder.count == defaultFeatureOrder.count,
           Set(savedFeatureOrder) == Set(defaultFeatureOrder) {
            featureOrder = savedFeatureOrder
        } else {
            featureOrder = defaultFeatureOrder
        }

        let legacyHomeModules: [HomeModule] = [
            .music, .pomodoro, .recorder, .windows, .mirror, .note, .commands, .clock, .calendar, .completions,
        ]
        var homeModules = Set<HomeModule>()
        for module in legacyHomeModules {
            if defaults.object(forKey: module.defaultsKey) as? Bool ?? true {
                homeModules.insert(module)
            }
        }
        if homeModules.isEmpty { homeModules = Set(legacyHomeModules) }
        enabledHomeModules = homeModules

        var moduleSizes: [HomeModule: HomeModuleSize] = [:]
        var storedSizeIsInvalid = false
        for module in HomeModule.allCases {
            let saved = defaults.string(forKey: "home-module-size-\(module)")
            if let saved, HomeModuleSize(rawValue: saved) == nil { storedSizeIsInvalid = true }
            let decoded = saved.flatMap(HomeModuleSize.init(rawValue:)) ?? Self.defaultSize(for: module)
            moduleSizes[module] = Self.allowedSizes(for: module).contains(decoded)
                ? decoded
                : Self.defaultSize(for: module)
        }
        homeModuleSizes = moduleSizes

        let defaultOrder = Self.defaultHomeModuleOrder
        let savedOrder = (defaults.array(forKey: "home-module-order") as? [String])?
            .compactMap(HomeModule.init(rawValue:))
        let resolvedHomeModuleOrder: [HomeModule]
        if let savedOrder,
           savedOrder.count == defaultOrder.count,
           Set(savedOrder) == Set(defaultOrder) {
            resolvedHomeModuleOrder = savedOrder
        } else {
            resolvedHomeModuleOrder = defaultOrder
        }
        homeModuleOrder = resolvedHomeModuleOrder
        // v0.2.34 起每个业务功能只能处于顶部、首页或隐藏三种位置之一。
        // 首次升级沿用旧版位置；之后以统一位置键为准。
        for feature in Feature.movableCases {
            guard let module = feature.homeModule,
                  let raw = defaults.string(forKey: "workspace-placement-\(feature.rawValue)"),
                  let placement = WorkspacePlacement(rawValue: raw) else { continue }
            features.remove(feature)
            homeModules.remove(module)
            if placement == .tab { features.insert(feature) }
            if placement == .home { homeModules.insert(module) }
        }
        // 旧版本可能已经在首页放了超过六个模块。升级时随机隐藏溢出的模块，
        // 并立即保存结果，确保只处理一次，后续启动不会反复随机变化。
        let overflowCount = max(0, homeModules.count - Self.maximumHomeModuleCount)
        if overflowCount > 0 {
            for module in homeModules.shuffled().prefix(overflowCount) {
                homeModules.remove(module)
                features.remove(module.feature)
                defaults.set(WorkspacePlacement.hidden.rawValue, forKey: "workspace-placement-\(module.feature.rawValue)")
                defaults.set(false, forKey: module.feature.defaultsKey)
                defaults.set(false, forKey: module.defaultsKey)
            }
        }
        if features.intersection(Set(Feature.movableCases)).isEmpty && homeModules.isEmpty {
            features.insert(.memo)
        }
        if homeModules.isEmpty { features.remove(.home) }
        else { features.insert(.home) }
        features.insert(.settings)
        enabledFeatures = features
        enabledHomeModules = homeModules
        homeLayoutReadOnly = storedSizeIsInvalid
        memoSubtasksEnabled = defaults.object(forKey: "memo-subtasks-enabled") as? Bool ?? true
        memoDueDatesEnabled = defaults.object(forKey: "memo-due-dates-enabled") as? Bool ?? true
        memoPrioritiesEnabled = defaults.object(forKey: "memo-priorities-enabled") as? Bool ?? true
        memoCompletedEnabled = defaults.object(forKey: "memo-completed-enabled") as? Bool ?? true
        memoTrashEnabled = defaults.object(forKey: "memo-trash-enabled") as? Bool ?? true
        memoCategoriesEnabled = defaults.object(forKey: "memo-categories-enabled") as? Bool ?? true
        if let data = defaults.data(forKey: "memo-categories-v1"),
           let decoded = try? JSONDecoder().decode([MemoCategory].self, from: data),
           !decoded.isEmpty, decoded.count <= 4 {
            memoCategories = decoded
        } else {
            memoCategories = Self.defaultMemoCategories
        }
        clockStyle = defaults.string(forKey: "home-clock-style")
            .flatMap(ClockStyle.init(rawValue:)) ?? .digital
        clipboardCaptureText = defaults.object(forKey: "clipboard-capture-text") as? Bool ?? true
        clipboardCaptureImages = defaults.object(forKey: "clipboard-capture-images") as? Bool ?? true
        clipboardShowSource = defaults.object(forKey: "clipboard-show-source") as? Bool ?? true
        let savedClipboardLimit = defaults.integer(forKey: "clipboard-max-items")
        clipboardMaxItems = savedClipboardLimit > 0 ? min(max(savedClipboardLimit, 5), 100) : 20
        let savedPreviewLines = defaults.integer(forKey: "clipboard-preview-lines")
        clipboardPreviewLines = savedPreviewLines > 0 ? min(max(savedPreviewLines, 1), 8) : 4
        linksShowURL = defaults.object(forKey: "links-show-url") as? Bool ?? true
        linksAutoMetadata = defaults.object(forKey: "links-auto-metadata") as? Bool ?? true
        credentialsAllowReveal = defaults.object(forKey: "credentials-allow-reveal") as? Bool ?? true
        let savedPriorityNames = defaults.dictionary(forKey: "task-priority-names") as? [String: String] ?? [:]
        priorityNames = Dictionary(uniqueKeysWithValues: TaskPriority.allCases.map { priority in
            (priority, savedPriorityNames[priority.rawValue] ?? Self.defaultPriorityName(priority))
        })
        let savedPriorityColors = defaults.dictionary(forKey: "task-priority-colors") as? [String: String] ?? [:]
        priorityColorHexes = Dictionary(uniqueKeysWithValues: TaskPriority.allCases.map { priority in
            (priority, savedPriorityColors[priority.rawValue] ?? Self.defaultPriorityColorHex(priority))
        })
        shortcutDisplayText = ShortcutConfiguration.load().displayText
        autoLaunch = SMAppService.mainApp.status == .enabled
    }

    func isEnabled(_ feature: Feature) -> Bool {
        enabledFeatures.contains(feature)
    }

    func setFeature(_ feature: Feature, enabled: Bool) {
        guard feature != .settings else {
            enabledFeatures.insert(.settings)
            UserDefaults.standard.set(true, forKey: feature.defaultsKey)
            return
        }
        if feature == .home { return }
        setWorkspacePlacement(feature, placement: enabled ? .tab : .hidden)
    }

    var orderedVisibleFeatures: [Feature] {
        featureOrder.filter { feature in
            if feature == .settings { return true }
            if feature == .home { return !enabledHomeModules.isEmpty }
            return enabledFeatures.contains(feature)
        }
    }

    func workspacePlacement(for feature: Feature) -> WorkspacePlacement {
        if enabledFeatures.contains(feature) { return .tab }
        if let module = feature.homeModule, enabledHomeModules.contains(module) { return .home }
        return .hidden
    }

    func setWorkspacePlacement(_ feature: Feature, placement: WorkspacePlacement) {
        guard let module = feature.homeModule else { return }
        let oldPlacement = workspacePlacement(for: feature)
        guard oldPlacement != placement else { return }
        if placement == .home,
           !enabledHomeModules.contains(module),
           enabledHomeModules.count >= Self.maximumHomeModuleCount {
            settingsError = "首页最多显示 \(Self.maximumHomeModuleCount) 个模块，请先移出一个模块"
            return
        }
        if (module == .recorder || module == .recordings), placement != .home,
           !(canDisableHomeModule?(module) ?? true) {
            settingsError = "录音进行中，暂时不能移动录音功能"
            return
        }

        var nextFeatures = enabledFeatures
        var nextModules = enabledHomeModules
        nextFeatures.remove(feature)
        nextModules.remove(module)
        if placement == .tab { nextFeatures.insert(feature) }
        if placement == .home { nextModules.insert(module) }
        let visibleContentTabs = nextFeatures.intersection(Set(Feature.movableCases))
        guard !visibleContentTabs.isEmpty || !nextModules.isEmpty else {
            settingsError = "弹窗至少保留一个功能"
            return
        }

        let visible = homeModuleOrder.filter(nextModules.contains)
        if !visible.isEmpty {
            let sizes = normalizeHomeModuleSizes(
                homeModuleSizes,
                visibleModules: visible,
                preferred: placement == .home ? module : nil
            )
            guard canPackHomeModules(sizes, visibleModules: visible) else {
                settingsError = "首页空间不足，请先隐藏或移出一个模块"
                return
            }
            homeModuleSizes = sizes
            for visibleModule in visible {
                persist(sizes[visibleModule]?.rawValue, forKey: "home-module-size-\(visibleModule)")
            }
        }
        enabledFeatures = nextFeatures
        enabledHomeModules = nextModules
        if nextModules.isEmpty { enabledFeatures.remove(.home) }
        else { enabledFeatures.insert(.home) }
        enabledFeatures.insert(.settings)
        UserDefaults.standard.set(placement.rawValue, forKey: "workspace-placement-\(feature.rawValue)")
        UserDefaults.standard.set(placement == .tab, forKey: feature.defaultsKey)
        UserDefaults.standard.set(placement == .home, forKey: module.defaultsKey)
    }

    func moveFeatures(fromOffsets: IndexSet, toOffset: Int) {
        featureOrder = Self.moving(featureOrder, fromOffsets: fromOffsets, toOffset: toOffset)
        persist(featureOrder.map(\.rawValue), forKey: "feature-order")
    }

    var orderedMovableFeatures: [Feature] {
        featureOrder.filter { Feature.movableCases.contains($0) }
    }

    func moveWorkspaceFeatures(fromOffsets: IndexSet, toOffset: Int) {
        let reordered = Self.moving(orderedMovableFeatures, fromOffsets: fromOffsets, toOffset: toOffset)
        var iterator = reordered.makeIterator()
        featureOrder = featureOrder.map { Feature.movableCases.contains($0) ? (iterator.next() ?? $0) : $0 }
        persist(featureOrder.map(\.rawValue), forKey: "feature-order")
    }

    func updateShortcutDisplayText(_ text: String) {
        shortcutDisplayText = text
    }

    func priorityName(for priority: TaskPriority) -> String {
        let value = priorityNames[priority]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? Self.defaultPriorityName(priority) : value
    }

    func priorityColorHex(for priority: TaskPriority) -> String {
        priorityColorHexes[priority] ?? Self.defaultPriorityColorHex(priority)
    }

    func setPriorityName(_ priority: TaskPriority, name: String) {
        priorityNames[priority] = String(name.prefix(8))
        persistPriorityAppearance()
    }

    func setPriorityColorHex(_ priority: TaskPriority, hex: String) {
        priorityColorHexes[priority] = hex
        persistPriorityAppearance()
    }

    func resetPriorityAppearance() {
        priorityNames = Dictionary(uniqueKeysWithValues: TaskPriority.allCases.map {
            ($0, Self.defaultPriorityName($0))
        })
        priorityColorHexes = Dictionary(uniqueKeysWithValues: TaskPriority.allCases.map {
            ($0, Self.defaultPriorityColorHex($0))
        })
        persistPriorityAppearance()
    }

    func addMemoCategory() {
        guard memoCategories.count < 4 else {
            settingsError = "备忘录最多可以创建 4 个分类"
            return
        }
        let colors = ["#0A84FF", "#30D978", "#FF9F0A", "#BF5AF2"]
        memoCategories.append(MemoCategory(
            name: "分类 \(memoCategories.count + 1)",
            colorHex: colors[memoCategories.count % colors.count]
        ))
        persistMemoCategories()
    }

    func updateMemoCategory(_ category: MemoCategory, name: String? = nil, colorHex: String? = nil) {
        guard let index = memoCategories.firstIndex(where: { $0.id == category.id }) else { return }
        if let name {
            let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
            memoCategories[index].name = String((cleaned.isEmpty ? "未命名分类" : cleaned).prefix(16))
        }
        if let colorHex { memoCategories[index].colorHex = colorHex }
        persistMemoCategories()
    }

    func setMemoCategorySize(_ category: MemoCategory, size: MemoCategory.Size) {
        guard let index = memoCategories.firstIndex(where: { $0.id == category.id }) else { return }
        // The 12 x 4 grid has one featured slot. Expanding a category therefore
        // returns its siblings to standard size and always keeps a gapless layout.
        for itemIndex in memoCategories.indices { memoCategories[itemIndex].size = .standard }
        memoCategories[index].size = size
        persistMemoCategories()
    }

    func removeMemoCategory(_ category: MemoCategory) {
        guard memoCategories.count > 1 else {
            settingsError = "备忘录至少保留一个分类"
            return
        }
        memoCategories.removeAll { $0.id == category.id }
        persistMemoCategories()
    }

    func moveMemoCategory(_ sourceID: String, before targetID: String) {
        guard sourceID != targetID,
              let sourceIndex = memoCategories.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = memoCategories.firstIndex(where: { $0.id == targetID }) else { return }
        let item = memoCategories.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        memoCategories.insert(item, at: adjustedTarget)
        persistMemoCategories()
    }

    func resetMemoCategories() {
        memoCategories = Self.defaultMemoCategories
        persistMemoCategories()
    }

    func isHomeModuleEnabled(_ module: HomeModule) -> Bool {
        enabledHomeModules.contains(module)
    }

    func setHomeModule(_ module: HomeModule, enabled: Bool) {
        if !enabled {
            setWorkspacePlacement(module.feature, placement: .hidden)
            return
        }
        guard !homeLayoutReadOnly else {
            settingsError = "首页布局处于安全模式，请重新启动应用后再试"
            return
        }
        if enabled,
           !enabledHomeModules.contains(module),
           enabledHomeModules.count >= Self.maximumHomeModuleCount {
            settingsError = "首页最多显示 \(Self.maximumHomeModuleCount) 个模块，请先移出一个模块"
            return
        }
        var candidate = enabledHomeModules
        if enabled {
            candidate.insert(module)
        } else if candidate.count > 1 {
            guard canDisableHomeModule?(module) ?? true else {
                settingsError = "录音进行中，暂时不能隐藏快速录音模块"
                return
            }
            candidate.remove(module)
        } else {
            settingsError = "首页至少保留一个模块"
            return
        }
        let visible = homeModuleOrder.filter { candidate.contains($0) && $0 != .completions }
        let sizes = normalizeHomeModuleSizes(homeModuleSizes, visibleModules: visible, preferred: nil)
        let spans = visible.map {
            let size = sizes[$0] ?? Self.defaultSize(for: $0)
            return HomeGridSpan(columns: size.columns, rows: size.rows)
        }
        guard spans.isEmpty || HomeLayoutEngine.resolve(spans: spans) != nil else {
            settingsError = "这组组件暂时无法铺满首页，设置没有更改"
            return
        }
        enabledHomeModules = candidate
        enabledFeatures.remove(module.feature)
        enabledFeatures.insert(.home)
        UserDefaults.standard.set(WorkspacePlacement.home.rawValue, forKey: "workspace-placement-\(module.feature.rawValue)")
        persist(enabled, forKey: module.defaultsKey)
    }

    func normalizedHomeModuleSizes(for visibleModules: [HomeModule]) -> [HomeModule: HomeModuleSize] {
        normalizeHomeModuleSizes(homeModuleSizes, visibleModules: visibleModules, preferred: nil)
    }

    func cycleHomeModuleSize(_ module: HomeModule, visibleModules: [HomeModule]) {
        guard !homeLayoutReadOnly, visibleModules.contains(module) else { return }
        var candidate = homeModuleSizes
        let allowed = Self.allowedSizes(for: module)
        let current = candidate[module] ?? Self.defaultSize(for: module)
        let index = allowed.firstIndex(of: current) ?? 0
        candidate[module] = allowed[(index + 1) % allowed.count]
        candidate = normalizeHomeModuleSizes(candidate, visibleModules: visibleModules, preferred: module)
        guard visibleModules.reduce(0, { $0 + (candidate[$1]?.area ?? 0) }) <= 48,
              canPackHomeModules(candidate, visibleModules: visibleModules) else {
            settingsError = "当前首页空间不足，无法继续放大这个模块"
            return
        }
        homeModuleSizes = candidate
        for visibleModule in visibleModules {
            persist(candidate[visibleModule]?.rawValue, forKey: "home-module-size-\(visibleModule)")
        }
    }

    func orderedVisibleModules(includeCompletions: Bool) -> [HomeModule] {
        homeModuleOrder.filter {
            enabledHomeModules.contains($0) && ($0 != .completions || includeCompletions)
        }
    }

    func moveHomeModules(fromOffsets: IndexSet, toOffset: Int) {
        guard !homeLayoutReadOnly else { return }
        homeModuleOrder = Self.moving(homeModuleOrder, fromOffsets: fromOffsets, toOffset: toOffset)
        persist(homeModuleOrder.map(\.rawValue), forKey: "home-module-order")
    }

    func moveVisibleHomeModules(fromOffsets: IndexSet, toOffset: Int) {
        guard !homeLayoutReadOnly else { return }
        let visible = homeModuleOrder.filter(enabledHomeModules.contains)
        let reordered = Self.moving(visible, fromOffsets: fromOffsets, toOffset: toOffset)
        var iterator = reordered.makeIterator()
        homeModuleOrder = homeModuleOrder.map { enabledHomeModules.contains($0) ? (iterator.next() ?? $0) : $0 }
        persist(homeModuleOrder.map(\.rawValue), forKey: "home-module-order")
    }

    func setHomeModuleSize(_ module: HomeModule, size: HomeModuleSize) {
        guard canResizeHomeModules else {
            settingsError = "隐藏组件时由系统自动铺满；全部显示后才能设置单个尺寸"
            return
        }
        guard Self.allowedSizes(for: module).contains(size) else {
            settingsError = "常用指令最小尺寸为中"
            return
        }
        let visible = orderedVisibleModules(includeCompletions: true)
        var candidate = homeModuleSizes
        candidate[module] = size
        candidate = normalizeHomeModuleSizes(candidate, visibleModules: visible, preferred: module)
        guard canPackHomeModules(candidate, visibleModules: visible) else {
            settingsError = "这个尺寸组合无法完整铺满首页"
            return
        }
        homeModuleSizes = candidate
        for item in visible {
            persist(candidate[item]?.rawValue, forKey: "home-module-size-\(item)")
        }
    }

    var usesAutomaticHomeLayout: Bool {
        false
    }

    var canResizeHomeModules: Bool {
        !homeLayoutReadOnly
    }

    func resetHomeLayout() {
        homeModuleOrder = Self.defaultHomeModuleOrder
        let rawSizes = Dictionary(uniqueKeysWithValues: HomeModule.allCases.map {
            ($0, Self.defaultSize(for: $0))
        })
        homeModuleSizes = normalizeHomeModuleSizes(
            rawSizes,
            visibleModules: homeModuleOrder.filter(enabledHomeModules.contains),
            preferred: nil
        )
        homeLayoutReadOnly = false
        persist(homeModuleOrder.map(\.rawValue), forKey: "home-module-order")
        for module in HomeModule.allCases {
            persist(homeModuleSizes[module]?.rawValue, forKey: "home-module-size-\(module)")
        }
        settingsError = "首页模块顺序和尺寸已恢复默认"
    }

    func resetWorkspaceLayout() {
        let defaultHome: Set<HomeModule> = [
            .music, .pomodoro, .recorder, .windows, .clock, .calendar,
        ]
        let defaultTabs = Set(Feature.movableCases.filter { feature in
            guard let module = feature.homeModule else { return true }
            return !defaultHome.contains(module)
        })
        featureOrder = Feature.allCases
        enabledFeatures = defaultTabs.union([.home, .settings])
        enabledHomeModules = defaultHome
        homeModuleSizes = normalizeHomeModuleSizes(
            homeModuleSizes,
            visibleModules: homeModuleOrder.filter(defaultHome.contains),
            preferred: nil
        )
        persist(featureOrder.map(\.rawValue), forKey: "feature-order")
        for module in defaultHome {
            persist(homeModuleSizes[module]?.rawValue, forKey: "home-module-size-\(module)")
        }
        for feature in Feature.movableCases {
            guard let module = feature.homeModule else { continue }
            let placement: WorkspacePlacement = defaultHome.contains(module) ? .home : .tab
            UserDefaults.standard.set(placement.rawValue, forKey: "workspace-placement-\(feature.rawValue)")
            UserDefaults.standard.set(placement == .tab, forKey: feature.defaultsKey)
            UserDefaults.standard.set(placement == .home, forKey: module.defaultsKey)
        }
        settingsError = "功能位置和顶部顺序已恢复默认"
    }

    @discardableResult
    func swapHomeModules(_ source: HomeModule, _ target: HomeModule, visibleModules: [HomeModule]) -> Bool {
        guard !homeLayoutReadOnly,
              let sourceIndex = homeModuleOrder.firstIndex(of: source),
              let targetIndex = homeModuleOrder.firstIndex(of: target),
              sourceIndex != targetIndex else { return false }
        let previous = homeModuleOrder
        homeModuleOrder.swapAt(sourceIndex, targetIndex)
        let reorderedVisible = homeModuleOrder.filter { visibleModules.contains($0) }
        let sizes = normalizedHomeModuleSizes(for: reorderedVisible)
        let spans = reorderedVisible.map {
            let size = sizes[$0] ?? Self.defaultSize(for: $0)
            return HomeGridSpan(columns: size.columns, rows: size.rows)
        }
        guard HomeLayoutEngine.resolve(spans: spans) != nil else {
            homeModuleOrder = previous
            settingsError = "布局未更新，请重试"
            return false
        }
        persist(homeModuleOrder.map(\.rawValue), forKey: "home-module-order")
        return true
    }

    private static func defaultSize(for module: HomeModule) -> HomeModuleSize {
        switch module {
        case .memo, .clipboard, .links, .recordings, .credentials: return .medium
        case .music, .mirror, .note, .clock, .calendar: return .medium
        case .commands: return .medium
        case .pomodoro, .completions: return .mini
        case .recorder: return .small
        case .windows: return .large
        }
    }

    private func normalizeHomeModuleSizes(
        _ source: [HomeModule: HomeModuleSize],
        visibleModules: [HomeModule],
        preferred: HomeModule?
    ) -> [HomeModule: HomeModuleSize] {
        var result = source
        for module in visibleModules {
            let current = result[module] ?? Self.defaultSize(for: module)
            if !Self.allowedSizes(for: module).contains(current) {
                result[module] = Self.defaultSize(for: module)
            }
        }
        let siblings = visibleModules.filter { $0 != preferred }
        func totalArea() -> Int {
            visibleModules.reduce(0) { $0 + (result[$1] ?? Self.defaultSize(for: $1)).area }
        }

        while totalArea() > 48 {
            let excess = totalArea() - 48
            let candidate = siblings.compactMap { module -> (HomeModule, HomeModuleSize, Int)? in
                let current = result[module] ?? Self.defaultSize(for: module)
                guard let smaller = Self.adjacentAllowedSize(for: module, from: current, growing: false) else { return nil }
                let reduction = current.area - smaller.area
                return reduction <= excess ? (module, smaller, reduction) : nil
            }.max { $0.2 < $1.2 }
            guard let candidate else { break }
            result[candidate.0] = candidate.1
        }

        while totalArea() < 48 {
            let remaining = 48 - totalArea()
            let candidate = siblings.compactMap { module -> (HomeModule, HomeModuleSize, Int)? in
                let current = result[module] ?? Self.defaultSize(for: module)
                guard let larger = Self.adjacentAllowedSize(for: module, from: current, growing: true) else { return nil }
                let increase = larger.area - current.area
                return increase <= remaining ? (module, larger, increase) : nil
            }.max { $0.2 < $1.2 }
            guard let candidate else { break }
            result[candidate.0] = candidate.1
        }
        return result
    }

    private func canPackHomeModules(
        _ sizes: [HomeModule: HomeModuleSize],
        visibleModules: [HomeModule]
    ) -> Bool {
        let spans = visibleModules.map {
            let size = sizes[$0] ?? Self.defaultSize(for: $0)
            return HomeGridSpan(columns: size.columns, rows: size.rows)
        }
        return HomeLayoutEngine.resolve(spans: spans) != nil
    }

    private static let defaultHomeModuleOrder: [HomeModule] = [
        .memo, .clipboard, .links, .recordings, .credentials,
        .music, .pomodoro, .windows, .recorder, .mirror, .note, .commands, .clock, .calendar, .completions,
    ]

    func allowedHomeModuleSizes(for module: HomeModule) -> [HomeModuleSize] {
        Self.allowedSizes(for: module)
    }

    private static func allowedSizes(for module: HomeModule) -> [HomeModuleSize] {
        switch module {
        case .commands, .memo, .clipboard, .links, .recordings, .credentials, .calendar:
            return [.medium, .large]
        default:
            return HomeModuleSize.allCases
        }
    }

    private static func adjacentAllowedSize(
        for module: HomeModule,
        from size: HomeModuleSize,
        growing: Bool
    ) -> HomeModuleSize? {
        let values = allowedSizes(for: module)
        guard let index = values.firstIndex(of: size) else { return defaultSize(for: module) }
        let nextIndex = growing ? index + 1 : index - 1
        guard values.indices.contains(nextIndex) else { return nil }
        return values[nextIndex]
    }

    private static let defaultMemoCategories: [MemoCategory] = [
        MemoCategory(id: "memo-category-course", name: "课程", colorHex: "#0A84FF"),
        MemoCategory(id: "memo-category-writing", name: "自媒体&写作", colorHex: "#BF5AF2"),
        MemoCategory(id: "memo-category-coding", name: "Vibe coding", colorHex: "#30D978"),
        MemoCategory(id: "memo-category-daily", name: "日常", colorHex: "#FF9F0A"),
    ]

    private static func defaultPriorityName(_ priority: TaskPriority) -> String {
        switch priority {
        case .blue: return "普通"
        case .yellow: return "一般"
        case .orange: return "重要"
        case .red: return "紧急"
        }
    }

    private static func defaultPriorityColorHex(_ priority: TaskPriority) -> String {
        switch priority {
        case .blue: return "#0A84FF"
        case .yellow: return "#FFD60A"
        case .orange: return "#FF9F0A"
        case .red: return "#FF453A"
        }
    }

    private func persistPriorityAppearance() {
        UserDefaults.standard.set(
            Dictionary(uniqueKeysWithValues: priorityNames.map { ($0.key.rawValue, $0.value) }),
            forKey: "task-priority-names"
        )
        UserDefaults.standard.set(
            Dictionary(uniqueKeysWithValues: priorityColorHexes.map { ($0.key.rawValue, $0.value) }),
            forKey: "task-priority-colors"
        )
    }

    private func persistMemoCategories() {
        if let data = try? JSONEncoder().encode(memoCategories) {
            UserDefaults.standard.set(data, forKey: "memo-categories-v1")
        }
    }

    private static func moving<T>(_ source: [T], fromOffsets: IndexSet, toOffset: Int) -> [T] {
        let movingItems = fromOffsets.sorted().map { source[$0] }
        var result = source
        for index in fromOffsets.sorted(by: >) { result.remove(at: index) }
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        let destination = min(max(0, toOffset - removedBeforeDestination), result.count)
        result.insert(contentsOf: movingItems, at: destination)
        return result
    }

    private func persist(_ value: Any?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        homeLayoutPersisted = UserDefaults.standard.synchronize()
    }

    private func applyAutoLaunch() {
        do {
            if autoLaunch {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            settingsError = "开机启动设置失败：\(error.localizedDescription)"
            autoLaunch = SMAppService.mainApp.status == .enabled
        }
    }
}
