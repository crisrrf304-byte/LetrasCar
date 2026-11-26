import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double // segundos
    let text: String
}

struct LyricsResult {
    let synced: [LyricLine]
    let plain: String?
}

/// Busca letras sincronizadas en LRCLIB (https://lrclib.net), base gratuita y abierta.
enum LRCLib {
    private struct Record: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static let userAgent = "LetrasCar/1.0 (app personal)"

    static func fetch(title: String, artist: String, album: String, durationSec: Double) async -> LyricsResult? {
        // 1) Coincidencia exacta (título, artista, álbum y duración).
        if let record = await get(title: title, artist: artist, album: album, duration: durationSec),
           let result = makeResult(record) {
            return result
        }
        // 2) Búsqueda más flexible, con el título limpio ("- Remastered", "(feat. …)").
        let clean = cleanTitle(title)
        let candidates = await search(title: clean, artist: artist)
        let sorted = candidates.sorted {
            abs(($0.duration ?? 0) - durationSec) < abs(($1.duration ?? 0) - durationSec)
        }
        if let best = sorted.first(where: { ($0.syncedLyrics ?? "").isEmpty == false
            && abs(($0.duration ?? durationSec) - durationSec) < 4 }) {
            return makeResult(best)
        }
        if let best = sorted.first(where: { ($0.syncedLyrics ?? "").isEmpty == false }) {
            return makeResult(best)
        }
        return sorted.first.flatMap(makeResult)
    }

    private static func makeResult(_ record: Record) -> LyricsResult? {
        if record.instrumental == true {
            return LyricsResult(synced: [LyricLine(id: 0, time: 0, text: "♪ Instrumental ♪")], plain: nil)
        }
        let synced = parse(record.syncedLyrics ?? "")
        let plain = record.plainLyrics?.isEmpty == false ? record.plainLyrics : nil
        if synced.isEmpty && plain == nil { return nil }
        return LyricsResult(synced: synced, plain: plain)
    }

    private static func get(title: String, artist: String, album: String, duration: Double) async -> Record? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        guard let data = await load(components.url!) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private static func search(title: String, artist: String) async -> [Record] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let data = await load(components.url!) else { return [] }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    private static func load(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    static func cleanTitle(_ title: String) -> String {
        var result = title
        if let range = result.range(of: " - ") {
            result = String(result[..<range.lowerBound])
        }
        if let regex = try? NSRegularExpression(pattern: "\\s*[\\(\\[](feat\\.?|ft\\.?|with)[^\\)\\]]*[\\)\\]]",
                                                options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Convierte formato LRC ("[01:23.45] texto") en líneas con tiempo.
    static func parse(_ lrc: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(pattern: "\\[(\\d+):(\\d+(?:[.:]\\d+)?)\\]") else { return [] }
        var entries: [(Double, String)] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))
                    .replacingOccurrences(of: ":", with: ".")) ?? 0
                entries.append((minutes * 60 + seconds, text))
            }
        }
        return entries
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1.isEmpty ? "♪" : $0.element.1) }
    }
}
