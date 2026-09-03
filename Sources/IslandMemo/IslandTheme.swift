import SwiftUI

/// 设计令牌，对齐 TO-DO-Panel styles.css :root 变量。
/// 备忘录 Tab 内部样式保留原样，不使用本主题。
enum IslandTheme {
    // 颜色 · 黑白灰主体 + 少量状态色
    static let background = Color.black.opacity(0.92)
    static let surface1 = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)
    static let surface2 = Color(red: 0x19 / 255, green: 0x19 / 255, blue: 0x19 / 255)
    static let surface3 = Color(red: 0x25 / 255, green: 0x25 / 255, blue: 0x25 / 255)
    static let hairline = Color.white.opacity(0.08)
    static let hairlineSoft = Color.white.opacity(0.06)

    static let text1 = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255)
    static let text2 = Color(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xA1 / 255)
    static let text3 = Color(red: 0x70 / 255, green: 0x70 / 255, blue: 0x70 / 255)
    static let text4 = Color(red: 0x4A / 255, green: 0x4A / 255, blue: 0x4A / 255)

    static let accentGreen = Color(red: 0x30 / 255, green: 0xD9 / 255, blue: 0x78 / 255)
    static let accentOrange = Color(red: 0xFF / 255, green: 0x93 / 255, blue: 0x52 / 255)
    static let accentBlue = Color(red: 0x43 / 255, green: 0x8C / 255, blue: 0xFF / 255)
    static let p0 = Color(red: 0xFF / 255, green: 0x5F / 255, blue: 0x57 / 255)

    // 圆角
    static let radiusPanel: CGFloat = 16
    static let radiusTile: CGFloat = 18
    static let radiusSquircle: CGFloat = 12
    static let radiusInput: CGFloat = 10

    // 间距（8pt 体系）
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24

    // 布局
    static let topbarHeight: CGFloat = 40
    static let panelWidth: CGFloat = 868
    static let panelContentHeight: CGFloat = 345
}

extension View {
    /// 大卡片：surface-1 + 18px 圆角（对应 .tile）。
    func tileStyle() -> some View {
        padding(IslandTheme.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: IslandTheme.radiusTile))
    }

    /// 列表行：surface-1 + 12px 圆角（对应 --r-list-item）。
    func listRowStyle() -> some View {
        padding(.horizontal, IslandTheme.s3)
            .padding(.vertical, 10)
            .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: IslandTheme.radiusSquircle))
    }

    /// 输入区：surface-1 + 10px 圆角（对应 --r-input）。
    func inputStyle() -> some View {
        padding(IslandTheme.s3)
            .background(IslandTheme.surface1, in: RoundedRectangle(cornerRadius: IslandTheme.radiusInput))
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .blue
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension AppSettingsStore {
    func priorityColor(for priority: TaskPriority) -> Color {
        Color(hex: priorityColorHex(for: priority))
    }
}
