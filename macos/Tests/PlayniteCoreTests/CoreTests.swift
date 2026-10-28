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
            ("Conservative title normalization", suite.testNormalizationIsConservative)
        ]
        for (name, test) in tests {
            let before = failures.count
            do { try test() } catch { failures.append("\(name): \(error.localizedDescription)") }
            print("\(failures.count == before ? "PASS" : "FAIL"): \(name)")
        }
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
