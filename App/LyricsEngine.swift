import ActivityKit
import Foundation

/// Coordina todo: consulta Spotify, baja la letra, calcula la línea actual
/// y la envía a la Actividad en vivo (Pantalla bloqueada, Dynamic Island y CarPlay).
@MainActor
final class LyricsEngine: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plainLyrics: String?
    @Published private(set) var currentIndex: Int?
    @Published private(set) var status = "Detenido"
    @Published private(set) var isRunning = false

    /// Adelanto/atraso manual de la letra, en segundos (positivo = la letra va antes).
    @Published var offset: Double = UserDefaults.standard.double(forKey: "lyricsOffset") {
        didSet {
            UserDefaults.standard.set(offset, forKey: "lyricsOffset")
            lastPushed = nil
        }
    }

    private let keeper = BackgroundKeeper()
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var activity: Activity<LyricsAttributes>?
    private var lastPushed: LyricsAttributes.ContentState?
    private var lyricsTrackID: String?

    private let pollInterval: Double = 4

    // MARK: Control

    func start() {
        guard !isRunning else { return }
        guard SpotifyAuth.shared.isLoggedIn else {
            status = "Primero conecta Spotify"
            return
        }
        isRunning = true
        status = "Conectando con Spotify…"
        keeper.start()
        startActivity()
        pollTask = Task { [weak self] in await self?.pollLoop() }
        tickTask = Task { [weak self] in await self?.tickLoop() }
    }

    func stop() {
        pollTask?.cancel()
        tickTask?.cancel()
        pollTask = nil
        tickTask = nil
        keeper.stop()
        isRunning = false
        status = "Detenido"
        activity = nil
        lastPushed = nil
        Task {
            for running in Activity<LyricsAttributes>.activities {
                await running.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Posición estimada de la canción en segundos, ya con el ajuste manual.
    var position: Double {
        guard let np = nowPlaying else { return 0 }
        var seconds = Double(np.progressMs) / 1000
        if np.isPlaying {
            seconds += Date().timeIntervalSince(np.fetchedAt)
        }
        return min(seconds, Double(np.durationMs) / 1000) + offset
    }

    // MARK: Bucles

    private func pollLoop() async {
        while !Task.isCancelled {
            var wait = pollInterval
            do {
                let np = try await SpotifyClient.currentlyPlaying()
                await handle(np)
            } catch SpotifyError.rateLimited(let seconds) {
                wait = Double(max(seconds, 5))
                status = "Spotify pidió una pausa (\(seconds) s)"
            } catch is CancellationError {
                return
            } catch {
                status = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    private func tickLoop() async {
        while !Task.isCancelled {
            updateCurrentLine()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    // MARK: Lógica

    private func handle(_ np: NowPlaying?) async {
        guard let np else {
            nowPlaying = nil
            status = "Nada sonando en Spotify"
            push(current: "Esperando canción…", next: "")
            return
        }
        nowPlaying = np
        if np.id != lyricsTrackID {
            lyricsTrackID = np.id
            await loadLyrics(for: np)
        } else if lines.isEmpty {
            push(current: emptyMessage, next: "") // refresca título / pausa
        }
    }

    private func loadLyrics(for np: NowPlaying) async {
        lines = []
        plainLyrics = nil
        currentIndex = nil
        status = "Buscando letra…"
        push(current: "Buscando letra…", next: "")

        let result = await LRCLib.fetch(
            title: np.title, artist: np.artist, album: np.album,
            durationSec: Double(np.durationMs) / 1000)

        guard lyricsTrackID == np.id else { return } // ya cambió la canción
        lines = result?.synced ?? []
        plainLyrics = result?.plain
        lastPushed = nil

        if lines.isEmpty {
            status = plainLyrics == nil ? "No encontré la letra" : "Solo hay letra sin sincronizar"
            push(current: emptyMessage, next: "")
        } else {
            status = "Letra sincronizada ✓"
            updateCurrentLine()
        }
    }

    private var emptyMessage: String {
        plainLyrics == nil ? "Sin letra disponible" : "Letra sin sincronizar (ver en el iPhone)"
    }

    private func updateCurrentLine() {
        guard !lines.isEmpty else { return }
        let pos = position
        let index = lines.lastIndex(where: { $0.time <= pos })
        if index != currentIndex { currentIndex = index }

        let current = index.map { lines[$0].text } ?? "♪"
        let nextIndex = (index ?? -1) + 1
        let next = nextIndex < lines.count ? lines[nextIndex].text : ""
        push(current: current, next: next)
    }

    // MARK: Actividad en vivo

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "Activa «Actividades en vivo» para LetrasCar en Ajustes"
            return
        }
        if let existing = Activity<LyricsAttributes>.activities.first {
            activity = existing
            return
        }
        let initial = LyricsAttributes.ContentState(
            current: "Esperando canción…", next: "", title: "LetrasCar", artist: "", isPlaying: false)
        do {
            activity = try Activity.request(
                attributes: LyricsAttributes(appName: "LetrasCar"),
                content: ActivityContent(state: initial, staleDate: nil),
                pushType: nil)
            lastPushed = initial
        } catch {
            status = "No se pudo crear la Actividad en vivo: \(error.localizedDescription)"
        }
    }

    private func push(current: String, next: String) {
        let np = nowPlaying
        let state = LyricsAttributes.ContentState(
            current: current,
            next: next,
            title: np?.title ?? "LetrasCar",
            artist: np?.artist ?? "",
            isPlaying: np?.isPlaying ?? false)
        guard state != lastPushed else { return }
        lastPushed = state

        guard let activity else { return }
        if activity.activityState == .ended || activity.activityState == .dismissed {
            self.activity = nil
            status = "La Actividad en vivo se cerró: abre la app y pulsa Detener e Iniciar"
            return
        }
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}
