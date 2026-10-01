import Foundation

/// Playlist passwords, kept in a user-only (0600) file in Application Support.
/// Chosen over the Keychain because ad-hoc signed builds trigger a Keychain
/// access prompt after every rebuild.
public struct SecretStore: Sendable {
    private let store: JSONFileStore<[String: String]>

    public init(url: URL = AppPaths.secrets) {
        store = JSONFileStore(url: url)
    }

    public func get(_ account: String) -> String? {
        store.load()?[account]
    }

    public func set(_ secret: String, for account: String) {
        var secrets = store.load() ?? [:]
        secrets[account] = secret
        write(secrets)
    }

    public func remove(_ account: String) {
        var secrets = store.load() ?? [:]
        guard secrets.removeValue(forKey: account) != nil else { return }
        write(secrets)
    }

    private func write(_ secrets: [String: String]) {
        try? store.save(secrets)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.url.path)
    }
}
