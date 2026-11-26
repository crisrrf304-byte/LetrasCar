import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LetrasWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyricsLiveActivity()
    }
}

struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsAttributes.self) { context in
            LyricsActivityView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note")
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.current)
                            .font(.headline)
                            .lineLimit(2)
                        if !context.state.next.isEmpty {
                            Text(context.state.next)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.current)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 90)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(.green)
            }
        }
        // .small es el tamaño que usan CarPlay y el Apple Watch.
        .supplementalActivityFamilies([.small, .medium])
    }
}

struct LyricsActivityView: View {
    let state: LyricsAttributes.ContentState
    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            smallView
        } else {
            mediumView
        }
    }

    /// Vista compacta (CarPlay): solo la línea actual, grande y legible.
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.current)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
            if !state.next.isEmpty {
                Text(state.next)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(10)
    }

    /// Vista de pantalla bloqueada.
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: state.isPlaying ? "music.note" : "pause.fill")
                    .foregroundStyle(.green)
                Text(state.artist.isEmpty ? state.title : "\(state.title) · \(state.artist)")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))

            Text(state.current)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if !state.next.isEmpty {
                Text(state.next)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}
