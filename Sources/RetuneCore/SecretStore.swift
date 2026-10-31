import Foundation
import Security

/// Playlist passwords, kept in the user's login Keychain.
///
/// Builds that aren't signed with a stable identity get "allow access" prompts after each update,
/// because the Keychain ties access to the app's code signature. A single read can show two: one for
/// the item's access list and one for its partition list.
public struct SecretStore: Sendable {
    private let service: String

    public init(service: String = "io.github.0xaliraza.retune.playlist") {
        self.service = service
    }

    public func get(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)
        let update = SecItemUpdate(baseQuery(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw RetuneError.keychain(update) }
        var attributes = baseQuery(account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let add = SecItemAdd(attributes as CFDictionary, nil)
        guard add == errSecSuccess else { throw RetuneError.keychain(add) }
    }

    public func remove(_ account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    /// Moves passwords out of the plain JSON file used by early builds. The file is only deleted once
    /// every entry reads back from the Keychain, so a denied prompt loses nothing and retries next launch.
    public func migrateLegacyFile(at url: URL = AppPaths.legacySecrets) {
        guard let legacy = JSONFileStore<[String: String]>(url: url).load() else { return }
        for (account, secret) in legacy { try? set(secret, for: account) }
        guard legacy.allSatisfy({ get($0.key) == $0.value }) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
