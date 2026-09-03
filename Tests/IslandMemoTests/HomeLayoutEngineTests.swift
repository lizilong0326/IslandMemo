import Foundation

@main
struct HomeLayoutValidation {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("验证失败：\(message)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func main() {
        referenceDefaultSizesFillFourRowsWithoutHoles()
        fragmentedLogicalOrderStillPacksExactly()
        currentNineModuleLayoutPacksWithoutPermutationExplosion()
        oneThroughSixModulesUseCompleteTemplates()
        incompleteSevenModuleLayoutIsRejected()
        print("首页布局验证通过")
    }

    static func referenceDefaultSizesFillFourRowsWithoutHoles() {
        let spans = [
            HomeGridSpan(columns: 4, rows: 2),
            HomeGridSpan(columns: 2, rows: 1),
            HomeGridSpan(columns: 4, rows: 4),
            HomeGridSpan(columns: 2, rows: 2),
            HomeGridSpan(columns: 4, rows: 2),
            HomeGridSpan(columns: 4, rows: 2),
            HomeGridSpan(columns: 2, rows: 1),
        ]
        let layout = HomeLayoutEngine.resolve(spans: spans)
        require(layout != nil, "参考模块尺寸无法铺满")
        require(HomeLayoutEngine.validate(layout ?? [], expectedCount: spans.count), "参考布局存在空洞")
    }

    static func fragmentedLogicalOrderStillPacksExactly() {
        let spans = [
            HomeGridSpan(columns: 2, rows: 2),
            HomeGridSpan(columns: 4, rows: 4),
            HomeGridSpan(columns: 2, rows: 1),
            HomeGridSpan(columns: 4, rows: 2),
            HomeGridSpan(columns: 4, rows: 2),
            HomeGridSpan(columns: 4, rows: 2),
            HomeGridSpan(columns: 2, rows: 1),
        ]
        require(HomeLayoutEngine.resolve(spans: spans) != nil, "换序后无法满格")
    }

    static func currentNineModuleLayoutPacksWithoutPermutationExplosion() {
        let spans = [
            HomeGridSpan(columns: 2, rows: 1),
            HomeGridSpan(columns: 2, rows: 1),
            HomeGridSpan(columns: 2, rows: 2),
            HomeGridSpan(columns: 2, rows: 2),
            HomeGridSpan(columns: 2, rows: 2),
            HomeGridSpan(columns: 2, rows: 2),
            HomeGridSpan(columns: 4, rows: 2),
            HomeGridSpan(columns: 2, rows: 2),
            HomeGridSpan(columns: 4, rows: 4),
        ]
        let layout = HomeLayoutEngine.resolve(spans: spans)
        require(layout != nil, "当前九模块首页无法铺满")
        require(HomeLayoutEngine.validate(layout ?? [], expectedCount: spans.count), "九模块布局存在空洞")
    }

    static func oneThroughSixModulesUseCompleteTemplates() {
        for count in 1...6 {
            let layout = HomeLayoutEngine.resolve(
                spans: Array(repeating: HomeGridSpan(columns: 2, rows: 1), count: count)
            )
            require(layout != nil, "\(count) 个模块没有模板")
            require(HomeLayoutEngine.validate(layout ?? [], expectedCount: count), "\(count) 个模块模板有空洞")
        }
    }

    static func incompleteSevenModuleLayoutIsRejected() {
        let spans = Array(repeating: HomeGridSpan(columns: 2, rows: 1), count: 7)
        require(HomeLayoutEngine.resolve(spans: spans) == nil, "不完整的七模块布局未被拒绝")
    }
}
