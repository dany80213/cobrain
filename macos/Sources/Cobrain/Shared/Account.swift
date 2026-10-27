import SwiftUI
import Security

// Accounts: guest by default, optional sign-in with an e-mail code (Supabase Auth, passwordless).
// Everything works as a guest; signing in only adds a name and an identity, the files stay where they are.
// The publishable key below is meant to be public (it is shipped inside the app); it gives no access to data by itself.

enum SupabaseConfig {
    static let url = URL(string: "https://hxjjdfiqdechhzdrnepk.supabase.co")!
    static let publishableKey = "sb_publishable_98QVmMBqcjzinvbaWf0xug_EKSTB0Rc"
}

struct AuthSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String
}

/// Where the session is kept: the Keychain on iPad; a private file on the Mac (an ad-hoc signed build can't use the
/// data-protection keychain, and the login keychain would ask for the password after every rebuild).
enum SessionStorage {
    private static let account = "cobrain.session"

    #if os(macOS)
    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Cobrain/session.json")
    }
    static func load() -> AuthSession? {
        guard let d = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: d)
    }
    static func save(_ s: AuthSession) {
        guard let d = try? JSONEncoder().encode(s) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func clear() { try? FileManager.default.removeItem(at: file) }
    #else
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.cobrain.app", kSecAttrAccount as String: account] }
    static func load() -> AuthSession? {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: d)
    }
    static func save(_ s: AuthSession) {
        guard let d = try? JSONEncoder().encode(s) else { return }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = d
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
    #endif
}

private let profileNameKey = "cobrain.profileName"

@MainActor final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published private(set) var session: AuthSession?
    /// The address a code was sent to, while waiting for it to be typed.
    @Published private(set) var pendingEmail: String?
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var displayName: String { didSet { UserDefaults.standard.set(displayName, forKey: profileNameKey) } }

    var isSignedIn: Bool { session != nil }
    var initial: String { String((displayName.isEmpty ? (session?.email ?? "") : displayName).first.map { String($0) } ?? "?").uppercased() }

    /// The name for new comments and tracked changes; empty means the engine's own default.
    nonisolated static var profileName: String { UserDefaults.standard.string(forKey: profileNameKey) ?? "" }

    init() {
        displayName = UserDefaults.standard.string(forKey: profileNameKey) ?? ""
        session = SessionStorage.load()
        if session != nil { Task { await refreshIfNeeded() } }
    }

    // MARK: Sign in with an e-mail code

    func sendCode(to email: String) async {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard address.contains("@"), address.contains("."), !address.hasSuffix(".") else { error = "Enter a valid e-mail address."; return }
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await call("auth/v1/otp", body: ["email": address, "create_user": true])
            pendingEmail = address
        } catch { self.error = Self.message(error) }
    }

    func verify(code: String) async {
        guard let email = pendingEmail else { return }
        let token = code.filter(\.isNumber)
        guard token.count >= 6 else { error = "Enter the 6-digit code from the e-mail."; return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let json = try await call("auth/v1/verify", body: ["type": "email", "email": email, "token": token])
            guard let s = Self.parse(json) else { error = "The server’s answer was not understood."; return }
            session = s; pendingEmail = nil
            SessionStorage.save(s)
            if displayName.isEmpty { displayName = email.split(separator: "@").first.map { String($0).replacingOccurrences(of: ".", with: " ").capitalized } ?? "" }
        } catch { self.error = Self.message(error) }
    }

    func cancelCode() { pendingEmail = nil; error = nil }

    func signOut() async {
        if let s = session { _ = try? await call("auth/v1/logout", body: [:], bearer: s.accessToken) }
        session = nil; pendingEmail = nil
        SessionStorage.clear()
    }

    /// Renews the session when it is about to expire; a refused renewal (revoked elsewhere) signs out.
    func refreshIfNeeded() async {
        guard let s = session, s.expiresAt.timeIntervalSinceNow < 300 else { return }
        do {
            let json = try await call("auth/v1/token?grant_type=refresh_token", body: ["refresh_token": s.refreshToken])
            if let n = Self.parse(json) { session = n; SessionStorage.save(n) }
        } catch AuthError.server(let status, _) where status == 400 || status == 401 || status == 403 {
            session = nil; SessionStorage.clear()
        } catch {}   // offline: keep the session, try again next time
    }

    // MARK: Requests

    enum AuthError: Error { case server(Int, String), network }

    private func call(_ path: String, body: [String: Any], bearer: String? = nil) async throws -> [String: Any] {
        guard let url = URL(string: path, relativeTo: SupabaseConfig.url) else { throw AuthError.network }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(bearer ?? SupabaseConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) } catch { throw AuthError.network }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            throw AuthError.server(status, (json["msg"] ?? json["error_description"] ?? json["message"] ?? "") as? String ?? "")
        }
        return json
    }

    private static func parse(_ j: [String: Any]) -> AuthSession? {
        guard let access = j["access_token"] as? String, let refresh = j["refresh_token"] as? String, let user = j["user"] as? [String: Any],
              let id = user["id"] as? String else { return nil }
        let expires = (j["expires_in"] as? Double) ?? 3600
        return AuthSession(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expires), userID: id, email: user["email"] as? String ?? "")
    }

    private static func message(_ e: Error) -> String {
        guard case AuthError.server(let status, let text) = e else { return "No connection. Check your internet and try again." }
        let t = text.lowercased()
        if status == 429 || t.contains("rate limit") { return "Too many requests: wait a minute and try again." }
        if t.contains("expired") || t.contains("invalid") { return "That code is wrong or expired. Ask for a new one." }
        if t.contains("email") && t.contains("invalid") { return "That e-mail address isn’t valid." }
        return text.isEmpty ? "Something went wrong (\(status))." : text
    }
}

