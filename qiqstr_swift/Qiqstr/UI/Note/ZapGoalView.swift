import SwiftUI

struct ZapGoal: Hashable, Sendable {
    static let kind = 9041

    var noteId: String
    var targetSats: Int
    var closesAt: Int?
    var summary: String?

    init?(note: Note) {
        guard note.kind == Self.kind else { return nil }
        guard let msats = note.tags.first(where: { $0.count > 1 && $0[0] == "amount" }).flatMap({ Int($0[1]) }), msats >= 1000 else { return nil }
        noteId = note.id
        targetSats = msats / 1000
        closesAt = note.tags.first { $0.count > 1 && $0[0] == "closed_at" }.flatMap { Int($0[1]) }
        summary = note.tags.first { $0.count > 1 && $0[0] == "summary" }?[1].nilIfEmpty
    }

    var isClosed: Bool { closesAt.map { $0 <= TimeFormat.now } ?? false }
}

struct ZapGoalView: View {
    let goal: ZapGoal
    let note: Note
    var interactive = true
    @State private var store = NoteInteractionStore.shared
    @State private var zaps = ZapService.shared

    private var raised: Int { store.model(for: note).counts.zapAmount + zaps.optimisticSats(for: note.id) }
    private var fraction: Double { min(1, Double(raised) / Double(max(1, goal.targetSats))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Label(L("zapGoalTitle"), systemImage: "target")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 8)
                if goal.isClosed {
                    Text(L("zapGoalEnded")).font(.footnote).foregroundStyle(.secondary)
                } else if let closesAt = goal.closesAt {
                    Text(L("zapGoalEnds", ["date": Date(timeIntervalSince1970: TimeInterval(closesAt)).formatted(date: .abbreviated, time: .omitted)]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: fraction)
                .tint(AppColors.zap)
                .animation(.snappy, value: fraction)
            HStack(alignment: .firstTextBaseline) {
                Text(L("zapGoalProgress", ["raised": Sats.format(raised), "target": Sats.format(goal.targetSats)]))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppColors.textPrimary)
            }
            if interactive, !goal.isClosed, AppStorePolicy.allowsContentZaps, note.pubkey != Session.shared.pubkey {
                Button {
                    guard ReadOnlyGate.check() else { return }
                    Router.shared.sheet = .zap(note)
                } label: {
                    Label(L("zapGoalContribute"), systemImage: "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .secondaryGlassStyle()
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("zap-goal-contribute")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.inputFill, in: .rect(cornerRadius: 16, style: .continuous))
        .task(id: note.id) { store.requestCounts([note.id]) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zap-goal")
    }
}

struct ComposeGoalEditor: View {
    @Bindable var model: ComposeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "target").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(L("zapGoalAmountPlaceholder"), text: $model.goalAmount)
                    .keyboardType(.numberPad)
                    .font(.body.monospacedDigit())
                    .accessibilityLabel(L("zapGoalAmount"))
                    .accessibilityIdentifier("compose-goal-amount")
                Text(L("walletSats")).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppColors.inputFill, in: .rect(cornerRadius: 14, style: .continuous))
            Toggle(L("zapGoalDeadline"), isOn: $model.goalHasEnd.animation(.snappy))
                .font(.subheadline)
                .accessibilityIdentifier("compose-goal-end-toggle")
            if model.goalHasEnd {
                DatePicker(L("zapGoalEndsOn"), selection: $model.goalEndsAt, in: Date().addingTimeInterval(3600)..., displayedComponents: .date)
                    .font(.subheadline)
                    .accessibilityIdentifier("compose-goal-end-date")
            }
        }
        .padding(.leading, 52)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("compose-goal-editor")
    }
}
