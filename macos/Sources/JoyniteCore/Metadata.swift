import Foundation

public struct SearchMatch: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var artwork: String
}
public actor MetadataClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    private func request(_ url: URL) async throws -> Data {
        guard (ProcessInfo.processInfo.environment["JOYNITE_OFFLINE"] ?? ProcessInfo.processInfo.environment["PLAYNITE_OFFLINE"]) != "1" else { throw LibraryError.invalid("Offline mode: saved metadata remains available.") }
        guard url.scheme == "https", Self.allowedHost(url.host ?? "") else { throw LibraryError.invalid("Use an HTTPS store page or a supported project/publisher page.") }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        request.setValue("Joynite/0.4 (+https://github.com/joy-arz/Joynite)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let finalURL = http.url, finalURL.scheme == "https", Self.allowedHost(finalURL.host ?? "") else {
            throw LibraryError.invalid("\(url.host ?? "Store") could not provide metadata. Try a Steam match or a different store page.")
        }
        guard data.count < 12_000_000 else { throw LibraryError.invalid("Store response exceeds the 12 MB limit.") }
        return data
    }
    public static func allowedHost(_ host: String) -> Bool {
        let standard = ["steampowered.com", "gog.com", "epicgames.com", "itch.io", "roblox.com", "playvalorant.com", "hoyoverse.com", "leagueoflegends.com", "minecraft.net"].contains { host == $0 || host.hasSuffix("." + $0) }
        return standard || PublisherCatalog.games.contains { entry in
            guard let domain = URL(string: entry.metadata.url)?.host else { return false }
            return host == domain || host.hasSuffix("." + domain)
        }
    }
    public func search(_ name: String) async throws -> [SearchMatch] {
        var components = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
        components.queryItems = [.init(name: "term", value: name), .init(name: "l", value: "english"), .init(name: "cc", value: "us")]
        let data = try await request(components.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let items = json["items"] as? [[String: Any]] else { throw LibraryError.invalid("Steam returned an unsupported search response.") }
        return items.compactMap { item in
            guard item["type"] as? String == "app", let id = item["id"] as? Int, let name = item["name"] as? String else { return nil }
            return SearchMatch(id: String(id), name: name, artwork: item["tiny_image"] as? String ?? "")
        }
    }
    public func steam(_ id: String) async throws -> Metadata {
        guard Int(id) != nil else { throw LibraryError.invalid("Steam app ID must be numeric.") }
        let data = try await request(URL(string: "https://store.steampowered.com/api/appdetails?appids=\(id)&l=english&cc=us")!)
        return try Self.parseSteam(data, id: id)
    }
    public static func parseSteam(_ data: Data, id: String) throws -> Metadata {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let wrapper = root[id] as? [String: Any], wrapper["success"] as? Bool == true, let item = wrapper["data"] as? [String: Any] else { throw LibraryError.invalid("Steam has no public details for app \(id).") }
        return Metadata(name: item["name"] as? String ?? "", summary: HTML.text(item["short_description"] as? String ?? ""), developer: (item["developers"] as? [String] ?? []).joined(separator: ", "), releaseDate: (item["release_date"] as? [String: Any])?["date"] as? String ?? "", artwork: item["header_image"] as? String ?? "", url: "https://store.steampowered.com/app/\(id)/", source: "Steam", genres: (item["genres"] as? [[String: Any]] ?? []).compactMap { $0["description"] as? String }, background: (item["screenshots"] as? [[String: Any]])?.first?["path_full"] as? String ?? item["background_raw"] as? String ?? "")
    }
    public func page(_ value: String) async throws -> Metadata {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", let host = url.host, Self.allowedHost(host) else { throw LibraryError.invalid("Enter an HTTPS Steam, GOG, Epic Games, or itch.io store page.") }
        let parts = url.pathComponents
        if host.hasSuffix("steampowered.com"), let index = parts.firstIndex(of: "app"), index + 1 < parts.count { return try await steam(parts[index + 1]) }
        let data = try await request(url)
        guard let html = String(data: data, encoding: .utf8) else { throw LibraryError.invalid("Store page is not UTF-8.") }
        return try HTML.metadata(html, url: url)
    }
    public func publisher(_ entry: PublisherGame) async -> Metadata {
        var details = entry.metadata
        if let remote = try? await page(details.url) {
            if details.artwork.isEmpty && !remote.artwork.isEmpty { details.artwork = remote.artwork }
            if details.background.isEmpty && !remote.background.isEmpty { details.background = remote.background }
        }
        return details
    }
    public func automatic(_ game: Game) async throws -> Metadata {
        if let entry = PublisherCatalog.match(game.name) { return await publisher(entry) }
        if game.store == .steam, !game.storeID.isEmpty { return try await steam(game.storeID) }
        if !game.storeURL.isEmpty { return try await page(game.storeURL) }
        let matches = try await search(game.name)
        let exact = matches.filter { Game.normalized($0.name) == Game.normalized(game.name) }
        if exact.count == 1 { return try await steam(exact[0].id) }
        if game.store == .gog {
            var c = URLComponents(string: "https://catalog.gog.com/v1/catalog")!
            c.queryItems = [.init(name: "query", value: game.name), .init(name: "limit", value: "10"), .init(name: "countryCode", value: "US"), .init(name: "locale", value: "en-US"), .init(name: "currencyCode", value: "USD")]
            let data = try await request(c.url!)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let products = json["products"] as? [[String: Any]] ?? []
            let exact = products.filter { Game.normalized($0["title"] as? String ?? "") == Game.normalized(game.name) }
            if exact.count == 1, let path = exact[0]["storeLink"] as? String, let url = URL(string: path, relativeTo: URL(string: "https://www.gog.com"))?.absoluteURL { return try await page(url.absoluteString) }
        }
        throw LibraryError.invalid("No unambiguous metadata match for \(game.name). Use Find metadata to choose a match or paste its store page.")
    }
}

