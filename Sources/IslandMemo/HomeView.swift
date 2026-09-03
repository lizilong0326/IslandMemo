import AppKit
import LunarSwift
import SwiftUI

private struct BentoSpanKey: LayoutValueKey {
    static let defaultValue = HomeGridSpan(columns: 4, rows: 2)
}

private struct HomeBentoLayout: Layout {
    let columns = 12
    let spacing: CGFloat = 12
    let availableHeight: CGFloat

    private var rowHeight: CGFloat {
        // 与参考项目 repeat(4, minmax(0, 1fr)) + height: 100% 一致：
        // 四行共同分完首页全部可用高度。
        max(58, (availableHeight - spacing * 3) / 4)
    }

    private func placements(for subviews: Subviews) -> [HomeGridPlacement] {
        let spans = subviews.map { $0[BentoSpanKey.self] }
        return HomeLayoutEngine.resolve(spans: spans) ?? []
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? IslandTheme.panelWidth
        return CGSize(
            width: width,
            height: 4 * rowHeight + 3 * spacing
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let cellWidth = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let layout = placements(for: subviews)
        for (index, item) in layout.enumerated() {
            let width = cellWidth * CGFloat(item.span.columns)
                + spacing * CGFloat(item.span.columns - 1)
            let height = rowHeight * CGFloat(item.span.rows)
                + spacing * CGFloat(item.span.rows - 1)
            let point = CGPoint(
                x: bounds.minX + CGFloat(item.column) * (cellWidth + spacing),
                y: bounds.minY + CGFloat(item.row) * (rowHeight + spacing)
            )
            subviews[index].place(
                at: point,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: height)
            )
        }
    }
}

private struct HomeModuleFrameKey: PreferenceKey {
    static let defaultValue: [AppSettingsStore.HomeModule: CGRect] = [:]

    static func reduce(
        value: inout [AppSettingsStore.HomeModule: CGRect],
        nextValue: () -> [AppSettingsStore.HomeModule: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum HomeModuleVariant {
    case mini, compact, wide, tall, full

    init(span: HomeGridSpan) {
        if span.rows == 1 || span.columns <= 2 { self = .mini }
        else if span.columns >= 8 && span.rows <= 2 { self = .wide }
        else if span.columns >= 6 && span.rows >= 4 { self = .full }
        else if span.rows >= 4 { self = .tall }
        else { self = .compact }
    }
}

private enum LunarCalendarText {
    private static let monthNames = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let dayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
    ]
    private static let festivals = [
        "1-1": "春节", "1-15": "元宵", "5-5": "端午", "7-7": "七夕",
        "8-15": "中秋", "9-9": "重阳", "12-8": "腊八",
    ]
    private static let heavenlyStems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let earthlyBranches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .chinese)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    static func short(for date: Date) -> String {
        let components = components(for: date)
        guard let month = components.month, let day = components.day,
              monthNames.indices.contains(month - 1), dayNames.indices.contains(day - 1) else { return "" }
        if components.isLeapMonth != true, let festival = festivals["\(month)-\(day)"] { return festival }
        if day == 1 { return (components.isLeapMonth == true ? "闰" : "") + monthNames[month - 1] }
        return dayNames[day - 1]
    }

    static func full(for date: Date) -> String {
        let components = components(for: date)
        guard let month = components.month, let day = components.day,
              monthNames.indices.contains(month - 1), dayNames.indices.contains(day - 1) else { return "农历日期不可用" }
        let cycleYear = max(1, components.year ?? 1) - 1
        let yearName = heavenlyStems[cycleYear % heavenlyStems.count]
            + earthlyBranches[cycleYear % earthlyBranches.count]
        let leap = components.isLeapMonth == true ? "闰" : ""
        let festival = components.isLeapMonth == true ? nil : festivals["\(month)-\(day)"]
        return "农历 \(yearName)年 \(leap)\(monthNames[month - 1])\(dayNames[day - 1])"
            + (festival.map { " · \($0)" } ?? "")
    }

    private static func components(for date: Date) -> DateComponents {
        // 请求月份时 Foundation 会一并填充 DateComponents.isLeapMonth；
        // 不直接使用 macOS 14 才新增的 Calendar.Component.isLeapMonth，保持 macOS 13 兼容。
        calendar.dateComponents([.year, .month, .day], from: date)
    }
}

private struct AlmanacInfo {
    let yi: [String]
    let ji: [String]
    let ganZhi: String
    let chongSha: String
    let duty: String
    let directions: String
    let pengZu: String
    let solarTerm: String?

    init(date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let solar = Solar.fromYmdHms(
            year: components.year ?? 2000,
            month: components.month ?? 1,
            day: components.day ?? 1,
            hour: 12
        )
        let lunar = solar.lunar
        yi = lunar.dayYi
        ji = lunar.dayJi
        ganZhi = "\(lunar.yearInGanZhi)年 · \(lunar.monthInGanZhi)月 · \(lunar.dayInGanZhi)日"
        chongSha = "冲\(lunar.dayChongDesc) · 煞\(lunar.daySha)"
        duty = "\(lunar.zhiXing)日 · \(lunar.dayTianShen)（\(lunar.dayTianShenLuck)）"
        directions = "喜神\(lunar.dayPositionXiDesc) · 财神\(lunar.dayPositionCaiDesc) · 福神\(lunar.dayPositionFuDesc)"
        pengZu = "\(lunar.pengZuGan)；\(lunar.pengZuZhi)"
        solarTerm = lunar.jieQi.isEmpty ? nil : lunar.jieQi
    }
}

struct AnalogClockFace: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side * 0.43
            let calendar = Calendar.current
            let hour = Double(calendar.component(.hour, from: date) % 12)
            let minute = Double(calendar.component(.minute, from: date))
            let second = Double(calendar.component(.second, from: date))

            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(.white.opacity(0.12)),
                lineWidth: 1
            )

            for tick in 0..<60 {
                let angle = Double(tick) * .pi / 30 - .pi / 2
                let major = tick % 5 == 0
                let outer = point(center: center, radius: radius, angle: angle)
                let inner = point(center: center, radius: radius - (major ? side * 0.055 : side * 0.025), angle: angle)
                var path = Path()
                path.move(to: inner)
                path.addLine(to: outer)
                context.stroke(
                    path,
                    with: .color(.white.opacity(major ? 0.55 : 0.16)),
                    style: StrokeStyle(lineWidth: major ? 1.6 : 0.7, lineCap: .round)
                )
            }

            drawHand(
                in: &context,
                center: center,
                radius: radius * 0.52,
                angle: (hour + minute / 60) * .pi / 6 - .pi / 2,
                width: 4,
                color: .white.opacity(0.92)
            )
            drawHand(
                in: &context,
                center: center,
                radius: radius * 0.74,
                angle: (minute + second / 60) * .pi / 30 - .pi / 2,
                width: 2.7,
                color: .white.opacity(0.82)
            )
            drawHand(
                in: &context,
                center: center,
                radius: radius * 0.8,
                angle: second * .pi / 30 - .pi / 2,
                width: 1.2,
                color: IslandTheme.accentBlue
            )
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                with: .color(IslandTheme.accentBlue)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Text(date, format: .dateTime.hour().minute().second()))
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }

    private func drawHand(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        angle: Double,
        width: CGFloat,
        color: Color
    ) {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center: center, radius: radius, angle: angle))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

