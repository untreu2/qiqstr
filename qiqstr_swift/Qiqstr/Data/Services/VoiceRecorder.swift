import AVFoundation
import Foundation
import Observation

nonisolated struct VoiceRecording: Hashable, Sendable {
    var url: URL
    var duration: Double
    var waveform: [Int]
}

@MainActor
@Observable
final class VoiceRecorder {
    enum State: Equatable {
        case idle, recording, finished(VoiceRecording), denied, failed
    }

    static let maxDuration: Double = 300
    static let waveformBars = 48

    private(set) var state: State = .idle
    private(set) var elapsed: Double = 0
    private(set) var levels: [Float] = []
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meter: Task<Void, Never>?

    var isRecording: Bool { state == .recording }

    func start() async {
        guard state != .recording else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .denied
            return
        }
        AudioPlayback.shared.stop()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true)
        #endif
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else {
            state = .failed
            return
        }
        recorder.isMeteringEnabled = true
        guard recorder.record(forDuration: Self.maxDuration) else {
            state = .failed
            return
        }
        self.recorder = recorder
        levels = []
        elapsed = 0
        state = .recording
        meter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, let recorder = self.recorder, !Task.isCancelled else { return }
                guard recorder.isRecording else {
                    self.finish()
                    return
                }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                self.levels.append(max(0, min(1, pow(10, power / 20) * 2.2)))
                self.elapsed = recorder.currentTime
            }
        }
    }

    func stop() {
        guard state == .recording else { return }
        finish()
    }

    func cancel() {
        meter?.cancel()
        meter = nil
        if let recorder {
            recorder.stop()
            try? FileManager.default.removeItem(at: recorder.url)
        }
        if case .finished(let recording) = state { try? FileManager.default.removeItem(at: recording.url) }
        recorder = nil
        levels = []
        elapsed = 0
        state = .idle
        releaseSession()
    }

    private func finish() {
        meter?.cancel()
        meter = nil
        guard let recorder else { return }
        let duration = max(recorder.currentTime, elapsed)
        recorder.stop()
        self.recorder = nil
        releaseSession()
        guard duration >= 0.5 else {
            try? FileManager.default.removeItem(at: recorder.url)
            levels = []
            elapsed = 0
            state = .idle
            return
        }
        elapsed = duration
        state = .finished(VoiceRecording(url: recorder.url, duration: duration, waveform: Self.waveform(levels)))
    }

    private func releaseSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    static func waveform(_ levels: [Float], bars: Int = waveformBars) -> [Int] {
        guard !levels.isEmpty else { return [] }
        let bucket = max(1, Int((Double(levels.count) / Double(bars)).rounded(.up)))
        var result: [Int] = []
        var index = 0
        while index < levels.count {
            let slice = levels[index..<min(index + bucket, levels.count)]
            result.append(Int(((slice.max() ?? 0) * 100).rounded()))
            index += bucket
        }
        return result
    }

    static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

@MainActor
@Observable
final class AudioPlayback {
    static let shared = AudioPlayback()

    private(set) var currentURL: String?
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var duration: Double = 0
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    func isCurrent(_ url: String) -> Bool { currentURL == url }

    func toggle(_ url: String) {
        if currentURL == url, let player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                PlaybackAudio.prepare(muted: false)
                player.play()
                isPlaying = true
            }
            return
        }
        stop()
        guard let remote = url.hasPrefix("/") ? URL(fileURLWithPath: url) : URL(string: url) else { return }
        PlaybackAudio.prepare(muted: false)
        let player = AVPlayer(url: remote)
        self.player = player
        currentURL = url
        progress = 0
        duration = 0
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let item = self.player?.currentItem else { return }
                let total = item.duration.seconds
                if total.isFinite, total > 0 {
                    self.duration = total
                    self.progress = min(1, max(0, time.seconds / total))
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        player.play()
        isPlaying = true
    }

    func seek(_ url: String, to fraction: Double) {
        guard currentURL == url, let player, duration > 0 else { return }
        player.seek(to: CMTime(seconds: duration * min(1, max(0, fraction)), preferredTimescale: 600))
        progress = fraction
    }

    func stop() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        if player != nil { PlaybackAudio.release() }
        player = nil
        currentURL = nil
        isPlaying = false
        progress = 0
        duration = 0
    }
}
