import SwiftUI
import AppKit
import PlayniteCore
import UniformTypeIdentifiers

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
            LibraryView().environmentObject(model).frame(minWidth: 980, minHeight: 660)
                .preferredColorScheme(.dark)
                .task {
                    await model.startup()
                }
        }.defaultSize(width: 1440, height: 900)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Add game…", action: model.addApplication).keyboardShortcut("n")
                    Button("Add games folder…", action: model.addFolder)
                    Button("Scan installed games") { Task { await model.scan() } }.keyboardShortcut("r").disabled(model.busy)
                }
                CommandMenu("Library") {
                    Button("Find a game") { model.searchRequested += 1 }.keyboardShortcut("f")
                    Button("Show or hide libraries") { model.showLibrary.toggle() }.keyboardShortcut("l")
                    Button("Show or hide game details") { model.showDetails.toggle() }.keyboardShortcut("i")
                    Button("Edit selected metadata and images…") { model.showCustomMetadata = true }.keyboardShortcut("e").disabled(model.selected == nil)
                    Button("Publisher metadata catalog") { model.showPublisherCatalog = true }
                    Button("Refresh metadata") { Task { await model.refresh() } }.disabled(model.busy)
                    Button("Restore hidden games", action: model.restoreHidden)
                    Divider()
                    Button("Import library…", action: model.importLibrary)
                    Button("Export library…", action: model.exportLibrary)
                    Button("Import and launch help") { model.showHelp = true }
                }
            }
    }
}
enum Palette {
    static let canvas = Color.black
    static let sidebar = Color(red: 0.055, green: 0.055, blue: 0.055)
    static let panel = Color(red: 0.105, green: 0.105, blue: 0.105)
    static let accent = Color(red: 1, green: 0.43, blue: 0.12)
}
struct LibraryView: View {
    @EnvironmentObject private var model: LibraryModel
    @StateObject private var input = InputRouter()
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var searchFocused: Bool
    @FocusState private var toolbarFocus: Int?
    @State private var backdropGame: Game?
    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                if model.visible.isEmpty { emptyState }
                else { CarouselView().environmentObject(model) }
                Spacer(minLength: 8)
                selectionCaption
                controls
            }
            if model.showLibrary { libraryPanel.frame(width: 245).frame(maxWidth: .infinity, alignment: .leading).transition(.move(edge: .leading)) }
            if model.showDetails, let game = model.selected {
                VStack(spacing: 0) {
                    HStack { Text("Game details").font(.headline); Spacer(); Button { model.showDetails = false } label: { Image(systemName: "xmark") }.help("Close details") }.padding(22)
                    GameDetail(game: game)
                }.frame(width: 340).background(Palette.sidebar.opacity(0.98)).overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.1)).frame(width: 1) }.frame(maxWidth: .infinity, alignment: .trailing).transition(.move(edge: .trailing))
            }
        }.background(Palette.canvas).tint(Palette.accent)
            .animation(reducedMotion ? nil : .easeInOut(duration: 0.22), value: model.showLibrary)
            .animation(reducedMotion ? nil : .easeInOut(duration: 0.22), value: model.showDetails)
            .alert("Playnite", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
            .sheet(isPresented: $model.showMetadata) { if let game = model.selected { MetadataSheet(game: game).environmentObject(model) } }
            .sheet(isPresented: $model.showCustomMetadata) { if let game = model.selected { CustomMetadataSheet(game: game).environmentObject(model) } }
            .sheet(isPresented: $model.showHelp) { HelpSheet().environmentObject(model) }
            .sheet(isPresented: $model.showPublisherCatalog) { PublisherSheet().environmentObject(model) }
            .onAppear {
                input.acceptsInput = { !model.showMetadata && !model.showHelp && !model.showPublisherCatalog && !model.showCustomMetadata && model.error == nil }
                input.perform = { action in
                    searchFocused = false
                    switch action {
                    case .previous: model.move(-1)
                    case .next: model.move(1)
                    case .launch: if let game = model.selected { model.launch(game) }
                    case .info: model.showDetails.toggle()
                    case .library: model.showLibrary.toggle()
                    case .back: model.showLibrary = false; model.showDetails = false
                    case .favorite: if let game = model.selected { model.toggleFavorite(game) }
                    case .search: searchFocused = true
                    }
                }
                input.start(); model.ensureSelection()
            }
            .onDisappear { input.stop() }
            .task(id: model.selected) {
                let game = model.selected
                do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
                backdropGame = game
            }
            .onChange(of: model.search) { _, _ in model.ensureSelection() }
            .onChange(of: model.filter) { _, _ in model.ensureSelection() }
            .onChange(of: model.searchRequested) { _, _ in searchFocused = true }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.reconcileUninstalls() } } }
    }
    private var backdrop: some View {
        ZStack {
            Color.black
            if let game = backdropGame {
                Artwork(game: game, role: .background).id(game.cachedBackground ?? game.backgroundArtwork ?? game.id)
                    .opacity(0.50).transition(.opacity)
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.7), location: 0), .init(color: .black.opacity(0.3), location: 0.45), .init(color: .black.opacity(0.95), location: 1)], startPoint: .top, endPoint: .bottom)
        }.ignoresSafeArea().allowsHitTesting(false)
            .animation(reducedMotion ? nil : .easeInOut(duration: 0.32), value: backdropGame?.id)
    }
    private var header: some View {
        HStack(spacing: 18) {
            Button { model.showLibrary.toggle() } label: { Image(systemName: "sidebar.left").font(.title3).frame(width: 34, height: 34) }.focused($toolbarFocus, equals: 0).focusEffectDisabled().overlay(RoundedRectangle(cornerRadius: 6).stroke(toolbarFocus == 0 ? Palette.accent : .clear, lineWidth: 1.5)).help("Libraries (L)")
            HStack(spacing: 8) { BrandMark().frame(width: 30, height: 30); Text("Playnite").font(.system(size: 24, weight: .bold, design: .rounded)) }
            Text(model.filter).font(.callout).foregroundStyle(.secondary)
            Spacer()
            if model.busy { ProgressView().controlSize(.small) }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a game", text: $model.search).textFieldStyle(.plain).focused($searchFocused)
                    .onExitCommand { model.search = ""; searchFocused = false }
                if !model.search.isEmpty { Button { model.search = ""; searchFocused = false } label: { Image(systemName: "xmark.circle.fill") } }
            }.padding(9).frame(width: 210).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
            Menu {
                Button("Add Mac application…", action: model.addApplication)
                Button("Add games folder…", action: model.addFolder)
                Button("Scan installed games") { Task { await model.scan() } }.disabled(model.busy)
                Button("Publisher metadata catalog") { model.showPublisherCatalog = true }
                Button("Help and notices") { model.showHelp = true }
            } label: { Label("Add / manage", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
            Button { model.showDetails.toggle() } label: { Image(systemName: "sidebar.right").font(.title3).frame(width: 34, height: 34) }.focused($toolbarFocus, equals: 1).focusEffectDisabled().overlay(RoundedRectangle(cornerRadius: 6).stroke(toolbarFocus == 1 ? Palette.accent : .clear, lineWidth: 1.5)).help("Game details (Shift)")
        }.buttonStyle(.plain).padding(.horizontal, 30).padding(.vertical, 22)
    }
    private var selectionCaption: some View {
        HStack(spacing: 14) {
            if let game = model.selected {
                Text("\((model.visible.firstIndex { $0.id == game.id } ?? 0) + 1) / \(model.visible.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Rectangle().fill(Palette.accent).frame(width: 30, height: 2)
                Text(game.genres.prefix(3).joined(separator: " • ")).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if model.media.file(gameID: game.id, key: game.customArtwork ?? game.cachedArtwork) != nil { Label("Saved offline", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.horizontal, 40).padding(.top, 10).padding(.bottom, 22).frame(height: 55)
    }
    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 26) {
                if input.usingController {
                    hint("dpad", "Browse", symbol: true)
                    hint(input.playGlyph, "Play", symbol: true)
                    hint(input.infoGlyph, "Details", symbol: true)
                    hint(input.libraryGlyph, "Libraries", symbol: true)
                    hint(input.backGlyph, "Close panels", symbol: true)
                } else {
                    hint("← →", "Browse"); hint("Return", "Play"); hint("Shift", "Details"); hint("L", "Libraries"); hint("F", "Favorite")
                }
                Spacer(minLength: 4)
                Label(input.usingController ? (input.controllerName ?? "Controller") : "Keyboard", systemImage: input.usingController ? "gamecontroller.fill" : "keyboard").font(.caption).foregroundStyle(Palette.accent)
            }
            HStack {
                Text(model.status).lineLimit(1)
                Spacer()
                if !model.issues.isEmpty { Button("\(model.issues.count) notices") { model.showHelp = true }.buttonStyle(.plain).foregroundStyle(Palette.accent) }
                if !input.usingController, let name = input.controllerName { Text("\(name) connected").foregroundStyle(.secondary) }
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 36).padding(.top, 18).padding(.bottom, 18).background(.black.opacity(0.85))
    }
    private func hint(_ key: String, _ title: String, symbol: Bool = false) -> some View {
        HStack(spacing: 7) {
            Group { if symbol { Image(systemName: key).font(.system(size: 21)) } else { Text(key).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 4).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5)) } }.foregroundStyle(.white)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller").font(.system(size: 70, weight: .ultraLight)).foregroundStyle(Palette.accent)
            Text(model.games.isEmpty ? "Your next game starts here." : "No matching games.").font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Add a Mac game or scan your installed libraries. Metadata is saved for offline use.").foregroundStyle(.secondary)
            Button("Add a game…", action: model.addApplication).buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, minHeight: 320)
    }
    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Libraries").font(.title2.bold()); Spacer(); Button { model.showLibrary = false } label: { Image(systemName: "xmark") } }.padding(.bottom, 22)
            ForEach([("All games", "square.stack"), ("Favorites", "heart"), ("Recently played", "clock")], id: \.0) { name, icon in libraryButton(name, icon: icon) }
            Divider().padding(.vertical, 14)
            ForEach(Store.allCases) { store in libraryButton(store.rawValue, icon: store == .local ? "desktopcomputer" : "shippingbox") }
            Spacer()
            Button("Restore hidden games", action: model.restoreHidden)
            Button("Help and notices") { model.showHelp = true }
        }.buttonStyle(.plain).padding(22).frame(maxHeight: .infinity).background(Palette.sidebar.opacity(0.98)).overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.1)).frame(width: 1) }
    }
    private func libraryButton(_ name: String, icon: String) -> some View {
        Button { model.filter = name; model.showLibrary = false } label: {
            Label(name, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .foregroundStyle(model.filter == name ? Palette.accent : .white.opacity(0.8))
                .background(model.filter == name ? Palette.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
private struct CarouselSlot: Identifiable {
    let id: Int
    let game: Game
    let offset: Int
}
struct CarouselView: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var drag: CGFloat = 0
    private var displaySlots: [CarouselSlot] {
        let games = model.visible
        let center = games.firstIndex { $0.id == model.selection } ?? 0
        return (games.isEmpty ? [] : games.count == 1 ? [0] : Array(-4...4)).compactMap { offset in
            guard let index = Carousel.wrappedIndex(center + offset, count: games.count) else { return nil }
            let game = games[index]
            return CarouselSlot(id: model.carouselPosition + offset, game: game, offset: offset)
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width * 0.30, 410, max(220, (geometry.size.height - 20) * 2 / 3))
            let height = width * 1.5
            ZStack {
                ForEach(displaySlots) { slot in
                        let game = slot.game
                        let offset = slot.offset
                        let distance = abs(offset)
                        let scale = distance == 0 ? 1.0 : distance == 1 ? 0.78 : distance == 2 ? 0.59 : 0.45
                        let spacing = distance == 0 ? 0 : distance == 1 ? width * 0.80 : distance == 2 ? width * 1.37 : width * (1.85 + Double(distance - 3) * 0.45)
                        Button { model.move(offset) } label: {
                            CarouselCard(game: game, selected: offset == 0)
                                .frame(width: width, height: max(260, height))
                        }.buttonStyle(.plain).scaleEffect(scale)
                            .opacity(distance > 2 ? 0 : distance == 0 ? 1 : distance == 1 ? 0.83 : 0.50)
                            .allowsHitTesting(distance <= 2).accessibilityHidden(distance > 2)
                            .offset(x: CGFloat(offset < 0 ? -1 : 1) * spacing + drag * 0.18, y: distance == 0 ? -10 : CGFloat(distance * 10))
                            .zIndex(Double(5 - distance)).transition(.identity)
                            .accessibilityLabel("\(game.name)\(offset == 0 ? ", selected" : "")")
                            .contextMenu {
                                Button("Play") { model.launch(game) }
                                Button("Game details") { model.move(offset); model.showDetails = true }
                                Button("Edit metadata and images…") { model.move(offset); model.showCustomMetadata = true }
                                Button(game.favorite ? "Remove favorite" : "Add favorite") { model.toggleFavorite(game) }
                                Divider()
                                Button("Uninstall…") { model.uninstall(game) }
                                Button("Hide from library") { model.remove(game) }
                            }
                }
                HStack {
                    Button { model.move(-1) } label: { Image(systemName: "chevron.left").font(.title2).frame(width: 44, height: 54).background(.black.opacity(0.5), in: Capsule()) }.accessibilityLabel("Previous game")
                    Spacer()
                    Button { model.move(1) } label: { Image(systemName: "chevron.right").font(.title2).frame(width: 44, height: 54).background(.black.opacity(0.5), in: Capsule()) }.accessibilityLabel("Next game")
                }.buttonStyle(.plain).padding(.horizontal, 16).zIndex(5)
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 20).onChanged { drag = $0.translation.width }.onEnded { value in
                    if abs(value.translation.width) > 45 { model.move(value.translation.width < 0 ? 1 : -1) }; drag = 0
                })
                .animation(reducedMotion ? nil : .interactiveSpring(response: 0.42, dampingFraction: 0.92, blendDuration: 0.12), value: model.carouselPosition)
        }.frame(maxHeight: 560).accessibilityElement(children: .contain).accessibilityLabel("Game carousel")
    }
}
enum ArtworkRole: String { case portrait, landscape, background }
struct Artwork: View {
    @EnvironmentObject private var model: LibraryModel
    let game: Game
    var role: ArtworkRole = .portrait
    @State private var image: NSImage?
    @State private var fill: NSImage?
    private var cacheKey: String? {
        switch role {
        case .portrait: return game.customArtwork ?? game.cachedArtwork
        case .landscape: return game.customLandscape ?? game.cachedLandscape ?? game.customArtwork ?? game.cachedArtwork
        case .background: return game.customBackground ?? game.cachedBackground ?? game.customLandscape ?? game.cachedLandscape ?? game.customArtwork ?? game.cachedArtwork
        }
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.panel
                if let image {
                    if let fill { Image(nsImage: fill).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped().opacity(0.7) }
                    Image(nsImage: image).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                } else { Image(systemName: "gamecontroller").font(.system(size: 70, weight: .ultraLight)).foregroundStyle(.white.opacity(0.18)) }
            }
        }.clipped().accessibilityHidden(true)
            .task(id: game.id + role.rawValue + (cacheKey ?? "")) {
                let loaded: NSImage?
                var loadedFill: NSImage?
                if let url = model.media.file(gameID: game.id, key: cacheKey) {
                    loadedFill = await ImageRepository.shared.image(at: url, maximum: 64, softened: true)
                    loaded = await ImageRepository.shared.image(at: url, maximum: role == .portrait ? 960 : role == .landscape ? 960 : 1280)
                } else if game.launchKind == .application { loaded = NSWorkspace.shared.icon(forFile: game.launchTarget) }
                else { loaded = nil }
                guard !Task.isCancelled else { return }; image = loaded; fill = loadedFill
            }
    }
}
struct CarouselCard: View {
    let game: Game
    let selected: Bool
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(game: game)
            LinearGradient(stops: [.init(color: .clear, location: 0.15), .init(color: .black.opacity(0.45), location: 0.45), .init(color: .black.opacity(0.97), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 11) {
                HStack { Text(game.store.rawValue).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5).background(.black.opacity(0.65), in: Capsule()); Spacer(); if game.favorite { Image(systemName: "heart.fill").foregroundStyle(Palette.accent) } }
                Spacer()
                Text(game.name).font(.system(size: 29, weight: .bold, design: .rounded)).lineLimit(3).minimumScaleFactor(0.75)
                if selected {
                    Text(game.summary.isEmpty ? "Ready in your library." : game.summary).font(.system(size: 12)).foregroundStyle(.white.opacity(0.72)).lineLimit(3).lineSpacing(3)
                    HStack { Image(systemName: "play.fill"); Text("Ready to play").fontWeight(.semibold); Spacer(); Image(systemName: "arrow.turn.down.left") }.font(.caption).foregroundStyle(Palette.accent).padding(.top, 6)
                } else if !game.developer.isEmpty { Text(game.developer).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }.padding(24)
        }.clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? Palette.accent : .white.opacity(0.15), lineWidth: selected ? 2 : 1))
            .shadow(color: .black.opacity(0.8), radius: selected ? 12 : 5, y: 10)
    }
}
struct GameDetail: View {
    @EnvironmentObject private var model: LibraryModel
    let game: Game
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                Artwork(game: game, role: .landscape).frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 10))
                Text(game.name).font(.system(size: 27, weight: .bold, design: .rounded)).textSelection(.enabled)
                Button { model.launch(game) } label: { Label("Play", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(12).foregroundStyle(.black).background(Palette.accent, in: RoundedRectangle(cornerRadius: 8)) }
                Text(game.summary.isEmpty ? "Find metadata to add a description." : game.summary).font(.callout).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled)
                if !game.developer.isEmpty { field("Developer", game.developer) }
                if !game.releaseDate.isEmpty { field("Released", game.releaseDate) }
                if !game.genres.isEmpty { field("Genres", game.genres.joined(separator: ", ")) }
                if !game.metadataSource.isEmpty { field("Metadata", game.metadataSource) }
                if game.cachedArtwork != nil { Label("Artwork saved on this Mac", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary) }
                Divider()
                Button(game.favorite ? "Remove from favorites" : "Add to favorites") { model.toggleFavorite(game) }
                Button("Edit metadata and images…") { model.showCustomMetadata = true }
                Button("Find metadata…") { model.showMetadata = true }
                if let url = URL(string: game.storeURL), url.scheme == "https" { Link("Publisher / store page", destination: url) }
                if !game.installPath.isEmpty { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: game.installPath)]) } }
                Divider()
                Button("Uninstall…") { model.uninstall(game) }.foregroundStyle(Palette.accent)
                Button("Hide from library") { model.remove(game) }.foregroundStyle(.secondary)
                if game.pendingUninstall == true { Text("Waiting for the store client to finish uninstalling. Metadata stays available until removal is confirmed.").font(.caption).foregroundStyle(.secondary) }
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
        Task { await model.applyMetadata(metadata, to: game.id) }
        model.status = "Metadata updated for \(game.name)."; dismiss()
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
                    Text("Use Left/Right or A/D to browse the infinite carousel. Return launches immediately. Shift toggles details, L toggles libraries, F toggles favorites, and Escape closes panels. Connected controllers use D-pad/left stick to browse, the bottom face button to launch, the top face button for details, the left face button for libraries, and the right face button to close panels. The hints update when your input changes.")
                    Text("Metadata and downloaded artwork stay in Application Support/PlayniteMac until uninstall succeeds. Hide keeps metadata; Restore hidden games brings entries back. Native Uninstall moves the application bundle to Trash, including any data inside it. Steam opens its uninstall dialog. Epic/Heroic open their own client for uninstall. Temporarily disconnected drives never trigger automatic cleanup.")
                    Text("Your library is stored locally in ~/Library/Application Support/PlayniteMac/library.json. The previous save is kept as library.json.backup. Export a library before moving to another Mac.")
                    if !model.library.folders.isEmpty { Text("Additional game folders").font(.headline); ForEach(model.library.folders, id: \.self) { folder in HStack { Text(folder).font(.caption).textSelection(.enabled); Spacer(); Button("Remove") { model.library.folders.removeAll { $0 == folder }; model.save() } } } }
                    if !model.issues.isEmpty { Text("Scan and metadata notices").font(.headline); ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in Text(issue).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Button("Export library…", action: model.exportLibrary); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(26).frame(width: 650, height: 570)
    }
}

