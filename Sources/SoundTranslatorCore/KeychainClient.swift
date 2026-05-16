import Foundation
import Security

public protocol APIKeyStore: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
}

public struct KeychainClient: APIKeyStore {
    public static let defaultService = "com.yurari.realtimecaptionformac.openai"
    public static let legacyServices = [
        "com.gamst.realtimecaptionformac.openai",
        "com.gamst.soundtranslator.openai"
    ]

    private let service: String
    private let account: String
    private let legacyServices: [String]

    public init(
        service: String = Self.defaultService,
        account: String = "openai-api-key",
        legacyServices: [String] = Self.legacyServices
    ) {
        self.service = service
        self.account = account
        self.legacyServices = legacyServices
    }

    public func loadAPIKey() throws -> String? {
        if let apiKey = try loadAPIKey(service: service) {
            return apiKey
        }

        for legacyService in legacyServices where legacyService != service {
            guard let apiKey = try loadAPIKey(service: legacyService) else {
                continue
            }
            try saveAPIKey(apiKey, service: service)
            try? deleteAPIKey(service: legacyService)
            return apiKey
        }

        return nil
    }

    public func saveAPIKey(_ apiKey: String) throws {
        try saveAPIKey(apiKey, service: service)
    }

    public func deleteAPIKey() throws {
        try deleteAPIKey(service: service)
        for legacyService in legacyServices where legacyService != service {
            try? deleteAPIKey(service: legacyService)
        }
    }

    private func loadAPIKey(service: String) throws -> String? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SoundTranslatorError.system("Keychain read failed with OSStatus \(status).")
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func saveAPIKey(_ apiKey: String, service: String) throws {
        let data = Data(apiKey.utf8)
        var query = baseQuery(service: service)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(service: service) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw SoundTranslatorError.system("Keychain update failed with OSStatus \(updateStatus).")
            }
            return
        }
        guard status == errSecSuccess else {
            throw SoundTranslatorError.system("Keychain save failed with OSStatus \(status).")
        }
    }

    private func deleteAPIKey(service: String) throws {
        let status = SecItemDelete(baseQuery(service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SoundTranslatorError.system("Keychain delete failed with OSStatus \(status).")
        }
    }

    private func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}
