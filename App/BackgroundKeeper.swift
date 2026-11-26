import AVFoundation

/// Reproduce silencio mezclado con Spotify para que iOS no suspenda la app
/// en segundo plano y así pueda ir actualizando la letra en CarPlay.
/// (Truco válido para uso personal; Apple no lo aceptaría en la App Store.)
final class BackgroundKeeper: NSObject {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var silence: AVAudioPCMBuffer = {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        if let channel = buffer.floatChannelData?[0] {
            channel.update(repeating: 0, count: Int(buffer.frameLength))
        }
        return buffer
    }()
    private(set) var isRunning = false

    override init() {
        super.init()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleReset),
            name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    func start() {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
        } catch {
            print("No se pudo iniciar el audio de fondo: \(error)")
            return
        }
        play()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
    }

    private func play() {
        player.stop()
        player.scheduleBuffer(silence, at: nil, options: .loops)
        player.play()
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard isRunning,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
        play()
    }

    @objc private func handleReset() {
        guard isRunning else { return }
        isRunning = false
        start()
    }
}