struct PublisherSheet: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Beyond the stores").font(.title.bold())
            Text("Built-in metadata for popular publisher games. Matching installed applications receive this automatically. Metadata does not change a game's macOS compatibility.").foregroundStyle(.secondary)
            List(PublisherCatalog.games) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text(entry.metadata.name).font(.headline); Text(entry.metadata.developer).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if let game = model.selected {
                        Button("Use for selected game") { Task { let details = await model.metadata.publisher(entry); await model.applyMetadata(details, to: game.id) }; dismiss() }
                    }
                    Link(destination: URL(string: entry.metadata.url)!) { Image(systemName: "arrow.up.right.square") }
                }.padding(.vertical, 8)
            }
            HStack { Text("Descriptions are bundled. Publisher artwork is cached when available.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(26).frame(width: 680, height: 590).tint(Palette.accent)
    }
}

@MainActor private enum BrandAssets {
    static let logo: NSImage? = Bundle.main.url(forResource: "BrandMark", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
}
struct BrandMark: View {
    var body: some View {
        if let image = BrandAssets.logo { Image(nsImage: image).resizable().scaledToFit().accessibilityHidden(true) }
        else { Image(systemName: "gamecontroller.fill").foregroundStyle(Palette.accent) }
    }
}
struct CustomMetadataSheet: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    let game: Game
    @State private var values: [String: String] = [:]
    @State private var baseline: [String: String] = [:]
    @State private var resetText = false
    @State private var replacements: [String: URL] = [:]
    @State private var resetImages = Set<String>()
    @State private var saving = false
    @State private var error = ""
    private let fields = ["name", "summary", "developer", "releaseDate", "genres"]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit metadata and images").font(.title2.bold())
            Text("Custom fields survive automatic refresh. Images are copied into this game's offline cache.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Game title", text: binding("name"))
                    TextField("Developer", text: binding("developer"))
                    HStack { TextField("Release date", text: binding("releaseDate")); TextField("Genres, separated by commas", text: binding("genres")) }
                    Text("Description").font(.headline)
                    TextEditor(text: binding("summary")).frame(height: 105).padding(6).background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                    Button("Reset custom text to the last automatic values") { resetText = true; baseline = game.automaticMetadata ?? game.metadataValues; values = baseline }
                        .font(.caption).buttonStyle(.link)
                    Divider()
                    ForEach([("portrait", "Card cover", "Portrait, ideally 2:3"), ("landscape", "Inspection image", "Landscape, ideally 16:9"), ("background", "Alternate background", "Landscape scene")], id: \.0) { role, title, hint in
                        HStack(spacing: 14) {
                            CustomImagePreview(url: preview(role)).frame(width: 60, height: 64)
                            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(hint).font(.caption).foregroundStyle(.secondary); if let path = replacements[role] { Text(path.lastPathComponent).font(.caption).lineLimit(1) } }
                            Spacer()
                            Button("Choose image…") { choose(role) }
                            Button("Use automatic") { replacements.removeValue(forKey: role); resetImages.insert(role) }.font(.caption)
                        }.padding(.vertical, 4)
                    }
                    Text("PNG, JPEG, WebP, or GIF. Up to 24 MB per image. The original files remain unchanged.").font(.caption).foregroundStyle(.secondary)
                }.textFieldStyle(.roundedBorder)
            }
            if !error.isEmpty { Text(error).font(.callout).foregroundStyle(Palette.accent) }
            HStack { if saving { ProgressView().controlSize(.small) }; Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving); Button("Save offline") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(saving) }
        }.padding(26).frame(width: 740, height: 710).tint(Palette.accent)
            .onAppear { baseline = game.metadataValues; values = baseline }
    }
    private func binding(_ key: String) -> Binding<String> { Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }) }
    private func choose(_ role: String) {
        let panel = NSOpenPanel(); panel.title = "Choose \(role) image"; panel.allowedContentTypes = [.png, .jpeg, .webP, .gif]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        replacements[role] = url; resetImages.remove(role)
    }
    private func preview(_ role: String) -> URL? {
        if let replacement = replacements[role] { return replacement }
        let automatic: String? = role == "portrait" ? game.cachedArtwork : role == "landscape" ? game.cachedLandscape : game.cachedBackground
        let custom: String? = role == "portrait" ? game.customArtwork : role == "landscape" ? game.customLandscape : game.customBackground
        return model.media.file(gameID: game.id, key: resetImages.contains(role) ? automatic : custom ?? automatic)
    }
    private func save() {
        saving = true; error = ""
        let changes = Dictionary(uniqueKeysWithValues: fields.compactMap { key in values[key] != baseline[key] ? (key, values[key] ?? "") : nil })
        Task { do { try await model.saveCustomMetadata(id: game.id, changes: changes, resetText: resetText, images: replacements, resetImages: resetImages); dismiss() } catch { self.error = error.localizedDescription }; saving = false }
    }
}
struct CustomImagePreview: View {
    let url: URL?
    @State private var image: NSImage?
    var body: some View {
        ZStack { Palette.panel; if let image { Image(nsImage: image).resizable().scaledToFit() } else { Image(systemName: "photo").foregroundStyle(.secondary) } }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: url?.path) { if let url { image = await ImageRepository.shared.image(at: url, maximum: 200) } else { image = nil } }
    }
}
