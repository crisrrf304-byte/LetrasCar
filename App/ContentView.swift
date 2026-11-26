import AuthenticationServices
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var engine: LyricsEngine
    @Environment(\.webAuthenticationSession) private var webAuth

    @State private var clientID = SpotifyConfig.clientID
    @State private var loggedIn = SpotifyAuth.shared.isLoggedIn
    @State private var connecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    spotifySection
                    if loggedIn {
                        controlSection
                        lyricsSection
                    }
                }
                .onChange(of: engine.currentIndex) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .navigationTitle("LetrasCar")
            .alert("Ups", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Secciones

    private var spotifySection: some View {
        Section("Spotify") {
            if loggedIn {
                Label("Cuenta conectada", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Desconectar", role: .destructive) {
                    engine.stop()
                    SpotifyAuth.shared.logout()
                    loggedIn = false
                }
            } else {
                TextField("Client ID de tu app de Spotify", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Redirect URI que debes registrar en Spotify:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(SpotifyConfig.redirectURI)
                            .font(.system(.callout, design: .monospaced))
                        Spacer()
                        Button {
                            UIPasteboard.general.string = SpotifyConfig.redirectURI
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Text("Conectar con Spotify")
                        if connecting { Spacer(); ProgressView() }
                    }
                }
                .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
            }
        }
    }

    private var controlSection: some View {
        Section {
            Button {
                engine.isRunning ? engine.stop() : engine.start()
            } label: {
                Label(engine.isRunning ? "Detener" : "Iniciar letras en vivo",
                      systemImage: engine.isRunning ? "stop.fill" : "play.fill")
                    .font(.headline)
            }
            .tint(engine.isRunning ? .red : .green)

            if let np = engine.nowPlaying {
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.title).font(.headline)
                    Text(np.artist).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            Text(engine.status)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Stepper(value: $engine.offset, in: -5...5, step: 0.25) {
                VStack(alignment: .leading) {
                    Text("Ajuste de sincronía")
                    Text(offsetLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Control")
        } footer: {
            Text("Pulsa Iniciar con la app abierta. Después puedes bloquear el teléfono o conectarlo a CarPlay: la letra aparece como Actividad en vivo.")
        }
    }

    private var offsetLabel: String {
        if engine.offset == 0 { return "Sin ajuste" }
        let value = String(format: "%.2f s", abs(engine.offset))
        return engine.offset > 0 ? "Letra adelantada \(value)" : "Letra atrasada \(value)"
    }

    @ViewBuilder
    private var lyricsSection: some View {
        if !engine.lines.isEmpty {
            Section("Letra") {
                ForEach(engine.lines) { line in
                    Text(line.text)
                        .font(line.id == engine.currentIndex ? .title3.bold() : .body)
                        .foregroundStyle(line.id == engine.currentIndex ? Color.primary : Color.secondary)
                        .id(line.id)
                }
            }
        } else if let plain = engine.plainLyrics {
            Section("Letra (sin sincronizar)") {
                Text(plain).font(.body)
            }
        }
    }

    // MARK: Acciones

    private func connect() async {
        connecting = true
        defer { connecting = false }
        SpotifyConfig.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let verifier = SpotifyAuth.makeVerifier()
        do {
            let url = try SpotifyAuth.authorizeURL(verifier: verifier)
            let callback = try await webAuth.authenticate(
                using: url,
                callbackURLScheme: SpotifyConfig.callbackScheme,
                preferredBrowserSession: .ephemeral)
            try await SpotifyAuth.shared.handleCallback(callback, verifier: verifier)
            loggedIn = true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
