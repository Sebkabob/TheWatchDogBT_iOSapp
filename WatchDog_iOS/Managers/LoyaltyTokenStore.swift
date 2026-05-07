//
//  LoyaltyTokenStore.swift
//  BluetoothTesting
//
//  Stores a single 4-byte iPhone-wide "loyalty token" in Keychain. Used as
//  the application-layer ownership marker that each WatchDog persists in its
//  EEPROM. Same token is used to claim every WatchDog this iPhone ever
//  bonds with.
//

import Foundation
import Security

@Observable
final class LoyaltyTokenStore {
    static let shared = LoyaltyTokenStore()

    private let service = "com.watchdog.loyalty"
    private let account = "device-token-v1"
    private let tokenLength = 4

    private init() {}

    /// Get the iPhone's loyalty token, generating it on first call.
    /// Returns nil only if Keychain access fails (extremely rare).
    var token: Data? {
        if let existing = readKeychain() { return existing }
        guard let fresh = generateRandom(byteCount: tokenLength) else { return nil }
        if writeKeychain(fresh) { return fresh }
        return nil
    }

    private func generateRandom(byteCount: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return status == errSecSuccess ? Data(bytes) : nil
    }

    private func readKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private func writeKeychain(_ data: Data) -> Bool {
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    account,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
}
