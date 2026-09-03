import Foundation

struct HomeGridSpan: Equatable, Hashable, Sendable {
    let columns: Int
    let rows: Int

    var area: Int { columns * rows }
}

struct HomeGridPlacement: Equatable, Sendable {
    let column: Int
    let row: Int
    let span: HomeGridSpan
}

/// TO-DO-Panel 首页布局纯逻辑的原生实现：
/// 1～6 个模块使用无空洞模板；7 个及以上使用回溯装箱；所有结果必须覆盖完整 12×4 网格。
enum HomeLayoutEngine {
    static let columns = 12
    static let rows = 4

    static func resolve(spans: [HomeGridSpan]) -> [HomeGridPlacement]? {
        guard !spans.isEmpty else { return [] }
        if spans.reduce(0, { $0 + $1.area }) == columns * rows,
           let packed = pack(spans: spans) {
            return packed
        }
        if spans.count <= 6, let template = gaplessTemplate(count: spans.count) {
            return validate(template, expectedCount: spans.count) ? template : nil
        }
        return pack(spans: spans)
    }

    static func pack(spans: [HomeGridSpan]) -> [HomeGridPlacement]? {
        guard spans.reduce(0, { $0 + $1.area }) == columns * rows else { return nil }
        var occupied = Array(repeating: Array(repeating: false, count: columns), count: rows)
        var result = Array<HomeGridPlacement?>(repeating: nil, count: spans.count)

        func fits(_ span: HomeGridSpan, column: Int, row: Int) -> Bool {
            guard span.columns > 0, span.rows > 0,
                  column + span.columns <= columns,
                  row + span.rows <= rows else { return false }
            for y in row..<(row + span.rows) {
                for x in column..<(column + span.columns) where occupied[y][x] { return false }
            }
            return true
        }

        func mark(_ span: HomeGridSpan, column: Int, row: Int, value: Bool) {
            for y in row..<(row + span.rows) {
                for x in column..<(column + span.columns) { occupied[y][x] = value }
            }
        }

        func firstEmptyCell() -> (column: Int, row: Int)? {
            for row in 0..<rows {
                for column in 0..<columns where !occupied[row][column] {
                    return (column, row)
                }
            }
            return nil
        }

        // Always cover the first empty cell. In any valid rectangular tiling the
        // rectangle covering that cell must start there: every cell before it in
        // row-major order is already occupied. This removes the translation and
        // identical-card permutations that made the old search grow explosively.
        func place(_ remaining: [Int]) -> Bool {
            guard let cell = firstEmptyCell() else { return remaining.isEmpty }
            guard !remaining.isEmpty else { return false }

            var attemptedSpans = Set<HomeGridSpan>()
            for (remainingOffset, originalIndex) in remaining.enumerated() {
                let span = spans[originalIndex]
                guard attemptedSpans.insert(span).inserted,
                      fits(span, column: cell.column, row: cell.row) else {
                    continue
                }
                mark(span, column: cell.column, row: cell.row, value: true)
                result[originalIndex] = HomeGridPlacement(
                    column: cell.column,
                    row: cell.row,
                    span: span
                )
                var next = remaining
                next.remove(at: remainingOffset)
                if place(next) { return true }
                result[originalIndex] = nil
                mark(span, column: cell.column, row: cell.row, value: false)
            }
            return false
        }

        guard place(Array(spans.indices)) else { return nil }
        let placements = result.compactMap { $0 }
        return validate(placements, expectedCount: spans.count) ? placements : nil
    }

    static func validate(_ placements: [HomeGridPlacement], expectedCount: Int) -> Bool {
        guard placements.count == expectedCount, expectedCount > 0 else { return false }
        var cells = Array(repeating: 0, count: columns * rows)
        for placement in placements {
            let span = placement.span
            guard placement.column >= 0, placement.row >= 0,
                  span.columns > 0, span.rows > 0,
                  placement.column + span.columns <= columns,
                  placement.row + span.rows <= rows else { return false }
            for y in placement.row..<(placement.row + span.rows) {
                for x in placement.column..<(placement.column + span.columns) {
                    let index = y * columns + x
                    cells[index] += 1
                    if cells[index] > 1 { return false }
                }
            }
        }
        return cells.allSatisfy { $0 == 1 }
    }

    private static func gaplessTemplate(count: Int) -> [HomeGridPlacement]? {
        let slots: [(Int, Int, Int, Int)]
        switch count {
        case 1:
            slots = [(0, 0, 12, 4)]
        case 2:
            slots = [(0, 0, 6, 4), (6, 0, 6, 4)]
        case 3:
            slots = [(0, 0, 4, 4), (4, 0, 4, 4), (8, 0, 4, 4)]
        case 4:
            slots = [(0, 0, 6, 2), (6, 0, 6, 2), (0, 2, 6, 2), (6, 2, 6, 2)]
        case 5:
            slots = [(0, 0, 4, 4), (4, 0, 4, 2), (8, 0, 4, 2), (4, 2, 4, 2), (8, 2, 4, 2)]
        case 6:
            slots = [(0, 0, 4, 2), (4, 0, 4, 2), (8, 0, 4, 2), (0, 2, 4, 2), (4, 2, 4, 2), (8, 2, 4, 2)]
        default:
            return nil
        }
        return slots.map {
            HomeGridPlacement(column: $0.0, row: $0.1, span: HomeGridSpan(columns: $0.2, rows: $0.3))
        }
    }
}
