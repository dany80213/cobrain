import AppKit

/// Proofing languages the status bar offers, the language new documents start in, and the
/// Hunspell dictionaries Cobrain can download. The engine checks Italian against an installed
/// `it_IT` dictionary it can't ship (the file is GPL), so the user downloads it once into
/// `~/Library/Spelling`, where the engine looks.
enum Proofing {
    struct Language: Identifiable, Hashable {
        let tag: String
        let name: String
        var id: String { tag }
    }

    static let languages: [Language] = [
        Language(tag: "it-IT", name: "Italiano"),
        Language(tag: "en-US", name: "English (United States)"),
        Language(tag: "en-GB", name: "English (United Kingdom)"),
    ]

    static func name(for tag: String?) -> String {
        guard let tag, !tag.isEmpty else { return "No language" }
        return languages.first { $0.tag.caseInsensitiveCompare(tag) == .orderedSame }?.name ?? tag
    }

    /// The language blank documents start in: chosen in the status bar, else the Mac's own.
    static var defaultTag: String {
        get {
            if let t = UserDefaults.standard.string(forKey: "proofingLanguage") { return t }
            return Locale.current.language.languageCode?.identifier == "it" ? "it-IT" : "en-US"
        }
        set { UserDefaults.standard.set(newValue, forKey: "proofingLanguage") }
    }

    /// Dictionaries we know where to get, by primary language subtag: file name and folder URL
    /// in LibreOffice's dictionaries repository.
    private static let downloads: [String: (file: String, base: String, size: String)] = [
        "it": ("it_IT", "https://raw.githubusercontent.com/LibreOffice/dictionaries/master/it_IT/", "about 1 MB"),
    ]

    static var spellingFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Spelling")
    }

    static func primary(_ tag: String) -> String { tag.split(separator: "-").first.map { $0.lowercased() } ?? tag.lowercased() }

    /// The engine's proofing settings. `file.options` with no setting would open the Options
    /// dialog; with one it only applies it, so this passes the spelling switch Cobrain keeps on.
    private static func options(_ engine: Engine) -> [String: Any] {
        guard case .success(let r) = engine.run("file.options", ["checkSpelling": true]) else { return [:] }
        return r as? [String: Any] ?? [:]
    }

    /// Whether `tag` needs a dictionary that isn't installed and that we can download.
    static func missingDictionary(_ tag: String, engine: Engine) -> Bool {
        let lang = primary(tag)
        guard downloads[lang] != nil, let dicts = options(engine)["dictionaries"] as? [[String: Any]] else { return false }
        return dicts.contains { ($0["language"] as? String) == lang && $0["file"] is NSNull }
    }

    static func downloadSize(_ tag: String) -> String { downloads[primary(tag)]?.size ?? "" }

    /// Downloads the `.aff` and `.dic` files into `~/Library/Spelling`, then calls `done` on the
    /// main queue with an error message, or `nil` once both are there.
    static func downloadDictionary(_ tag: String, done: @escaping (String?) -> Void) {
        guard let d = downloads[primary(tag)] else { done("No dictionary to download for \(name(for: tag))."); return }
        let group = DispatchGroup()
        var failure: String?
        var files: [(Data, String)] = []
        let lock = NSLock()
        for ext in ["aff", "dic"] {
            guard let url = URL(string: d.base + d.file + "." + ext) else { continue }
            group.enter()
            URLSession.shared.dataTask(with: url) { data, response, error in
                defer { group.leave() }
                lock.lock(); defer { lock.unlock() }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if let data, error == nil, status == 200, !data.isEmpty {
                    files.append((data, d.file + "." + ext))
                } else {
                    failure = error?.localizedDescription ?? "the server answered \(status)"
                }
            }.resume()
        }
        group.notify(queue: .main) {
            if let failure { done("Could not download the dictionary: \(failure)"); return }
            do {
                try FileManager.default.createDirectory(at: spellingFolder, withIntermediateDirectories: true)
                for (data, name) in files { try data.write(to: spellingFolder.appendingPathComponent(name), options: .atomic) }
                done(nil)
            } catch { done("Could not save the dictionary: \(error.localizedDescription)") }
        }
    }

    /// Makes the engine look for dictionaries again (it remembers "not installed"), keeping the
    /// dictionaries folder setting as it was.
    static func reloadDictionaries(engine: Engine) {
        let folder = (options(engine)["dictionariesFolder"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "auto"
        _ = engine.run("file.options", ["dictionariesFolder": folder])
    }
}

/// A menu item that runs a closure (for menus built in code, like the page's context menu).
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: enabled ? #selector(fire) : nil, keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}
