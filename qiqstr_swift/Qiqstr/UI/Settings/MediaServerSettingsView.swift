import SwiftUI

struct MediaServerSettingsView: View {
    @State private var store = MediaServerStore.shared
    @State private var showAdd = false
    @State private var newServer = ""
    @State private var feedback = 0

    var body: some View {
        Form {
            Section {
                ForEach(store.options, id: \.self) { server in
                    Button { select(server) } label: {
                        HStack {
                            Label(MediaServerStore.displayName(server), systemImage: "server.rack")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if server == store.current {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(AppColors.textPrimary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(server == store.current ? .isSelected : [])
                    .accessibilityIdentifier("media-server-\(MediaServerStore.displayName(server))")
                    .swipeActions {
                        if store.servers.contains(server), server != store.current {
                            Button(L("delete"), systemImage: "trash", role: .destructive) { remove(server) }
                        }
                    }
                }
            } header: {
                Text(L("settingsMediaServerUpload"))
            } footer: {
                Text(L("settingsMediaServerFooter")).wrapsInFooter()
            }
            Section {
                Button(L("settingsMediaServerAdd"), systemImage: "plus") {
                    newServer = ""
                    showAdd = true
                }
                .accessibilityIdentifier("media-server-add")
            }
        }
        .settingsListStyle()
        .disabled(store.isSaving)
        .overlay { if store.isSaving { ProgressView().controlSize(.large) } }
        .navigationTitle(L("settingsMediaServer"))
        .navigationBarTitleDisplayMode(.large)
        .alert(L("settingsMediaServerAdd"), isPresented: $showAdd) {
            TextField("blossom.example.com", text: $newServer)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("media-server-field")
            Button(L("cancel"), role: .cancel) {}
            Button(L("settingsAdd")) { select(newServer) }
                .disabled(MediaServerStore.normalized(newServer) == nil)
        }
        .task { await store.load() }
        .sensoryFeedback(.success, trigger: feedback)
    }

    private func select(_ server: String) {
        guard ReadOnlyGate.check() else { return }
        Task {
            do {
                try await store.select(server)
                feedback += 1
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }

    private func remove(_ server: String) {
        Task {
            do { try await store.remove(server) } catch { ToastCenter.shared.error(error) }
        }
    }
}
