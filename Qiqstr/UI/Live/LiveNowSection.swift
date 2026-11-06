import SwiftUI

@MainActor
@Observable
final class LiveNowSectionModel {
    private let service = LiveService.shared

    var streams: [LiveStream] { Array(service.snapshot.live.prefix(10)) }

    static func load(force: Bool = false) async { _ = await LiveService.shared.load(force: force) }
}

struct LiveNowSection: View {
    @State private var model = LiveNowSectionModel()

    var body: some View {
        if !model.streams.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(model.streams) { stream in
                            NavigationLink(value: Route.liveStream(stream.coordinate)) {
                                LiveStreamCard(stream: stream, compact: true)
                                    .frame(width: 250)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("search-live-\(stream.identifier)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } header: {
                SearchSectionHeader(title: L("liveNow")) { Router.shared.push(.liveStreams) }
            }
            .accessibilityIdentifier("search-live-now")
        }
    }
}
