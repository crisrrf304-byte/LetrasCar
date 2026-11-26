import Foundation

struct NowPlaying: Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let durationMs: Int
    let progressMs: Int
    let isPlaying: Bool
    let fetchedAt: Date
}

enum SpotifyError: LocalizedError {
    case rateLimited(Int)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let seconds): return "Spotify pidió esperar \(seconds) s."
        case .http(let code): return "Spotify respondió con error \(code)."
        }
    }
}

/// Pregunta a Spotify qué canción suena y en qué segundo va.
@MainActor
enum SpotifyClient {
    private struct Response: Decodable {
        let is_playing: Bool
        let progress_ms: Int?
        let item: Item?

        struct Item: Decodable {
            let id: String?
            let name: String
            let duration_ms: Int
            let artists: [Artist]?
            let album: Album?
        }
        struct Artist: Decodable { let name: String }
        struct Album: Decodable { let name: String }
    }

    static func currentlyPlaying(retry: Bool = true) async throws -> NowPlaying? {
        let token = try await SpotifyAuth.shared.validAccessToken()
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8

        let sentAt = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let receivedAt = Date()
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        switch status {
        case 200:
            break
        case 204:
            return nil
        case 401 where retry:
            try await SpotifyAuth.shared.refresh()
            return try await currentlyPlaying(retry: false)
        case 429:
            let wait = Int(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 10
            throw SpotifyError.rateLimited(wait)
        default:
            throw SpotifyError.http(status)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let item = decoded.item else { return nil } // p. ej. un podcast
        let artist = item.artists?.map(\.name).first ?? ""
        // El progreso corresponde aprox. a la mitad del viaje de ida y vuelta.
        let midpoint = sentAt.addingTimeInterval(receivedAt.timeIntervalSince(sentAt) / 2)
        return NowPlaying(
            id: item.id ?? "\(item.name)|\(artist)",
            title: item.name,
            artist: artist,
            album: item.album?.name ?? "",
            durationMs: item.duration_ms,
            progressMs: decoded.progress_ms ?? 0,
            isPlaying: decoded.is_playing,
            fetchedAt: midpoint
        )
    }
}
