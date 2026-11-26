import ActivityKit
import Foundation

/// Datos que comparten la app y la Actividad en vivo (lo que se ve en CarPlay).
struct LyricsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var current: String
        var next: String
        var title: String
        var artist: String
        var isPlaying: Bool
    }

    var appName: String
}
