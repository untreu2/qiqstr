import SwiftUI

struct LivePill: View {
    var body: some View {
        Text(L("liveBadge"))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.red, in: Capsule())
            .accessibilityLabel(L("liveNow"))
    }
}

struct LiveReplayPill: View {
    var body: some View {
        Label(L("liveReplay"), systemImage: "play.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.6), in: Capsule())
    }
}

struct LiveViewerCount: View {
    let count: Int

    var body: some View {
        Label(L("liveWatching", ["count": Sats.compact(count)]), systemImage: "eye")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
    }
}

struct LiveThumbnail: View {
    let stream: LiveStream

    var body: some View {
        RemoteImage(url: stream.image, maxPixel: 900) {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            Group {
                if stream.isLive { LivePill() } else if stream.canReplay { LiveReplayPill() }
            }
            .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            if stream.isLive, let viewers = stream.participants, viewers > 0 {
                LiveViewerCount(count: viewers).padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LiveHostName: View {
    let pubkey: String
    @State private var cache = ProfileCache.shared

    var body: some View {
        Text(cache.profile(pubkey)?.bestName.nilIfEmpty ?? Profile.shortNpub(pubkey))
    }
}

struct LiveStreamCard: View {
    let stream: LiveStream
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LiveThumbnail(stream: stream)
            HStack(alignment: .top, spacing: 10) {
                ProfileAvatar(pubkey: stream.host, size: compact ? 28 : 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stream.title.nilIfEmpty ?? L("liveUntitled"))
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        LiveHostName(pubkey: stream.host)
                            .lineLimit(1)
                        Text(verbatim: "·")
                        Text(stream.isLive ? L("liveStarted", ["time": TimeFormat.relative(stream.startedAt)]) : TimeFormat.relative(stream.startedAt))
                            .lineLimit(1)
                    }
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    if !compact, !stream.summary.isEmpty {
                        Text(stream.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
