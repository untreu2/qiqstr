import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @State private var service = LocalNotificationService.shared
    @AppStorage(LocalNotificationType.replies.key) private var replies = true
    @AppStorage(LocalNotificationType.reactions.key) private var reactions = true
    @AppStorage(LocalNotificationType.reposts.key) private var reposts = true
    @AppStorage(LocalNotificationType.zaps.key) private var zaps = true
    @AppStorage(LocalNotificationType.messages.key) private var messages = true
    @AppStorage(WebOfTrustService.filterNotificationsKey) private var onlyKnown = true
    @State private var isRequesting = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                Toggle(isOn: masterBinding) {
                    SettingsRowLabel(title: L("localNotifyAllow"), systemImage: "bell.badge")
                }
                .tint(AppColors.switchActive)
                .disabled(isRequesting)
                .accessibilityIdentifier("notify-master")
                if service.isDenied {
                    Button(L("walletOpenSettings")) { openSystemSettings() }
                        .accessibilityIdentifier("notify-open-settings")
                }
            } footer: {
                Text(service.isDenied ? L("localNotifyDeniedFooter") : L("localNotifyAllowFooter"))
            }
            Section {
                typeToggle($replies, L("notificationFilterReplies"), "bubble.left.and.bubble.right", "replies")
                typeToggle($reactions, L("reactions"), "heart", "reactions")
                typeToggle($reposts, L("reposts"), "arrow.2.squarepath", "reposts")
                typeToggle($zaps, L("zaps"), "bolt", "zaps")
                typeToggle($messages, L("messages"), "message", "messages")
            } header: {
                Text(L("localNotifyTypesHeader"))
            }
            .disabled(!service.isEnabled)
            Section {
                Toggle(isOn: $onlyKnown) {
                    SettingsRowLabel(title: L("notificationsOnlyKnown"), systemImage: "person.2")
                }
                .tint(AppColors.switchActive)
                .accessibilityIdentifier("notify-only-known")
            } footer: {
                Text(L("localNotifyOnlyKnownFooter"))
            }
            Section {
                LabeledContent(L("localNotifyBackgroundRefresh")) {
                    Text(service.backgroundRefreshAvailable ? L("localNotifyOn") : L("localNotifyOff"))
                }
                .accessibilityIdentifier("notify-background-refresh")
                if !service.backgroundRefreshAvailable {
                    Button(L("walletOpenSettings")) { openSystemSettings() }
                }
            } footer: {
                Text(L("localNotifyDeliveryFooter"))
            }
        }
        .settingsListStyle()
        .navigationTitle(L("notifications"))
        .navigationBarTitleDisplayMode(.large)
        .task(id: scenePhase) { await service.refreshStatus() }
        .sensoryFeedback(.selection, trigger: service.isEnabled)
        .sensoryFeedback(.selection, trigger: onlyKnown)
    }

    private var masterBinding: Binding<Bool> {
        Binding(
            get: { service.isDelivering },
            set: { isOn in
                guard isOn else {
                    service.isEnabled = false
                    return
                }
                if service.isDenied {
                    openSystemSettings()
                    return
                }
                isRequesting = true
                Task {
                    await service.enable()
                    isRequesting = false
                }
            }
        )
    }

    private func typeToggle(_ binding: Binding<Bool>, _ title: String, _ systemImage: String, _ id: String) -> some View {
        Toggle(isOn: binding) {
            SettingsRowLabel(title: title, systemImage: systemImage)
        }
        .tint(AppColors.switchActive)
        .sensoryFeedback(.selection, trigger: binding.wrappedValue)
        .accessibilityIdentifier("notify-type-\(id)")
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }
}

struct NotificationPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge")
                .font(.largeTitle)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(L("localNotifyPromptTitle"))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(L("localNotifyPromptMessage"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                Button {
                    isRequesting = true
                    Task {
                        await LocalNotificationService.shared.enable()
                        isRequesting = false
                        dismiss()
                    }
                } label: {
                    Text(L("localNotifyPromptAllow")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(isRequesting)
                .accessibilityIdentifier("notify-prompt-allow")
                Button {
                    LocalNotificationService.shared.dismissPrompt()
                    dismiss()
                } label: {
                    Text(L("localNotifyPromptLater")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityIdentifier("notify-prompt-later")
            }
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isRequesting)
        .onDisappear { LocalNotificationService.shared.dismissPrompt() }
        .accessibilityIdentifier("notify-prompt")
    }
}

struct NotificationPromptModifier: ViewModifier {
    @State private var service = LocalNotificationService.shared
    @State private var session = Session.shared
    @State private var router = Router.shared
    @State private var isPresented = false
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) { NotificationPromptSheet() }
            .task(id: canOffer) {
                guard canOffer else { return }
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, canOffer else { return }
                isPresented = true
            }
    }

    private var canOffer: Bool {
        service.shouldOfferPrompt && session.phase == .ready && !session.isNewAccount && scenePhase == .active
            && router.sheet == nil && !router.isComposing && !router.showSidebar
    }
}

extension View {
    func notificationPrompt() -> some View { modifier(NotificationPromptModifier()) }
}
