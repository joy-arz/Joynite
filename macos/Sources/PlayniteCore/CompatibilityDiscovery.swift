import Foundation

public struct CompatibilityDiscovery {
    let home: URL
    let fm = FileManager.default
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    public func scan(apps: [Game], folders: [String]) -> DiscoveryResult {
        var result = DiscoveryResult()
        var prefixes: [(URL, URL?, String)] = [(home.appendingPathComponent(".wine"), nil, "Wine")]
        for relative in ["Library/Application Support/CrossOver/Bottles", "Library/Containers/com.isaacmarovitz.Whisky/Bottles", "Library/Containers/com.isaacmarovitz.Whisky/Data/Bottles"] {
            let root = home.appendingPathComponent(relative)
            for child in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] {
                prefixes.append((child, nil, relative.contains("CrossOver") ? "CrossOver" : "Wine"))
            }
        }
        for game in apps where game.launchKind == .application {
            let wrapper = URL(fileURLWithPath: game.launchTarget)
            for relative in ["Contents/SharedSupport/prefix", "Contents/Resources"] {
                let prefix = wrapper.appendingPathComponent(relative)
                if fm.fileExists(atPath: prefix.appendingPathComponent("drive_c").path) { prefixes.append((prefix, wrapper, "Sikarugir / Wineskin")) }
            }
        }
        for path in folders {
            let root = URL(fileURLWithPath: path)
            if fm.fileExists(atPath: root.appendingPathComponent("drive_c").path) { prefixes.append((root, nil, "Wine")) }
            for child in ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []).prefix(128) {
                if fm.fileExists(atPath: child.appendingPathComponent("drive_c").path) { prefixes.append((child, nil, "Wine")) }
            }
        }
        var seen = Set<String>()
        for (prefix, wrapper, label) in prefixes where seen.insert(prefix.standardizedFileURL.path).inserted {
            for directory in ["Program Files (x86)/Steam", "Program Files/Steam", "Steam"] {
                let steam = prefix.appendingPathComponent("drive_c").appendingPathComponent(directory)
                let exe = steam.appendingPathComponent("steam.exe")
                guard fm.fileExists(atPath: exe.path) else { continue }
                let runtime = runtimeBinary(wrapper: wrapper, label: label)
                var libraries = [steam.appendingPathComponent("steamapps")]
                if let text = try? String(contentsOf: libraries[0].appendingPathComponent("libraryfolders.vdf"), encoding: .utf8), let parsed = try? VDF.parse(text) {
                    for value in (VDF.object(parsed, "libraryfolders") ?? [:]).values {
                        if case .object(let object) = value, let path = VDF.string(object, "path"), let mapped = Self.resolveWindowsPath(path, prefix: prefix) { libraries.append(mapped.appendingPathComponent("steamapps")) }
                    }
                }
                for library in Set(libraries) {
                    for manifest in (try? fm.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? [] where manifest.pathExtension == "acf" && manifest.lastPathComponent.hasPrefix("appmanifest_") {
                        do {
                            guard var game = try Discovery(home: home).steamGame(manifest: manifest) else { continue }
                            game.id = "wine-steam:" + MediaCache.identifier(prefix.path).prefix(16) + ":" + game.storeID
                            game.launchKind = .compatibility
                            game.launchTarget = exe.path
                            var environment = ["WINEPREFIX": prefix.path]
                            if label == "CrossOver" {
                                environment["CX_BOTTLE"] = prefix.lastPathComponent
                                let x11 = URL(fileURLWithPath: "/Applications/CrossOver.app/Contents/SharedSupport/X11")
                                environment["DYLD_FALLBACK_LIBRARY_PATH"] = x11.appendingPathComponent("lib").path + ":" + home.appendingPathComponent("lib").path + ":/lib:/usr/lib:/usr/X11/lib"
                                environment["FONTCONFIG_PATH"] = x11.appendingPathComponent("etc/fonts").path
                                environment["FONTCONFIG_ROOT"] = x11.path
                                environment["FONT_ENCODINGS_DIRECTORY"] = x11.appendingPathComponent("lib/X11/fonts/encodings/encodings.dir").path
                                environment["VERSIONER_PERL_PREFER_32_BIT"] = "yes"
                                if let display = UserDefaults(suiteName: "com.codeweavers.CrossOver")?.object(forKey: "Display") { environment["DISPLAY"] = ":\(display)" }
                            }
                            if let wrapper {
                                let support = wrapper.appendingPathComponent("Contents/SharedSupport")
                                environment["DYLD_FALLBACK_LIBRARY_PATH"] = support.appendingPathComponent("wine/lib").path
                                if let settings = Bundle(url: wrapper)?.infoDictionary {
                                    for key in ["WINEESYNC", "WINEMSYNC", "WINEDEBUG", "DXVK", "D3DMETAL", "MTL_HUD_ENABLED", "WINEDLLOVERRIDES"] {
                                        if let value = settings[key] { environment[key] = String(describing: value) }
                                    }
                                }
                            }
                            game.compatibility = CompatibilityLaunch(executable: runtime ?? "", arguments: [exe.path, "-applaunch", game.storeID], environment: environment, workingDirectory: steam.path, label: label)
                            result.games.append(game)
                            if runtime == nil { result.warnings.append("\(game.name): \(label) prefix found, but no Wine runtime was located. Install Wine or use its existing wrapper.") }
                        } catch { result.warnings.append("\(label) \(manifest.lastPathComponent): \(error.localizedDescription)") }
                    }
                }
            }
        }
        return result
    }
    private func runtimeBinary(wrapper: URL?, label: String) -> String? {
        var paths: [String] = []
        if let wrapper { paths += ["Contents/SharedSupport/wine/bin/wine", "Contents/Frameworks/wswine.bundle/bin/wine64", "Contents/Resources/wine/bin/wine"].map { wrapper.appendingPathComponent($0).path } }
        if label == "CrossOver" { paths += ["/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine", home.appendingPathComponent("Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine").path] }
        if wrapper == nil && label != "CrossOver" { paths += ["/opt/homebrew/bin/wine", "/usr/local/bin/wine", "/usr/bin/wine"] }
        return paths.first { fm.isExecutableFile(atPath: $0) }
    }
    public static func resolveWindowsPath(_ path: String, prefix: URL) -> URL? {
        let clean = path.replacingOccurrences(of: "\\", with: "/")
        let parts = clean.split(separator: "/").map(String.init)
        guard let drive = parts.first, drive.count == 2, drive.last == ":", !parts.contains(".."), !parts.contains(".") else { return nil }
        let root: URL
        if drive.lowercased() == "c:" { root = prefix.appendingPathComponent("drive_c") }
        else {
            let link = prefix.appendingPathComponent("dosdevices").appendingPathComponent(drive.lowercased())
            guard FileManager.default.fileExists(atPath: link.path) else { return nil }
            root = link.resolvingSymlinksInPath()
        }
        return parts.dropFirst().reduce(root) { $0.appendingPathComponent($1) }.standardizedFileURL
    }
}