private extension View {
    func homeBentoSpan(columns: Int, rows: Int) -> some View {
        GeometryReader { geometry in
            self
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .topLeading
                )
                // 普通 SwiftUI 内容会按自身理想高度收缩；外层补齐同一张卡片背景，
                // 保证相同 row span 的模块视觉高度严格一致。
                .background(
                    IslandTheme.surface1,
                    in: RoundedRectangle(cornerRadius: IslandTheme.radiusTile)
                )
                .clipShape(RoundedRectangle(cornerRadius: IslandTheme.radiusTile))
        }
            // Layout value 必须挂在最外层，否则 Frame/Clipped 容器会让
            // HomeBentoLayout 只能读到默认尺寸。
            .layoutValue(key: BentoSpanKey.self, value: HomeGridSpan(columns: columns, rows: rows))
    }
}

/// 首页 Bento 工作台：时钟、番茄钟、音乐、镜子、快速录音、常用指令、当前窗口、AI 完成提醒。
/// 对应 TO-DO-Panel 的首页：12 列 × 4 行、密排、撑满可用高度。
struct HomeView: View {
    @ObservedObject var tasks: TaskStore
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var links: LinksStore
    @ObservedObject var credentials: CredentialsStore
    @ObservedObject var pomodoro: PomodoroStore
    @ObservedObject var music: MusicService
    @ObservedObject var windows: WindowListService
    @ObservedObject var commands: CommandsStore
    @ObservedObject var recordings: RecordingStore
    @ObservedObject var notifyServer: AgentNotifyServer
    @ObservedObject var codexStatus: CodexStatusStore
    @ObservedObject var panelMetrics: PanelMetrics
    @ObservedObject var settings: AppSettingsStore
    var standaloneModule: AppSettingsStore.HomeModule? = nil

    @State private var now = Date()
    @State private var newCommand = ""
    @State private var memoDraft = ""
    @FocusState private var memoDraftFocused: Bool
    @AppStorage("home-quick-note") private var quickNote = ""
    @State private var calendarMonth = Date()
    @State private var selectedCalendarDate = Date()
    @State private var selectedAlmanac = AlmanacInfo(date: Date())
    @State private var hoveredModule: AppSettingsStore.HomeModule?
    @State private var draggingModule: AppSettingsStore.HomeModule?
    @State private var dragTargetModule: AppSettingsStore.HomeModule?
    @State private var dragTranslation: CGSize = .zero
    @State private var moduleFrames: [AppSettingsStore.HomeModule: CGRect] = [:]
    @State private var statusMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var showsCompletions: Bool {
        settings.isHomeModuleEnabled(.completions)
    }

    private var visibleHomeModules: [AppSettingsStore.HomeModule] {
        settings.orderedVisibleModules(includeCompletions: showsCompletions)
    }

    private var effectiveModuleSizes: [AppSettingsStore.HomeModule: AppSettingsStore.HomeModuleSize] {
        settings.normalizedHomeModuleSizes(for: visibleHomeModules)
    }

