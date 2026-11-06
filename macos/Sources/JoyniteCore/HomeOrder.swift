import Foundation

public enum HomeOrder {
    public static func ranked(_ games: [Game], counts: [String: UInt32]? = nil) -> [Game] {
        games.filter { $0.hidden != true }.sorted { a, b in
            if a.favorite != b.favorite { return a.favorite }
            let left = counts?[a.id] ?? a.launchCount ?? 0, right = counts?[b.id] ?? b.launchCount ?? 0
            if left != right { return left > right }
            let comparison = a.name.localizedStandardCompare(b.name)
            return comparison == .orderedSame ? a.id < b.id : comparison == .orderedAscending
        }
    }
    public static func carousel(_ games: [Game], counts: [String: UInt32]? = nil) -> [Game] {
        let ranked = ranked(games, counts: counts)
        let featured = Array(ranked.prefix(5))
        let rest = Array(ranked.dropFirst(5))
        func at(_ index: Int) -> [Game] { featured.indices.contains(index) ? [featured[index]] : [] }
        return at(0) + at(2) + at(4) + rest + at(3) + at(1)
    }
}
