import SwiftUI

@MainActor
@Observable
final class TopicsManagerViewModel {
    var draft = ""
    private(set) var feedback = 0

    private var service: HashtagFollowService { HashtagFollowService.shared }

    var tags: [String] { service.tags }
    var isLoaded: Bool { service.isLoaded }

    var normalizedDraft: String? { HashtagFollowService.normalize(draft) }

    var canAdd: Bool {
        guard let tag = normalizedDraft else { return false }
        return !service.isFollowing(tag)
    }

    var showsInvalidHint: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft != "#" && normalizedDraft == nil
    }

    func isPending(_ tag: String) -> Bool { service.isPending(tag) }

    func add() {
        guard canAdd, let tag = normalizedDraft else { return }
        draft = ""
        feedback &+= 1
        Task {
            do { try await service.follow(tag) } catch { ToastCenter.shared.error(error) }
        }
    }

    func remove(_ tag: String) {
        feedback &+= 1
        Task {
            do { try await service.unfollow(tag) } catch { ToastCenter.shared.error(error) }
        }
    }
}

struct TopicsManagerView: View {
    var onSelect: (String) -> Void = { _ in }
    @State private var model = TopicsManagerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(L("feedTopicPlaceholder"), text: $model.draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { model.add() }
                            .accessibilityIdentifier("topics-field")
                        Button(L("feedAddTopic"), systemImage: "plus.circle.fill") { model.add() }
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .disabled(!model.canAdd)
                            .accessibilityIdentifier("topics-add")
                    }
                } footer: {
                    if model.showsInvalidHint {
                        Text(L("feedTopicInvalid"))
                    } else {
                        Text(L("feedTopicsFooter"))
                    }
                }
                topicsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("feedManageTopics"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("done")) { dismiss() }
                        .accessibilityIdentifier("topics-done")
                }
            }
            .sensoryFeedback(.selection, trigger: model.feedback)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var topicsSection: some View {
        if model.tags.isEmpty {
            Section {
                if model.isLoaded {
                    ContentUnavailableView(L("feedNoTopics"), systemImage: "number", description: Text(L("feedNoTopicsMessage")))
                } else {
                    ForEach(0..<3, id: \.self) { _ in
                        Label(String("#placeholder"), systemImage: "number")
                    }
                    .redacted(reason: .placeholder)
                }
            }
        } else {
            Section(L("feedTopics")) {
                ForEach(model.tags, id: \.self) { tag in
                    Button {
                        onSelect(tag)
                        dismiss()
                    } label: {
                        Label("#\(tag)", systemImage: "number")
                            .foregroundStyle(.primary)
                    }
                    .disabled(model.isPending(tag))
                    .swipeActions(edge: .trailing) {
                        Button(L("feedRemoveTopic"), systemImage: "trash", role: .destructive) { model.remove(tag) }
                    }
                    .contextMenu {
                        Button(L("feedRemoveTopic"), systemImage: "trash", role: .destructive) { model.remove(tag) }
                    }
                    .accessibilityIdentifier("topics-row-\(tag)")
                }
            }
        }
    }
}
