import SwiftUI

extension GossipMode {
    var title: String {
        switch self {
        case .normal: L("settingsGossipNormal")
        case .aggressive: L("settingsGossipAggressive")
        case .psycho: L("settingsGossipPsycho")
        }
    }

    var detail: String {
        L("settingsGossipDetail", ["relays": maxOutboxRelays, "frequency": minRelayFrequency])
    }
}

struct RelaySettingsView: View {
    @State private var model = RelaySettingsModel()
    @FocusState private var urlFocused: Bool

    var body: some View {
        List {
            SettingsPageHeader(subtitle: L("manageYourRelayConnections"))
            Section {
                HStack(spacing: 10) {
                    Circle()
                        .fill(model.connectedCount > 0 ? AppColors.success : AppColors.warning)
                        .frame(width: 10, height: 10)
                    Text("\(model.connectedCount)/\(model.totalCount) \(L("connected").lowercased())")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Spacer()
                    Text(SettingsByteFormat.string(model.totalBytes))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("relays-summary")
                if let progress = model.broadcastProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress.total > 0 ? Double(progress.sent) / Double(progress.total) : 0)
                            .tint(AppColors.textPrimary)
                        Text(progress.total > 0 ? L("broadcastProgress", ["sent": progress.sent, "total": progress.total]) : L("fetchingYourEvents"))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityIdentifier("relays-broadcast-progress")
                }
            }

            Section {
                actionButtons
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                if model.relays.isEmpty {
                    Text(L("noRelaysInCategory"))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    ForEach(model.relays, id: \.self) { relay in
                        SettingsRelayRow(url: relay, status: model.status(for: relay), flags: model.flags(for: relay))
                            .swipeActions(edge: .trailing) {
                                Button(L("delete"), role: .destructive) { Task { await model.remove(relay) } }
                            }
                            .contextMenu { relayMenu(relay) }
                            .accessibilityIdentifier("relay-row-\(RelaySettingsModel.host(relay))")
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
            } header: {
                HStack {
                    Text(L("relays"))
                    Spacer()
                    Button { model.showAdd = true } label: {
                        Label(L("addRelay"), systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .textCase(nil)
                    .accessibilityIdentifier("relays-add")
                }
            }

            Section {
                Picker(selection: $model.gossipMode) {
                    ForEach(GossipMode.allCases) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.title)
                            Text(mode.detail).font(.caption).foregroundStyle(AppColors.textSecondary)
                        }
                        .tag(mode)
                    }
                } label: {
                    SettingsRowLabel(title: L("gossipMode"), systemImage: "point.3.filled.connected.trianglepath.dotted")
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("relays-gossip-mode")
            } footer: {
                Text(L("gossipModeDescription"))
            }

            Section {
                Button(role: .destructive) { model.showResetConfirm = true } label: {
                    SettingsRowLabel(title: L("resetToDefaults"), systemImage: "arrow.counterclockwise", tint: AppColors.error)
                }
                .accessibilityIdentifier("relays-reset")
            }
        }
        .settingsListStyle()
        .navigationTitle(L("relays"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().accessibilityIdentifier("relays-edit") }
        }
        .onAppear {
            model.load()
            model.startStatus()
        }
        .onDisappear { model.stopStatus() }
        .sheet(isPresented: $model.showAdd) { addSheet }
        .confirmationDialog(L("resetToDefaults"), isPresented: $model.showResetConfirm, titleVisibility: .visible) {
            Button(L("reset"), role: .destructive) { Task { await model.resetToDefaults() } }
                .accessibilityIdentifier("relays-reset-confirm")
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("resetRelaysConfirm"))
        }
        .alert(L("settingsBroadcastTitle"), isPresented: $model.showBroadcastPrompt) {
            Button(L("settingsNo"), role: .cancel) { model.pendingBroadcast = [] }
            Button(L("settingsYes")) { Task { await model.broadcastPending() } }
                .accessibilityIdentifier("relays-broadcast-confirm")
        } message: {
            Text(model.pendingBroadcast.count == 1 ? L("settingsBroadcastOne") : L("settingsBroadcastMany", ["count": model.pendingBroadcast.count]))
        }
        .sensoryFeedback(.success, trigger: model.feedback)
    }

