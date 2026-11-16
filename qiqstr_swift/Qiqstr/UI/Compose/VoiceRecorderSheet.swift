import SwiftUI

struct VoiceRecorderSheet: View {
    let onFinish: (VoiceRecording) -> Void
    @State private var recorder = VoiceRecorder()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                switch recorder.state {
                case .denied:
                    EmptyStateView(systemImage: "mic.slash", title: L("voiceMicDenied"), message: L("voiceMicDeniedMessage"), actionTitle: L("openSettings")) {
                        SystemSettings.open()
                    }
                case .failed:
                    EmptyStateView(systemImage: "exclamationmark.triangle", title: L("voiceRecordFailed"), actionTitle: L("retryText")) {
                        Task { await recorder.start() }
                    }
                case .finished(let recording):
                    Text(VoiceRecorder.format(recording.duration))
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                    AudioPlayerView(url: recording.url.path, duration: recording.duration, waveform: recording.waveform)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppColors.inputFill, in: .rect(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 20)
                case .idle, .recording:
                    Text(VoiceRecorder.format(recorder.elapsed))
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("voice-elapsed")
                    WaveformBars(levels: Array(recorder.levels.suffix(60)).map { Int($0 * 100) }, progress: 1, tint: AppColors.reaction)
                        .frame(height: 56)
                        .padding(.horizontal, 28)
                        .opacity(recorder.isRecording ? 1 : 0.3)
                }
                Spacer(minLength: 0)
                controls
            }
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(AppColors.background)
            .navigationTitle(L("voiceTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel"), systemImage: "xmark") { close() }
                        .accessibilityIdentifier("voice-cancel")
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(recorder.isRecording)
        .task { await recorder.start() }
        .onDisappear {
            AudioPlayback.shared.stop()
            if recorder.isRecording { recorder.cancel() }
        }
        .sensoryFeedback(.impact, trigger: recorder.isRecording)
        .accessibilityIdentifier("voice-recorder")
    }

    @ViewBuilder
    private var controls: some View {
        switch recorder.state {
        case .recording:
            Button { recorder.stop() } label: {
                Label(L("voiceStop"), systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .padding(.horizontal, 20)
            .accessibilityIdentifier("voice-stop")
        case .finished(let recording):
            HStack(spacing: 12) {
                Button {
                    AudioPlayback.shared.stop()
                    recorder.cancel()
                    Task { await recorder.start() }
                } label: {
                    Label(L("voiceRecordAgain"), systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .secondaryGlassStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .accessibilityIdentifier("voice-redo")
                Button {
                    AudioPlayback.shared.stop()
                    onFinish(recording)
                    dismiss()
                } label: {
                    Label(L("voiceAttach"), systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .prominentButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .accessibilityIdentifier("voice-attach")
            }
            .padding(.horizontal, 20)
        case .idle, .denied, .failed:
            EmptyView()
        }
    }

    private func close() {
        AudioPlayback.shared.stop()
        recorder.cancel()
        dismiss()
    }
}

enum SystemSettings {
    static func open() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
        #endif
    }
}
