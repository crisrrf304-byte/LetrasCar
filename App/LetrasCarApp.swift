import SwiftUI

@main
struct LetrasCarApp: App {
    @StateObject private var engine = LyricsEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}