    var body: some View {
        Group {
            if let standaloneModule {
                moduleContent(standaloneModule, variant: .full)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        HomeBentoLayout(availableHeight: geometry.size.height) {
                            ForEach(visibleHomeModules) { module in
                                resizableModule(module)
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .coordinateSpace(name: "home-grid")
                        .onPreferenceChange(HomeModuleFrameKey.self) { moduleFrames = $0 }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(IslandTheme.text1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.78), in: Capsule())
                                .overlay(Capsule().stroke(IslandTheme.hairline, lineWidth: 1))
                                .padding(.bottom, 8)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
            }
        }
        .onReceive(clockTimer) { now = $0 }
        .onAppear {
            windows.refresh()
            music.refreshStatus()
        }
        .onChange(of: tasks.focusAddRequest) { _ in
            guard settings.workspacePlacement(for: .memo) == .home else { return }
            DispatchQueue.main.async { memoDraftFocused = true }
        }
    }

    private func resizableModule(_ module: AppSettingsStore.HomeModule) -> some View {
        let size = effectiveModuleSizes[module] ?? .small
        let span = HomeGridSpan(columns: size.columns, rows: size.rows)
        let variant = HomeModuleVariant(span: span)
        return moduleContent(module, variant: variant)
            // 模块自身的刷新、翻页等操作通常位于右上角；统一尺寸按钮放在右下角，
            // 避免 hover 后覆盖业务按钮。
            .overlay(alignment: .bottomTrailing) {
                if settings.canResizeHomeModules {
                    Button {
                        animateLayout {
                            settings.cycleHomeModuleSize(module, visibleModules: visibleHomeModules)
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(IslandTheme.text3)
                            .frame(width: 23, height: 23)
                            .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(IslandTheme.hairlineSoft, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("组件尺寸：\(size.label)，点击切换")
                    .opacity(hoveredModule == module ? 1 : 0)
                    .allowsHitTesting(hoveredModule == module)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: IslandTheme.radiusTile)
                    .stroke(
                        dragTargetModule == module ? IslandTheme.accentBlue : Color.clear,
                        lineWidth: 2
                    )
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HomeModuleFrameKey.self,
                        value: [module: proxy.frame(in: .named("home-grid"))]
                    )
                }
            }
            .offset(draggingModule == module ? dragTranslation : .zero)
            .scaleEffect(draggingModule == module ? 1.025 : 1)
            .shadow(color: .black.opacity(draggingModule == module ? 0.42 : 0), radius: 18, y: 8)
            .zIndex(draggingModule == module ? 10 : 0)
            .onHover { hovering in hoveredModule = hovering ? module : (hoveredModule == module ? nil : hoveredModule) }
            .simultaneousGesture(reorderGesture(for: module))
            .homeBentoSpan(columns: span.columns, rows: span.rows)
    }

    @ViewBuilder
    private func moduleContent(_ module: AppSettingsStore.HomeModule, variant: HomeModuleVariant) -> some View {
        switch module {
        case .memo: memoWidgetCard(variant)
        case .clipboard: clipboardWidgetCard(variant)
        case .links: linksWidgetCard(variant)
        case .recordings: recordingsWidgetCard(variant)
        case .credentials: credentialsWidgetCard(variant)
        case .music: musicCard(variant)
        case .pomodoro: pomodoroCard(variant)
        case .recorder: quickRecordCard(variant)
        case .windows: windowsCard(variant)
        case .mirror: mirrorCard
        case .note: noteCard(variant)
        case .commands: commandsCard(variant)
        case .clock: clockCard(variant)
        case .calendar: calendarCard(variant)
        case .completions: completionsCard(variant)
        }
    }

    // MARK: - 一级页面的首页卡片形态

    private func memoWidgetCard(_ variant: HomeModuleVariant) -> some View {
        let items = Array(tasks.activeTasks.filter { !$0.isCompleted }.prefix(variant == .full ? 8 : 3))
        return VStack(alignment: .leading, spacing: 8) {
            cardLabel("备忘录", systemImage: "checklist")
            if items.isEmpty {
                Text("暂无未完成任务").font(.caption).foregroundStyle(IslandTheme.text4)
            } else {
                ForEach(items) { task in
                    Button { tasks.toggle(task) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "circle").foregroundStyle(IslandTheme.text3)
                            Text(task.title).lineLimit(1).foregroundStyle(IslandTheme.text2)
                            Spacer()
                            if let dueDate = task.dueDate {
                                Text(dueDate, format: .dateTime.month().day().hour().minute())
                                    .font(.caption2).foregroundStyle(IslandTheme.text4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if variant != .mini {
                HStack(spacing: 7) {
                    TextField("新建任务", text: $memoDraft)
                        .textFieldStyle(.plain)
                        .focused($memoDraftFocused)
                        .onSubmit(addMemoWidgetTask)
                    Button(action: addMemoWidgetTask) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(memoDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(IslandTheme.surface2, in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer(minLength: 0)
        }
        .tileStyle()
    }

    private func addMemoWidgetTask() {
        let categoryID = settings.memoCategoriesEnabled ? settings.memoCategories.first?.id : nil
        tasks.add(title: memoDraft, dueDate: nil, categoryID: categoryID)
        memoDraft = ""
    }

    private func clipboardWidgetCard(_ variant: HomeModuleVariant) -> some View {
        let items = Array(clipboard.entries.prefix(variant == .full ? 10 : 4))
        return VStack(alignment: .leading, spacing: 8) {
            cardLabel("复制记录", systemImage: "doc.on.clipboard")
            if items.isEmpty {
                Text("复制内容后会出现在这里").font(.caption).foregroundStyle(IslandTheme.text4)
            } else {
                ForEach(items) { entry in
                    Button { clipboard.copy(entry) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: entry.kind == .image ? "photo" : "doc.text")
                                .foregroundStyle(IslandTheme.text3)
                            Text(entry.kind == .image ? "图片" : (entry.text ?? ""))
                                .lineLimit(1).foregroundStyle(IslandTheme.text2)
                            Spacer()
                            Image(systemName: "doc.on.doc").foregroundStyle(IslandTheme.text4)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .tileStyle()
    }

    private func linksWidgetCard(_ variant: HomeModuleVariant) -> some View {
        let items = Array(links.groups.flatMap(\.links).prefix(variant == .full ? 10 : 4))
        return VStack(alignment: .leading, spacing: 8) {
            cardLabel("链接", systemImage: "link")
            if items.isEmpty {
                Text("暂无收藏链接").font(.caption).foregroundStyle(IslandTheme.text4)
            } else {
                ForEach(items) { link in
                    Button { links.open(link) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "globe").foregroundStyle(IslandTheme.text3)
                            Text(link.title).lineLimit(1).foregroundStyle(IslandTheme.text2)
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(IslandTheme.text4)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .tileStyle()
    }

    private func recordingsWidgetCard(_ variant: HomeModuleVariant) -> some View {
        let items = Array(recordings.recordings.prefix(variant == .full ? 8 : 3))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                cardLabel("录制", systemImage: "waveform")
                Spacer()
                Button { recordings.toggleRecording() } label: {
                    Image(systemName: recordings.state == .idle ? "record.circle" : "stop.circle.fill")
                        .foregroundStyle(recordings.state == .idle ? IslandTheme.p0 : IslandTheme.text1)
                }.buttonStyle(.plain)
            }
            if items.isEmpty {
                Text("暂无录音").font(.caption).foregroundStyle(IslandTheme.text4)
            } else {
                ForEach(items) { recording in
                    HStack {
                        Text(recording.title).lineLimit(1).foregroundStyle(IslandTheme.text2)
                        Spacer()
                        Text(recording.createdAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption2).foregroundStyle(IslandTheme.text4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .tileStyle()
    }

    private func credentialsWidgetCard(_ variant: HomeModuleVariant) -> some View {
        let items = Array(credentials.credentials.prefix(variant == .full ? 10 : 4))
        return VStack(alignment: .leading, spacing: 8) {
            cardLabel("密钥", systemImage: "key")
            if items.isEmpty {
                Text("暂无密钥").font(.caption).foregroundStyle(IslandTheme.text4)
            } else {
                ForEach(items) { credential in
                    HStack(spacing: 7) {
                        Image(systemName: "key.fill").foregroundStyle(IslandTheme.accentOrange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(credential.service).lineLimit(1).foregroundStyle(IslandTheme.text2)
                            Text(credential.account).lineLimit(1).font(.caption2).foregroundStyle(IslandTheme.text4)
                        }
                        Spacer()
                        Button { credentials.copyPassword(credential) } label: {
                            Image(systemName: "doc.on.doc")
                        }.buttonStyle(.borderless).help("复制密钥")
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .tileStyle()
    }

    private func reorderGesture(for module: AppSettingsStore.HomeModule) -> some Gesture {
        LongPressGesture(minimumDuration: 0.42, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("home-grid")))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if draggingModule == nil {
                    draggingModule = module
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                dragTranslation = drag.translation
                dragTargetModule = moduleFrames.first(where: { target, frame in
                    target != module && frame.contains(drag.location)
                })?.key
            }
            .onEnded { value in
                var target = dragTargetModule
                if case .second(true, let drag?) = value {
                    target = moduleFrames.first(where: { candidate, frame in
                        candidate != module && frame.contains(drag.location)
                    })?.key ?? target
                }
                if let target {
                    animateLayout {
                        if settings.swapHomeModules(module, target, visibleModules: visibleHomeModules) {
                            showStatus("已调整首页模块位置")
                        } else {
                            showStatus("布局未改变")
                        }
                    }
                }
                draggingModule = nil
                dragTargetModule = nil
                dragTranslation = .zero
            }
    }

    private func animateLayout(_ changes: () -> Void) {
        if reduceMotion { changes() }
        else { withAnimation(.spring(response: 0.32, dampingFraction: 0.82), changes) }
    }

    private func showStatus(_ message: String) {
        withAnimation(.easeOut(duration: 0.16)) { statusMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard statusMessage == message else { return }
            withAnimation(.easeIn(duration: 0.16)) { statusMessage = nil }
        }
    }

    // MARK: - 时钟

    @ViewBuilder
    private func clockCard(_ variant: HomeModuleVariant) -> some View {
        if settings.clockStyle == .analog {
            analogClockCard(variant)
        } else {
            digitalClockCard(variant)
        }
    }

    private func digitalClockCard(_ variant: HomeModuleVariant) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if variant != .mini {
                HStack {
                    Text("LOCAL TIME")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(IslandTheme.text4)
                    Spacer()
                    Text(now, format: .dateTime.month().day().weekday(.abbreviated))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(IslandTheme.text3)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: standaloneModule == .clock ? 68 : (variant == .mini ? 23 : 38), weight: .medium, design: .rounded))
                    .tracking(-1.1)
                    .monospacedDigit()
                    .foregroundStyle(IslandTheme.text1)
                Text(String(format: "%02d", Calendar.current.component(.second, from: now)))
                    .font(.system(size: standaloneModule == .clock ? 18 : (variant == .mini ? 10 : 13), weight: .semibold, design: .monospaced))
                    .foregroundStyle(IslandTheme.accentBlue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(IslandTheme.accentBlue.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(IslandTheme.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [IslandTheme.surface2, IslandTheme.surface1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func analogClockCard(_ variant: HomeModuleVariant) -> some View {
        Group {
            switch variant {
            case .mini:
                AnalogClockFace(date: now)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .compact:
                HStack(spacing: 14) {
                    AnalogClockFace(date: now)
                        .frame(maxWidth: 112, maxHeight: .infinity)
                    analogClockDetails(timeSize: 24, centered: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .wide:
                HStack(spacing: 18) {
                    AnalogClockFace(date: now)
                        .frame(maxWidth: 118, maxHeight: .infinity)
                    Rectangle()
                        .fill(IslandTheme.hairlineSoft)
                        .frame(width: 1, height: 56)
                    analogClockDetails(timeSize: 32, centered: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .tall:
                VStack(spacing: 12) {
                    AnalogClockFace(date: now)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    analogClockDetails(timeSize: 27, centered: true)
                }
            case .full:
                HStack(spacing: 22) {
                    AnalogClockFace(date: now)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    analogClockDetails(timeSize: 34, centered: false)
                        .frame(minWidth: 116, maxWidth: 150, alignment: .leading)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RadialGradient(
                colors: [IslandTheme.surface3.opacity(0.7), IslandTheme.surface1],
                center: .leading,
                startRadius: 0,
                endRadius: 180
            )
        )
    }

    private func analogClockDetails(timeSize: CGFloat, centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 5) {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: timeSize, weight: .medium, design: .rounded))
                    .tracking(-0.8)
                    .monospacedDigit()
                    .foregroundStyle(IslandTheme.text1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(String(format: "%02d", Calendar.current.component(.second, from: now)))
                    .font(.system(size: max(9, timeSize * 0.38), weight: .semibold, design: .monospaced))
                    .foregroundStyle(IslandTheme.accentBlue)
            }
            Text(now, format: .dateTime.month().day().weekday(.wide))
                .font(.caption.weight(.medium))
                .foregroundStyle(IslandTheme.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    // MARK: - 日历

    private func calendarCard(_ variant: HomeModuleVariant) -> some View {
        let dates = calendarGridDates(for: calendarMonth)
        let showsLunarInCells = standaloneModule == .calendar || variant == .tall || variant == .full
        let almanac = selectedAlmanac
        if standaloneModule == .calendar {
            return AnyView(
                HStack(alignment: .top, spacing: 14) {
                    calendarMonthContent(dates: dates, showsLunarInCells: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    Divider().overlay(IslandTheme.hairlineSoft)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            cardLabel("黄历", systemImage: "seal")
                            Spacer()
                            Text(selectedCalendarDate, format: .dateTime.month().day().weekday(.wide))
                                .font(.caption2)
                                .foregroundStyle(IslandTheme.text3)
                        }
                        Text(LunarCalendarText.full(for: selectedCalendarDate))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(IslandTheme.accentOrange)
                        almanacDetail(almanac)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .tileStyle()
            )
        }
        return AnyView(VStack(alignment: .leading, spacing: standaloneModule == .calendar ? 8 : 5) {
            HStack(spacing: 8) {
                cardLabel("日历", systemImage: "calendar")
                Spacer()
                if variant != .mini {
                    Button { moveCalendarMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                    Button("今天") { showCalendarToday() }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    Button { moveCalendarMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless)
                }
            }

            if variant == .mini {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(now, format: .dateTime.day())
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(IslandTheme.text1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(now, format: .dateTime.month(.wide).weekday(.wide))
                            .font(.caption)
                            .foregroundStyle(IslandTheme.text2)
                        Text(LunarCalendarText.full(for: now))
                            .font(.caption2)
                            .foregroundStyle(IslandTheme.accentOrange)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(calendarMonth.formatted(
                    Date.FormatStyle().year().month(.wide).locale(Locale(identifier: "zh_CN"))
                ))
                .font(standaloneModule == .calendar ? .title3.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(IslandTheme.text1)

                HStack(spacing: 0) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: standaloneModule == .calendar ? 10 : 8, weight: .medium))
                            .foregroundStyle(IslandTheme.text4)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                    ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                        calendarDayCell(date, showsLunar: showsLunarInCells)
                    }
                }

                HStack(spacing: 6) {
                    Text(selectedCalendarDate, format: .dateTime.month().day().weekday(.wide))
                        .foregroundStyle(IslandTheme.text2)
                    Text(LunarCalendarText.full(for: selectedCalendarDate))
                        .foregroundStyle(IslandTheme.accentOrange)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.caption2)

                if standaloneModule == .calendar {
                    almanacDetail(almanac)
                } else {
                    HStack(spacing: 8) {
                        Text("宜 \(almanac.yi.prefix(3).joined(separator: " · "))")
                            .foregroundStyle(IslandTheme.accentGreen)
                            .lineLimit(1)
                        Text("忌 \(almanac.ji.prefix(3).joined(separator: " · "))")
                            .foregroundStyle(IslandTheme.p0.opacity(0.9))
                            .lineLimit(1)
                    }
                    .font(.system(size: 8, weight: .medium))
                }
            }
            Spacer(minLength: 0)
        }
        .tileStyle())
    }

    private func calendarMonthContent(dates: [Date], showsLunarInCells: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                cardLabel("日历", systemImage: "calendar")
                Spacer()
                Button { moveCalendarMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Button("今天") { showCalendarToday() }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                Button { moveCalendarMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
            }
            Text(calendarMonth.formatted(
                Date.FormatStyle().year().month(.wide).locale(Locale(identifier: "zh_CN"))
            ))
            .font(.title3.weight(.semibold))
            .foregroundStyle(IslandTheme.text1)
            HStack(spacing: 0) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(IslandTheme.text4)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                    calendarDayCell(date, showsLunar: showsLunarInCells)
                }
            }
        }
    }

    private func almanacDetail(_ info: AlmanacInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    almanacActivities("宜", items: info.yi, color: IslandTheme.accentGreen)
                    almanacActivities("忌", items: info.ji, color: IslandTheme.p0)
                }
                Divider().overlay(IslandTheme.hairlineSoft)
                HStack(spacing: 12) {
                    almanacFact("干支", info.ganZhi)
                    almanacFact("冲煞", info.chongSha)
                }
                HStack(spacing: 12) {
                    almanacFact("值日", info.duty)
                    almanacFact("方位", info.directions)
                }
                almanacFact("彭祖百忌", info.pengZu)
                if let solarTerm = info.solarTerm {
                    almanacFact("节气", solarTerm)
                }
                Text("传统文化信息，仅供参考")
                    .font(.system(size: 8))
                    .foregroundStyle(IslandTheme.text4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .scrollIndicators(.automatic)
    }

    private func almanacActivities(_ title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text(items.isEmpty ? "无" : items.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(IslandTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func almanacFact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8, weight: .semibold)).foregroundStyle(IslandTheme.text4)
            Text(value).font(.caption2).foregroundStyle(IslandTheme.text2).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func calendarDayCell(_ date: Date, showsLunar: Bool) -> some View {
        let calendar = gregorianCalendar()
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedCalendarDate)
        let isCurrentMonth = calendar.isDate(date, equalTo: calendarMonth, toGranularity: .month)
        return Button {
            selectedCalendarDate = date
            selectedAlmanac = AlmanacInfo(date: date)
            if !isCurrentMonth { calendarMonth = date }
        } label: {
            VStack(spacing: 0) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: standaloneModule == .calendar ? 12 : 10, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isToday ? IslandTheme.accentBlue : IslandTheme.text1)
                if showsLunar {
                    Text(LunarCalendarText.short(for: date))
                        .font(.system(size: standaloneModule == .calendar ? 8 : 7))
                        .foregroundStyle(IslandTheme.text4)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: showsLunar ? (standaloneModule == .calendar ? 34 : 27) : 18)
            .background(isSelected ? IslandTheme.accentBlue.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 6).stroke(IslandTheme.accentBlue.opacity(0.7), lineWidth: 1)
                }
            }
            .opacity(isCurrentMonth ? 1 : 0.34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(date.formatted(date: .long, time: .omitted)) · \(LunarCalendarText.full(for: date))")
    }

    private func calendarGridDates(for month: Date) -> [Date] {
        let calendar = gregorianCalendar()
        guard let monthStart = calendar.dateInterval(of: .month, for: month)?.start else { return [] }
        let weekdayOffset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: monthStart) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func moveCalendarMonth(by offset: Int) {
        let calendar = gregorianCalendar()
        guard let nextMonth = calendar.date(byAdding: .month, value: offset, to: calendarMonth) else { return }
        let selectedDate = calendar.dateInterval(of: .month, for: nextMonth)?.start ?? nextMonth
        calendarMonth = nextMonth
        selectedCalendarDate = selectedDate
        selectedAlmanac = AlmanacInfo(date: selectedDate)
    }

    private func showCalendarToday() {
        calendarMonth = now
        selectedCalendarDate = now
        selectedAlmanac = AlmanacInfo(date: now)
    }

    private func gregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    // MARK: - 番茄钟

    private func pomodoroCard(_ variant: HomeModuleVariant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                cardLabel("番茄钟", systemImage: "timer")
                Spacer()
                if variant == .mini {
                    Button {
                        pomodoro.phase == .running ? pomodoro.pause() : pomodoro.start()
                    } label: {
                        Image(systemName: pomodoro.phase == .running ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if standaloneModule == .pomodoro { Spacer(minLength: 12) }
            Text(pomodoro.displayText)
                .font(.system(size: standaloneModule == .pomodoro ? 58 : (variant == .mini ? 22 : 28), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(IslandTheme.text1)
                .frame(maxWidth: standaloneModule == .pomodoro ? .infinity : nil)
            if variant != .mini {
                ProgressView(value: pomodoro.progress)
                    .tint(IslandTheme.accentBlue)
            }
            if variant != .mini {
            HStack(spacing: 8) {
                Button {
                    pomodoro.phase == .running ? pomodoro.pause() : pomodoro.start()
                } label: {
                    Image(systemName: pomodoro.phase == .running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .help(pomodoro.phase == .running ? "暂停" : "开始")

                Button { pomodoro.reset() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("重置")

                Spacer()

                Picker("", selection: $pomodoro.durationMinutes) {
                    ForEach(pomodoroDurationOptions, id: \.self) { minutes in
                        Text("\(minutes)分钟").tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .disabled(pomodoro.phase == .running)
            }
            .frame(maxWidth: standaloneModule == .pomodoro ? .infinity : nil)
            }
            if standaloneModule == .pomodoro { Spacer(minLength: 12) }
        }
        .tileStyle()
    }

    private var pomodoroDurationOptions: [Int] {
        Array(Set([5, 15, 25, 45, 60, pomodoro.durationMinutes])).sorted()
    }

    // MARK: - 音乐

    private func musicCard(_ variant: HomeModuleVariant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cardLabel(music.displayName, systemImage: "music.note")
            if music.isInstalled {
                if standaloneModule == .music {
                    Spacer(minLength: 12)
                    if let icon = music.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 58, height: 58)
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 16) {
                    if variant != .mini {
                        Button { music.control(.previous) } label: {
                            Image(systemName: "backward.fill")
                        }
                    }
                    Button { music.control(music.isPlaying ? .pause : .play) } label: {
                        Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                            .font(standaloneModule == .music ? .system(size: 30) : .title3)
                            .frame(width: standaloneModule == .music ? 58 : nil, height: standaloneModule == .music ? 58 : nil)
                            .background(standaloneModule == .music ? IslandTheme.accentBlue.opacity(0.18) : Color.clear, in: Circle())
                    }
                    if variant != .mini {
                        Button { music.control(.next) } label: {
                            Image(systemName: "forward.fill")
                        }
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(IslandTheme.text1)
                .frame(maxWidth: .infinity)
                .font(standaloneModule == .music ? .title2 : .body)
                if variant != .mini {
                    Text(music.isRunning ? (music.isPlaying ? "播放中" : "已暂停") : "未运行")
                        .font(.caption2)
                        .foregroundStyle(IslandTheme.text3)
                        .frame(maxWidth: .infinity)
                }
                if standaloneModule == .music { Spacer(minLength: 12) }
            } else {
                Text("请在设置中启用音乐服务")
                    .font(.caption)
                    .foregroundStyle(IslandTheme.text4)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .tileStyle()
    }

    // MARK: - 镜子

    private var mirrorCard: some View {
        MirrorView(panelMetrics: panelMetrics)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 快速录音

    private func quickRecordCard(_ variant: HomeModuleVariant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cardLabel("快速录音", systemImage: "mic.fill")
            if standaloneModule == .recorder { Spacer(minLength: 12) }
            Button { recordings.toggleRecording() } label: {
                HStack(spacing: 10) {
                    Image(systemName: recordings.state == .idle ? "record.circle" : "stop.circle.fill")
                        .font(.system(size: standaloneModule == .recorder ? 62 : 26))
                        .foregroundStyle(recordings.state == .idle ? IslandTheme.p0 : IslandTheme.text1)
                    if recordings.state != .idle {
                        Text(recordings.elapsedText)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(IslandTheme.text2)
                    } else if variant != .mini {
                        Text("点击开始")
                            .font(.caption)
                            .foregroundStyle(IslandTheme.text3)
                    }
                    if standaloneModule != .recorder { Spacer() }
                }
                .frame(maxWidth: standaloneModule == .recorder ? .infinity : nil)
            }
            .buttonStyle(.plain)
            if standaloneModule == .recorder { Spacer(minLength: 12) }
        }
        .tileStyle()
    }

    // MARK: - 常用指令

    private func commandsCard(_ variant: HomeModuleVariant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cardLabel("常用指令", systemImage: "command")
            if variant != .mini {
                TextField("添加指令，回车保存", text: $newCommand)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(IslandTheme.text1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(IslandTheme.surface2, in: RoundedRectangle(cornerRadius: IslandTheme.radiusInput))
                    .onSubmit {
                        commands.add(text: newCommand)
                        newCommand = ""
                    }
            }
            if !commands.commands.isEmpty {
                ScrollView {
                    VStack(spacing: 5) {
                    ForEach(commands.commands.prefix(standaloneModule == .commands ? Int.max : (variant == .mini ? 1 : (variant == .compact ? 2 : 4)))) { command in
                        Button { commands.copy(command) } label: {
                            HStack {
                                Text(command.text)
                                    .font(.caption)
                                    .foregroundStyle(IslandTheme.text2)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                                    .foregroundStyle(IslandTheme.text4)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(IslandTheme.surface2, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("点击复制：\(command.text)")
                    }
                    }
                }
                .scrollIndicators(standaloneModule == .commands ? .automatic : .never)
            }
        }
        .tileStyle()
    }

    // MARK: - 当前窗口

    private func windowsCard(_ variant: HomeModuleVariant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                cardLabel("当前窗口", systemImage: "macwindow")
                Spacer()
                Button { windows.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(IslandTheme.text3)
                }
                .buttonStyle(.borderless)
                .help("刷新")
            }
            if windows.needsScreenRecording {
                VStack(spacing: 9) {
                    Image(systemName: "rectangle.on.rectangle.slash")
                        .font(.system(size: standaloneModule == .windows ? 30 : 18))
                        .foregroundStyle(IslandTheme.text4)
                    Text("当前版本尚未获得“屏幕录制”权限")
                        .font(.caption)
                        .foregroundStyle(IslandTheme.text3)
                    Text(windows.screenRecordingRestartRequired
                         ? "权限已更改，请完全退出并重新打开丫丫灵动"
                         : "授权后请完全退出并重新打开丫丫灵动")
                        .font(.caption2)
                        .foregroundStyle(IslandTheme.text4)
                    HStack(spacing: 10) {
                        Button("申请权限") { windows.requestScreenRecording() }
                            .buttonStyle(.borderedProminent)
                        Button("打开系统设置") { WindowListService.openScreenRecordingSettings() }
                            .buttonStyle(.bordered)
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: standaloneModule == .windows ? .infinity : nil)
                .padding(.vertical, 6)
            } else if windows.windows.isEmpty {
                Text("没有读取到可切换窗口")
                    .font(.caption)
                    .foregroundStyle(IslandTheme.text4)
            } else {
                if !windows.hasDetailedWindowTitles {
                    HStack(spacing: 7) {
                        Image(systemName: "info.circle")
                        Text("暂未读取到窗口标题，仍可切换到对应应用")
                        Spacer(minLength: 0)
                    }
                    .font(.caption2)
                    .foregroundStyle(IslandTheme.text4)
                }
                if windows.needsAccessibility && variant != .mini {
                    HStack(spacing: 7) {
                        Image(systemName: "hand.raised")
                        Text("精确切换指定窗口需开启“辅助功能”")
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button("去授权") { windows.requestAccessibility() }
                            .buttonStyle(.borderless)
                    }
                    .font(.caption2)
                    .foregroundStyle(IslandTheme.text4)
                }
                ScrollView {
                    LazyVGrid(columns: windowGridColumns(for: variant), spacing: 6) {
                        ForEach(windows.windows.prefix(windowLimit(for: variant))) { window in
                        Button {
                            let switched = windows.focus(window)
                            showStatus(switched ? "已切换到 \(window.appName)" : "切换失败，请开启辅助功能权限")
                        } label: {
                            HStack(spacing: 8) {
                                if let icon = windows.icon(for: window) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                } else {
                                    Image(systemName: "app")
                                        .frame(width: 18, height: 18)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(window.appName)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(IslandTheme.text1)
                                    Text(window.title)
                                        .font(.caption2)
                                        .foregroundStyle(IslandTheme.text3)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(7)
                            .background(IslandTheme.surface2, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(standaloneModule == .windows ? .automatic : .never)
            }
        }
        .tileStyle()
    }

    // MARK: - AI 状态与完成提醒

    @ViewBuilder
    private func completionsCard(_ variant: HomeModuleVariant) -> some View {
        if standaloneModule == .completions {
            standaloneCompletionsView
        } else {
            VStack(alignment: .leading, spacing: 8) {
            HStack {
                cardLabel("AI 任务", systemImage: "sparkles")
                Spacer()
                if let quota = codexStatus.preferredQuota {
                    Text("Codex \(Int(quota.remainingPercent.rounded()))%")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(quotaColor(quota.remainingPercent))
                }
                Button { codexStatus.refreshNow() } label: {
                    if codexStatus.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(IslandTheme.text4)
                    }
                }
                .buttonStyle(.plain)
                .help("刷新 Codex 额度与任务")
            }

            if variant == .mini {
                compactAIStatus
            } else {
                codexQuotaSection

                let codexTaskLimit = variant == .full || variant == .tall ? 3 : 1
                if !codexStatus.tasks.isEmpty {
                    Divider().overlay(IslandTheme.hairlineSoft)
                    ForEach(codexStatus.tasks.prefix(codexTaskLimit)) { task in
                        codexTaskRow(task)
                    }
                }

                Divider().overlay(IslandTheme.hairlineSoft)
                if notifyServer.recentCompletions.isEmpty {
                    HStack(spacing: 8) {
                        Text(notifyServer.isRunning ? "等待其他 AI 工具完成通知" : "通知端口暂不可用")
                            .font(.caption2)
                            .foregroundStyle(IslandTheme.text3)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button("测试") { notifyServer.sendTestCompletion() }
                            .buttonStyle(.borderless)
                            .font(.caption2.weight(.medium))
                    }
                } else {
                    let completionLimit = variant == .full ? 4 : (variant == .tall ? 2 : 1)
                    ForEach(notifyServer.recentCompletions.prefix(completionLimit)) { completion in
                        completionRow(completion)
                    }
                }
            }
            }
            .tileStyle()
        }
    }

    private var standaloneCompletionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(IslandTheme.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 任务")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(IslandTheme.text1)
                    Text("Codex 额度、进行中的任务与完成通知")
                        .font(.caption2)
                        .foregroundStyle(IslandTheme.text3)
                }
                Spacer()
                if !codexStatus.workingTasks.isEmpty {
                    Label("\(codexStatus.workingTasks.count) 个进行中", systemImage: "circle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(IslandTheme.accentOrange)
                }
                Button { codexStatus.refreshNow() } label: {
                    Label(codexStatus.isRefreshing ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(codexStatus.isRefreshing)
            }

            HStack(alignment: .top, spacing: 12) {
                aiStandaloneSection(title: "额度", systemImage: "gauge.with.dots.needle.50percent") {
                    codexQuotaSection
                    Spacer(minLength: 0)
                }
                .frame(width: 230)

                aiStandaloneSection(
                    title: "Codex 任务",
                    systemImage: "terminal",
                    count: codexStatus.tasks.count
                ) {
                    if codexStatus.tasks.isEmpty {
                        aiStandaloneEmpty("暂无可显示的 Codex 任务")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 7) {
                                ForEach(codexStatus.tasks) { task in
                                    codexTaskRow(task)
                                        .padding(8)
                                        .background(IslandTheme.surface3.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                                }
                            }
                        }
                        .scrollIndicators(.automatic)
                    }
                }

                aiStandaloneSection(
                    title: "完成通知",
                    systemImage: "checkmark.circle",
                    count: notifyServer.recentCompletions.count
                ) {
                    if notifyServer.recentCompletions.isEmpty {
                        aiStandaloneEmpty(notifyServer.isRunning ? "等待其他 AI 工具完成通知" : "通知端口暂不可用")
                        Button("发送测试通知") { notifyServer.sendTestCompletion() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 7) {
                                ForEach(notifyServer.recentCompletions) { completion in
                                    completionRow(completion)
                                        .padding(8)
                                        .background(IslandTheme.surface3.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                                }
                            }
                        }
                        .scrollIndicators(.automatic)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .tileStyle()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func aiStandaloneSection<Content: View>(
        title: String,
        systemImage: String,
        count: Int? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(IslandTheme.text3)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IslandTheme.text2)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(IslandTheme.text4)
                }
            }
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IslandTheme.surface2, in: RoundedRectangle(cornerRadius: 12))
    }

    private func aiStandaloneEmpty(_ message: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(IslandTheme.text4)
            Text(message)
                .font(.caption2)
                .foregroundStyle(IslandTheme.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var compactAIStatus: some View {
        if let task = codexStatus.workingTasks.first {
            HStack(spacing: 7) {
                Circle().fill(IslandTheme.accentOrange).frame(width: 7, height: 7)
                Text(task.title).font(.caption).foregroundStyle(IslandTheme.text1).lineLimit(1)
                Spacer(minLength: 0)
                Text("工作中").font(.caption2).foregroundStyle(IslandTheme.text3)
            }
        } else if let completion = notifyServer.recentCompletions.first {
            completionRow(completion)
        } else if let task = codexStatus.tasks.first {
            HStack(spacing: 7) {
                Circle().fill(taskColor(task.state)).frame(width: 7, height: 7)
                Text(task.title).font(.caption).foregroundStyle(IslandTheme.text2).lineLimit(1)
                Spacer(minLength: 0)
                Text(task.state.label).font(.caption2).foregroundStyle(IslandTheme.text4)
            }
        } else {
            Text(codexStatus.quotaError ?? (notifyServer.isRunning ? "等待 AI 任务" : "AI 状态暂不可用"))
                .font(.caption2)
                .foregroundStyle(IslandTheme.text3)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var codexQuotaSection: some View {
        if codexStatus.displayQuotaWindows.isEmpty {
            Text(codexStatus.quotaError ?? "正在读取 Codex 额度…")
                .font(.caption2)
                .foregroundStyle(IslandTheme.text3)
                .lineLimit(2)
        } else {
            ForEach(codexStatus.displayQuotaWindows) { quota in
                HStack(spacing: 8) {
                    Text(quota.shortName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(IslandTheme.text2)
                        .frame(width: 42, alignment: .leading)
                    ProgressView(value: quota.remainingPercent, total: 100)
                        .progressViewStyle(.linear)
                        .tint(quotaColor(quota.remainingPercent))
                    Text("\(Int(quota.remainingPercent.rounded()))%")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(quotaColor(quota.remainingPercent))
                        .frame(width: 34, alignment: .trailing)
                    if let resetsAt = quota.resetsAt {
                        Text(resetsAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(IslandTheme.text4)
                    }
                }
            }
            if let count = codexStatus.quota?.resetCreditCount, count > 0 {
                Text("额外 Reset × \(count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(IslandTheme.accentBlue)
            }
        }
    }

    private func codexTaskRow(_ task: CodexTaskSummary) -> some View {
        Button {
            if let url = task.deepLink { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(taskColor(task.state)).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.caption)
                        .foregroundStyle(IslandTheme.text1)
                        .lineLimit(1)
                    Text("Codex · \(task.state.label)")
                        .font(.caption2)
                        .foregroundStyle(IslandTheme.text3)
                }
                Spacer(minLength: 0)
                Text(task.updatedAt, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(IslandTheme.text4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("在 Codex 中打开任务")
    }

    private func completionRow(_ completion: TaskCompletion) -> some View {
        HStack(spacing: 8) {
            Circle().fill(sourceColor(completion.source)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(completion.title)
                    .font(.caption)
                    .foregroundStyle(IslandTheme.text1)
                    .lineLimit(1)
                Text(completion.project.isEmpty
                     ? completion.source
                     : "\(completion.source) · \(completion.project)")
                    .font(.caption2)
                    .foregroundStyle(IslandTheme.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(completion.receivedAt, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(IslandTheme.text4)
        }
    }

    private func quotaColor(_ remainingPercent: Double) -> Color {
        if remainingPercent <= 5 { return IslandTheme.p0 }
        if remainingPercent <= 20 { return IslandTheme.accentOrange }
        return IslandTheme.accentGreen
    }

    private func taskColor(_ state: CodexTaskState) -> Color {
        switch state {
        case .working: return IslandTheme.accentOrange
        case .error: return IslandTheme.p0
        case .idle: return IslandTheme.accentGreen
        }
    }

    // MARK: - 随笔记

    private func noteCard(_ variant: HomeModuleVariant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                cardLabel("随笔记", systemImage: "pencil.line")
                Spacer()
                if !quickNote.isEmpty {
                    Text("自动保存")
                        .font(.caption2)
                        .foregroundStyle(IslandTheme.text4)
                }
            }
            if variant == .mini {
                Text(quickNote.isEmpty ? "长按拖动模块" : quickNote)
                    .font(.caption)
                    .foregroundStyle(quickNote.isEmpty ? IslandTheme.text4 : IslandTheme.text2)
                    .lineLimit(1)
            } else {
                TextEditor(text: $quickNote)
                    .font(.callout)
                    .foregroundStyle(IslandTheme.text1)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(IslandTheme.surface2, in: RoundedRectangle(cornerRadius: IslandTheme.radiusInput))
            }
        }
        .tileStyle()
    }

    private func windowGridColumns(for variant: HomeModuleVariant) -> [GridItem] {
        let count: Int
        if standaloneModule == .windows {
            return Array(repeating: GridItem(.flexible()), count: 2)
        }
        switch variant {
        case .mini: count = 1
        case .compact, .tall: count = 2
        case .wide: count = 3
        case .full: count = 4
        }
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    private func windowLimit(for variant: HomeModuleVariant) -> Int {
        if standaloneModule == .windows { return Int.max }
        switch variant {
        case .mini: return 2
        case .compact: return 4
        case .wide: return 6
        case .tall: return 8
        case .full: return 12
        }
    }

    private func cardLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(IslandTheme.text3)
    }

    private func sourceColor(_ source: String) -> Color {
        switch source {
        case "codex": return IslandTheme.accentGreen
        case "claude": return IslandTheme.accentOrange
        case "gpt": return IslandTheme.accentBlue
        case "windsurf": return IslandTheme.accentBlue
        case "cursor": return IslandTheme.accentGreen
        default: return IslandTheme.text3
        }
    }
}
