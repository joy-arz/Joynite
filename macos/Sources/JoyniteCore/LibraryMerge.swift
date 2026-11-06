import Foundation

public enum LibraryMerge {
    public static func discovery(_ found: [Game], into current: LibraryFile) -> (library: LibraryFile, added: Int) {
        var next = current
        var indices = Dictionary(current.games.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        func location(_ game: Game) -> String { game.installPath + "\0" + game.launchKind.rawValue }
        var installations = Set(current.games.filter { !$0.installPath.isEmpty }.map(location))
        var added = 0
        for game in found {
            if let index = indices[game.id] {
                if next.games[index].launchTarget != game.launchTarget { next.games[index].launchTarget = game.launchTarget }
                if next.games[index].installPath != game.installPath { next.games[index].installPath = game.installPath }
                if next.games[index].compatibility != game.compatibility { next.games[index].compatibility = game.compatibility }
                if !game.installPath.isEmpty { installations.insert(location(game)) }
            } else if game.installPath.isEmpty || !installations.contains(location(game)) {
                indices[game.id] = next.games.count
                next.games.append(game)
                if !game.installPath.isEmpty { installations.insert(location(game)) }
                added += 1
            }
        }
        return (next, added)
    }
}
