import SwiftUI
import AppKit
import PlayniteCore

@main enum EntryPoint {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnostics") {
            let result = Discovery().scan(folders: [])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do { print(String(decoding: try encoder.encode(result.games), as: UTF8.self)); result.warnings.forEach { fputs($0 + "\n", stderr) } }
            catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
            return
        }
        PlayniteApplication.main()
    }
}
struct PlayniteApplication: App {
    @StateObject private var model = LibraryModel()
    var body: some Scene {
        WindowGroup("Playnite for Mac") {
            LibraryView().environmentObject(model).frame(minWidth: 1020, minHeight: 680)
                .preferredColorScheme(.dark)
                .task { if model.games.isEmpty { await model.scan() } }
        }.defaultSize(width: 1320, height: 860)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Add game…", action: model.addApplication).keyboardShortcut("n")
                    Button("Add games folder…", action: model.addFolder)
                    Button("Scan installed games") { Task { await model.scan() } }.keyboardShortcut("r").disabled(model.busy)
                }
                CommandMenu("Library") {
                    Button("Refresh metadata") { Task { await model.refresh() } }.disabled(model.busy)
                    Button("Import library…", action: model.importLibrary)
                    Button("Export library…", action: model.exportLibrary)
                    Divider()
                    Button("Import and launch help") { model.showHelp = true }
                }
            }
    }
}
private enum Palette {
    static let canvas = Color(red: 0.065, green: 0.085, blue: 0.13)
    static let sidebar = Color(red: 0.09, green: 0.11, blue: 0.17)
    static let panel = Color(red: 0.12, green: 0.15, blue: 0.22)
    static let accent = Color(red: 0.53, green: 0.67, blue: 1)
}
struct LibraryView: View {
    @EnvironmentObject private var model: LibraryModel
    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 22, alignment: .top)]
    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 190, idealWidth: 210, maxWidth: 250)
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.filter).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("\(model.visible.count) games in your collection").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                    Button { Task { await model.scan() } } label: { Label("Scan", systemImage: "arrow.clockwise") }.disabled(model.busy)
                    Menu { Button("Add Mac application…", action: model.addApplication); Button("Add games folder…", action: model.addFolder) } label: { Label("Add game", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize().padding(9).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                }.padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 18)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search games or genres", text: $model.search).textFieldStyle(.plain)
                    if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(11).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 28).padding(.bottom, 22)
                if model.visible.isEmpty {
                    VStack(spacing: 18) {
                        Image(systemName: "gamecontroller").font(.system(size: 60, weight: .ultraLight)).foregroundStyle(Palette.accent)
                        Text(model.games.isEmpty ? "Make room for play." : "No matching games.").font(.title2.bold())
                        Text(model.games.isEmpty ? "Scan your installed libraries or add a Mac game.\nCovers and descriptions arrive automatically." : "Try another search or library.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                        if model.games.isEmpty { Button("Add a game…", action: model.addApplication).buttonStyle(.borderedProminent).tint(Palette.accent) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                            ForEach(model.visible) { game in Button { model.selection = game.id } label: { GameCard(game: game, selected: model.selection == game.id) }.buttonStyle(.plain).contextMenu {
                                Button("Play") { model.launch(game) }
                                Button(game.favorite ? "Remove from favorites" : "Add to favorites") { model.toggleFavorite(game) }
                                Button("Find metadata…") { model.selection = game.id; model.showMetadata = true }
                                Button("Remove from library…") { model.remove(game) }
                            }.accessibilityElement(children: .combine).accessibilityLabel(game.name).accessibilityAddTraits(.isButton) }
                        }.padding(.horizontal, 28).padding(.bottom, 28)
                    }
                }
                HStack(spacing: 8) {
                    Circle().fill(model.busy ? Color.orange : Palette.accent).frame(width: 6, height: 6)
                    Text(model.status).font(.caption).lineLimit(1)
                    Spacer()
                    if !model.issues.isEmpty { Button("\(model.issues.count) notices") { model.showHelp = true }.buttonStyle(.link).font(.caption) }
                }.foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 12).background(Palette.sidebar)
            }.frame(minWidth: 500).background(Palette.canvas)
            if let game = model.selected { GameDetail(game: game).frame(minWidth: 285, idealWidth: 320, maxWidth: 400).background(Palette.sidebar) }
        }.tint(Palette.accent)
            .alert("Playnite", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
            .sheet(isPresented: $model.showMetadata) { if let game = model.selected { MetadataSheet(game: game).environmentObject(model) } }
            .sheet(isPresented: $model.showHelp) { HelpSheet().environmentObject(model) }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 25)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 1) { Text("Playnite").font(.system(size: 23, weight: .bold, design: .rounded)); Text("for Mac").font(.caption).foregroundStyle(.secondary) }
            }.padding(.top, 30).padding(.horizontal, 20).padding(.bottom, 34)
            ForEach([("All games", "square.grid.2x2"), ("Favorites", "heart"), ("Recently played", "clock")], id: \.0) { name, icon in nav(name, icon: icon) }
            Text("Libraries").font(.headline).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 10)
            ForEach(Store.allCases) { store in nav(store.rawValue, icon: store == .local ? "desktopcomputer" : "shippingbox") }
            Spacer()
            Button { model.showHelp = true } label: { Label("Import and launch help", systemImage: "questionmark.circle").font(.caption) }.buttonStyle(.plain).foregroundStyle(.secondary).padding(20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Palette.sidebar)
    }
    private func nav(_ name: String, icon: String) -> some View {
        Button { model.filter = name } label: {
            HStack { Image(systemName: icon).frame(width: 22); Text(name); Spacer(); Text("\(count(name))").font(.caption).foregroundStyle(.secondary) }
                .padding(.horizontal, 12).padding(.vertical, 10).foregroundStyle(model.filter == name ? Color.white : .secondary)
                .background(model.filter == name ? Palette.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).padding(.horizontal, 10)
    }
    private func count(_ name: String) -> Int {
        model.games.filter { name == "All games" || (name == "Favorites" && $0.favorite) || (name == "Recently played" && $0.lastPlayed != nil) || $0.store.rawValue == name }.count
    }
}
struct Artwork: View {
    let game: Game
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.17, green: 0.22, blue: 0.32)
                Image(systemName: "gamecontroller").font(.system(size: 45, weight: .ultraLight)).foregroundStyle(.white.opacity(0.25))
                if let url = URL(string: game.artwork), url.scheme == "https" {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else if game.launchKind == .application {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: game.launchTarget)).resizable().interpolation(.high).scaledToFit().padding(22)
                }
            }
        }.clipped().accessibilityHidden(true)
    }
}
struct GameCard: View {
    let game: Game
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Artwork(game: game).aspectRatio(460.0 / 215, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Palette.accent : .white.opacity(0.08), lineWidth: selected ? 2 : 1))
            HStack(alignment: .firstTextBaseline) { Text(game.name).font(.system(size: 14, weight: .semibold)).lineLimit(2); Spacer(minLength: 0); if game.favorite { Image(systemName: "heart.fill").foregroundStyle(Palette.accent).font(.caption) } }
            Text(game.store.rawValue).font(.caption).foregroundStyle(.secondary)
        }.padding(3).contentShape(Rectangle())
    }
}
struct GameDetail: View {
    @EnvironmentObject private var model: LibraryModel
    let game: Game
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Artwork(game: game).frame(height: 155).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 8) { Text(game.store.rawValue).font(.caption).foregroundStyle(Palette.accent); Text(game.name).font(.system(size: 26, weight: .bold, design: .rounded)).textSelection(.enabled) }
                HStack {
                    Button { model.launch(game) } label: { Label("Play", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(Palette.canvas).background(Palette.accent, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                    Button { model.toggleFavorite(game) } label: { Image(systemName: game.favorite ? "heart.fill" : "heart").padding(.vertical, 7) }.help("Toggle favorite")
                }
                if !game.summary.isEmpty { Text(game.summary).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled) }
                else { Text("A description and cover will appear after a metadata match.").font(.callout).foregroundStyle(.secondary) }
                if !game.developer.isEmpty { field("Developer", game.developer) }
                if !game.releaseDate.isEmpty { field("Released", game.releaseDate) }
                if !game.genres.isEmpty { field("Genres", game.genres.joined(separator: ", ")) }
                if let date = game.lastPlayed { field("Last launch request", date.formatted(date: .abbreviated, time: .shortened)) }
                if !game.metadataSource.isEmpty { field("Metadata", game.metadataSource) }
                Divider()
                Button { model.showMetadata = true } label: { Label("Find metadata…", systemImage: "sparkle.magnifyingglass") }
                if let url = URL(string: game.storeURL), url.scheme == "https" { Link(destination: url) { Label("View store page", systemImage: "arrow.up.right.square") } }
                if !game.installPath.isEmpty { Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: game.installPath)]) } label: { Label("Show in Finder", systemImage: "folder") } }
                Button("Remove from library…") { model.remove(game) }.foregroundStyle(.secondary)
            }.buttonStyle(.plain).padding(22)
        }.id(game.id)
    }
    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout).textSelection(.enabled) }
    }
}
struct MetadataSheet: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    let game: Game
    @State private var query = ""
    @State private var page = ""
    @State private var matches: [SearchMatch] = []
    @State private var loading = false
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Find metadata").font(.title2.bold())
            Text("Match \(game.name) without changing how it launches.").foregroundStyle(.secondary)
            HStack { TextField("Game title", text: $query).onSubmit { search() }; Button("Search Steam", action: search).disabled(loading || query.isEmpty) }
            if loading { ProgressView().controlSize(.small) }
            List(matches) { match in
                HStack {
                    AsyncImage(url: URL(string: match.artwork)) { image in image.resizable().scaledToFit() } placeholder: { Color.gray.opacity(0.2) }.frame(width: 96, height: 42)
                    Text(match.name); Spacer(); Button("Use match") { applySteam(match) }.disabled(loading)
                }.padding(.vertical, 4)
            }.frame(height: 230)
            Divider()
            Text("Or use a Steam, GOG, Epic Games, or itch.io game page.").font(.callout)
            HStack { TextField("https://…", text: $page); Button("Fetch page") { fetchPage() }.disabled(loading || page.isEmpty) }
            Text(message).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(26).frame(width: 610).onAppear { query = game.name; page = game.storeURL; search() }
    }
    private func search() {
        loading = true; message = ""
        Task { do { matches = try await model.metadata.search(query); if matches.isEmpty { message = "No matches. Try a shorter title or paste a store page." } } catch { message = error.localizedDescription }; loading = false }
    }
    private func applySteam(_ match: SearchMatch) {
        loading = true
        Task { do { apply(try await model.metadata.steam(match.id)) } catch { message = error.localizedDescription }; loading = false }
    }
    private func fetchPage() {
        loading = true
        Task { do { apply(try await model.metadata.page(page)) } catch { message = error.localizedDescription }; loading = false }
    }
    private func apply(_ metadata: Metadata) {
        guard let current = model.games.first(where: { $0.id == game.id }) else { return }
        model.update(metadata.applying(to: current)); model.status = "Metadata updated for \(game.name)."; dismiss()
    }
}
struct HelpSheet: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your library on Mac").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Scan reads installed Steam libraries, Epic manifests, Heroic installations, and Mac games in Applications and Games folders. Add a games folder for GOG offline installers, itch.io downloads, or another disk.")
                    Text("Mac applications launch through macOS. Steam, Epic, and Heroic games launch through their installed client. A launch request confirms the handoff; it does not prove the game reached its main menu.")
                    Text("Windows .exe files and Playnite's Windows plugins do not run in this native port. Games installed through Heroic can use the compatibility runtime configured there.")
                    Text("Metadata is matched automatically by Steam app ID or an exact game title. Use Find metadata for alternate titles, ambiguous matches, or a GOG, Epic, or itch.io store page. Some stores block automated access; a Steam match remains available.")
                    Text("Your library is stored locally in ~/Library/Application Support/PlayniteMac/library.json. The previous save is kept as library.json.backup. Export a library before moving to another Mac.")
                    if !model.library.folders.isEmpty { Text("Additional game folders").font(.headline); ForEach(model.library.folders, id: \.self) { folder in HStack { Text(folder).font(.caption).textSelection(.enabled); Spacer(); Button("Remove") { model.library.folders.removeAll { $0 == folder }; model.save() } } } }
                    if !model.issues.isEmpty { Text("Scan and metadata notices").font(.headline); ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Button("Export library…", action: model.exportLibrary); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(26).frame(width: 650, height: 570)
    }
}
