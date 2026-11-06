import Foundation

public enum GameSearch {
    public struct Entry: Sendable {
        public let title: String
        public let words: [String]
        public let genres: String
        public init(name: String, genres: [String] = []) {
            title = Game.normalized(String(name.prefix(256)))
            words = name.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }.map(Game.normalized)
            self.genres = Game.normalized(genres.joined(separator: " "))
        }
        public func score(_ query: String) -> Double? {
            let q = Game.normalized(String(query.prefix(64)))
            return score(normalized: q)
        }
        public func score(normalized q: String) -> Double? {
            if q.isEmpty { return 0 }
            if title == q { return 0 }
            if title.hasPrefix(q) { return 1 }
            if title.contains(q) { return 2 }
            if genres.contains(q) { return 3 }
            guard q.count >= 4 else { return nil }
            let similarity = ((q.count >= Int(Double(title.count) * 0.7) ? [title] : []) + words.filter { $0.count >= 4 }).map { GameSearch.similarity(q, $0) }.max() ?? 0
            return similarity >= 0.5 ? 4 + (1 - similarity) : nil
        }
    }
    public static func similarity(_ left: String, _ right: String) -> Double {
        let a = Array(left), b = Array(right)
        let count = max(a.count, b.count)
        guard count > 0, abs(a.count - b.count) <= count / 2 else { return 0 }
        var previous = Array(0...b.count), older = previous
        for i in a.indices {
            var row = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                row[j + 1] = min(row[j] + 1, previous[j + 1] + 1, previous[j] + (a[i] == b[j] ? 0 : 1))
                if i > 0, j > 0, a[i] == b[j - 1], a[i - 1] == b[j] { row[j + 1] = min(row[j + 1], older[j - 1] + 1) }
            }
            older = previous; previous = row
        }
        return 1 - Double(previous[b.count]) / Double(count)
    }
}
