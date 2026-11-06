import Foundation
import Combine
import JoyniteCore

@main enum ModelValidation {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        setenv("JOYNITE_DATA_DIRECTORY", root.path, 1)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ModelProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var games = (0..<400).map { Game(id: String($0), name: "Game \($0)", store: .local, launchKind: .store, launchTarget: "steam://rungameid/480") }
        games[0].storeURL = "https://fixture.itch.io/slow"
        let storage = LibraryStorage(url: root.appendingPathComponent("library.json"))
        try storage.save(LibraryFile(games: games))
        let installedGames = games
        let model = LibraryModel(metadata: MetadataClient(session: session), discover: { _ in
            DiscoveryResult(games: installedGames.map { original in var game = original; game.launchTarget = "steam://rungameid/481"; return game })
        })
        var emissions = 0
        let observer = model.$library.dropFirst().sink { _ in emissions += 1 }
        await model.scan(fetchMetadata: false)
        precondition(emissions == 1, "Scan must publish one batch")
        precondition(model.games.allSatisfy { $0.launchTarget == "steam://rungameid/481" })
        await model.scan(fetchMetadata: false)
        precondition(emissions == 1, "Unchanged scan must not republish")
        observer.cancel()
        print("PASS: 400-record native scan publishes once; unchanged scan publishes zero times")
        let refresh = Task { await model.refresh() }
        try await Task.sleep(nanoseconds: 100_000_000)
        await model.applyMetadata(Metadata(summary: "New manual selection", source: "Manual match"), to: "0")
        // Stop the remaining fixture queue after the first delayed result has returned.
        try await Task.sleep(nanoseconds: 600_000_000)
        refresh.cancel(); await refresh.value
        precondition(model.games[0].summary == "New manual selection", "Older provider result overwrote manual choice")
        print("PASS: delayed native provider cannot replace a newer manual match")
        var foreign = model.games[0]
        foreign.launchKind = .executable
        let count = foreign.launchCount
        model.launch(foreign)
        precondition(model.error?.contains("shared desktop edition") == true)
        precondition(foreign.launchCount == count)
        print("PASS: foreign launch routes are retained and rejected without launching")
        var changed = games; changed[0].launchTarget = "steam://rungameid/482"
        let changedGames = changed
        let failing = LibraryModel(discover: { _ in DiscoveryResult(games: changedGames) })
        let before = failing.library
        try FileManager.default.removeItem(at: storage.url.appendingPathExtension("backup"))
        try FileManager.default.createDirectory(at: storage.url.appendingPathExtension("backup"), withIntermediateDirectories: true)
        await failing.scan(fetchMetadata: false)
        precondition(failing.library == before && failing.error != nil, "Failed scan save changed live state")
        print("PASS: failed scan commit retains the prior live library")
    }
}
private final class ModelProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let slow = request.url!.path == "/slow"
        let body = slow ? "<meta property='og:title' content='Game 0'><meta property='og:description' content='Older automatic result'>" : #"{"items":[]}"#
        DispatchQueue.global().asyncAfter(deadline: .now() + (slow ? 0.4 : 0)) { [self] in
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
