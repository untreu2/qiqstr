import SwiftUI

struct NoteAudioItem: Hashable, Sendable, Identifiable {
    var id: String { url }
    var url: String
    var duration: Double?
    var waveform: [Int]

    static let extensions = ["m4a", "mp3", "aac", "ogg", "oga", "opus", "wav", "flac"]

    static func isAudio(_ url: String, mimeType: String?) -> Bool {
        if let mimeType { return mimeType.hasPrefix("audio/") }
        guard let ext = URL(string: url)?.pathExtension.lowercased(), !ext.isEmpty else { return false }
        return extensions.contains(ext)
    }
}

struct AudioPlayerView: View {
    let url: String
    var duration: Double?
    var waveform: [Int] = []
    var tint: Color = AppColors.textPrimary
    @State private var playback = AudioPlayback.shared

    private var isCurrent: Bool { playback.isCurrent(url) }
    private var progress: Double { isCurrent ? playback.progress : 0 }
    private var total: Double? { isCurrent && playback.duration > 0 ? playback.duration : duration }

    var body: some View {
        HStack(spacing: 12) {
            Button { playback.toggle(url) } label: {
                Image(systemName: isCurrent && playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(AppColors.background)
                    .frame(width: 40, height: 40)
                    .background(tint, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCurrent && playback.isPlaying ? L("voicePause") : L("voicePlay"))
            .accessibilityIdentifier("audio-play")
            WaveformBars(levels: waveform, progress: progress, tint: tint)
                .frame(height: 32)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    guard isCurrent else { return }
                    playback.seek(url, to: value.location.x / max(1, waveformWidth))
                })
                .background(GeometryReader { proxy in Color.clear.onAppear { waveformWidth = proxy.size.width }.onChange(of: proxy.size.width) { _, width in waveformWidth = width } })
            Text(VoiceRecorder.format(isCurrent ? progress * (total ?? 0) : (total ?? 0)))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(total == nil)
        }
        .accessibilityElement(children: .contain)
    }

    @State private var waveformWidth: CGFloat = 1
}

struct WaveformBars: View {
    let levels: [Int]
    var progress: Double = 0
    var tint: Color = AppColors.textPrimary

    private static let placeholder: [Int] = (0..<40).map { 28 + Int(42 * abs(sin(Double($0) * 0.55))) }

    var body: some View {
        let bars = levels.isEmpty ? Self.placeholder : levels
        GeometryReader { proxy in
            let count = max(1, min(bars.count, Int(proxy.size.width / 4)))
            let step = Double(bars.count) / Double(count)
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { index in
                    let level = bars[min(bars.count - 1, Int(Double(index) * step))]
                    Capsule()
                        .fill(Double(index) / Double(count) < progress ? tint : tint.opacity(0.28))
                        .frame(height: max(3, proxy.size.height * CGFloat(min(100, max(6, level))) / 100))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}

struct NoteAudioView: View {
    let item: NoteAudioItem

    var body: some View {
        AudioPlayerView(url: item.url, duration: item.duration, waveform: item.waveform)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.inputFill, in: .rect(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: 420, alignment: .leading)
            .accessibilityIdentifier("note-audio")
    }
}
