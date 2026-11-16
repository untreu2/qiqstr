import AVKit
import MediaPlayer
import SwiftUI

/// Owns the live stream player so audio keeps going when the app is in the background or the
/// screen is locked, and shows the stream on the lock screen and in Control Center.
@MainActor
@Observable
final class LivePlayback {
    static let shared = LivePlayback()

    private(set) var player: AVPlayer?
    /// True while the app is in the background. The video surface lets go of the player then,
    /// because iOS pauses a player that is attached to a video layer when the app leaves the screen.
    private(set) var isVideoDetached = false
    private(set) var isPlaying = false
    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var stream: LiveStream?
    @ObservationIgnored private var wasPlayingBeforeBackground = false
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var commandTargets: [Any] = []
    @ObservationIgnored private var artworkTask: Task<Void, Never>?

    private init() {
        #if os(iOS)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LivePlayback.shared.willResignActive() }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LivePlayback.shared.didEnterBackground() }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LivePlayback.shared.willEnterForeground() }
        })
        #endif
    }

    /// Starts (or keeps) playing the stream and returns its player.
    @discardableResult
    func play(_ stream: LiveStream, url: URL) -> AVPlayer {
        self.stream = stream
        PlaybackAudio.prepare(muted: false)
        if url == self.url, let player {
            player.play()
            updateNowPlaying()
            return player
        }
        let next = AVPlayer(url: url)
        next.automaticallyWaitsToMinimizeStalling = true
        player?.pause()
        player = next
        self.url = url
        statusObservation = next.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                guard LivePlayback.shared.player === player else { return }
                LivePlayback.shared.isPlaying = playing
                LivePlayback.shared.updatePlaybackState()
            }
        }
        next.play()
        enableRemoteCommands()
        updateNowPlaying()
        return next
    }

    /// Refreshes the title and artwork, for example after the stream's details change.
    func update(_ stream: LiveStream) {
        guard self.stream?.coordinate == stream.coordinate else { return }
        self.stream = stream
        updateNowPlaying()
    }

    func resume() {
        PlaybackAudio.prepare(muted: false)
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        player?.pause()
        player = nil
        url = nil
        stream = nil
        isPlaying = false
        statusObservation = nil
        artworkTask?.cancel()
        disableRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        PlaybackAudio.release()
    }

    // MARK: Background

    private func willResignActive() {
        wasPlayingBeforeBackground = player.map { $0.timeControlStatus != .paused } ?? false
    }

    private func didEnterBackground() {
        guard player != nil else { return }
        isVideoDetached = true
        guard wasPlayingBeforeBackground else { return }
        // iOS pauses the player as the video layer goes away; start it again for audio only.
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard isVideoDetached else { return }
            resume()
        }
    }

    private func willEnterForeground() {
        isVideoDetached = false
    }

    // MARK: Now Playing

    private func updateNowPlaying() {
        guard let stream else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: stream.title.nilIfEmpty ?? L("liveTitle"),
            MPMediaItemPropertyArtist: ProfileCache.shared.profile(stream.host)?.bestName.nilIfEmpty ?? Profile.shortNpub(stream.host),
            MPNowPlayingInfoPropertyIsLiveStream: stream.isLive,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = existing
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updatePlaybackState()
        loadArtwork(stream)
    }

    private func updatePlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #endif
    }

    private func loadArtwork(_ stream: LiveStream) {
        artworkTask?.cancel()
        guard let source = stream.image?.nilIfEmpty, let url = URL(string: source) else { return }
        let coordinate = stream.coordinate
        artworkTask = Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), !Task.isCancelled,
                  let image = ImagePipeline.downsample(data, maxPixel: 600) else { return }
            guard self.stream?.coordinate == coordinate, var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }

    private func enableRemoteCommands() {
        guard commandTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        commandTargets.append(center.playCommand.addTarget { _ in
            MainActor.assumeIsolated { LivePlayback.shared.resume() }
            return .success
        })
        commandTargets.append(center.pauseCommand.addTarget { _ in
            MainActor.assumeIsolated { LivePlayback.shared.pause() }
            return .success
        })
        commandTargets.append(center.togglePlayPauseCommand.addTarget { _ in
            MainActor.assumeIsolated {
                let playback = LivePlayback.shared
                if playback.isPlaying { playback.pause() } else { playback.resume() }
            }
            return .success
        })
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand] { command.isEnabled = true }
        for command in [center.skipForwardCommand, center.skipBackwardCommand, center.changePlaybackPositionCommand, center.nextTrackCommand, center.previousTrackCommand] {
            command.isEnabled = false
        }
    }

    private func disableRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        for target in commandTargets {
            center.playCommand.removeTarget(target)
            center.pauseCommand.removeTarget(target)
            center.togglePlayPauseCommand.removeTarget(target)
        }
        commandTargets = []
    }
}
