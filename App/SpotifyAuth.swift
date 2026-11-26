import CryptoKit
import Foundation

enum SpotifyConfig {
    static let redirectURI = "letrascar://callback"
    static let callbackScheme = "letrascar"
    static let scopes = "user-read-currently-playing user-read-playback-state"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: "spotifyClientID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "spotifyClientID") }
    }
}

struct SpotifyTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum SpotifyAuthError: LocalizedError {
    case missingClientID
    case denied(String)
    case noCode
    case notLoggedIn
    case tokenRequest(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingClientID: return "Falta el Client ID de Spotify."
        case .denied(let reason): return "Spotify rechazó el acceso: \(reason)"
        case .noCode: return "Spotify no devolvió el código de acceso."
        case .notLoggedIn: return "Primero conecta tu cuenta de Spotify."
        case .tokenRequest(let code, let body): return "Error \(code) al pedir el token: \(body)"
        }
    }
}

/// Inicio de sesión con Spotify usando PKCE (no necesita Client Secret).
@MainActor
final class SpotifyAuth {
    static let shared = SpotifyAuth()

    private let storeKey = "spotifyTokens"

    private(set) var tokens: SpotifyTokens? {
        didSet {
            if let tokens, let data = try? JSONEncoder().encode(tokens) {
                UserDefaults.standard.set(data, forKey: storeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storeKey)
            }
        }
    }

    var isLoggedIn: Bool { tokens != nil }

    private init() {
        if let data = UserDefaults.standard.data(forKey: storeKey) {
            tokens = try? JSONDecoder().decode(SpotifyTokens.self, from: data)
        }
    }

    // MARK: PKCE

    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizeURL(verifier: String) throws -> URL {
        let clientID = SpotifyConfig.clientID
        guard !clientID.isEmpty else { throw SpotifyAuthError.missingClientID }
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
        ]
        return components.url!
    }

    // MARK: Tokens

    func handleCallback(_ url: URL, verifier: String) async throws {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw SpotifyAuthError.denied(error)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw SpotifyAuthError.noCode
        }
        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": verifier,
        ])
    }

    func validAccessToken() async throws -> String {
        guard let tokens else { throw SpotifyAuthError.notLoggedIn }
        if tokens.expiresAt.timeIntervalSinceNow > 60 {
            return tokens.accessToken
        }
        try await refresh()
        guard let fresh = self.tokens else { throw SpotifyAuthError.notLoggedIn }
        return fresh.accessToken
    }

    func refresh() async throws {
        guard let tokens else { throw SpotifyAuthError.notLoggedIn }
        try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": SpotifyConfig.clientID,
        ])
    }

    func logout() {
        tokens = nil
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
    }

    private func requestToken(_ params: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 400, params["grant_type"] == "refresh_token" {
                tokens = nil // el token expiró o se revocó: hay que conectar de nuevo
            }
            throw SpotifyAuthError.tokenRequest(status, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        tokens = SpotifyTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? tokens?.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in))
        )
    }
}
