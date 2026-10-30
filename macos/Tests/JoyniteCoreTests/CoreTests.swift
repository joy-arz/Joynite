import Foundation
import AppKit
import JoyniteCore
import ZIPFoundation

final class CoreTests {
    func testLocalLaunchCountsAndHomeOrder() throws {
        var games = (1...9).map { value -> Game in
            var game = Game(id: String(value), name: "Game \(value)", store: .local, launchKind: .application, launchTarget: "/fixture/Game.app")
            game.launchCount = UInt32(100 - value * 10); return game
        }
        let ring = HomeOrder.carousel(games)
        XCTAssertEqual(ring.map(\.id), ["1", "3", "5", "6", "7", "8", "9", "4", "2"])
        XCTAssertEqual([ring[ring.count-2].id, ring.last!.id, ring[0].id, ring[1].id, ring[2].id], ["4", "2", "1", "3", "5"])
        let counts = Dictionary(games.map { ($0.id, $0.launchCount ?? 0) }, uniquingKeysWith: { _, last in last })
        games[8].launchCount = 500
        XCTAssertEqual(HomeOrder.carousel(games, counts: counts).first?.id, "1")
        XCTAssertEqual(HomeOrder.carousel(games).first?.id, "9")
        games[7].favorite = true
        XCTAssertEqual(HomeOrder.carousel(games).first?.id, "8")
        games[7].hidden = true
        XCTAssertFalse(HomeOrder.carousel(games).contains { $0.id == "8" })
        var legacy = Game(id: "legacy", name: "Legacy", store: .local, launchKind: .application, launchTarget: "/fixture")
        legacy.lastPlayed = Date(); XCTAssertNil(legacy.launchCount)
        let data = try JSONEncoder().encode(legacy)
        legacy = try JSONDecoder().decode(Game.self, from: data); XCTAssertNil(legacy.launchCount)
        legacy.recordLaunch(); XCTAssertEqual(legacy.launchCount, 1)
        legacy.launchCount = UInt32.max; legacy.recordLaunch(); XCTAssertEqual(legacy.launchCount, UInt32.max)
        try XCTAssertEqual(try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(legacy)).launchCount, UInt32.max)
        for count in 0...5 { XCTAssertEqual(HomeOrder.carousel(Array(games.prefix(count))).count, count) }
    }
    func testLaunchReportsStayLocalAndPreserveExitDetails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let report = LaunchReport(state: "exited", detail: "Runtime ended", processID: 123, exitCode: 7, elapsedSeconds: 0.5)
        try LaunchDiagnostics.write(report, root: root, gameID: "../game")
        let loaded = LaunchDiagnostics.read(root: root, gameID: "../game")
        XCTAssertEqual(loaded?.exitCode, 7); XCTAssertEqual(loaded?.processID, 123)
        XCTAssertEqual(LaunchDiagnostics.file(root: root, gameID: "../game").deletingLastPathComponent(), root.appendingPathComponent("Logs"))
        XCTAssertNil(LaunchDiagnostics.read(root: root, gameID: "other"))
    }
    func testFuzzySearchAndPortableBackup() throws {
        let entry = GameSearch.Entry(name: "Inscryption")
        XCTAssertEqual(entry.score("INSCRYPTION"), 0)
        XCTAssertTrue(entry.score("incryption") != nil)
        XCTAssertTrue(entry.score("inkriotion") != nil)
        XCTAssertNil(entry.score("zzzzzzzzzz"))
        XCTAssertEqual(GameSearch.Entry(name: "Pokémon").score("pokemon"), 0)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("source/Media")
        var game = Game(id: "backup-test", name: "Inscryption", store: .local, launchKind: .application, launchTarget: "/missing/Game.app")
        game.launchCount = 42
        game.customArtwork = String(repeating: "a", count: 64) + ".png"
        game.metadataOverrides = ["summary": "Offline custom description"]
        let file = media.appendingPathComponent(MediaCache.identifier(game.id)).appendingPathComponent(game.customArtwork!)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let image = Data("portable artwork fixture".utf8); try image.write(to: file)
        let source = LibraryFile(games: [game]); let zip = root.appendingPathComponent("backup.zip")
        try LibraryBackup.export(source, media: media, to: zip)
        let originalArchive = try Data(contentsOf: zip), progress = Progress(totalUnitCount: 1)
        let observation = progress.observe(\.completedUnitCount, options: [.new]) { value, _ in if value.completedUnitCount >= 2 { value.cancel() } }
        try withExtendedLifetime(observation) { XCTAssertThrowsError(try LibraryBackup.export(source, media: media, to: zip, progress: progress)) }
        try XCTAssertEqual(Data(contentsOf: zip), originalArchive)
        let destination = root.appendingPathComponent("restored")
        let storage = LibraryStorage(url: destination.appendingPathComponent("library.json"))
        let preview = try LibraryBackup.restore(zip, current: LibraryFile(), storage: storage, media: destination.appendingPathComponent("Media"), previewOnly: true)
        XCTAssertEqual(preview.games.count, 1); XCTAssertFalse(FileManager.default.fileExists(atPath: storage.url.path))
        let restored = try LibraryBackup.restore(zip, current: LibraryFile(), storage: storage, media: destination.appendingPathComponent("Media"))
        XCTAssertEqual(restored.games, source.games)
        try XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Media/\(MediaCache.identifier(game.id))/\(game.customArtwork!)")), image)
        var existing = game; existing.name = "Kept edit"
        let merged = try LibraryBackup.restore(zip, current: LibraryFile(games: [existing]), storage: storage, media: destination.appendingPathComponent("Media"))
        XCTAssertEqual(merged.games.first?.name, "Kept edit")
        try Data("interrupted download".utf8).write(to: zip)
        XCTAssertThrowsError(try LibraryBackup.restore(zip, current: merged, storage: storage, media: destination.appendingPathComponent("Media")))
        try XCTAssertEqual(try storage.load().games.first?.name, "Kept edit")
    }
    func testBackupRejectsPathsAndChangedContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (index, path) in ["../escape", "library.json"].enumerated() {
            let file = root.appendingPathComponent("bad-\(index).zip")
            let archive = try Archive(url: file, accessMode: .create)
            let content = Data("{}".utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(content.count)) { position, size in content.subdata(in: Int(position)..<Int(position) + size) }
            let manifest = Data(#"{"format":1,"files":{"library.json":"incorrect"}}"#.utf8)
            try archive.addEntry(with: "manifest.json", type: .file, uncompressedSize: Int64(manifest.count)) { position, size in manifest.subdata(in: Int(position)..<Int(position) + size) }
            XCTAssertThrowsError(try LibraryBackup.restore(file, current: LibraryFile(), storage: LibraryStorage(url: root.appendingPathComponent("restored/library.json")), media: root.appendingPathComponent("restored/Media")))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("restored/library.json").path))
        }
    }
    func testVDFNestedPathsAndEscapes() throws {
        let input = #"""
        // installed libraries
        "libraryfolders" { "0" { "path" "/Volumes/Game Disk/Steam" "label" "A \"quoted\" library" } }
        "windows" "C:\\Games"
        "numeric" "123"
        "unescaped" "C:\Games"
        """#
        let value = try VDF.parse(input)
        let entry = try XCTUnwrap(VDF.object(try XCTUnwrap(VDF.object(value, "libraryfolders")), "0"))
        XCTAssertEqual(VDF.string(entry, "path"), "/Volumes/Game Disk/Steam")
        XCTAssertEqual(VDF.string(entry, "label"), "A \"quoted\" library")
        XCTAssertEqual(VDF.string(value, "windows"), "C:\\Games")
        XCTAssertEqual(VDF.string(value, "unescaped"), "C:\\Games")
        XCTAssertThrowsError(try VDF.parse("\"root\" { \"name\" \"missing brace\""))
        XCTAssertThrowsError(try VDF.parse("}"))
    }
    func testSteamDiscoveryChecksInstalledBitAndDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let steamapps = root.appendingPathComponent("Library/Application Support/Steam/steamapps")
        try FileManager.default.createDirectory(at: steamapps.appendingPathComponent("common/Test Game"), withIntermediateDirectories: true)
        let file = steamapps.appendingPathComponent("appmanifest_480.acf")
        try #"""
        "AppState" { "appid" "480" "name" "Test Game" "installdir" "Test Game" "StateFlags" "6" }
        """#.write(to: file, atomically: true, encoding: .utf8)
        let discovery = Discovery(home: root)
        let game = try XCTUnwrap(discovery.steamGame(manifest: file))
        XCTAssertEqual(game.launchTarget, "steam://rungameid/480")
        XCTAssertEqual(game.name, "Test Game")
        try #"""
        "AppState" { "appid" "480" "name" "Test Game" "installdir" "Test Game" "StateFlags" "2" }
        """#.write(to: file, atomically: true, encoding: .utf8)
        try XCTAssertNil(try discovery.steamGame(manifest: file))
    }
    func testPersistenceRoundTripAndBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryStorage(url: root.appendingPathComponent("library.json"))
        try XCTAssertTrue(try storage.load().games.isEmpty)
        let game = Game(id: "fixture", name: "Test", store: .local, launchKind: .application, launchTarget: "/Applications/Game.app")
        try storage.save(LibraryFile(games: [game]))
        try storage.save(LibraryFile())
        let previous = LibraryStorage(url: storage.url.appendingPathExtension("backup"))
        try XCTAssertEqual(try previous.load().games, [game])
        try Data("broken".utf8).write(to: storage.url)
        XCTAssertThrowsError(try storage.load())
        try XCTAssertEqual(try previous.load().games, [game])
    }
    func testSteamMetadataDoesNotAlterLaunchOrFavorite() throws {
        let data = Data(#"""
        {"480":{"success":true,"data":{"name":"Spacewar","short_description":"A &amp; B","developers":["Valve"],"genres":[{"description":"Action"}],"header_image":"https://example.com/image.jpg","release_date":{"date":"2007"}}}}
        """#.utf8)
        let details = try MetadataClient.parseSteam(data, id: "480")
        var game = Game(id: "local", name: "Spacewar", store: .itch, launchKind: .application, launchTarget: "/Games/Spacewar.app")
        game.favorite = true
        let updated = details.applying(to: game)
        XCTAssertEqual(updated.launchTarget, game.launchTarget)
        XCTAssertEqual(updated.store, .itch)
        XCTAssertTrue(updated.favorite)
        XCTAssertEqual(updated.summary, "A & B")
        XCTAssertEqual(updated.genres, ["Action"])
        XCTAssertNotNil(updated.metadataUpdated)
        XCTAssertThrowsError(try MetadataClient.parseSteam(Data(#"{"480":{"success":false}}"#.utf8), id: "480"))
    }
    func testSoftwareUpdatesAndReminderPersistence() throws {
        XCTAssertTrue(SoftwareVersion("0.10.0")! > SoftwareVersion("0.9.9")!)
        XCTAssertEqual(SoftwareVersion("v1.2.3+build5")?.description, "1.2.3")
        for invalid in ["", "garbage", "0.6.0-rc.1", "01.2.3", "1..2", "999999999999999999999.0.0"] { XCTAssertNil(SoftwareVersion(invalid)) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var reminder = UpdateReminder()
        XCTAssertTrue(reminder.allows("0.6.0", now: now))
        reminder.postpone("0.6.0", now: now)
        XCTAssertFalse(reminder.allows("0.6.0", now: now.addingTimeInterval(60)))
        XCTAssertTrue(reminder.allows("0.7.0", now: now))
        XCTAssertTrue(reminder.allows("0.6.0", now: now.addingTimeInterval(86400)))
        reminder.skip("0.6.0")
        let restored = try JSONDecoder().decode(UpdateReminder.self, from: JSONEncoder().encode(reminder))
        XCTAssertFalse(restored.allows("0.6.0", now: now.addingTimeInterval(90000)))
        XCTAssertTrue(restored.allows("0.7.0", now: now))
        let asset = "https://github.com/joy-arz/Joynite/releases/download/v0.6.0/"
        let payload: [String: Any] = ["tag_name": "v0.6.0", "draft": false, "prerelease": false, "assets": [["name":"Joynite-0.6.0-arm64.zip","browser_download_url":asset + "Joynite-0.6.0-arm64.zip","size":1000],["name":"appcast.xml","browser_download_url":asset + "appcast.xml","size":500]]]
        func release(_ payload: [String: Any]) throws -> SoftwareRelease { try JSONDecoder().decode(SoftwareRelease.self, from: JSONSerialization.data(withJSONObject: payload)) }
        let valid = try release(payload)
        XCTAssertEqual(valid.nativeUpdate(after: "0.5.0", architecture: "arm64")?.description, "0.6.0")
        XCTAssertNil(valid.nativeUpdate(after: "0.6.0", architecture: "arm64"))
        XCTAssertNil(valid.nativeUpdate(after: "0.5.0", architecture: "x86_64"))
        var altered = payload; altered["prerelease"] = true
        try XCTAssertNil(try release(altered).nativeUpdate(after: "0.5.0", architecture: "arm64"))
        altered = payload; altered["assets"] = [["name":"Joynite-0.6.0-arm64.zip","browser_download_url":"https://evil.invalid/app.zip","size":1000]]
        try XCTAssertNil(try release(altered).nativeUpdate(after: "0.5.0", architecture: "arm64"))
    }
    func testGameEditCommitReportsStorageFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blocked = root.appendingPathComponent("not-a-directory"); try Data("blocked".utf8).write(to: blocked)
        let original = Game(id: "fixture", name: "Before", store: .local, launchKind: .application, launchTarget: "/game.app")
        var edited = original; edited.name = "After"
        let library = LibraryFile(games: [original])
        XCTAssertThrowsError(try LibraryStorage(url: blocked.appendingPathComponent("library.json")).replacing(edited, in: library))
        XCTAssertEqual(library.games, [original])
        let storage = LibraryStorage(url: root.appendingPathComponent("library.json"))
        let committed = try storage.replacing(edited, in: library)
        try XCTAssertEqual(try storage.load().games, committed.games)
    }
    func testJoyniteMigrationAndIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("PlayniteMac")
        let current = root.appendingPathComponent("Joynite")
        let media = old.appendingPathComponent("Media/game")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        var game = Game(id: "migrated", name: "Inscryption", store: .local, launchKind: .application, launchTarget: "/Games/Inscryption.app")
        game.favorite = true; game.applyCustomMetadata(changes: ["developer": "My studio"])
        try LibraryStorage(url: old.appendingPathComponent("library.json")).save(LibraryFile(games: [game]))
        try Data("image fixture".utf8).write(to: media.appendingPathComponent("cover.png"))
        try LibraryMigration.prepare(destination: current, legacyDirectories: [old])
        try XCTAssertEqual(try LibraryStorage(url: current.appendingPathComponent("library.json")).load().games, [game])
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.appendingPathComponent("Media/game/cover.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("library.json").path))
        try LibraryStorage(url: current.appendingPathComponent("library.json")).save(LibraryFile())
        try LibraryMigration.prepare(destination: current, legacyDirectories: [old])
        try XCTAssertTrue(try LibraryStorage(url: current.appendingPathComponent("library.json")).load().games.isEmpty)
        for id in ["io.github.joy-arz.JoyniteNative", "io.github.joy-arz.joynite.desktop", "io.github.joy-arz.PlayniteMac", "io.github.joy-arz.playnite-carousel"] { XCTAssertTrue(JoyniteIdentity.isLauncher(id)) }
        XCTAssertFalse(JoyniteIdentity.isLauncher("com.game.inscryption"))
    }
    func testCustomMetadataSurvivesRefreshAndReset() throws {
        var game = Game(id: "custom", name: "Original", store: .local, launchKind: .application, launchTarget: "/Games/Original.app")
        game = Metadata(summary: "Automatic", developer: "Studio", source: "Steam").applying(to: game)
        game.applyCustomMetadata(changes: ["name": "My title", "summary": "", "genres": "Action, Puzzle", "launchTarget": "/bad"])
        XCTAssertEqual(game.name, "My title"); XCTAssertEqual(game.summary, "")
        XCTAssertEqual(game.genres, ["Action", "Puzzle"]); XCTAssertEqual(game.launchTarget, "/Games/Original.app")
        game.customArtwork = MediaCache.identifier("custom") + ".png"
        game = Metadata(summary: "Updated automatic", developer: "New studio", source: "GOG").applying(to: game)
        XCTAssertEqual(game.name, "My title"); XCTAssertEqual(game.summary, "")
        XCTAssertEqual(game.developer, "New studio"); XCTAssertEqual(game.metadataSource, "GOG + custom")
        let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(decoded, game)
        game.applyCustomMetadata(changes: [:], reset: true)
        XCTAssertEqual(game.name, "Original"); XCTAssertEqual(game.summary, "Updated automatic")
        XCTAssertNotNil(game.customArtwork)
        game.customArtwork = nil; game.refreshMetadataSource()
        XCTAssertEqual(game.metadataSource, "GOG")
    }
    func testStoreHTMLAttributeOrderAndEntities() throws {
        let html = #"""
        <meta content="Game &amp; Friends" property="og:title">
        <meta name='description' content='Build &#x1F680; &amp; play &#39;today&#39;.'>
        <meta content='/cover.png' property='og:image'>
        """#
        let data = try HTML.metadata(html, url: URL(string: "https://developer.itch.io/game")!)
        XCTAssertEqual(data.name, "Game & Friends")
        XCTAssertEqual(data.summary, "Build 🚀 & play 'today'.")
        XCTAssertEqual(data.artwork, "https://developer.itch.io/cover.png")
        XCTAssertEqual(data.source, "itch.io")
        XCTAssertThrowsError(try HTML.metadata("<html>blocked</html>", url: URL(string: "https://www.gog.com/game/x")!))
        XCTAssertTrue(MetadataClient.allowedHost("developer.itch.io"))
        XCTAssertFalse(MetadataClient.allowedHost("itch.io.evil.example"))
        XCTAssertFalse(MetadataClient.allowedHost("notgog.com"))
    }
    func testEpicLaunchUsesCatalogIdentityAndEscapesInjection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let json: [String: Any] = ["DisplayName": "Game", "AppName": "name&bad=true", "CatalogNamespace": "namespace", "CatalogItemId": "item", "InstallLocation": root.path]
        let game = try XCTUnwrap(Discovery.epicGame(json))
        XCTAssertTrue(game.launchTarget.contains("namespace:item:name%26bad=true"))
        XCTAssertTrue(game.launchTarget.hasSuffix("?action=launch&silent=true"))
        var incomplete = json; incomplete["bIsIncompleteInstall"] = true
        XCTAssertNil(Discovery.epicGame(incomplete))
    }
    func testApplicationNamesAndSelfExclusion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let application = root.appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: application.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.joynite.fixture", "CFBundleName": "Fixture", "CFBundleDisplayName": "A &amp; B", "CFBundleExecutable": "Fixture"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: application.appendingPathComponent("Contents/Info.plist"))
        let game = try XCTUnwrap(Discovery.application(application))
        XCTAssertEqual(game.name, "A & B")
        XCTAssertEqual(game.launchTarget, application.path)
        XCTAssertNil(Discovery.application(root.appendingPathComponent("missing.app")))
        let ownApp = root.appendingPathComponent("Joynite.app")
        try FileManager.default.createDirectory(at: ownApp.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "io.github.joy-arz.Joynite"], format: .xml, options: 0).write(to: ownApp.appendingPathComponent("Contents/Info.plist"))
        XCTAssertNil(Discovery.application(ownApp))
    }
    func testCarouselWrapping() throws {
        let games = (0..<5).map { Game(id: String($0), name: "Game \($0)", store: .local, launchKind: .application, launchTarget: "/Games/\($0).app") }
        XCTAssertEqual(Carousel.move("0", by: -1, in: games), "4")
        XCTAssertEqual(Carousel.move("4", by: 1, in: games), "0")
        XCTAssertEqual(Carousel.move("2", by: 500, in: games), "2")
        XCTAssertEqual(Carousel.wrappedIndex(-1001, count: 5), 4)
        XCTAssertEqual(Carousel.slots(count: 5), [-2, -1, 0, 1, 2])
        XCTAssertEqual(Carousel.slots(count: 1), [0])
        var game = games[0]
        game.storeURL = "https://store.steampowered.com/app/480/"
        XCTAssertEqual(MediaCache.portraitURL(for: game), "https://cdn.akamai.steamstatic.com/steam/apps/480/library_600x900.jpg")
        game.storeURL = "https://store.steampowered.com.evil.example/app/480/"
        XCTAssertNil(MediaCache.portraitURL(for: game))
        XCTAssertNil(Carousel.move(nil, by: 1, in: []))
        XCTAssertNil(Carousel.wrappedIndex(0, count: 0))
    }
    func testLegacyLibraryMigrationAndOfflineFields() throws {
        let game = Game(id: "legacy", name: "Legacy", store: .local, launchKind: .application, launchTarget: "/Games/Legacy.app")
        let data = try JSONEncoder().encode(game)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["backgroundArtwork", "cachedArtwork", "cachedBackground", "hidden", "pendingUninstall"] { json.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(Game.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.id, game.id); XCTAssertNil(legacy.cachedArtwork); XCTAssertNil(legacy.hidden)
        var updated = Metadata(summary: "Saved description", background: "https://example.com/scene.jpg").applying(to: legacy)
        updated.cachedArtwork = MediaCache.identifier("cover") + ".png"; updated.hidden = true
        let roundTrip = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(roundTrip.summary, "Saved description")
        XCTAssertEqual(roundTrip.backgroundArtwork, "https://example.com/scene.jpg")
        XCTAssertEqual(roundTrip.cachedArtwork, updated.cachedArtwork)
        XCTAssertEqual(roundTrip.hidden, true)
        XCTAssertEqual(Metadata(summary: "").applying(to: updated).summary, "Saved description")
    }
    func testPublisherMetadataWithoutNetwork() {
        for title in ["Roblox", "Valorant", "Genshin Impact", "Honkai: Star Rail", "Zenless Zone Zero", "League of Legends", "Minecraft Launcher", "EDOPro", "YGOPro", "YGOPro Percy", "YGOPro 2", "KoishiPro", "YGO Omega", "MDPro3"] {
            let entry = PublisherCatalog.match(title)
            XCTAssertNotNil(entry)
            XCTAssertFalse(entry?.metadata.summary.isEmpty ?? true)
            XCTAssertFalse(entry?.metadata.developer.isEmpty ?? true)
        }
        XCTAssertNil(PublisherCatalog.match("Roblox Fake Game"))
        XCTAssertNil(PublisherCatalog.match("Genshin Impact Soundtrack"))
        for (alias, id) in [("edopro.exe", "edopro"), ("Project Ignis", "edopro"), ("ygopro_percy.exe", "ygopro-percy"), ("YGOPro2", "ygopro2"), ("Koishi Pro", "koishipro"), ("YGO Omega (Mac)", "ygo-omega"), ("mdpro3.exe", "mdpro3")] { XCTAssertEqual(PublisherCatalog.match(alias)?.id, id) }
        for name in ["EDOPro Installer", "YGOPro Soundtrack", "YGOPro 2 Server", "YGO Omega Server", "MDPro30", "KoishiPro 2"] { XCTAssertNil(PublisherCatalog.match(name)) }
        XCTAssertTrue(MetadataClient.allowedHost("projectignis.github.io"))
        XCTAssertTrue(MetadataClient.allowedHost("cli.koishi.pro"))
        XCTAssertFalse(MetadataClient.allowedHost("projectignis.github.io.evil.example"))
        for name in ["EDOPro", "YGOPro", "YGOPro Percy", "YGOPro 2", "KoishiPro", "YGO Omega", "MDPro3"] {
            if let entry = PublisherCatalog.match(name) {
                var game = Game(id: "project-test", name: name, store: .local, launchKind: .application, launchTarget: "/fixture/Game.app")
                game.favorite = true; game.customArtwork = "custom-cover.png"
                game.applyCustomMetadata(changes: ["summary": "My offline notes"])
                let updated = entry.metadata.applying(to: game)
                XCTAssertEqual(updated.launchTarget, game.launchTarget)
                XCTAssertEqual(updated.summary, "My offline notes")
                XCTAssertEqual(updated.customArtwork, "custom-cover.png")
                XCTAssertTrue(updated.favorite)
                XCTAssertEqual(updated.developer, entry.metadata.developer)
            }
        }
    }
    func testUninstallPlansAndDisconnectedVolumes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Fixture.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "fixture.uninstall"], format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        var game = Game(id: "fixture", name: "Fixture", store: .local, launchKind: .application, launchTarget: app.path, installPath: app.path)
        if case .trashApplication(let planned) = try UninstallPlan.make(for: game) { XCTAssertEqual(planned.path, app.path) }
        else { throw LibraryError.invalid("Expected native Trash uninstall plan.") }
        game.installPath = root.path
        XCTAssertThrowsError(try UninstallPlan.make(for: game))
        var steam = Game(id: "steam:480", name: "Steam game", store: .steam, launchKind: .store, launchTarget: "steam://rungameid/480", storeID: "480")
        try XCTAssertEqual(try UninstallPlan.make(for: steam), .steam(URL(string: "steam://uninstall/480")!))
        steam.storeID = "480&malformed=true"
        XCTAssertThrowsError(try UninstallPlan.make(for: steam))
        game.installPath = root.appendingPathComponent("missing.app").path
        XCTAssertFalse(UninstallPlan.confirmedMissing(game))
        game.pendingUninstall = true
        XCTAssertTrue(UninstallPlan.confirmedMissing(game))
        game.installPath = "/Volumes/Disconnected-Validation-Disk/Games/Example.app"
        XCTAssertFalse(UninstallPlan.confirmedMissing(game))
        game.installPath = app.path
        XCTAssertFalse(UninstallPlan.confirmedMissing(game))
    }
    func testCompatibilitySteamRoutesAndArtworkRoles() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        for name in ["First", "Second"] {
            let wrapper = home.appendingPathComponent("Applications/Sikarugir/\(name).app")
            let prefix = wrapper.appendingPathComponent("Contents/SharedSupport/prefix")
            let steam = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam")
            let runtime = wrapper.appendingPathComponent("Contents/SharedSupport/wine/bin/wine")
            try FileManager.default.createDirectory(at: steam.appendingPathComponent("steamapps/common/Prefix Game"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: runtime.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: steam.appendingPathComponent("steam.exe"))
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: runtime)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "fixture.\(name)", "CFBundleName": name], format: .xml, options: 0).write(to: wrapper.appendingPathComponent("Contents/Info.plist"))
            try #"""
            "AppState" { "appid" "480" "name" "Prefix Game" "installdir" "Prefix Game" "StateFlags" "4" }
            """#.write(to: steam.appendingPathComponent("steamapps/appmanifest_480.acf"), atomically: true, encoding: .utf8)
        }
        let games = Discovery(home: home).scan(folders: []).games.filter { $0.name == "Prefix Game" }
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(Set(games.map(\.id)).count, 2)
        for game in games {
            XCTAssertEqual(game.launchKind, .compatibility)
            let plan = try XCTUnwrap(game.compatibility)
            XCTAssertTrue(plan.executable.hasSuffix("Contents/SharedSupport/wine/bin/wine"))
            XCTAssertEqual(Array(plan.arguments.suffix(2)), ["-applaunch", "480"])
            XCTAssertTrue(plan.environment["WINEPREFIX"]?.contains(".app/Contents/SharedSupport/prefix") == true)
            let encoded = try JSONEncoder().encode(game)
            let decoded = try JSONDecoder().decode(Game.self, from: encoded)
            XCTAssertEqual(decoded.compatibility, game.compatibility)
            if case .compatibility(let uninstall) = try UninstallPlan.make(for: game) { XCTAssertEqual(uninstall.arguments.last, "steam://uninstall/480") }
            else { throw LibraryError.invalid("Expected prefix-specific uninstall plan.") }
        }
        XCTAssertEqual(CompatibilityDiscovery.resolveWindowsPath("C:\\Games\\Steam", prefix: home)?.path, home.appendingPathComponent("drive_c/Games/Steam").path)
        XCTAssertNil(CompatibilityDiscovery.resolveWindowsPath("C:\\..\\Users", prefix: home))
        XCTAssertTrue(CachedImageRole.portrait.fits(width: 600, height: 900))
        XCTAssertFalse(CachedImageRole.portrait.fits(width: 1920, height: 1080))
        XCTAssertTrue(CachedImageRole.landscape.fits(width: 460, height: 215))
        XCTAssertFalse(CachedImageRole.landscape.fits(width: 600, height: 900))
    }
    func testNormalizationIsConservative() {
        XCTAssertEqual(Game.normalized("Hades™"), Game.normalized("Hades"))
        XCTAssertNotEqual(Game.normalized("Hades II"), Game.normalized("Hades"))
    }
}

private var failures: [String] = []
private var assertions = 0
private func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) rethrows { assertions += 1; if try !value() { failures.append("\(file):\(line): expected true") } }
private func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) rethrows { assertions += 1; if try value() { failures.append("\(file):\(line): expected false") } }
private func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) rethrows { assertions += 1; if try lhs() != rhs() { failures.append("\(file):\(line): values differ") } }
private func XCTAssertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, line: UInt = #line) { assertions += 1; if lhs == rhs { failures.append("line \(line): values unexpectedly equal") } }
private func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, line: UInt = #line) rethrows { assertions += 1; if try value() != nil { failures.append("line \(line): expected nil") } }
private func XCTAssertNotNil<T>(_ value: T?, line: UInt = #line) { assertions += 1; if value == nil { failures.append("line \(line): expected non-nil") } }
private func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw LibraryError.invalid("Expected a non-nil value.") }; return value }
private func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, line: UInt = #line) { assertions += 1; do { _ = try value(); failures.append("line \(line): expected error") } catch {} }

@main enum Validation {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--benchmark") {
            for count in [1000, 10000] {
                let games = (0..<count).map { Game(id: "bench-\($0)", name: "Game \($0) Adventure", store: .local, launchKind: .application, launchTarget: "/missing") }
                let start = Date(); let entries = games.map { GameSearch.Entry(name: $0.name) }; let indexed = Date()
                let matches = entries.compactMap { $0.score("inkriotion") }; let searched = Date()
                let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do { try LibraryStorage(url: root.appendingPathComponent("library.json")).save(LibraryFile(games: games)); print("BENCH native count=\(count) index_ms=\(indexed.timeIntervalSince(start)*1000) fuzzy_ms=\(searched.timeIntervalSince(indexed)*1000) save_ms=\(Date().timeIntervalSince(searched)*1000) matches=\(matches.count)"); try? FileManager.default.removeItem(at: root) }
                catch { print("BENCH failed: \(error)"); exit(1) }
            }
            return
        }
        let suite = CoreTests()
        let tests: [(String, () throws -> Void)] = [
            ("Local launch counts, startup center and stable session order", suite.testLocalLaunchCountsAndHomeOrder),
            ("Local launch diagnostic report integrity", suite.testLaunchReportsStayLocalAndPreserveExitDetails),
            ("Backup traversal and altered-content rejection", suite.testBackupRejectsPathsAndChangedContent),
            ("Fuzzy search and portable offline backup", suite.testFuzzySearchAndPortableBackup),
            ("VDF nested objects, escaped paths, malformed input", suite.testVDFNestedPathsAndEscapes),
            ("Steam installed-state bitmask and directory checks", suite.testSteamDiscoveryChecksInstalledBitAndDirectory),
            ("Atomic persistence, backup, corrupt library handling", suite.testPersistenceRoundTripAndBackup),
            ("Steam metadata preserves launch identity", suite.testSteamMetadataDoesNotAlterLaunchOrFavorite),
            ("Release filtering, version ordering, reminder persistence", suite.testSoftwareUpdatesAndReminderPersistence),
            ("Game edit commits surface storage failures", suite.testGameEditCommitReportsStorageFailure),
            ("Joynite migration retains offline media and metadata; self-exclusion", suite.testJoyniteMigrationAndIdentity),
            ("Custom overrides, refresh, serialization, automatic reset", suite.testCustomMetadataSurvivesRefreshAndReset),
            ("Store HTML, entities, relative artwork, host validation", suite.testStoreHTMLAttributeOrderAndEntities),
            ("Epic launch identity, URL escaping, incomplete installs", suite.testEpicLaunchUsesCatalogIdentityAndEscapesInjection),
            ("Mac application names, missing paths, self-exclusion", suite.testApplicationNamesAndSelfExclusion),
            ("Infinite five-card carousel and empty libraries", suite.testCarouselWrapping),
            ("Legacy library migration and offline metadata fields", suite.testLegacyLibraryMigrationAndOfflineFields),
            ("Publisher catalog available without network", suite.testPublisherMetadataWithoutNetwork),
            ("Uninstall plans, cancellation retention, disconnected volumes", suite.testUninstallPlansAndDisconnectedVolumes),
            ("Prefix-specific Wine Steam routes and three artwork roles", suite.testCompatibilitySteamRoutesAndArtworkRoles),
            ("Conservative title normalization", suite.testNormalizationIsConservative)
        ]
        for (name, test) in tests {
            let before = failures.count
            do { try test() } catch { failures.append("\(name): \(error.localizedDescription)") }
            print("\(failures.count == before ? "PASS" : "FAIL"): \(name)")
        }
        do {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let bytes = bitmap.representation(using: .png, properties: [:])!
            let remote = "https://offline.example.invalid/cover.png"
            let key = MediaCache.identifier(remote) + ".png"
            let cache = MediaCache(root: root)
            _ = try await cache.store(bytes, gameID: "game1", key: key)
            _ = try await cache.store(bytes, gameID: "game2", key: key)
            XCTAssertNotNil(cache.file(gameID: "game1", key: key))
            XCTAssertNil(cache.file(gameID: "game1", key: "../../etc/passwd"))
            let customURL = root.appendingPathComponent("original-custom.png")
            try bytes.write(to: customURL)
            let imported = try await cache.importImage(customURL, gameID: "game2")
            try FileManager.default.removeItem(at: customURL)
            XCTAssertNotNil(cache.file(gameID: "game2", key: imported))
            let restarted = MediaCache(root: root)
            let offlineKey = try await restarted.cache(remote, gameID: "game1")
            XCTAssertEqual(offlineKey, key)
            XCTAssertNotNil(NSImage(contentsOf: try XCTUnwrap(restarted.file(gameID: "game1", key: key))))
            try await restarted.remove(gameID: "game1")
            XCTAssertNil(restarted.file(gameID: "game1", key: key))
            XCTAssertNotNil(restarted.file(gameID: "game2", key: key))
            print("PASS: artwork survives restart, works without network, isolated uninstall cleanup")
        } catch { failures.append("Offline artwork validation: \(error.localizedDescription)") }
        if CommandLine.arguments.contains("--live") {
            let client = MetadataClient()
            do {
                let matches = try await client.search("Hades")
                XCTAssertTrue(matches.contains { $0.id == "1145360" && $0.name == "Hades" })
                let details = try await client.steam("1145360")
                XCTAssertEqual(details.name, "Hades"); XCTAssertFalse(details.summary.isEmpty); XCTAssertFalse(details.artwork.isEmpty)
                print("PASS: live Steam search and app details")
            } catch { failures.append("Live Steam: \(error.localizedDescription)") }
            for (url, provider) in [("https://sokpop.itch.io/stacklands", "itch.io"), ("https://www.gog.com/en/game/loop_hero", "GOG")] {
                do {
                    let details = try await client.page(url)
                    XCTAssertEqual(details.source, provider); XCTAssertFalse(details.summary.isEmpty); XCTAssertFalse(details.artwork.isEmpty)
                    print("PASS: live \(provider) metadata")
                } catch { failures.append("Live \(provider): \(error.localizedDescription)") }
            }
        }
        print("\(assertions) assertions. \(failures.count) failures.")
        failures.forEach { print("FAIL: " + $0) }
        exit(failures.isEmpty ? 0 : 1)
    }
}
