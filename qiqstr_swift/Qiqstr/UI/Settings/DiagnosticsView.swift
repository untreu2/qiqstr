import SwiftUI

struct DiagnosticsView: View {
    @State private var store = DiagnosticsStore.shared
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                if store.reports.isEmpty {
                    EmptyStateView(systemImage: "checkmark.seal", title: L("diagnosticsEmpty"), message: L("diagnosticsEmptyMessage"))
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("diagnostics-empty")
                }
                ForEach(store.reports) { report in
                    ShareLink(item: report.file) {
                        LabeledContent {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(title(report))
                            Text(report.receivedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .swipeActions {
                        Button(L("delete"), role: .destructive) { store.delete(report) }
                    }
                    .accessibilityIdentifier("diagnostics-report")
                }
            } footer: {
                Text(L("diagnosticsFooter"))
            }
        }
        .settingsListStyle()
        .navigationTitle(L("diagnosticsTitle"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !store.reports.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("diagnosticsDeleteAll"), systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("diagnostics-delete-all")
                }
            }
        }
        .confirmationDialog(L("diagnosticsDeleteAll"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("diagnosticsDeleteAll"), role: .destructive) { store.deleteAll() }
            Button(L("cancel"), role: .cancel) {}
        }
        .onAppear { store.reload() }
        .accessibilityIdentifier("diagnostics-list")
    }

    private func title(_ report: DiagnosticReport) -> String {
        guard report.kind == .diagnostics else { return L("diagnosticsPerformance") }
        var parts: [String] = []
        if report.crashes > 0 { parts.append(L("diagnosticsCrashes", ["count": report.crashes])) }
        if report.hangs > 0 { parts.append(L("diagnosticsHangs", ["count": report.hangs])) }
        if report.other > 0 || parts.isEmpty { parts.append(L("diagnosticsOther")) }
        return parts.joined(separator: ", ")
    }
}
