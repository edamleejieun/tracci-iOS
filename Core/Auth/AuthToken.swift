import Foundation

struct AuthToken: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var accessTokenExpiresAt: String?
}

struct User: Codable, Equatable, Identifiable {
    let id: String
    let username: String?
    let email: String?
    let phone: String?
    let phoneVerified: Bool?
    let nickname: String?
    let avatarFileId: String?
    let avatarObjectKey: String?
    let avatarUrl: String?
    let createdAt: String?
    let loginType: String?
    let signature: String?
    let gender: String?
    let birthDate: String?
}

struct AuthResult: Codable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: String?
    let user: User
    let isNewUser: Bool?

    var token: AuthToken {
        AuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessTokenExpiresAt: accessTokenExpiresAt
        )
    }
}

struct RefreshTokenResult: Codable {
    let accessToken: String
    let accessTokenExpiresAt: String?
}
