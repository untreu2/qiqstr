import SwiftUI

struct ComposeScheduleSheet: View {
    @Binding var scheduledAt: Date?
    @State private var date = Date().addingTimeInterval(3600)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(L("feedScheduleDate"), selection: $date, in: Date().addingTimeInterval(120)...)
                        .datePickerStyle(.graphical)
                        .accessibilityIdentifier("compose-schedule-date")
                } footer: {
                    Text(L("feedScheduleFooter")).wrapsInFooter()
                }
                if scheduledAt != nil {
                    Section {
                        Button(L("feedScheduleRemove"), systemImage: "calendar.badge.minus", role: .destructive) {
                            scheduledAt = nil
                            dismiss()
                        }
                        .accessibilityIdentifier("compose-schedule-remove")
                    }
                }
            }
            .navigationTitle(L("feedSchedule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel"), systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("compose-schedule-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("done"), systemImage: "checkmark") {
                        scheduledAt = max(date, Date().addingTimeInterval(60))
                        dismiss()
                    }
                    .prominentButtonStyle()
                    .accessibilityIdentifier("compose-schedule-done")
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { if let scheduledAt { date = scheduledAt } }
    }
}
