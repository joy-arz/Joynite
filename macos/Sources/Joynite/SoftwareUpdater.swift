import AppKit
import SwiftUI
import Network
import JoyniteCore
import Sparkle

@MainActor final class SoftwareUpdater: NSObject, ObservableObject, SPUUserDriver {
    @Published private(set) var version: String?
    @Published private(set) var message = ""
    @Published private(set) var installing = false
    @Published var controlsFocused = false
    @Published private(set) var lastCheck = "Updates are checked quietly when Joynite opens."
    private var checked = false
    private var cancellation: (() -> Void)?
    private var expected: UInt64 = 0
    private var downloaded: UInt64 = 0
    private let defaults: UserDefaults
    private var reminder: UpdateReminder
    private lazy var engine = SPUUpdater(hostBundle: Bundle.main, applicationBundle: Bundle.main, userDriver: self, delegate: nil)
    private var engineStarted = false
    private let preview: String?
    override init() {
        defaults = .standard
        reminder = defaults.data(forKey: "updateReminder").flatMap { try? JSONDecoder().decode(UpdateReminder.self, from: $0) } ?? UpdateReminder()
        preview = Bundle.main.bundleIdentifier?.hasSuffix(".validation") == true ? ProcessInfo.processInfo.environment["JOYNITE_UPDATE_PREVIEW"] : nil
        super.init()
    }
    func check(manual: Bool = false) async {
        guard !installing, manual || !checked else { return }
        checked = true
        if let preview, SoftwareVersion(preview) != nil { if manual || reminder.allows(preview) { version = preview; message = "A new Joynite release is available." }; return }
        guard ProcessInfo.processInfo.environment["JOYNITE_OFFLINE"] != "1" else { lastCheck = "Offline. Update checks will resume next launch."; return }
        if !manual { do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return } }
        guard await Self.networkAvailable() else { lastCheck = "Offline. Update checks will resume next launch."; return }
        do {
            let release = try await SoftwareReleaseClient.latest()
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            if let candidate = release.nativeUpdate(after: current, architecture: architecture) {
                lastCheck = "Joynite \(candidate) is available."
                if manual || reminder.allows(candidate.description) { version = candidate.description; message = "A new Joynite release is available." }
            } else { lastCheck = "Joynite is up to date." }
        } catch { lastCheck = "Could not reach GitHub. Joynite remains ready to use." }
    }
    private static func networkAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in monitor.pathUpdateHandler = nil; monitor.cancel(); continuation.resume(returning: path.status == .satisfied) }
            monitor.start(queue: DispatchQueue(label: "Joynite.update-reachability"))
        }
    }
    private func saveReminder() { if let data = try? JSONEncoder().encode(reminder) { defaults.set(data, forKey: "updateReminder") } }
    func later() { guard !installing, let version else { return }; reminder.postpone(version); saveReminder(); self.version = nil }
    func skip() { guard !installing, let version else { return }; reminder.skip(version); saveReminder(); self.version = nil }
    func install() {
        guard version != nil, !installing else { return }
        if preview != nil { message = "Validation preview. No installer will run."; return }
        installing = true; message = "Preparing signed update…"
        do {
            if !engineStarted { try engine.start(); engineStarted = true }
            engine.checkForUpdates()
        } catch { installing = false; message = "Could not prepare update. Try again later." }
    }
    var canCancel: Bool { cancellation != nil }
    func cancel() { cancellation?(); cancellation = nil; installing = false; message = "Update cancelled. Your current version is unchanged." }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)) }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { self.cancellation = cancellation; message = "Checking signed update…" }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard installing, let announced = SoftwareVersion(appcastItem.displayVersionString), announced.description == version else { reply(.dismiss); installing = false; message = "Release metadata changed. Check for updates again."; return }
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { installing = false; message = "No installable update is available. Try again later."; acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { installing = false; cancellation = nil; message = "Update could not finish: \(error.localizedDescription)"; acknowledgement() }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { self.cancellation = cancellation; expected = 0; downloaded = 0; message = "Downloading signed update…" }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expected = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) { downloaded += length; if expected > 0 { message = "Downloading update… \(min(100, downloaded * 100 / expected))%" } }
    func showDownloadDidStartExtractingUpdate() { cancellation = nil; message = "Verifying and preparing update…" }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { message = "Installing update. Joynite will reopen…"; reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { message = "Installing update. Your library stays in place." }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { installing = false; version = nil; acknowledgement() }
    func dismissUpdateInstallation() { cancellation = nil; installing = false }
    func showUpdateInFocus() {}
}
struct SoftwareUpdateNotice: View {
    @EnvironmentObject private var updater: SoftwareUpdater
    @FocusState private var focused: String?
    var body: some View {
        if let version = updater.version {
            VStack(alignment: .leading, spacing: 12) {
                Label("Joynite \(version) is available", systemImage: "arrow.down.circle").font(.headline)
                Text(updater.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if updater.installing {
                    HStack { ProgressView().controlSize(.small); if updater.canCancel { Button("Cancel download") { updater.cancel() }.buttonStyle(.plain) } }
                } else {
                    HStack { Button("Update now") { updater.install() }.buttonStyle(.borderedProminent).focused($focused, equals: "now"); Button("Update later") { updater.later() }.buttonStyle(.plain).focused($focused, equals: "later") }
                    Button("Don’t remind me again") { updater.skip() }.buttonStyle(.plain).focused($focused, equals: "skip").font(.caption).foregroundStyle(.secondary)
                    Text("Reminders return when a newer version is released.").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(18).frame(width: 340, alignment: .leading).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.accent.opacity(0.7))).shadow(color: .black.opacity(0.4), radius: 10).padding(.top, 94).padding(.trailing, 20).tint(Palette.accent).accessibilityElement(children: .contain).accessibilityLabel("Software update").onChange(of: focused) { _, value in updater.controlsFocused = value != nil }.onDisappear { updater.controlsFocused = false }
        }
    }
}
