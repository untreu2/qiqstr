import AVKit
import SwiftUI

@MainActor
@Observable
final class LiveStreamViewModel {
    let coordinate: String
    private let service = LiveService.shared
    private(set) var stream: LiveStream?
    private(set) var notFound = false
    private(set) var player: AVPlayer?
    private(set) var messages: [LiveChatMessage] = []
    private(set) var chatLoaded = false
    private(set) var isSending = false
    var draft = ""
    @ObservationIgnored private var seen = Set<String>()
    @ObservationIgnored private var playingURL: URL?

    init(coordinate: String) {
        self.coordinate = coordinate
        stream = LiveService.shared.cached(coordinate)
    }

    var canSend: Bool { !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var showsChatInput: Bool { stream?.isLive == true }

    func load() async {
        if stream == nil {
            stream = await service.stream(coordinate: coordinate)
            notFound = stream == nil
        }
        startPlayback()
    }

    func refreshStreamPeriodically() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let updated = await service.stream(coordinate: coordinate) else { continue }
            stream = updated
            if updated.playbackURL != playingURL { startPlayback() }
        }
    }

    func runChat() async {
        guard let stream else { return }
        if !chatLoaded {
            merge(await service.chatHistory(stream))
            chatLoaded = true
        }
        guard stream.isLive else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.subscribe(stream) }
            group.addTask { await self.poll(stream) }
        }
    }

    private func subscribe(_ stream: LiveStream) async {
        var attempts = 0
        while !Task.isCancelled {
            do {
                for try await message in service.chatStream(stream) {
                    attempts = 0
                    merge([message])
                }
            } catch {}
            attempts += 1
            try? await Task.sleep(for: .seconds(min(30, 2 * attempts)))
        }
    }

    private func poll(_ stream: LiveStream) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            let since = (messages.last?.createdAt ?? TimeFormat.now) - 30
            merge(await service.chatSince(stream, since: since))
        }
    }

    private func merge(_ incoming: [LiveChatMessage]) {
        let muted = Set(Session.shared.mutedPubkeys)
        let fresh = incoming.filter { !muted.contains($0.pubkey) && seen.insert($0.id).inserted }
        guard !fresh.isEmpty else { return }
        var combined = messages + fresh
        combined.sort { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
        messages = Array(combined.suffix(500))
        Task { await ProfileCache.shared.load(Array(Set(fresh.map(\.pubkey)))) }
    }

    func refreshProfiles() async {
        await ProfileCache.shared.load(Array(Set(messages.map(\.pubkey) + [stream?.host].compactMap { $0 })), fetchMissing: false)
    }

    func send() async {
        guard let stream, canSend else { return }
        isSending = true
        defer { isSending = false }
        do {
            let message = try await service.sendChat(draft, to: stream)
            draft = ""
            merge([message])
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    func zapHost() {
        guard let host = stream?.host else { return }
        Router.shared.sheet = .zapProfile(host)
    }

    func openHost() {
        guard let host = stream?.host else { return }
        Router.shared.push(.profile(host))
    }

    func resume() {
        if player == nil { startPlayback() } else { player?.play() }
    }

    func stop() {
        player?.pause()
    }

    private func startPlayback() {
        guard let url = stream?.playbackURL, stream?.isLive == true || stream?.canReplay == true else {
            player?.pause()
            player = nil
            playingURL = nil
            return
        }
        if url == playingURL, let player {
            player.play()
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let next = AVPlayer(url: url)
        next.automaticallyWaitsToMinimizeStalling = true
        player?.pause()
        player = next
        playingURL = url
        next.play()
    }
}
