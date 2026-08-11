import ClearframeCore
import Combine
import Foundation
import Security

@MainActor
final class AIConfigurationStore: ObservableObject {
    @Published var isEnabled: Bool
    @Published var apiKey: String
    @Published var model: String
    @Published var statusMessage = ""

    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let safetyIdentifierKey = "clearframe.safetyIdentifier"

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        isEnabled = defaults.bool(forKey: "clearframe.remoteAIEnabled")
        model = defaults.string(forKey: "clearframe.openAIModel") ?? "gpt-5.6-luna"
        apiKey = keychain.read() ?? ""

        if defaults.string(forKey: safetyIdentifierKey) == nil {
            defaults.set("clearframe_\(UUID().uuidString.lowercased())", forKey: safetyIdentifierKey)
        }
    }

    var canUseRemoteAI: Bool {
        isEnabled && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var providerConfiguration: OpenAIProviderConfiguration? {
        guard canUseRemoteAI else { return nil }
        return OpenAIProviderConfiguration(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "gpt-5.6-luna" : model,
            safetyIdentifier: defaults.string(forKey: safetyIdentifierKey) ?? "clearframe_local"
        )
    }

    func save() {
        do {
            let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if isEnabled && cleanKey.isEmpty {
                statusMessage = "Add an API key or turn Optional AI off."
                return
            }
            try keychain.write(cleanKey)
            defaults.set(isEnabled, forKey: "clearframe.remoteAIEnabled")
            defaults.set(model, forKey: "clearframe.openAIModel")
            statusMessage = "Settings saved."
        } catch {
            statusMessage = "The API key could not be saved to Keychain."
        }
    }

    func removeKey() {
        do {
            try keychain.delete()
            apiKey = ""
            isEnabled = false
            defaults.set(false, forKey: "clearframe.remoteAIEnabled")
            statusMessage = "API key removed."
        } catch {
            statusMessage = "The API key could not be removed from Keychain."
        }
    }
}

struct KeychainStore {
    private let service = "com.clearframe.browser.prototype"
    private let account = "openai-api-key"

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) throws {
        if value.isEmpty {
            try delete()
            return
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.status(updateStatus)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}

private enum KeychainError: Error {
    case status(OSStatus)
}
