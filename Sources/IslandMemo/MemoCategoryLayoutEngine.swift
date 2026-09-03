import Foundation

/// A gapless 12 x 4 layout for one to four memo categories. The category marked
/// as expanded receives the featured slot; all remaining categories share the
/// rest of the board. This mirrors the home bento grid without allowing invalid
/// free-form combinations.
enum MemoCategoryLayoutEngine {
    static func resolve(categories: [MemoCategory]) -> [HomeGridPlacement] {
        guard !categories.isEmpty else { return [] }
        let count = min(categories.count, 4)
        let featured = categories.prefix(count).firstIndex { $0.size == .expanded }

        switch (count, featured) {
        case (1, _):
            return placements([(0, 0, 12, 4)])
        case (2, .some(let featuredIndex)):
            return featuredIndex == 0
                ? placements([(0, 0, 8, 4), (8, 0, 4, 4)])
                : placements([(0, 0, 4, 4), (4, 0, 8, 4)])
        case (2, nil):
            return placements([(0, 0, 6, 4), (6, 0, 6, 4)])
        case (3, .some(let featuredIndex)):
            return featuredLayout(
                count: 3,
                featuredIndex: featuredIndex,
                featured: (0, 0, 6, 4),
                remaining: [(6, 0, 6, 2), (6, 2, 6, 2)]
            )
        case (3, nil):
            return placements([(0, 0, 4, 4), (4, 0, 4, 4), (8, 0, 4, 4)])
        case (4, .some(let featuredIndex)):
            return featuredLayout(
                count: 4,
                featuredIndex: featuredIndex,
                featured: (0, 0, 12, 2),
                remaining: [(0, 2, 4, 2), (4, 2, 4, 2), (8, 2, 4, 2)]
            )
        default:
            return placements([(0, 0, 6, 2), (6, 0, 6, 2), (0, 2, 6, 2), (6, 2, 6, 2)])
        }
    }

    private static func featuredLayout(
        count: Int,
        featuredIndex: Int,
        featured: (Int, Int, Int, Int),
        remaining: [(Int, Int, Int, Int)]
    ) -> [HomeGridPlacement] {
        var slots = Array<HomeGridPlacement?>(repeating: nil, count: count)
        slots[featuredIndex] = placement(featured)
        var remainingIndex = 0
        for index in 0..<count where index != featuredIndex {
            slots[index] = placement(remaining[remainingIndex])
            remainingIndex += 1
        }
        return slots.compactMap { $0 }
    }

    private static func placements(_ values: [(Int, Int, Int, Int)]) -> [HomeGridPlacement] {
        values.map(placement)
    }

    private static func placement(_ value: (Int, Int, Int, Int)) -> HomeGridPlacement {
        HomeGridPlacement(
            column: value.0,
            row: value.1,
            span: HomeGridSpan(columns: value.2, rows: value.3)
        )
    }
}
