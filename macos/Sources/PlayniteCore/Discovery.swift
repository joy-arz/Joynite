import Foundation

public struct DiscoveryResult: Sendable {
    public var games: [Game] = []
    public var warnings: [String] = []
}
public struct Discovery {
    private let fm = FileManager.default
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    public func scan(folders: [String]) -> DiscoveryResult {
        var result = DiscoveryResult()
        let steam = home.appendingPathComponent("Library/Application Support/Steam/steamapps")
        var libraries = [steam]
        let libraryFile = steam.appendingPathComponent("libraryfolders.vdf")
        if fm.fileExists(atPath: libraryFile.path) {
            do {
                let root = try VDF.parse(String(contentsOf: libraryFile, encoding: .utf8))
                for (_, value) in VDF.object(root, "libraryfolders") ?? [:] {
                    if case .object(let entry) = value, let path = VDF.string(entry, "path") { libraries.append(URL(fileURLWithPath: path).appendingPathComponent("steamapps")) }
                }
            } catch { result.warnings.append("Steam libraries: \(error.localizedDescription)") }
        }
        for library in Set(libraries) {
            guard fm.fileExists(atPath: library.path) else { continue }
            do {
                for manifest in try fm.contentsOfDirectory(at: library, includingPropertiesForKeys: nil) where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension == "acf" {
                    do { if let game = try steamGame(manifest: manifest) { result.games.append(game) } }
                    catch { result.warnings.append("\(manifest.lastPathComponent): \(error.localizedDescription)") }
                }
            } catch { result.warnings.append("\(library.path): \(error.localizedDescription)") }
        }
        let epic = home.appendingPathComponent("Library/Application Support/Epic/EpicGamesLauncher/Data/Manifests")
        if let manifests = try? fm.contentsOfDirectory(at: epic, includingPropertiesForKeys: nil) {
            for url in manifests where url.pathExtension == "item" {
                do {
                    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
                    if let game = Self.epicGame(json) { result.games.append(game) }
                } catch { result.warnings.append("Epic \(url.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        let heroic = home.appendingPathComponent("Library/Application Support/heroic")
        for (file, store) in [("legendaryConfig/legendary/installed.json", Store.epic), ("gog_store/installed.json", Store.gog)] {
            let url = heroic.appendingPathComponent(file)
            guard fm.fileExists(atPath: url.path) else { continue }
            do {
                let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                let dictionary = raw as? [String: Any] ?? [:]
                let entries: [[String: Any]]
                if let installed = dictionary["installed"] as? [[String: Any]] { entries = installed }
                else { entries = dictionary.compactMap { key, value in
                    guard var game = value as? [String: Any] else { return nil }; game["_key"] = key; return game
                } }
                for item in entries {
                    let id = item["app_name"] as? String ?? item["appName"] as? String ?? item["_key"] as? String ?? ""
                    let path = item["install_path"] as? String ?? item["installPath"] as? String ?? ""
                    guard !id.isEmpty else { continue }
                    let name = item["title"] as? String ?? item["name"] as? String ?? id
                    let runner = store == .epic ? "legendary" : "gog"
                    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
                    result.games.append(Game(id: "heroic:\(store.rawValue):\(id)", name: name, store: store, launchKind: .store, launchTarget: "heroic://launch/\(runner)/\(encoded)", installPath: path, storeID: id))
                }
            } catch { result.warnings.append("Heroic \(file): \(error.localizedDescription)") }
        }
        let roots = ["/Applications/Games", "/Applications/GOG Games", home.appendingPathComponent("Games").path, home.appendingPathComponent("Applications/Sikarugir").path, home.appendingPathComponent("Applications/Wineskin").path, home.appendingPathComponent("GOG Games").path, home.appendingPathComponent("Library/Application Support/itch/apps").path] + folders
        for path in Set(roots) { scanApps(URL(fileURLWithPath: path), depth: 0, all: true, into: &result) }
        scanApps(URL(fileURLWithPath: "/Applications"), depth: 0, all: false, into: &result)
        scanApps(home.appendingPathComponent("Applications"), depth: 0, all: false, into: &result)
        let compatibility = CompatibilityDiscovery(home: home).scan(apps: result.games, folders: folders)
        result.games += compatibility.games; result.warnings += compatibility.warnings
        var seen = Set<String>()
        result.games = result.games.filter { seen.insert($0.id).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return result
    }
    private func scanApps(_ root: URL, depth: Int, all: Bool, into result: inout DiscoveryResult) {
        guard depth < 5, fm.fileExists(atPath: root.path) else { return }
        do {
            for url in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true { continue }
                if url.pathExtension.lowercased() == "app" {
                    let bundle = Bundle(url: url)
                    let category = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String ?? ""
                    let wrapped = ["Contents/SharedSupport/prefix/drive_c", "Contents/Resources/drive_c"].contains { fm.fileExists(atPath: url.appendingPathComponent($0).path) }
                    if all || wrapped || category.contains("games") || (Self.knownGames.contains(url.deletingPathExtension().lastPathComponent.lowercased()) || PublisherCatalog.match(url.deletingPathExtension().lastPathComponent) != nil) {
                        let path = url.path.lowercased()
                        let store: Store = path.contains("/itch/") ? .itch : path.contains("/gog") ? .gog : .local
                        if let game = Self.application(url, store: store) { result.games.append(game) }
                    }
                } else if all && values.isDirectory == true { scanApps(url, depth: depth + 1, all: all, into: &result) }
            }
        } catch { result.warnings.append("\(root.path): \(error.localizedDescription)") }
    }
    private static let knownGames: Set<String> = ["mindustry", "loop_hero", "dungeons & degenerate gamblers", "balatro", "stardew valley", "hades", "hollow knight", "minecraft", "roblox", "terraria", "celeste", "undertale"]
    public static func application(_ url: URL, store: Store = .local) -> Game? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app", FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path) else { return nil }
        let bundle = Bundle(url: url)
        guard bundle?.bundleIdentifier != "io.github.joy-arz.PlayniteMac" else { return nil }
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        return Game(id: "app:" + url.standardizedFileURL.path, name: HTML.text(name), store: store, launchKind: .application, launchTarget: url.path, installPath: url.path)
    }
    public func steamGame(manifest: URL) throws -> Game? {
        let root = try VDF.parse(String(contentsOf: manifest, encoding: .utf8))
        guard let state = VDF.object(root, "AppState"), let id = VDF.string(state, "appid"), Int(id) != nil, let name = VDF.string(state, "name"), let directory = VDF.string(state, "installdir") else { throw LibraryError.invalid("Missing Steam installation fields.") }
        guard !directory.contains(".."), !directory.contains("/"), !directory.contains("\\") else { throw LibraryError.invalid("Invalid Steam installation directory.") }
        let flags = Int(VDF.string(state, "StateFlags") ?? "0") ?? 0
        guard flags & 4 != 0 else { return nil }
        let path = manifest.deletingLastPathComponent().appendingPathComponent("common").appendingPathComponent(directory).path
        guard fm.fileExists(atPath: path) else { return nil }
        var game = Game(id: "steam:\(id)", name: name, store: .steam, launchKind: .store, launchTarget: "steam://rungameid/\(id)", installPath: path, storeID: id)
        game.storeURL = "https://store.steampowered.com/app/\(id)/"
        return game
    }
    public static func epicGame(_ json: [String: Any]) -> Game? {
        guard let name = json["DisplayName"] as? String, let id = json["AppName"] as? String, let path = json["InstallLocation"] as? String, FileManager.default.fileExists(atPath: path), json["bIsIncompleteInstall"] as? Bool != true else { return nil }
        let launch = [json["CatalogNamespace"] as? String, json["CatalogItemId"] as? String, id].compactMap { $0 }.joined(separator: ":")
        var allowed = CharacterSet.urlPathAllowed; allowed.remove(charactersIn: "/?#&")
        let target = "com.epicgames.launcher://apps/\(launch.addingPercentEncoding(withAllowedCharacters: allowed) ?? id)?action=launch&silent=true"
        return Game(id: "epic:\(id)", name: name, store: .epic, launchKind: .store, launchTarget: target, installPath: path, storeID: id)
    }
}
