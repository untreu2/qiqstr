import SwiftUI

struct SafetySettingsView: View {
    @State private var trust = WebOfTrustService.shared
    @AppStorage(WebOfTrustService.filterNotificationsKey) private var filterNotifications = true
    @AppStorage(WebOfTrustService.filterRepliesKey) private var filterReplies = true
    @AppStorage(WebOfTrustService.showSensitiveContentKey) private var showSensitive = false
    @State private var rebuildCount = 0

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $filterNotifications) {
                    SettingsRowLabel(title: L("safetyFilterNotifications"), systemImage: "bell.badge")
                }
                .tint(AppColors.switchActive)
                .accessibilityIdentifier("safety-filter-notifications")
                Toggle(isOn: $filterReplies) {
                    SettingsRowLabel(title: L("safetyFilterReplies"), systemImage: "bubble.left.and.bubble.right")
                }
                .tint(AppColors.switchActive)
                .accessibilityIdentifier("safety-filter-replies")
            } header: {
                Text(L("safetySpamFilter"))
            } footer: {
                Text(L("safetySpamFilterFooter", ["count": WebOfTrustService.minimumMutualFollows]))
            }
            Section {
                SettingsRowLabel(title: L("safetyTrustedNetwork"), systemImage: "person.3", value: networkValue)
                    .accessibilityIdentifier("safety-network-size")
                if trust.isBuilding {
                    ProgressView(value: trust.progress)
                        .accessibilityIdentifier("safety-network-progress")
                } else if let updatedAt = trust.updatedAt {
                    LabeledContent(L("safetyLastUpdated")) {
                        Text(updatedAt, format: .relative(presentation: .named))
                    }
                }
                Button {
                    rebuildCount += 1
                    trust.rebuild()
                } label: {
                    Text(L("safetyRebuild"))
                }
                .disabled(trust.isBuilding)
                .accessibilityIdentifier("safety-rebuild")
            } header: {
                Text(L("safetyTrustedNetwork"))
            } footer: {
                Text(L("safetyNetworkFooter"))
            }
            Section {
                Toggle(isOn: $showSensitive) {
                    SettingsRowLabel(title: L("safetySensitiveContent"), systemImage: "eye.trianglebadge.exclamationmark")
                }
                .tint(AppColors.switchActive)
                .accessibilityIdentifier("safety-show-sensitive")
            } header: {
                Text(L("safetyContent"))
            } footer: {
                Text(L("safetySensitiveFooter"))
            }
        }
        .settingsListStyle()
        .navigationTitle(L("safetyTitle"))
        .navigationBarTitleDisplayMode(.large)
        .sensoryFeedback(.selection, trigger: filterNotifications)
        .sensoryFeedback(.selection, trigger: filterReplies)
        .sensoryFeedback(.selection, trigger: showSensitive)
        .sensoryFeedback(.impact(weight: .light), trigger: rebuildCount)
    }

    private var networkValue: String {
        if trust.trustedCount == 0 {
            return trust.isBuilding ? L("safetyBuilding") : L("safetyNotBuilt")
        }
        return L("safetyPeopleCount", ["count": trust.trustedCount, "people": trust.trustedCount.formatted()])
    }
}
