import AppKit
import ServiceManagement
import SwiftUI

@MainActor final class StartupSettings: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var updating = false
    @Published var error: String?
    init() { refresh() }
    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }
    func setEnabled(_ value: Bool) {
        guard !updating else { return }
        updating = true; error = nil
        Task {
            do {
                if value { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
            } catch { self.error = "Could not update launch at login: \(error.localizedDescription)" }
            refresh(); updating = false
        }
    }
    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
struct JoyniteSettingsView: View {
    @StateObject private var startup = StartupSettings()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Joynite settings").font(.title2.bold())
            Toggle("Launch Joynite when I sign in", isOn: Binding(get: { startup.enabled }, set: { startup.setEnabled($0) }))
                .disabled(startup.updating)
            Text("Open your library automatically after signing in to this Mac. Off by default.").font(.callout).foregroundStyle(.secondary)
            if startup.requiresApproval { Text("Allow Joynite in Login Items to finish enabling startup launch.").foregroundStyle(Palette.accent) }
            if let error = startup.error { Text(error).font(.callout).foregroundStyle(Palette.accent) }
            Button("Open macOS Login Items…") { startup.openLoginItems() }
            Divider()
            KofiSupportButton()
        }.padding(28).frame(width: 480).tint(Palette.accent).preferredColorScheme(.dark)
            .onChange(of: phase) { _, value in if value == .active { startup.refresh() } }
    }
}
struct KofiSupportButton: View {
    private static let icon = Bundle.main.url(forResource: "Kofi", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    var body: some View {
        Link(destination: URL(string: "https://ko-fi.com/joyarz")!) {
            HStack(spacing: 7) {
                if let image = Self.icon { Image(nsImage: image).resizable().scaledToFit().frame(width: 20, height: 20) }
                Text("Support Joynite").font(.caption)
            }.foregroundStyle(Palette.accent)
        }.buttonStyle(.plain).help("Support joy-arz on Ko-fi").accessibilityLabel("Support Joynite on Ko-fi")
    }
}
