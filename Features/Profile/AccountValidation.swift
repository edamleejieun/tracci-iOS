import Foundation

enum AccountValidation {
    private static let emailPattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
    private static let phonePattern = "^\\+[1-9]\\d{6,14}$"
    private static let chinaMobilePattern = "^1\\d{10}$"

    static let chinaCountryCode = "+86"

    static func isValidEmail(_ email: String) -> Bool {
        email.range(of: emailPattern, options: .regularExpression) != nil
    }

    static func isValidPhone(_ phone: String) -> Bool {
        phone.range(of: phonePattern, options: .regularExpression) != nil
    }

    /// 中国大陆 11 位手机号（不含区号）。
    static func isValidChinaMobileNumber(_ nationalNumber: String) -> Bool {
        nationalNumber.range(of: chinaMobilePattern, options: .regularExpression) != nil
    }

    static func fullChinaPhone(nationalNumber: String) -> String {
        chinaCountryCode + nationalNumber.filter(\.isNumber)
    }

    /// 从 `+86138…` / `86138…` / `138…` 提取 11 位国内号。
    static func chinaNationalNumber(from phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        if digits.count >= 11, digits.hasPrefix("86") {
            return String(digits.suffix(11))
        }
        if digits.count == 11, digits.hasPrefix("1") {
            return digits
        }
        return digits
    }

    static func maskedPhone(_ phone: String?) -> String {
        guard let phone, !phone.isEmpty else { return "" }
        let national = chinaNationalNumber(from: phone)
        guard national.count == 11 else {
            return phone
        }
        let prefix = national.prefix(3)
        let suffix = national.suffix(4)
        return "\(chinaCountryCode) \(prefix)****\(suffix)"
    }

    static func maskedEmail(_ email: String?) -> String {
        guard let email, !email.isEmpty else { return "" }
        let parts = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return email }
        let local = String(parts[0])
        let domain = String(parts[1])
        guard !local.isEmpty else { return email }
        if local.count <= 2 {
            return "\(local.prefix(1))***@\(domain)"
        }
        return "\(local.prefix(2))***@\(domain)"
    }

    static func passwordValidationError(for password: String) -> String? {
        guard !password.isEmpty else { return nil }
        guard password.count >= 8, password.count <= 30 else {
            return "密码长度需要 8-30 个字符"
        }
        let hasLetter = password.range(of: "[a-zA-Z]", options: .regularExpression) != nil
        let hasDigit = password.range(of: "[0-9]", options: .regularExpression) != nil
        guard hasLetter, hasDigit else {
            return "密码需要包含字母和数字"
        }
        return nil
    }

    static func confirmPasswordError(
        password: String,
        confirm: String,
        mismatchMessage: String = "两次输入的密码不一致"
    ) -> String? {
        guard !confirm.isEmpty else { return nil }
        guard confirm == password else {
            return mismatchMessage
        }
        return nil
    }
}