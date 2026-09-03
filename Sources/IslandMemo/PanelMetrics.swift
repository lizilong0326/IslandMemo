import SwiftUI

/// 面板几何：顶边距（避让菜单栏/物理刘海），由 AppDelegate 在展示时按屏计算。
@MainActor
final class PanelMetrics: ObservableObject {
    @Published var topInset: CGFloat = 41
    @Published private(set) var collapseRequest = 0

    func panelWillHide() {
        collapseRequest += 1
    }
}
