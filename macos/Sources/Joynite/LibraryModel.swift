import AppKit
import SwiftUI
import JoyniteCore
import UniformTypeIdentifiers

@MainActor final class LibraryModel: ObservableObject {
    @Published var library = LibraryFile() { didSet { rebuildIndex(); rebuildVisible() } }
    @Published var selection: String?
    @Published var showLibrary = false
    @Published var showDetails = false
    @Published var searchRequested = 0
    @Published var cacheRevision = 0
    @Published var showPublisherCatalog = false
    @Published var filter = "All games" { didSet { rebuildVisible() } }
    @Published var search = "" { didSet { rebuildVisible() } }
    @Published var backupProgress: Progress?
    @Published var backupLabel = ""
    @Published var restoringBackup = false
    @Published var busy = false
    @Published var status = "Your games. One library."
    @Published var error: String?
    @Published var showMetadata = false
    @Published var showCustomMetadata = false
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
    private var startupCounts: [String: UInt32] = [:]
    private var processes: [String: Process] = [:]
    private var launchedApplications: [Int32: (String, Date)] = [:]
    private var terminationObserver: NSObjectProtocol?
    @Published private(set) var launchRevision = 0
    private var reports: [String: LaunchReport] = [:]
    func launchReport(for game: Game) -> LaunchReport? {
        if let cached = reports[game.id] { return cached }
        let report = LaunchDiagnostics.read(root: media.root.deletingLastPathComponent(), gameID: game.id)
        reports[game.id] = report; return report
    }
    private func report(_ value: LaunchReport, gameID: String) {
        reports[gameID] = value; launchRevision += 1
        try? LaunchDiagnostics.write(value, root: media.root.deletingLastPathComponent(), gameID: gameID)
    }
    private var searchIndex: [String: GameSearch.Entry] = [:]
    private var indexedNames: [String: String] = [:]
    private var indexedGenres: [String: [String]] = [:]
    @Published private(set) var searchPending = false
    private var searchTask: Task<Void, Never>?
    private var searchRevision = 0
    private func rebuildIndex() {
        for game in games where startupCounts[game.id] == nil { startupCounts[game.id] = game.launchCount ?? 0 }
        let ids = Set(games.map(\.id))
        searchIndex = searchIndex.filter { ids.contains($0.key) }
        for game in games where indexedNames[game.id] != game.name || indexedGenres[game.id] != game.genres {
            searchIndex[game.id] = GameSearch.Entry(name: game.name, genres: game.genres)
        }
        indexedNames = Dictionary(games.map { ($0.id, $0.name) }, uniquingKeysWith: { _, last in last })
        indexedGenres = Dictionary(games.map { ($0.id, $0.genres) }, uniquingKeysWith: { _, last in last })
    }
    private func rebuildVisible() {
        searchTask?.cancel(); searchRevision += 1
        let revision = searchRevision
        let query = Game.normalized(String(search.prefix(64))), index = searchIndex, scope = filter, counts = startupCounts
        let candidates = games.filter { game in
            game.hidden != true && (scope == "All games" || (scope == "Favorites" && game.favorite) || (scope == "Recently played" && game.lastPlayed != nil) || scope == game.store.rawValue)
        }
        let work: @Sendable () -> [Game] = {
            var scores: [String: Double] = [:]
            var results = candidates.filter { game in
                if Task.isCancelled { return false }
                guard !query.isEmpty else { return true }
                guard let score = index[game.id]?.score(normalized: query) else { return false }
                scores[game.id] = score; return true
            }
            if !query.isEmpty && scores.values.contains(where: { $0 < 4 }) { results.removeAll { (scores[$0.id] ?? 10) >= 4 } }
            if query.isEmpty && scope != "Recently played" { return HomeOrder.carousel(results, counts: counts) }
            return results.sorted { lhs, rhs in
                if !query.isEmpty, scores[lhs.id] != scores[rhs.id] { return (scores[lhs.id] ?? 10) < (scores[rhs.id] ?? 10) }
                if scope == "Recently played" { return (lhs.lastPlayed ?? .distantPast) > (rhs.lastPlayed ?? .distantPast) }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
        if candidates.count <= 500 { searchPending = false; searchTask = nil; visible = work(); return }
        searchPending = true
        searchTask = Task {
            let job = Task.detached(priority: .userInitiated, operation: work)
            let result = await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
            guard !Task.isCancelled, self.searchRevision == revision else { return }
            visible = result; searchPending = false; ensureSelection()
        }
    }
    func commitSearch(select id: String? = nil) -> Bool {
        guard !searchPending, let found = id ?? visible.first?.id else { return false }
        search = ""; selection = found; carouselPosition = 0
        status = "Selected \(selected?.name ?? "game")."; return true
    }
    func finishSearch(select id: String? = nil) async -> Bool {
        let text = search; await searchTask?.value
        guard text == search else { return false }
        return commitSearch(select: id)
    }
    init() {
        let environment = ProcessInfo.processInfo.environment
        let override = environment["JOYNITE_DATA_DIRECTORY"] ?? environment["PLAYNITE_DATA_DIRECTORY"]
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = override.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? support.appendingPathComponent("Joynite")
        storage = LibraryStorage(url: directory.appendingPathComponent("library.json"))
        media = MediaCache(root: directory.appendingPathComponent("Media", isDirectory: true))
        do {
            if override == nil { try LibraryMigration.prepare(destination: directory, legacyDirectories: [support.appendingPathComponent("PlayniteMac")]) }
            library = try storage.load()
        } catch { writable = false; self.error = "Library could not be read or migrated. Existing files have been preserved. \(error.localizedDescription)" }
        startupCounts = Dictionary(games.map { ($0.id, $0.launchCount ?? 0) }, uniquingKeysWith: { _, last in last })
        rebuildIndex(); rebuildVisible(); selection = visible.first?.id
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                guard let self, let (id, start) = self.launchedApplications.removeValue(forKey: app.processIdentifier) else { return }
                guard self.reports[id]?.processID == app.processIdentifier else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.report(LaunchReport(state: "exited", detail: elapsed < 5 ? "Application process exited early. This can be a launcher handoff; game readiness was not verified." : "Application process exited. Game readiness was not verified.", processID: app.processIdentifier, elapsedSeconds: elapsed), gameID: id)
            }
        }
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
    func saveCustomMetadata(id: String, changes: [String: String], resetText: Bool, images: [String: URL], resetImages: Set<String>) async throws {
        guard writable else { throw LibraryError.invalid("The library is read-only.") }
        guard changes.values.allSatisfy({ $0.utf8.count <= 50_000 }) else { throw LibraryError.invalid("Metadata fields must be shorter than 50,000 bytes.") }
        if let name = changes["name"], name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw LibraryError.invalid("Game title cannot be empty.") }
        var imported: [String: String] = [:]
        for (role, url) in images { imported[role] = try await media.importImage(url, gameID: id) }
        guard var current = games.first(where: { $0.id == id }) else { try? await media.remove(gameID: id); throw LibraryError.invalid("Game no longer exists.") }
        current.applyCustomMetadata(changes: changes, reset: resetText)
        if resetImages.contains("portrait") { current.customArtwork = nil }
        if resetImages.contains("landscape") { current.customLandscape = nil }
        if resetImages.contains("background") { current.customBackground = nil }
        if let key = imported["portrait"] { current.customArtwork = key }
        if let key = imported["landscape"] { current.customLandscape = key }
        if let key = imported["background"] { current.customBackground = key }
        current.refreshMetadataSource()
        library = try storage.replacing(current, in: library); ensureSelection(); cacheRevision += 1; status = "Custom metadata and artwork saved offline for \(current.name)."
    }
    func save() {
        guard writable else { error = "Library is read-only after a load failure. Restore library.json from library.json.backup in Application Support/Joynite and restart."; return }
        do { try storage.save(library) } catch { self.error = "Could not save library: \(error.localizedDescription)" }
    }
    @discardableResult func update(_ game: Game) -> Bool {
        guard writable else { error = "Library is read-only. Restore its backup before making changes."; return false }
        do { library = try storage.replacing(game, in: library); ensureSelection(); return true }
        catch { self.error = "Could not save game: \(error.localizedDescription)"; return false }
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
    private func failLaunch(_ message: String, game: Game) {
        report(LaunchReport(state: "failed", detail: message), gameID: game.id); error = message
    }
    func launch(_ game: Game) {
        guard !restoringBackup else { return }
        if game.launchKind == .compatibility {
            guard let plan = game.compatibility else { failLaunch("Compatibility launch settings are missing.", game: game); return }
            do { try runCompatibility(plan, id: game.id); didLaunch(game) } catch { report(LaunchReport(state: "failed", detail: error.localizedDescription), gameID: game.id); self.error = error.localizedDescription }
            return
        }
        if game.launchKind == .application {
            let url = URL(fileURLWithPath: game.launchTarget)
            guard FileManager.default.fileExists(atPath: url.path), url.pathExtension == "app" else { failLaunch("This application is missing. Re-add it from its current location.", game: game); return }
            status = "Launching \(game.name)…"
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { app, failure in
                Task { @MainActor in
                    if let failure { self.report(LaunchReport(state: "failed", detail: failure.localizedDescription), gameID: game.id); self.error = "Could not launch \(game.name): \(failure.localizedDescription)" }
                    else if let app {
                        self.launchedApplications[app.processIdentifier] = (game.id, Date())
                        self.report(LaunchReport(state: "accepted", detail: "macOS accepted the application launch. Reaching the game menu is not verified.", processID: app.processIdentifier), gameID: game.id)
                        self.didLaunch(game)
                    }
                }
            }
        } else {
            guard let url = URL(string: game.launchTarget), ["steam", "heroic", "com.epicgames.launcher"].contains(url.scheme ?? "") else { failLaunch("Unsupported launch URL.", game: game); return }
            guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { failLaunch("Install \(game.launchTarget.hasPrefix("heroic:") ? "Heroic" : game.store.rawValue) to launch this game.", game: game); return }
            if NSWorkspace.shared.open(url) { report(LaunchReport(state: "accepted", detail: "The store client accepted the launch request. Complete any client prompts; game readiness is not verified."), gameID: game.id); didLaunch(game) } else { failLaunch("The store client did not accept the launch request.", game: game) }
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
        let start = Date()
        process.terminationHandler = { [weak self] child in
            try? handle.close()
            Task { @MainActor in
                guard self?.processes[id]?.processIdentifier == child.processIdentifier else { return }
                self?.processes.removeValue(forKey: id)
                self?.report(LaunchReport(state: "exited", detail: "Compatibility runtime exited. See the runtime log for errors or a launcher handoff.", processID: child.processIdentifier, exitCode: child.terminationStatus, elapsedSeconds: Date().timeIntervalSince(start)), gameID: id)
                if child.terminationStatus != 0 { self?.error = "\(plan.label) exited with status \(child.terminationStatus). Details: \(log.path)" }
            }
        }
        try process.run(); processes[id] = process
        report(LaunchReport(state: "accepted", detail: "The original compatibility runtime started. Game readiness is not verified.", processID: process.processIdentifier), gameID: id)
    }
    private func didLaunch(_ game: Game) {
        guard var current = games.first(where: { $0.id == game.id }) else { return }
        current.recordLaunch()
        if update(current) { status = "Launch request accepted for \(game.name). \(current.launchCount ?? 0) opens via Joynite." }
    }
    func toggleFavorite(_ game: Game) { var game = game; game.favorite.toggle(); update(game) }
    func remove(_ game: Game) {
        var game = game; game.hidden = true; update(game); ensureSelection()
        status = "Hidden \(game.name). Its offline metadata is retained."
    }
    func restoreHidden() {
        guard writable else { return }
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
                alert.informativeText = "Select \(game.name) in \(client) and use its Uninstall command. Joynite will keep your offline metadata until the installation has been removed."
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
        guard writable else { return }
        for game in games where UninstallPlan.confirmedMissing(game) { await finishUninstall(game) }
    }
    func cancelBackup() { backupProgress?.cancel(); backupLabel = "Cancelling backup operation…" }
    func exportLibrary() {
        guard backupProgress == nil else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Joynite-backup.zip"; panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let snapshot = library, root = media.root, progress = Progress(totalUnitCount: 1)
        backupProgress = progress; backupLabel = "Backing up library and images…"
        Task {
            defer { backupProgress = nil }
            do { try await Task.detached { try LibraryBackup.export(snapshot, media: root, to: url, progress: progress) }.value; status = "Library and artwork backed up." }
            catch is CancellationError { status = "Backup cancelled. Existing files kept." }
            catch { self.error = error.localizedDescription }
        }
    }
    func previewBackup() {
        guard backupProgress == nil else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let current = library, root = media.root, storageURL = storage.url, progress = Progress(totalUnitCount: 1)
        backupProgress = progress; backupLabel = "Verifying backup preview…"
        Task {
            defer { backupProgress = nil }
            do {
                let next = try await Task.detached { try LibraryBackup.restore(url, current: current, storage: LibraryStorage(url: storageURL), media: root, progress: progress, previewOnly: true) }.value
                let ids = Set(current.games.map(\.id)), additions = next.games.filter { !ids.contains($0.id) }
                backupProgress = nil
                let alert = NSAlert(); alert.messageText = "Backup verified"
                alert.informativeText = "Adds \(additions.count) games. Keeps all \(current.games.count) existing records and edits. Available artwork hashes verified. No library changes have been made.\n\n" + additions.prefix(10).map(\.name).joined(separator: "\n")
                alert.addButton(withTitle: "OK"); alert.runModal()
            } catch is CancellationError { status = "Backup preview cancelled." }
            catch { self.error = error.localizedDescription }
        }
    }
    func importLibrary() {
        guard writable else { error = "Library is read-only. Restore its backup before making changes."; return }
        guard !busy && !preparing && backupProgress == nil else { error = "Wait for the current scan, metadata fetch or backup to finish before restoring."; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.zip, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let current = library, root = media.root, storageURL = storage.url, progress = Progress(totalUnitCount: 1)
        backupProgress = progress; backupLabel = "Verifying and restoring backup…"; restoringBackup = true; writable = false
        Task {
            defer { writable = true; restoringBackup = false; backupProgress = nil }
            do {
                let next = try await Task.detached { () throws -> LibraryFile in
                    let storage = LibraryStorage(url: storageURL)
                    if url.pathExtension.lowercased() == "zip" { return try LibraryBackup.restore(url, current: current, storage: storage, media: root, progress: progress) }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 25_000_000 else { throw LibraryError.invalid("Library exceeds 25 MB.") }
                    let imported = try LibraryStorage(url: url).load()
                    var next = current, ids = Set(current.games.map(\.id))
                    for game in imported.games where ids.insert(game.id).inserted { next.games.append(game) }
                    if progress.isCancelled { throw CancellationError() }
                    try storage.save(next); progress.completedUnitCount = 1; return next
                }.value
                library = next; cacheRevision += 1; ensureSelection(); status = "Library restored. Existing games kept."
            } catch is CancellationError { status = "Restore cancelled. Existing library kept." }
            catch { self.error = "Import failed: \(error.localizedDescription)" }
        }
    }
}