// MARK: Views

/// Sign in / profile: the same view in a popover on the Mac and a sheet on iPad.
struct AccountView: View {
    @ObservedObject var account: AccountStore = .shared
    var close: () -> Void = {}
    @State private var email = ""
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = account.session { profile(s) }
            else if let pending = account.pendingEmail { codeEntry(pending) }
            else { emailEntry }
            if let error = account.error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(22).frame(width: 340)
    }

    private var emailEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) { Image(systemName: "person.crop.circle").font(.system(size: 30)).foregroundStyle(.secondary); Text("Sign in").font(.title3.weight(.semibold)) }
            Text("You are using Cobrain as a guest: everything works without an account. Sign in to put your name on comments and tracked changes.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("E-mail address", text: $email).textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                #endif
                .onSubmit { Task { await account.sendCode(to: email) } }
            Text("We send you a 6-digit code. No password.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Continue as guest", action: close)
                Spacer()
                Button { Task { await account.sendCode(to: email) } } label: { if account.busy { ProgressView().controlSize(.small) } else { Text("Send code") } }
                    .buttonStyle(.borderedProminent).disabled(account.busy || email.isEmpty)
            }
        }
    }

    private func codeEntry(_ pending: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter the code").font(.title3.weight(.semibold))
            Text("We sent a 6-digit code to \(pending). It can take a minute; look in spam too.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("123456", text: $code).textFieldStyle(.roundedBorder).font(.system(size: 22, weight: .medium, design: .monospaced))
                #if os(iOS)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                #endif
                .onSubmit { Task { await account.verify(code: code) } }
            HStack {
                Button("Use another e-mail") { code = ""; account.cancelCode() }
                Spacer()
                Button { Task { await account.verify(code: code) } } label: { if account.busy { ProgressView().controlSize(.small) } else { Text("Sign in") } }
                    .buttonStyle(.borderedProminent).disabled(account.busy || code.filter(\.isNumber).count < 6)
            }
        }
    }

    private func profile(_ s: AuthSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(account.initial).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white).frame(width: 48, height: 48).background(Color.accentColor, in: Circle())
                VStack(alignment: .leading) { Text(account.displayName.isEmpty ? "Your profile" : account.displayName).font(.headline); Text(s.email).font(.callout).foregroundStyle(.secondary) }
            }
            TextField("Name on comments and changes", text: $account.displayName).textFieldStyle(.roundedBorder)
            Text("Your files stay on this device and in your own folders; signing out doesn't delete anything.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Sign out", role: .destructive) { Task { await account.signOut(); close() } }
                Spacer()
                Button("Done", action: close).buttonStyle(.borderedProminent)
            }
        }
    }
}

/// The round button that opens `AccountView`: the person icon for a guest, the initial once signed in.
struct AccountAvatar: View {
    @ObservedObject var account: AccountStore = .shared
    var body: some View {
        if account.isSignedIn { Text(account.initial).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(width: 24, height: 24).background(Color.accentColor, in: Circle()) }
        else { Image(systemName: "person.crop.circle").font(.system(size: 18)) }
    }
}
