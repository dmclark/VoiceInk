import Foundation
import os

/// Handles Voiceitt email/password authentication and token management.
final class VoiceittAuthService {
    static let shared = VoiceittAuthService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VoiceittAuthService")
    private let baseURL = "https://api2.voiceitt.com"
    private let keychain = KeychainService.shared

    private init() {}

    // MARK: - Keychain Keys

    private enum Keys {
        static let token = "voiceittAPIKey"  // matches APIKeyManager mapping
        static let refreshToken = "voiceittRefreshToken"
        static let email = "voiceittEmail"
        static let tokenExpiresAt = "voiceittTokenExpiresAt"
        static let refreshTokenExpiresAt = "voiceittRefreshTokenExpiresAt"
        static let appId = "voiceittAppId"
        static let apiKey = "voiceittApiKey"
    }

    // MARK: - Public API

    /// Sign in with email and password (personalised speech-to-text).
    /// Endpoint: POST /v1/auth/login/email
    func signIn(appId: String, apiKey: String, email: String, password: String) async throws {
        let url = URL(string: "\(baseURL)/v1/auth/login/email")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "app_id": appId,
            "api_key": apiKey,
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceittAuthError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw VoiceittAuthError.authFailed(message)
        }

        let result = try JSONDecoder().decode(VoiceittAuthResponse.self, from: data)

        // Store credentials
        keychain.save(result.token, forKey: Keys.token)
        keychain.save(result.refreshToken, forKey: Keys.refreshToken)
        keychain.save(email, forKey: Keys.email)
        keychain.save(appId, forKey: Keys.appId)
        keychain.save(apiKey, forKey: Keys.apiKey)
        keychain.save(String(result.tokenExpiresAt), forKey: Keys.tokenExpiresAt)
        keychain.save(String(result.refreshTokenExpiresAt), forKey: Keys.refreshTokenExpiresAt)

        logger.info("Voiceitt sign-in successful for \(email, privacy: .private)")
    }

    /// Refresh the token using the stored refresh token.
    /// Endpoint: POST /v1/auth/refresh_token
    func refreshTokenIfNeeded() async throws {
        guard let refreshToken = keychain.getString(forKey: Keys.refreshToken), !refreshToken.isEmpty else {
            throw VoiceittAuthError.authFailed("No refresh token available")
        }

        // Check if token is still valid (with 60s buffer)
        if let expiresStr = keychain.getString(forKey: Keys.tokenExpiresAt),
           let expiresMs = Double(expiresStr) {
            let expiresDate = Date(timeIntervalSince1970: expiresMs / 1000.0)
            if expiresDate.timeIntervalSinceNow > 60 {
                return // Token still valid
            }
        }

        let url = URL(string: "\(baseURL)/v1/auth/refresh_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VoiceittAuthError.authFailed("Token refresh failed")
        }

        let result = try JSONDecoder().decode(VoiceittAuthResponse.self, from: data)

        keychain.save(result.token, forKey: Keys.token)
        keychain.save(result.refreshToken, forKey: Keys.refreshToken)
        keychain.save(String(result.tokenExpiresAt), forKey: Keys.tokenExpiresAt)
        keychain.save(String(result.refreshTokenExpiresAt), forKey: Keys.refreshTokenExpiresAt)

        logger.info("Voiceitt token refreshed successfully")
    }

    /// Whether the user has stored Voiceitt credentials.
    var isSignedIn: Bool {
        guard let token = keychain.getString(forKey: Keys.token), !token.isEmpty else {
            return false
        }
        return true
    }

    /// The signed-in email, if any.
    var email: String? {
        keychain.getString(forKey: Keys.email)
    }

    /// Clear all stored Voiceitt credentials.
    func signOut() {
        keychain.delete(forKey: Keys.token)
        keychain.delete(forKey: Keys.refreshToken)
        keychain.delete(forKey: Keys.email)
        keychain.delete(forKey: Keys.tokenExpiresAt)
        keychain.delete(forKey: Keys.refreshTokenExpiresAt)
        keychain.delete(forKey: Keys.appId)
        keychain.delete(forKey: Keys.apiKey)
        logger.info("Voiceitt signed out")
    }
}

// MARK: - Models

struct VoiceittAuthResponse: Decodable {
    let token: String
    let tokenExpiresAt: Double
    let refreshToken: String
    let refreshTokenExpiresAt: Double

    enum CodingKeys: String, CodingKey {
        case token
        case tokenExpiresAt = "token_expires_at"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresAt = "refresh_token_expires_at"
    }
}

enum VoiceittAuthError: LocalizedError {
    case authFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .authFailed(let message):
            return "Voiceitt authentication failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
