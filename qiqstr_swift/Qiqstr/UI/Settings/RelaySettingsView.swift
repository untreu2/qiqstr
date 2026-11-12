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
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(verbatim: "\(model.connectedCount)/\(model.totalCount)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } label: {
                    Label {
                        Text(L("connected"))
                    } icon: {
                        SettingsIcon(systemImage: "antenna.radiowaves.left.and.right", tint: model.connectedCount > 0 ? AppColors.success : AppColors.warning)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("relays-summary")
                LabeledContent {
                    Text(SettingsByteFormat.string(model.totalBytes)).monospacedDigit()
                } label: {
                    SettingsRowLabel(title: L("settingsRelayTraffic"), systemImage: "arrow.up.arrow.down")
                }
                if let progress = model.broadcastProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress.total > 0 ? Double(progress.sent) / Double(progress.total) : 0)
                            .tint(AppColors.textPrimary)
                        Text(progress.total > 0 ? L("broadcastProgress", ["sent": progress.sent, "total": progress.total]) : L("fetchingYourEvents"))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("relays-broadcast-progress")
                }
            } footer: {
                Text(L("manageYourRelayConnections"))
            }

            Section {
                Button { Task { await model.fetchFromProfile() } } label: {
                    HStack {
                        SettingsRowLabel(title: model.isFetching ? L("fetching") : L("fetch"), systemImage: "arrow.down.circle")
                        Spacer()
                        if model.isFetching { ProgressView() }
                    }
                }
                .disabled(model.isFetching)
                .accessibilityIdentifier("relays-fetch")
                Button { Task { await model.publish() } } label: {
                    HStack {
                        SettingsRowLabel(title: model.isPublishing ? L("publishing") : L("publish"), systemImage: "arrow.up.circle")
                        Spacer()
                        if model.isPublishing { ProgressView() }
                    }
                }
                .disabled(model.isPublishing || model.relays.isEmpty)
                .accessibilityIdentifier("relays-publish")
            }

            Section {
                if model.relays.isEmpty {
                    Text(L("noRelaysInCategory"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.relays, id: \.self) { relay in
                        SettingsRelayRow(url: relay, status: model.status(for: relay), flags: model.flags(for: relay))
                            .contextMenu { relayMenu(relay) }
                            .swipeActions {
                                Button(L("delete"), systemImage: "trash", role: .destructive) { Task { await model.remove(relay) } }
                            }
                            .accessibilityIdentifier("relay-row-\(RelaySettingsModel.host(relay))")
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
            } header: {
                Text(L("relays"))
            }

            Section {
                Picker(selection: $model.gossipMode) {
                    ForEach(GossipMode.allCases) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.title)
                            Text(mode.detail).font(.caption).foregroundStyle(.secondary)
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
                Button(L("resetToDefaults"), role: .destructive) { model.showResetConfirm = true }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("relays-reset")
            }
        }
        .settingsListStyle()
        .environment(\.editMode, $editMode)
        .navigationTitle(L("relays"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? L("done") : L("edit")) {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
                .accessibilityIdentifier("relays-edit")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("addRelay"), systemImage: "plus") { model.showAdd = true }
                    .accessibilityIdentifier("relays-add")
            }
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

    private var isNewRelayValid: Bool {
        RelaySettingsModel.isValid(RelaySettingsModel.canonicalInput(model.newRelayURL))
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("relayUrlHint"), text: $model.newRelayURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .focused($urlFocused)
                        .submitLabel(.done)
                        .onSubmit { Task { await model.add() } }
                        .accessibilityIdentifier("relays-add-field")
                } footer: {
                    if !["", "wss://", "ws://"].contains(model.newRelayURL) && !isNewRelayValid {
                        Text(L("invalidRelayUrl")).foregroundStyle(AppColors.error)
                    }
                }
            }
            .navigationTitle(L("addRelay"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { model.showAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { Task { await model.add() } }
                        .disabled(!isNewRelayValid)
                        .accessibilityIdentifier("relays-add-confirm")
                }
            }
            .onAppear {
                if model.newRelayURL.isEmpty { model.newRelayURL = "wss://" }
                urlFocused = true
            }
        }
        .presentationDetents([.medium])
    }
}

struct SettingsRelayRow: View {
    let url: String
    let status: SettingsRelayStatus?
    let flags: SettingsRelayFlags

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(RelaySettingsModel.host(url))
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
                            .foregroundStyle(.secondary)
                    }
                    if !(flags.read && flags.write) {
                        Text(flags.read ? L("settingsRelayReadOnly") : L("settingsRelayWriteOnly"))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote.monospacedDigit())
                .labelStyle(SettingsCompactLabelStyle())
                .lineLimit(1)
            }
        } icon: {
            SettingsIcon(systemImage: "server.rack")
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(AppColors.surface, lineWidth: 2))
                        .offset(x: 3, y: 3)
                }
        }
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
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}
