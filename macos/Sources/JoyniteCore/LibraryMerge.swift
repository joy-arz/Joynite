import Foundation

public enum LibraryMerge {
    public static func discovery(_ found: [Game], into current: LibraryFile) -> (library: LibraryFile, added: Int) {
        var next = current
        var indices = Dictionary(current.games.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        func location(_ game: Game) -> String { game.installPath + "\0" + game.launchKind.rawValue }
        var installations = Dictionary(current.games.filter { !$0.installPath.isEmpty }.map { (location($0), 1) }, uniquingKeysWith: +)
        var added = 0
        let existing = Set(indices.keys)
        let ordered = found.filter { existing.contains($0.id) } + found.filter { !existing.contains($0.id) }
        for game in ordered {
            if let index = indices[game.id] {
                if next.games[index].launchTarget != game.launchTarget { next.games[index].launchTarget = game.launchTarget }
                if next.games[index].installPath != game.installPath {
                    let old = next.games[index]
                    if !old.installPath.isEmpty { installations[location(old), default: 0] -= 1 }
                    next.games[index].installPath = game.installPath
                    if !game.installPath.isEmpty { installations[location(next.games[index]), default: 0] += 1 }
                }
                if next.games[index].compatibility != game.compatibility { next.games[index].compatibility = game.compatibility }
            } else if game.installPath.isEmpty || installations[location(game), default: 0] == 0 {
                indices[game.id] = next.games.count
                next.games.append(game)
                if !game.installPath.isEmpty { installations[location(game), default: 0] += 1 }
                added += 1
            }
        }
        return (next, added)
    }
}
