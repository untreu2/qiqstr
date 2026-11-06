import SwiftUI

extension FollowInterest {
    var title: String { L("authInterest" + rawValue.capitalized) }

    static var saved: Set<FollowInterest> {
        get { Set((UserDefaults.standard.stringArray(forKey: "onboarding_interests") ?? []).compactMap(FollowInterest.init(rawValue:))) }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: "onboarding_interests") }
    }
}

struct OnboardingInterestsView: View {
    let onSkip: () -> Void
    let onContinue: (Set<FollowInterest>) -> Void

    @State private var selection: Set<FollowInterest> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                AuthHeader(title: L("authInterestsTitle"), subtitle: L("authInterestsSubtitle"))
                InterestChipGrid(selection: $selection)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(AppColors.background)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: L("continueButton"), isEnabled: !selection.isEmpty) {
                FollowInterest.saved = selection
                onContinue(selection)
            }
            .accessibilityIdentifier("onboarding-interests-continue")
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(AppColors.background)
        }
        .toolbar {
            ToolbarItem(placement: .principal) { OnboardingStepIndicator(current: 3) }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("skip"), action: onSkip)
                    .accessibilityIdentifier("onboarding-interests-skip")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct InterestChipGrid: View {
    @Binding var selection: Set<FollowInterest>

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            InterestFlowLayout(spacing: 10, lineSpacing: 10) {
                ForEach(FollowInterest.allCases) { interest in
                    InterestChip(interest: interest, isSelected: selection.contains(interest)) {
                        toggle(interest)
                    }
                }
            }
        }
        .accessibilityIdentifier("onboarding-interests")
    }

    private func toggle(_ interest: FollowInterest) {
        withAnimation(.snappy) {
            if selection.contains(interest) { selection.remove(interest) } else { selection.insert(interest) }
        }
    }
}

struct InterestChip: View {
    let interest: FollowInterest
    let isSelected: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(interest.title, systemImage: isSelected ? "checkmark" : interest.systemImage)
                .font(compact ? .subheadline.weight(.medium) : .body.weight(.medium))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isSelected ? AppColors.background : AppColors.textPrimary)
                .padding(.horizontal, compact ? 12 : 16)
                .padding(.vertical, compact ? 7 : 11)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .glassEffect(isSelected ? .regular.tint(AppColors.textPrimary).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("interest-\(interest.rawValue)")
    }
}

struct InterestFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + lineSpacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