    private var actionButtons: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button { Task { await model.fetchFromProfile() } } label: {
                    Label(model.isFetching ? L("fetching") : L("fetch"), systemImage: "arrow.down.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glass)
                .disabled(model.isFetching)
                .accessibilityIdentifier("relays-fetch")
                Button { Task { await model.publish() } } label: {
                    Label(model.isPublishing ? L("publishing") : L("publish"), systemImage: "arrow.up.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .tint(AppColors.textPrimary)
                .foregroundStyle(AppColors.background)
                .disabled(model.isPublishing || model.relays.isEmpty)
                .accessibilityIdentifier("relays-publish")
            }
        }
    }

    @ViewBuilder
    private func relayMenu(_ relay: String) -> some View {
        let f = model.flags(for: relay)
        Button {
            SettingsClipboard.copy(relay)
            ToastCenter.shared.show(L("copiedToClipboard"), style: .success)
        } label: { Label(L("copy"), systemImage: "doc.on.doc") }
        Section(L("settingsRelayUsage")) {
            Button { Task { await model.setFlags(relay, read: true, write: true) } } label: {
                Label(L("settingsRelayReadWrite"), systemImage: f.read && f.write ? "checkmark" : "arrow.up.arrow.down")
            }
            Button { Task { await model.setFlags(relay, read: true, write: false) } } label: {
                Label(L("settingsRelayReadOnly"), systemImage: f.read && !f.write ? "checkmark" : "arrow.down")
            }
            Button { Task { await model.setFlags(relay, read: false, write: true) } } label: {
                Label(L("settingsRelayWriteOnly"), systemImage: !f.read && f.write ? "checkmark" : "arrow.up")
            }
        }
        Button(role: .destructive) { Task { await model.remove(relay) } } label: {
            Label(L("delete"), systemImage: "trash")
        }
    }

    private var addSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                QiqTextField(placeholder: L("relayUrlHint"), text: $model.newRelayURL, keyboard: .URL)
                    .focused($urlFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await model.add() } }
                    .accessibilityIdentifier("relays-add-field")
                if !model.newRelayURL.isEmpty && !RelaySettingsModel.isValid(RelaySettingsModel.canonicalInput(model.newRelayURL)) {
                    Text(L("invalidRelayUrl"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.error)
                }
                PrimaryButton(title: L("addRelay"), isEnabled: RelaySettingsModel.isValid(RelaySettingsModel.canonicalInput(model.newRelayURL))) {
                    Task { await model.add() }
                }
                .accessibilityIdentifier("relays-add-confirm")
                Spacer()
            }
            .padding(20)
            .navigationTitle(L("addRelay"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { model.showAdd = false }
                }
            }
            .onAppear {
                if model.newRelayURL.isEmpty { model.newRelayURL = "wss://" }
                urlFocused = true
            }
        }
        .presentationDetents([.height(260)])
    }
}

struct SettingsRelayRow: View {
    let url: String
    let status: SettingsRelayStatus?
    let flags: SettingsRelayFlags

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                IconTile(systemImage: "server.rack", size: 36)
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(AppColors.surface, lineWidth: 2))
                    .offset(x: 14, y: 14)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(RelaySettingsModel.host(url))
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(statusText)
                        .foregroundStyle(statusColor)
                    if let status, status.latencyMs > 0 {
                        Label("\(status.latencyMs)ms", systemImage: "gauge.with.dots.needle.33percent")
                            .foregroundStyle(latencyColor(status.latencyMs))
                    }
                    if let status, status.bytesReceived > 0 {
                        Label(SettingsByteFormat.string(status.bytesReceived), systemImage: "arrow.down")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    if !(flags.read && flags.write) {
                        Text(flags.read ? L("settingsRelayReadOnly") : L("settingsRelayWriteOnly"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(AppColors.tile, in: Capsule())
                    }
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .labelStyle(SettingsCompactLabelStyle())
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .animation(.smooth, value: status)
    }

    private var statusText: String {
        switch status?.status {
        case "connected": L("connected")
        case "connecting", "pending", "initialized": L("connecting")
        case "sleeping": L("settingsRelaySleeping")
        default: L("disconnected")
        }
    }

    private var statusColor: Color {
        switch status?.status {
        case "connected": AppColors.success
        case "connecting", "pending", "initialized", "sleeping": AppColors.warning
        default: AppColors.error
        }
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 300 { return AppColors.success }
        if ms < 800 { return AppColors.warning }
        return AppColors.error
    }
}

struct SettingsCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}
