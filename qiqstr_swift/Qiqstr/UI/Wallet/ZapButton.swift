import SwiftUI

struct ZapButtonState: Equatable {
    var isZapped: Bool
    var isPending: Bool
    var addedSats: Int
}

struct ZapButton<Content: View>: View {
    let note: Note
    var hasZapped: Bool
    private let content: (ZapButtonState) -> Content
    @State private var zaps = ZapService.shared
    @State private var longPressAt: Date?
    @State private var longPressTick = 0
    @State private var tapTick = 0
    @State private var successTick = 0
    @State private var failureTick = 0

    init(note: Note, hasZapped: Bool = false, @ViewBuilder label: @escaping (ZapButtonState) -> Content) {
        self.note = note
        self.hasZapped = hasZapped
        self.content = label
    }

    private var state: ZapButtonState {
        let pending = zaps.pendingSats[note.id]
        return ZapButtonState(
            isZapped: hasZapped || pending != nil || zaps.hasZapped(note.id),
            isPending: pending != nil,
            addedSats: zaps.optimisticSats(for: note.id) + (pending ?? 0)
        )
    }

    var body: some View {
        Button(action: tap) {
            content(state)
                .symbolEffect(.bounce, value: tapTick)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                longPressAt = Date()
                longPressTick += 1
                openSheet()
            }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: tapTick)
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.error, trigger: failureTick)
        .sensoryFeedback(.selection, trigger: longPressTick)
        .accessibilityLabel(L("zap"))
        .accessibilityValue(state.isZapped ? L("walletZappedState") : "")
        .accessibilityHint(zaps.prefersQuickZap ? L("walletQuickZapHint", ["amount": Sats.format(ZapService.defaultAmount)]) : "")
        .accessibilityAction(named: L("walletZapCustom")) { openSheet() }
        .accessibilityIdentifier("note-zap")
    }

    private func tap() {
        if let longPressAt, Date().timeIntervalSince(longPressAt) < 3 {
            self.longPressAt = nil
            return
        }
        longPressAt = nil
        guard Router.shared.sheet == nil else { return }
        guard zaps.prefersQuickZap else {
            openSheet()
            return
        }
        guard !zaps.isPending(note.id) else { return }
        tapTick += 1
        Task {
            switch await zaps.quickZap(note: note) {
            case .zapped: successTick += 1
            case .failed: failureTick += 1
            case .needsSheet: openSheet()
            }
        }
    }

    private func openSheet() {
        Router.shared.sheet = .zap(note)
    }
}

extension ZapButton where Content == ZapButtonLabel {
    init(note: Note, hasZapped: Bool = false, zapAmount: Int = 0) {
        self.init(note: note, hasZapped: hasZapped) { state in
            ZapButtonLabel(state: state, baseAmount: zapAmount)
        }
    }
}

struct ZapButtonLabel: View {
    let state: ZapButtonState
    var baseAmount: Int = 0

    var body: some View {
        let total = baseAmount + state.addedSats
        HStack(spacing: 4) {
            Image(systemName: state.isZapped ? "bolt.fill" : "bolt")
                .contentTransition(.symbolEffect(.replace))
            if total > 0 {
                Text(Sats.compact(total))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(total)))
            }
        }
        .font(.subheadline)
        .foregroundStyle(state.isZapped ? AnyShapeStyle(AppColors.zap) : AnyShapeStyle(.secondary))
        .opacity(state.isPending ? 0.7 : 1)
        .animation(.snappy, value: state)
    }
}

struct ZapRetryToast: ViewModifier {
    @State private var zaps = ZapService.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let failure = zaps.failure {
                    ZapRetryBanner(failure: failure)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 72)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: failure.id) {
                            try? await Task.sleep(for: .seconds(6))
                            if zaps.failure?.id == failure.id { zaps.dismissFailure() }
                        }
                }
            }
            .animation(.snappy, value: zaps.failure)
            .onAppear { zaps.registerFailureHost() }
            .onDisappear { zaps.unregisterFailureHost() }
    }
}

struct ZapRetryBanner: View {
    let failure: ZapFailure
    @State private var retryTick = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(AppColors.error)
            VStack(alignment: .leading, spacing: 1) {
                Text(L("walletZapFailed", ["amount": Sats.format(failure.amountSats)]))
                    .font(.subheadline.weight(.semibold))
                Text(failure.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(L("retry")) {
                retryTick += 1
                Task { await ZapService.shared.retry(failure) }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("zap-retry")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .sensoryFeedback(.impact(weight: .light), trigger: retryTick)
        .onTapGesture { ZapService.shared.dismissFailure() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("zap-retry-toast")
    }
}

extension View {
    func zapRetryToast() -> some View { modifier(ZapRetryToast()) }
}
