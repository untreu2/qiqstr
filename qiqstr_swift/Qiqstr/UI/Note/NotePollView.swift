import SwiftUI

struct NotePollView: View {
    let poll: NotePoll
    let author: String
    var interactive = true
    @State private var service = PollService.shared
    @State private var session = Session.shared
    @State private var selection: Set<String> = []
    @State private var confirming = false
    @State private var voting = false
    @State private var revealed = false
    @State private var voted = 0

    var body: some View {
        if service.invalid.contains(poll.id) {
            EmptyView()
        } else {
            content
                .task(id: poll.id) { await service.load(poll) }
        }
    }

    private var content: some View {
        let tally = service.tally(poll.id) ?? PollTally()
        let ended = poll.isEnded()
        let canVote = interactive && !ended && session.privateKey != nil && tally.mine.isEmpty
        let showsResults = !canVote || revealed
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(poll.options) { option in
                if showsResults {
                    resultRow(option, tally: tally)
                } else {
                    optionButton(option)
                }
            }
            if canVote, !revealed, poll.multiple, !selection.isEmpty {
                Button { confirming = true } label: {
                    if voting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(L("feedPollVote")).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .foregroundStyle(AppColors.background)
                .disabled(voting)
                .accessibilityIdentifier("poll-vote")
            }
            footer(tally: tally, ended: ended, canVote: canVote, showsResults: showsResults)
        }
        .sensoryFeedback(.success, trigger: voted)
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button(L("feedPollVote")) { submit() }
                .accessibilityIdentifier("poll-confirm-vote")
            Button(L("cancel"), role: .cancel) { if !poll.multiple { selection = [] } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("note-poll")
    }

    private var confirmTitle: String {
        if poll.multiple { return L("feedPollVoteConfirmMultiple", ["count": selection.count]) }
        let label = poll.options.first { selection.contains($0.id) }?.label ?? ""
        return L("feedPollVoteConfirm", ["option": label])
    }

    private func optionButton(_ option: NotePoll.Option) -> some View {
        let selected = selection.contains(option.id)
        return Button {
            if poll.multiple {
                if selected { selection.remove(option.id) } else { selection.insert(option.id) }
            } else {
                selection = [option.id]
                confirming = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: poll.multiple ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(selected ? AnyShapeStyle(AppColors.link) : AnyShapeStyle(.secondary))
                Text(option.label)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(AppColors.inputFill, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? AppColors.link : AppColors.border, lineWidth: selected ? 1 : 0.5))
            .contentShape(.rect(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(voting)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("poll-option")
    }

    private func resultRow(_ option: NotePoll.Option, tally: PollTally) -> some View {
        let share = tally.share(option.id)
        let mine = tally.mine.contains(option.id)
        let leading = (tally.counts[option.id] ?? 0) > 0 && (tally.counts[option.id] ?? 0) == tally.counts.values.max()
        return HStack(spacing: 8) {
            Text(option.label)
                .fontWeight(leading ? .semibold : .regular)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
            if mine {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.link)
                    .accessibilityLabel(L("feedPollYourVote"))
            }
            Spacer(minLength: 8)
            Text(share, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(mine ? AnyShapeStyle(AppColors.link.opacity(0.22)) : AnyShapeStyle(AppColors.tile))
                    .frame(width: max(share > 0 ? 12 : 0, proxy.size.width * share))
            }
        }
        .background(AppColors.inputFill.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .animation(.snappy, value: share)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("poll-result")
    }

    private func footer(tally: PollTally, ended: Bool, canVote: Bool, showsResults: Bool) -> some View {
        HStack(spacing: 4) {
            Text(L("feedPollVotes", ["count": tally.voters]))
                .contentTransition(.numericText())
            if let status = status(ended: ended) {
                Text("· \(status)")
            }
            if poll.multiple, canVote {
                Text("· \(L("feedPollMultiple"))")
            }
            Spacer(minLength: 0)
            if canVote {
                Button(revealed ? L("feedPollHideResults") : L("feedPollShowResults")) {
                    withAnimation(.snappy) { revealed.toggle() }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppColors.link)
                .accessibilityIdentifier("poll-toggle-results")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.top, 2)
    }

    private func status(ended: Bool) -> String? {
        if ended { return L("feedPollEnded") }
        guard let endsAt = poll.endsAt else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(endsAt))
        return L("feedPollEndsIn", ["time": date.formatted(.relative(presentation: .named))])
    }

    private func submit() {
        let ids = poll.options.map(\.id).filter { selection.contains($0) }
        guard !ids.isEmpty, !voting else { return }
        voting = true
        Task {
            do {
                try await service.vote(poll, optionIds: ids)
                voted += 1
                revealed = false
            } catch {
                ToastCenter.shared.show("\(L("feedPollVoteFailed")): \(coreMessage(error))", style: .error)
            }
            selection = []
            voting = false
        }
    }
}
