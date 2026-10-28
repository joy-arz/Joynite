import AppKit
import SwiftUI
import PlayniteCore
import UniformTypeIdentifiers

@MainActor final class LibraryModel: ObservableObject {
    @Published var library = LibraryFile()
    @Published var selection: String?
    @Published var filter = "All games"
    @Published var search = ""
    @Published var busy = false
    @Published var status = "Your games. One library."
    @Published var error: String?
    @Published var showMetadata = false
    @Published var showHelp = false
    @Published var issues: [String] = []
    let metadata = MetadataClient()
    private let storage: LibraryStorage
    private var writable = true
    var games: [Game] { library.games }
    var selected: Game? { games.first { $0.id == selection } }
    var visible: [Game] {
        games.filter { game in
            let matches = filter == "All games" || (filter == "Favorites" && game.favorite) || (filter == "Recently played" && game.lastPlayed != nil) || filter == game.store.rawValue
            return matches && (search.isEmpty || game.name.localizedCaseInsensitiveContains(search) || game.genres.contains { $0.localizedCaseInsensitiveContains(search) })
        }.sorted { lhs, rhs in
            if filter == "Recently played" { return (lhs.lastPlayed ?? .distantPast) > (rhs.lastPlayed ?? .distantPast) }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlayniteMac")
        storage = LibraryStorage(url: directory.appendingPathComponent("library.json"))
        do { library = try storage.load() }
        catch { writable = false; self.error = "Library could not be read. It has been preserved at \(storage.url.path). \(error.localizedDescription)" }
        selection = games.first?.id
    }
    func save() {
        guard writable else { error = "Library is read-only after a load failure. Restore library.json from library.json.backup in Application Support/PlayniteMac and restart."; return }
        do { try storage.save(library) } catch { self.error = "Could not save library: \(error.localizedDescription)" }
    }
    func update(_ game: Game) {
        guard let i = library.games.firstIndex(where: { $0.id == game.id }) else { return }
        library.games[i] = game; save()
    }
    func scan() async {
        guard !busy, writable else { return }
        busy = true; status = "Scanning installed games…"; defer { busy = false }
        let folders = library.folders
        let result = await Task.detached { Discovery().scan(folders: folders) }.value
        var count = 0
        for found in result.games {
            if let i = library.games.firstIndex(where: { $0.id == found.id }) {
                library.games[i].launchTarget = found.launchTarget; library.games[i].installPath = found.installPath
            } else if !library.games.contains(where: { !$0.installPath.isEmpty && $0.installPath == found.installPath }) {
                library.games.append(found); count += 1
            }
        }
        if selection == nil { selection = games.first?.id }
        issues = result.warnings; save()
        status = "Imported \(count) new games. Fetching missing metadata…"
        await enrich(games.filter { $0.metadataUpdated == nil })
        status = "\(games.count) games in your library. \(issues.count) notices."
    }
    private func enrich(_ pending: [Game]) async {
        for game in pending {
            if Task.isCancelled { break }
            do {
                status = "Finding metadata for \(game.name)…"
                let details = try await metadata.automatic(game)
                if let current = games.first(where: { $0.id == game.id }) { update(details.applying(to: current)) }
            } catch { issues.append(error.localizedDescription) }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }
    func refresh() async {
        guard !busy else { return }; busy = true; issues = []; defer { busy = false }
        await enrich(games); status = "Metadata refresh finished. \(issues.count) notices."
    }
    func addApplication() {
        let panel = NSOpenPanel(); panel.title = "Add a Mac game"; panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let game = Discovery.application(url) else { continue }
            if !games.contains(where: { $0.id == game.id || $0.installPath == game.installPath }) { library.games.append(game) }
            selection = game.id
        }
        save()
        Task { guard !busy else { return }; busy = true; await enrich(games.filter { $0.metadataUpdated == nil }); busy = false; status = "Game import finished." }
    }
    func addFolder() {
        let panel = NSOpenPanel(); panel.title = "Choose a folder containing games"; panel.canChooseDirectories = true; panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !library.folders.contains(url.path) { library.folders.append(url.path); save() }
        Task { await scan() }
    }
    func launch(_ game: Game) {
        if game.launchKind == .application {
            let url = URL(fileURLWithPath: game.launchTarget)
            guard FileManager.default.fileExists(atPath: url.path), url.pathExtension == "app" else { error = "This application is missing. Re-add it from its current location."; return }
            status = "Launching \(game.name)…"
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { app, failure in
                Task { @MainActor in
                    if let failure { self.error = "Could not launch \(game.name): \(failure.localizedDescription)" }
                    else if app != nil { self.didLaunch(game) }
                }
            }
        } else {
            guard let url = URL(string: game.launchTarget), ["steam", "heroic", "com.epicgames.launcher"].contains(url.scheme ?? "") else { error = "Unsupported launch URL."; return }
            guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { error = "Install \(game.launchTarget.hasPrefix("heroic:") ? "Heroic" : game.store.rawValue) to launch this game."; return }
            if NSWorkspace.shared.open(url) { didLaunch(game) } else { error = "The store client did not accept the launch request." }
        }
    }
    private func didLaunch(_ game: Game) {
        guard var current = games.first(where: { $0.id == game.id }) else { return }
        current.lastPlayed = Date(); update(current); status = "Launch request sent for \(game.name)."
    }
    func toggleFavorite(_ game: Game) { var game = game; game.favorite.toggle(); update(game) }
    func remove(_ game: Game) {
        let alert = NSAlert(); alert.messageText = "Remove \(game.name) from the library?"; alert.informativeText = "The installed game and its saves will remain on disk. Scanning can import it again."; alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        library.games.removeAll { $0.id == game.id }; selection = visible.first?.id; save()
    }
    func exportLibrary() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "PlayniteMac-library.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(library).write(to: url, options: .atomic); status = "Library exported." }
        catch { self.error = error.localizedDescription }
    }
    func importLibrary() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try LibraryStorage(url: url).load()
            for game in imported.games where !games.contains(where: { $0.id == game.id }) { library.games.append(game) }
            save(); selection = games.first?.id; status = "Library merged."
        } catch { self.error = "Import failed: \(error.localizedDescription)" }
    }
}
