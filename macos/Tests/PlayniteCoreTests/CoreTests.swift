import Foundation
import AppKit
import PlayniteCore

final class CoreTests {
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
        let plist: [String: Any] = ["CFBundleIdentifier": "test.playnite.fixture", "CFBundleName": "Fixture", "CFBundleDisplayName": "A &amp; B", "CFBundleExecutable": "Fixture"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: application.appendingPathComponent("Contents/Info.plist"))
        let game = try XCTUnwrap(Discovery.application(application))
        XCTAssertEqual(game.name, "A & B")
        XCTAssertEqual(game.launchTarget, application.path)
        XCTAssertNil(Discovery.application(root.appendingPathComponent("missing.app")))
        let ownApp = root.appendingPathComponent("Playnite.app")
        try FileManager.default.createDirectory(at: ownApp.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "io.github.joy-arz.PlayniteMac"], format: .xml, options: 0).write(to: ownApp.appendingPathComponent("Contents/Info.plist"))
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
        for title in ["Roblox", "Valorant", "Genshin Impact", "Honkai: Star Rail", "Zenless Zone Zero", "League of Legends", "Minecraft Launcher"] {
            let entry = PublisherCatalog.match(title)
            XCTAssertNotNil(entry)
            XCTAssertFalse(entry?.metadata.summary.isEmpty ?? true)
            XCTAssertFalse(entry?.metadata.developer.isEmpty ?? true)
        }
        XCTAssertNil(PublisherCatalog.match("Roblox Fake Game"))
        XCTAssertNil(PublisherCatalog.match("Genshin Impact Soundtrack"))
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
        let suite = CoreTests()
        let tests: [(String, () throws -> Void)] = [
            ("VDF nested objects, escaped paths, malformed input", suite.testVDFNestedPathsAndEscapes),
            ("Steam installed-state bitmask and directory checks", suite.testSteamDiscoveryChecksInstalledBitAndDirectory),
            ("Atomic persistence, backup, corrupt library handling", suite.testPersistenceRoundTripAndBackup),
            ("Steam metadata preserves launch identity", suite.testSteamMetadataDoesNotAlterLaunchOrFavorite),
            ("Store HTML, entities, relative artwork, host validation", suite.testStoreHTMLAttributeOrderAndEntities),
            ("Epic launch identity, URL escaping, incomplete installs", suite.testEpicLaunchUsesCatalogIdentityAndEscapesInjection),
            ("Mac application names, missing paths, self-exclusion", suite.testApplicationNamesAndSelfExclusion),
            ("Infinite five-card carousel and empty libraries", suite.testCarouselWrapping),
            ("Legacy library migration and offline metadata fields", suite.testLegacyLibraryMigrationAndOfflineFields),
            ("Publisher catalog available without network", suite.testPublisherMetadataWithoutNetwork),
            ("Uninstall plans, cancellation retention, disconnected volumes", suite.testUninstallPlansAndDisconnectedVolumes),
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
