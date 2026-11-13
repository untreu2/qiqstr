import AVKit
import SwiftUI

struct LiveStreamView: View {
    @State private var model: LiveStreamViewModel
    @State private var bus = DataBus.shared
    @State private var session = Session.shared
    @State private var reportTarget: ReportTarget?
    @Environment(\.dismiss) private var dismiss

    init(coordinate: String) {
        _model = State(initialValue: LiveStreamViewModel(coordinate: coordinate))
    }

    var body: some View {
        Group {
            if let stream = model.stream {
                content(stream)
            } else if model.notFound {
                EmptyStateView(systemImage: "dot.radiowaves.left.and.right", title: L("liveNotFound"), message: L("liveNotFoundMessage"))
            } else {
                LoadingView()
            }
        }
        .background(AppColors.background)
        .navigationTitle(model.stream?.title.nilIfEmpty ?? L("liveTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let stream = model.stream {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let naddr = stream.naddr {
                            ShareLink(item: "nostr:\(naddr)") { Label(L("share"), systemImage: "square.and.arrow.up") }
                                .accessibilityIdentifier("live-share")
                        }
                        if stream.host != session.pubkey {
                            Section {
                                Button(L("mute"), systemImage: "speaker.slash", role: .destructive) { muteHost(stream) }
                                    .accessibilityIdentifier("live-mute-host")
                                Button(L("report"), systemImage: "flag", role: .destructive) {
                                    reportTarget = ReportTarget(pubkey: stream.host, eventId: stream.eventId)
                                }
                                .accessibilityIdentifier("live-report")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel(L("profileMoreActions"))
                    .accessibilityIdentifier("live-menu")
                }
            }
        }
        .reportSheet($reportTarget) { target in
            if MuteService.shared.isMuted(target.pubkey) { dismiss() }
        }
        .onChange(of: session.mutedPubkeys) { model.applyMutes() }
        .task { await model.load() }
        .task { await model.refreshStreamPeriodically() }
        .task(id: model.stream?.coordinate) { await model.runChat() }
        .task(id: bus.profileVersion) { await model.refreshProfiles() }
        .onAppear { model.resume() }
        .onDisappear { model.stop() }
        .accessibilityIdentifier("live-stream")
    }

    private func muteHost(_ stream: LiveStream) {
        Task {
            await Moderation.mute(stream.host)
            ToastCenter.shared.show(L("feedUserMuted"), style: .success)
            dismiss()
        }
    }

    private func content(_ stream: LiveStream) -> some View {
        VStack(spacing: 0) {
            LivePlayerArea(stream: stream, player: model.player)
            LiveStreamHeader(stream: stream, onHost: model.openHost, onZap: model.zapHost)
            Divider()
            LiveChatList(messages: model.messages, loaded: model.chatLoaded, isLive: stream.isLive)
        }
        .safeAreaInset(edge: .bottom) {
            if model.showsChatInput {
                LiveChatInput(text: $model.draft, canSend: model.canSend, isSending: model.isSending) {
                    Task { await model.send() }
                }
            }
        }
    }
}

struct LivePlayerArea: View {
    let stream: LiveStream
    let player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            } else {
                RemoteImage(url: stream.image, maxPixel: 900) { Color.black }
                    .opacity(0.35)
                VStack(spacing: 6) {
                    Image(systemName: "video.slash")
                        .font(.title2)
                    Text(L("liveEndedMessage"))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding()
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("live-player")
    }
}

struct LiveStreamHeader: View {
    let stream: LiveStream
    let onHost: () -> Void
    let onZap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if stream.isLive { LivePill() } else if stream.canReplay { Text(L("liveEnded")).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                if stream.isLive, let viewers = stream.participants {
                    Label(L("liveWatching", ["count": Sats.compact(viewers)]), systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(TimeFormat.relative(stream.startedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !stream.title.isEmpty {
                Text(stream.title)
                    .font(.headline)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Button(action: onHost) {
                    HStack(spacing: 8) {
                        ProfileAvatar(pubkey: stream.host, size: 32)
                        LiveHostName(pubkey: stream.host)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("live-host")
                Spacer(minLength: 8)
                Button(action: onZap) {
                    Label(L("liveZapHost"), systemImage: "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityIdentifier("live-zap-host")
            }
            if !stream.summary.isEmpty {
                Text(stream.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
