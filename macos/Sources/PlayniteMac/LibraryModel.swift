import AppKit
import SwiftUI
import PlayniteCore
import UniformTypeIdentifiers

@MainActor final class LibraryModel: ObservableObject {
    @Published var library = LibraryFile() { didSet { rebuildVisible() } }
    @Published var selection: String?
    @Published var showLibrary = false
    @Published var showDetails = false
    @Published var searchRequested = 0
    @Published var cacheRevision = 0
    @Published var showPublisherCatalog = false
    @Published var filter = "All games" { didSet { rebuildVisible() } }
    @Published var search = "" { didSet { rebuildVisible() } }
    @Published var busy = false
    @Published var status = "Your games. One library."
    @Published var error: String?
    @Published var showMetadata = false
    @Published var showHelp = false
    @Published var issues: [String] = []
    let metadata = MetadataClient()
    private let storage: LibraryStorage
    let media: MediaCache
    private var preparing = false
    private var writable = true
    var games: [Game] { library.games }
    var selected: Game? { games.first { $0.id == selection } }
    @Published private(set) var visible: [Game] = []
    @Published var carouselPosition = 0
    private var started = false
    private var processes: [String: Process] = [:]
    private func rebuildVisible() {
        visible = games.filter { game in
            guard game.hidden != true else { return false }
            let matches = filter == "All games" || (filter == "Favorites" && game.favorite) || (filter == "Recently played" && game.lastPlayed != nil) || filter == game.store.rawValue
            return matches && (search.isEmpty || game.name.localizedCaseInsensitiveContains(search) || game.genres.contains { $0.localizedCaseInsensitiveContains(search) })
        }.sorted { lhs, rhs in
            if filter == "Recently played" { return (lhs.lastPlayed ?? .distantPast) > (rhs.lastPlayed ?? .distantPast) }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
    init() {
        let directory = ProcessInfo.processInfo.environment["PLAYNITE_DATA_DIRECTORY"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlayniteMac")
        storage = LibraryStorage(url: directory.appendingPathComponent("library.json"))
        media = MediaCache(root: directory.appendingPathComponent("Media", isDirectory: true))
        do { library = try storage.load() }
        catch { writable = false; self.error = "Library could not be read. It has been preserved at \(storage.url.path). \(error.localizedDescription)" }
        rebuildVisible(); selection = visible.first?.id
    }
    func startup() async {
        guard !started else { return }; started = true
        await scan(fetchMetadata: false)
        await prepareOfflineLibrary()
        if !busy { busy = true; await enrich(games.filter { $0.metadataUpdated == nil }); busy = false }
        status = "\(games.count) games in your library. \(issues.count) notices."
    }
    func move(_ offset: Int) {
        guard visible.count > 1 else { return }
        carouselPosition += offset
        selection = Carousel.move(selection, by: offset, in: visible)
    }
    func ensureSelection() {
        if !visible.contains(where: { $0.id == selection }) { selection = visible.first?.id }
    }
    func prepareOfflineLibrary() async {
        guard !preparing, writable else { return }
        preparing = true; defer { preparing = false }
        await reconcileUninstalls()
        for original in games {
            var game = original
            if let entry = PublisherCatalog.match(game.name), game.metadataSource.isEmpty {
                game = entry.metadata.applying(to: game); update(game)
            }
            if game.backgroundArtwork == nil, game.metadataSource == "Steam", !busy,
               let details = try? await metadata.automatic(game), let current = games.first(where: { $0.id == game.id }) {
                game = details.applying(to: current); update(game)
            }
            await cacheArtwork(game)
        }
    }
    func cacheArtwork(_ original: Game) async {
        guard var game = games.first(where: { $0.id == original.id }) else { return }
        let poster = game.artwork
        let background = game.backgroundArtwork ?? ""
        let oldPoster = game.cachedArtwork; let oldBackground = game.cachedBackground; let oldLandscape = game.cachedLandscape
        if !poster.isEmpty, let key = try? await media.cache(poster, gameID: game.id, role: .landscape) { game.cachedLandscape = key }
        let candidates = MediaCache.portraitCandidates(for: game).sorted { lhs, rhs in
            let left = media.file(gameID: game.id, key: MediaCache.identifier(lhs) + ".png") != nil
            let right = media.file(gameID: game.id, key: MediaCache.identifier(rhs) + ".png") != nil
            return left && !right
        }
        var foundPortrait = false
        for candidate in candidates {
            if let key = try? await media.cache(candidate, gameID: game.id, role: .portrait) { game.cachedArtwork = key; foundPortrait = true; break }
        }
        if !foundPortrait, game.cachedArtwork == nil, !poster.isEmpty, let key = try? await media.cache(poster, gameID: game.id) { game.cachedArtwork = key }
        if !background.isEmpty, background != poster, let key = try? await media.cache(background, gameID: game.id) { game.cachedBackground = key }
        if game.cachedArtwork == nil, game.launchKind == .application,
           let data = NSWorkspace.shared.icon(forFile: game.launchTarget).tiffRepresentation,
           let key = try? await media.store(data, gameID: game.id, key: MediaCache.identifier("local-icon:" + game.id) + ".png") { game.cachedArtwork = key }
        guard var current = games.first(where: { $0.id == game.id }) else { try? await media.remove(gameID: game.id); return }
        if current.artwork == poster { current.cachedArtwork = game.cachedArtwork; current.cachedLandscape = game.cachedLandscape }
        if (current.backgroundArtwork ?? "") == background { current.cachedBackground = game.cachedBackground }
        if oldPoster != game.cachedArtwork || oldBackground != game.cachedBackground || oldLandscape != game.cachedLandscape { update(current); cacheRevision += 1 }
    }
    func applyMetadata(_ details: Metadata, to id: String) async {
        guard let current = games.first(where: { $0.id == id }) else { return }
        let updated = details.applying(to: current)
        update(updated)
        await cacheArtwork(updated)
    }
    func save() {
        guard writable else { error = "Library is read-only after a load failure. Restore library.json from library.json.backup in Application Support/PlayniteMac and restart."; return }
        do { try storage.save(library) } catch { self.error = "Could not save library: \(error.localizedDescription)" }
    }
    func update(_ game: Game) {
        guard writable else { error = "Library is read-only. Restore its backup before making changes."; return }
        guard let i = library.games.firstIndex(where: { $0.id == game.id }) else { return }
        library.games[i] = game; save()
    }
    func scan(fetchMetadata: Bool = true) async {
        guard !busy, writable else { return }
        busy = true; status = "Scanning installed games…"; defer { busy = false }
        let folders = library.folders
        let result = await Task.detached { Discovery().scan(folders: folders) }.value
        var count = 0
        for found in result.games {
            if let i = library.games.firstIndex(where: { $0.id == found.id }) {
                library.games[i].launchTarget = found.launchTarget; library.games[i].installPath = found.installPath
                library.games[i].compatibility = found.compatibility
            } else if !library.games.contains(where: { !$0.installPath.isEmpty && $0.installPath == found.installPath && $0.launchKind == found.launchKind }) {
                library.games.append(found); count += 1
            }
        }
        ensureSelection()
        issues = result.warnings; save(); await reconcileUninstalls()
        status = "Imported \(count) new games. Fetching missing metadata…"
        if fetchMetadata { await enrich(games.filter { $0.metadataUpdated == nil }) }
        status = "\(games.count) games in your library. \(issues.count) notices."
    }
    private func enrich(_ pending: [Game]) async {
        for game in pending {
            if Task.isCancelled { break }
            do {
                status = "Finding metadata for \(game.name)…"
                let details = try await metadata.automatic(game)
                await applyMetadata(details, to: game.id)
            } catch { issues.append(error.localizedDescription) }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }
    func refresh() async {
        guard !busy else { return }; busy = true; issues = []; defer { busy = false }
        await enrich(games); status = "Metadata refresh finished. \(issues.count) notices."
    }
    func addApplication() {
        guard writable else { error = "Library is read-only. Restore its backup before making changes."; return }
        let panel = NSOpenPanel(); panel.title = "Add a Mac game"; panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let game = Discovery.application(url) else { continue }
            if let index = library.games.firstIndex(where: { $0.id == game.id || $0.installPath == game.installPath }) { library.games[index].hidden = false }
            else { library.games.append(game) }
            selection = game.id
        }
        save()
        Task { guard !busy else { return }; busy = true; await enrich(games.filter { $0.metadataUpdated == nil }); busy = false; status = "Game import finished." }
    }
    func addFolder() {
        guard writable else { error = "Library is read-only. Restore its backup before making changes."; return }
        let panel = NSOpenPanel(); panel.title = "Choose a folder containing games"; panel.canChooseDirectories = true; panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !library.folders.contains(url.path) { library.folders.append(url.path); save() }
        Task { await scan() }
    }
    func launch(_ game: Game) {
        if game.launchKind == .compatibility {
            guard let plan = game.compatibility else { error = "Compatibility launch settings are missing."; return }
            do { try runCompatibility(plan, id: game.id); didLaunch(game) } catch { self.error = error.localizedDescription }
            return
        }
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
    private func runCompatibility(_ plan: CompatibilityLaunch, id: String) throws {
        guard ["wine", "wine64", "wine64-preloader"].contains(URL(fileURLWithPath: plan.executable).lastPathComponent),
              FileManager.default.isExecutableFile(atPath: plan.executable),
              let prefix = plan.environment["WINEPREFIX"], FileManager.default.fileExists(atPath: prefix + "/drive_c"),
              plan.arguments.first?.lowercased().hasSuffix("steam.exe") == true else { throw LibraryError.invalid("The existing Wine runtime or Steam prefix is unavailable. Rescan after connecting its disk.") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: plan.executable)
        process.arguments = plan.arguments; process.currentDirectoryURL = URL(fileURLWithPath: plan.workingDirectory)
        process.environment = ProcessInfo.processInfo.environment.merging(plan.environment) { _, value in value }
        let logs = media.root.deletingLastPathComponent().appendingPathComponent("Logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent(MediaCache.identifier(id) + ".log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log); process.standardOutput = handle; process.standardError = handle
        process.terminationHandler = { [weak self] child in
            try? handle.close()
            Task { @MainActor in
                self?.processes.removeValue(forKey: id)
                if child.terminationStatus != 0 { self?.error = "\(plan.label) exited with status \(child.terminationStatus). Details: \(log.path)" }
            }
        }
        try process.run(); processes[id] = process
    }
    private func didLaunch(_ game: Game) {
        guard var current = games.first(where: { $0.id == game.id }) else { return }
        current.lastPlayed = Date(); update(current); status = "Launch request sent for \(game.name)."
    }
    func toggleFavorite(_ game: Game) { var game = game; game.favorite.toggle(); update(game) }
    func remove(_ game: Game) {
        var game = game; game.hidden = true; update(game); ensureSelection()
        status = "Hidden \(game.name). Its offline metadata is retained."
    }
    func restoreHidden() {
        for index in library.games.indices { library.games[index].hidden = false }
        save(); ensureSelection()
    }
    func uninstall(_ game: Game) {
        guard writable else { error = "Library is read-only. Restore its backup before making changes."; return }
        do {
            let plan = try UninstallPlan.make(for: game)
            switch plan {
            case .trashApplication(let url):
                guard NSRunningApplication.runningApplications(withBundleIdentifier: Bundle(url: url)?.bundleIdentifier ?? "").isEmpty else { error = "Quit \(game.name) before uninstalling."; return }
                let alert = NSAlert(); alert.messageText = "Uninstall \(game.name)?"
                alert.informativeText = "Move \(url.path) to Trash, including any data inside the application bundle. External saves are left in place. The library entry and offline artwork are removed only after the move succeeds. You can recover the application from Trash."
                alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                NSWorkspace.shared.recycle([url]) { _, failure in
                    Task { @MainActor in
                        if let failure { self.error = "Uninstall failed: \(failure.localizedDescription)"; return }
                        guard !FileManager.default.fileExists(atPath: url.path) else { self.error = "The application is still installed. Its offline metadata has been kept."; return }
                        await self.finishUninstall(game)
                    }
                }
            case .compatibility(let plan):
                let alert = NSAlert(); alert.messageText = "Uninstall \(game.name) in \(plan.label) Steam?"; alert.informativeText = "The Steam client inside this existing prefix will open its uninstall dialog. Offline metadata stays until removal is confirmed."; alert.addButton(withTitle: "Open uninstall"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                try runCompatibility(plan, id: game.id)
                var pending = game; pending.pendingUninstall = true; update(pending)
            case .steam(let url):
                guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { error = "Install Steam to use its uninstall dialog."; return }
                if NSWorkspace.shared.open(url) {
                    var current = game; current.pendingUninstall = true; update(current)
                    status = "Complete uninstall in Steam. Metadata stays until removal is confirmed."
                }
            case .manageClient(let url, let client):
                guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { error = "Install \(client) to manage this installation."; return }
                let alert = NSAlert(); alert.messageText = "Uninstall through \(client)?"
                alert.informativeText = "Select \(game.name) in \(client) and use its Uninstall command. Playnite will keep your offline metadata until the installation has been removed."
                alert.addButton(withTitle: "Open \(client)"); alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn, NSWorkspace.shared.open(url) {
                    var current = game; current.pendingUninstall = true; update(current)
                    status = "Waiting for \(client) to remove \(game.name)."
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func finishUninstall(_ game: Game) async {
        library.games.removeAll { $0.id == game.id }; save(); ensureSelection()
        do { try await media.remove(gameID: game.id) } catch { issues.append("Offline artwork cleanup: \(error.localizedDescription)") }
        cacheRevision += 1; status = "Uninstalled \(game.name)."
    }
    func reconcileUninstalls() async {
        for game in games where UninstallPlan.confirmedMissing(game) { await finishUninstall(game) }
    }
    func exportLibrary() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "PlayniteMac-library.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(library).write(to: url, options: .atomic); status = "Library exported." }
        catch { self.error = error.localizedDescription }
    }
    func importLibrary() {
        guard writable else { error = "Library is read-only. Restore its backup before making changes."; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try LibraryStorage(url: url).load()
            for game in imported.games where !games.contains(where: { $0.id == game.id }) { library.games.append(game) }
            save(); selection = visible.first?.id; status = "Library merged."
            Task { await prepareOfflineLibrary() }
        } catch { self.error = "Import failed: \(error.localizedDescription)" }
    }
}