public enum HTML {
    public static func text(_ value: String) -> String {
        var output = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, replacement) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] { output = output.replacingOccurrences(of: entity, with: replacement) }
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            let source = output as NSString
            for match in regex.matches(in: output, range: NSRange(location: 0, length: source.length)).reversed() {
                let code = source.substring(with: match.range(at: 1))
                let number = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
                if let number, let scalar = UnicodeScalar(number), let range = Range(match.range, in: output) { output.replaceSubrange(range, with: String(scalar)) }
            }
        }
        return output.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func metadata(_ html: String, url: URL) throws -> Metadata {
        var tags: [String: String] = [:]
        let tagRegex = try NSRegularExpression(pattern: "<meta\\s+[^>]*>", options: [.caseInsensitive])
        let attributeRegex = try NSRegularExpression(pattern: "([\\w:-]+)\\s*=\\s*([\"'])(.*?)\\2", options: [.dotMatchesLineSeparators])
        let source = html as NSString
        for match in tagRegex.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let tag = source.substring(with: match.range); let ns = tag as NSString
            var attributes: [String: String] = [:]
            for a in attributeRegex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) { attributes[ns.substring(with: a.range(at: 1)).lowercased()] = ns.substring(with: a.range(at: 3)) }
            if let key = attributes["property"] ?? attributes["name"], let value = attributes["content"] { tags[key.lowercased()] = text(value) }
        }
        let name = tags["og:title"] ?? tags["twitter:title"] ?? ""
        let description = tags["og:description"] ?? tags["description"] ?? ""
        guard !name.isEmpty, !description.isEmpty else { throw LibraryError.invalid("This store page did not expose a game title and description. Select a Steam match instead.") }
        let image = tags["og:image"] ?? tags["twitter:image"] ?? ""
        let artwork = URL(string: image, relativeTo: url)?.absoluteURL
        let host = url.host ?? ""
        let sourceName = host.hasSuffix("itch.io") ? "itch.io" : host.hasSuffix("gog.com") ? "GOG" : host.hasSuffix("epicgames.com") ? "Epic Games" : host
        return Metadata(name: name, summary: description, artwork: artwork?.scheme == "https" ? artwork!.absoluteString : "", url: url.absoluteString, source: sourceName, background: tags["twitter:image:src"] ?? "")
    }
}
