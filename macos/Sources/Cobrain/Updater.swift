import AppKit
import SwiftUI
import UserNotifications

/// Keeps a Cobrain built from source (`macos/scripts/build-app.sh`) up to date with GitHub's
/// `main`: checks at launch and every six hours, notifies once per new version, and on request
/// pulls, rebuilds and restarts. The build script records the source folder and commit in
/// Info.plist; a copy without them (not built by the script) never checks.
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        /// `behind`: commits on main the running build doesn't have.
        case available(behind: Int, latest: String)
        case updating(String)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @AppStorage("checkForUpdatesAutomatically") var automatic = true

    static let repo = "dany80213/cobrain"
    private static let interval: TimeInterval = 6 * 60 * 60
    private var timer: Timer?

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    var builtCommit: String? { (info["CobrainCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    var sourceDir: URL? { (info["CobrainSourceDir"] as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } }
    var canUpdate: Bool { builtCommit != nil && sourceDir != nil }

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Cobrain-update.log")
    }

    /// Called once at launch: first check shortly after, then every six hours.
    func start() {
        guard canUpdate, timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.automatic else { return }
            self.check(userInitiated: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            guard let self, self.automatic else { return }
            self.check(userInitiated: false)
        }
    }

    // MARK: Check

    /// Asks GitHub how far `main` is ahead of the running build. `userInitiated` shows the
    /// answer even when there is nothing new.
    func check(userInitiated: Bool) {
        guard let built = builtCommit else {
            if userInitiated { Self.tell("Updates can’t be checked", "This copy of Cobrain wasn’t built with macos/scripts/build-app.sh, so it doesn’t know which version it is.") }
            return
        }
        if case .updating = state { return }
        state = .checking
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/compare/\(built)...main") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                guard error == nil, status == 200, let json else {
                    // 404: the build's commit isn't on GitHub (a local branch); nothing to compare.
                    self.state = .idle
                    if userInitiated {
                        let why = status == 404 ? "This build comes from a commit that isn’t on GitHub yet, so there’s nothing to compare it with." : (error?.localizedDescription ?? "GitHub answered \(status).")
                        Self.tell("Couldn’t check for updates", why)
                    }
                    return
                }
                let behind = json["ahead_by"] as? Int ?? 0
                let latest = ((json["commits"] as? [[String: Any]])?.last?["sha"] as? String) ?? ""
                if behind > 0 {
                    self.state = .available(behind: behind, latest: latest)
                    if userInitiated { self.offerUpdate() } else { self.notifyOnce(behind: behind, latest: latest) }
                } else {
                    self.state = .upToDate
                    if userInitiated { Self.tell("Cobrain is up to date", "You have the latest version from GitHub.") }
                }
            }
        }.resume()
    }

    /// One notification per new version on main.
    private func notifyOnce(behind: Int, latest: String) {
        let key = "lastUpdateNotified"
        guard !latest.isEmpty, UserDefaults.standard.string(forKey: key) != latest else { return }
        UserDefaults.standard.set(latest, forKey: key)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "A new version of Cobrain is available"
            content.body = behind == 1 ? "1 change on GitHub. Open Cobrain and click Update." : "\(behind) changes on GitHub. Open Cobrain and click Update."
            center.add(UNNotificationRequest(identifier: "cobrain-update", content: content, trigger: nil))
        }
    }

    // MARK: Update

    /// The title bar's Update button: says what will happen, then updates.
    func offerUpdate() {
        guard case .available(let behind, _) = state else { return }
        let alert = NSAlert()
        alert.messageText = "Update Cobrain?"
        alert.informativeText = "\(behind) new change\(behind == 1 ? "" : "s") on GitHub. Cobrain downloads them and rebuilds itself (a few minutes; you can keep working), then asks to restart."
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        Self.ask(alert) { if $0 == .alertFirstButtonReturn { self.update() } }
    }

    /// `git pull --ff-only` on main, then the build script; only on a clean `main`, so work in
    /// progress in the source folder is never touched.
    func update() {
        guard let dir = sourceDir else { return }
        state = .updating("Checking the source folder…")
        DispatchQueue.global(qos: .userInitiated).async {
            let branch = Self.shell("git rev-parse --abbrev-ref HEAD", in: dir).output.trimmingCharacters(in: .whitespacesAndNewlines)
            let dirty = !Self.shell("git status --porcelain --untracked-files=no", in: dir).output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if branch != "main" || dirty {
                let why = branch != "main" ? "is on the branch “\(branch)”" : "has changes that aren’t committed"
                Self.finish(.failed("Cobrain can’t update itself because its source folder (\(dir.path)) \(why). Switch it to main without changes (git switch main), then try again."))
                return
            }
            DispatchQueue.main.async { self.state = .updating("Downloading changes…") }
            let pull = Self.shell("git pull --ff-only origin main", in: dir)
            guard pull.ok else { Self.finish(.failed("Downloading the changes failed. Details are in \(Self.logURL.path).")); return }
            DispatchQueue.main.async { self.state = .updating("Building… (a few minutes)") }
            let build = Self.shell("CARGO_BUILD_JOBS=6 nice -n 10 macos/scripts/build-app.sh", in: dir)
            guard build.ok else { Self.finish(.failed("Building the new version failed. Details are in \(Self.logURL.path).")); return }
            Self.finish(.ready)
        }
    }

    private static func finish(_ s: State) {
        DispatchQueue.main.async {
            shared.state = s
            switch s {
            case .failed(let why): tell("Cobrain wasn’t updated", why)
            case .ready: shared.offerRestart()
            default: break
            }
        }
    }

    private func offerRestart() {
        let alert = NSAlert()
        alert.messageText = "Cobrain was updated"
        alert.informativeText = "Restart now to use the new version? Documents with unsaved changes ask first."
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")
        Self.ask(alert) { if $0 == .alertFirstButtonReturn { self.restart() } }
    }

    /// Quits (each document asks about unsaved edits as usual) and opens the new build once
    /// this process is gone. If quitting is cancelled the helper gives up after a minute.
    func restart() {
        guard let app = sourceDir?.appendingPathComponent("macos/build/Cobrain.app") else { return }
        let pid = ProcessInfo.processInfo.processIdentifier
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "for i in $(seq 120); do kill -0 \(pid) 2>/dev/null || { open \"$0\"; exit 0; }; sleep 0.5; done", app.path]
        try? helper.run()
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    /// Runs `command` with bash in `dir`, appending its output to the update log.
    private static func shell(_ command: String, in dir: URL) -> (ok: Bool, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", command]
        p.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "\(home)/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (false, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        log("$ \(command)\n\(out)\n")
        return (p.terminationStatus == 0, out)
    }

    private static func log(_ text: String) {
        let url = logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }

    /// Shows `alert` as a sheet on the front window (visible in full screen too).
    private static func ask(_ alert: NSAlert, then: @escaping (NSApplication.ModalResponse) -> Void) {
        if let w = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible), w.attachedSheet == nil {
            alert.beginSheetModal(for: w, completionHandler: then)
        } else {
            then(alert.runModal())
        }
    }

    private static func tell(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        ask(alert) { _ in }
    }
}

/// Title bar: "Update" while a new version is waiting, progress while updating.
struct UpdateButton: View {
    @ObservedObject var updater: Updater = .shared

    var body: some View {
        switch updater.state {
        case .available:
            Button { updater.offerUpdate() } label: {
                Label { Text("Update") } icon: { Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green) }
                    .labelStyle(.titleAndIcon)
            }
            .help("A new version of Cobrain is on GitHub")
        case .updating(let step):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(step).font(.caption) }
        case .ready:
            Button { updater.restart() } label: { Label("Restart to Update", systemImage: "arrow.clockwise.circle.fill") }
        default:
            EmptyView()
        }
    }
}
