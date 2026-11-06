import SwiftUI

@MainActor
@Observable
final class LiveListViewModel {
    private let service = LiveService.shared
    private(set) var loaded = false

    var snapshot: LiveSnapshot { service.snapshot }
    var isLoading: Bool { service.isLoading && snapshot.isEmpty }

    func load(force: Bool = false) async {
        _ = await service.load(force: force)
        loaded = true
    }

    func refreshProfiles() async {
        let hosts = (snapshot.live + snapshot.recordings).map(\.host)
        await ProfileCache.shared.load(hosts, fetchMissing: false)
    }
}

struct LiveListView: View {
    @State private var model = LiveListViewModel()
    @State private var bus = DataBus.shared

    var body: some View {
        List {
            if model.isLoading {
                Section {
                    ForEach(0..<3, id: \.self) { _ in LiveCardSkeleton().liveCardRow() }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("liveLoading"))
            } else {
                streamSection(L("liveFollowing"), streams: model.snapshot.following, identifier: "live-following")
                streamSection(L("livePopular"), streams: model.snapshot.popular, identifier: "live-popular")
                streamSection(L("liveRecordings"), streams: model.snapshot.recordings, identifier: "live-recordings")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .overlay { emptyOverlay }
        .navigationTitle(L("liveTitle"))
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.load(force: true) }
        .task { await model.load() }
        .task(id: bus.profileVersion) { await model.refreshProfiles() }
        .accessibilityIdentifier("live-list")
    }

    @ViewBuilder
    private func streamSection(_ title: String, streams: [LiveStream], identifier: String) -> some View {
        if !streams.isEmpty {
            Section {
                ForEach(streams) { stream in
                    NavigationLink(value: Route.liveStream(stream.coordinate)) {
                        LiveStreamCard(stream: stream)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .liveCardRow()
                    .contextMenu {
                        if let naddr = stream.naddr {
                            ShareLink(item: "nostr:\(naddr)") { Label(L("share"), systemImage: "square.and.arrow.up") }
                        }
                        Button { Router.shared.push(.profile(stream.host)) } label: {
                            Label(L("exploreOpenProfile"), systemImage: "person")
                        }
                    }
                }
            } header: {
                SearchSectionHeader(title: title)
            }
            .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if model.loaded, !model.isLoading, model.snapshot.isEmpty {
            EmptyStateView(systemImage: "dot.radiowaves.left.and.right", title: L("liveEmptyTitle"), message: L("liveEmptyMessage"), actionTitle: L("retry")) {
                Task { await model.load(force: true) }
            }
        }
    }
}

struct LiveCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(16 / 9, contentMode: .fit)
            HStack(spacing: 10) {
                Circle().fill(.quaternary).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Placeholder stream title").font(.headline)
                    Text(verbatim: "Host name").font(.subheadline)
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

extension View {
    func liveCardRow() -> some View {
        listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
