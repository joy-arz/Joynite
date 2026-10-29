import Foundation

public enum Carousel {
    public static func wrappedIndex(_ index: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let remainder = index % count
        return remainder < 0 ? remainder + count : remainder
    }
    public static func move(_ selection: String?, by offset: Int, in games: [Game]) -> String? {
        guard !games.isEmpty else { return nil }
        let current = games.firstIndex { $0.id == selection } ?? 0
        guard let next = wrappedIndex(current + offset, count: games.count) else { return nil }
        return games[next].id
    }
    public static func slots(count: Int) -> [Int] { count == 0 ? [] : count == 1 ? [0] : [-2, -1, 0, 1, 2] }
}

public enum UninstallPlan: Equatable {
    case trashApplication(URL)
    case steam(URL)
    case compatibility(CompatibilityLaunch)
    case manageClient(URL, String)
    public static func make(for game: Game, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> UninstallPlan {
        if game.launchKind == .compatibility {
            guard var plan = game.compatibility, UInt64(game.storeID) != nil, let steam = plan.arguments.first else { throw LibraryError.invalid("Compatibility uninstall settings are missing.") }
            plan.arguments = [steam, "steam://uninstall/\(game.storeID)"]
            return .compatibility(plan)
        }
        if game.launchKind == .store {
            if game.store == .steam, let id = UInt64(game.storeID), id > 0 {
                return .steam(URL(string: "steam://uninstall/\(id)")!)
            }
            if game.launchTarget.hasPrefix("heroic://"), let url = URL(string: "heroic://") { return .manageClient(url, "Heroic") }
            if game.store == .epic, let url = URL(string: "com.epicgames.launcher://") { return .manageClient(url, "Epic Games Launcher") }
            throw LibraryError.invalid("Uninstall this game through its original installer or client.")
        }
        let target = URL(fileURLWithPath: game.launchTarget).standardizedFileURL
        let resolved = target.resolvingSymlinksInPath()
        guard target.pathExtension.lowercased() == "app", target.path == resolved.path,
              !game.installPath.isEmpty, URL(fileURLWithPath: game.installPath).standardizedFileURL == target,
              !target.path.hasPrefix("/System/"), !target.path.hasPrefix("/Library/"),
              !target.path.contains(".app/"), !target.path.contains("/.Trash/"),
              !JoyniteIdentity.isLauncher(Bundle(url: target)?.bundleIdentifier ?? ""),
              FileManager.default.fileExists(atPath: target.appendingPathComponent("Contents/Info.plist").path) else {
            throw LibraryError.invalid("Only this game's existing, top-level Mac application can be moved to Trash. System apps, links, and Joynite itself are protected.")
        }
        return .trashApplication(target)
    }
    public static func confirmedMissing(_ game: Game, fileManager: FileManager = .default) -> Bool {
        guard game.pendingUninstall == true, !game.installPath.isEmpty else { return false }
        let path = URL(fileURLWithPath: game.installPath).standardizedFileURL
        if path.path.hasPrefix("/Volumes/") {
            guard path.pathComponents.count > 2 else { return false }
            let volume = "/Volumes/" + path.pathComponents[2]
            guard fileManager.fileExists(atPath: volume) else { return false }
        }
        guard !fileManager.fileExists(atPath: path.path) else { return false }
        return fileManager.fileExists(atPath: path.deletingLastPathComponent().path)
    }
}
