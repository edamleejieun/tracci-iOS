import Foundation
import Security

/// Token 存储抽象。生产实现是 `KeychainTokenStore`；SwiftUI 预览用内存实现，
/// 不碰 Keychain（预览硬规则：#Preview 不得触达 Keychain / 真实后端）。
protocol AuthTokenStoring {
    func save(token: AuthToken) throws
    func loadToken() throws -> AuthToken?
    func clear() throws
}

final class KeychainTokenStore: AuthTokenStoring {
    private let service = "com.tracci.ios.auth"
    private let account = "token"

    func save(token: AuthToken) throws {
        let data = try JSONEncoder().encode(token)
        var query = baseQuery()
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandled(status: updateStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    func loadToken() throws -> AuthToken? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unhandled(status: status)
        }

        return try JSONDecoder().decode(AuthToken.self, from: data)
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }
}

enum KeychainError: Error {
    case unhandled(status: OSStatus)
}

#if DEBUG
/// 预览 / 单元测试用的内存 token store：不碰 Keychain。
final class InMemoryTokenStore: AuthTokenStoring {
    private var token: AuthToken?

    init(token: AuthToken? = nil) {
        self.token = token
    }

    func save(token: AuthToken) throws { self.token = token }
    func loadToken() throws -> AuthToken? { token }
    func clear() throws { token = nil }
}
#endif
