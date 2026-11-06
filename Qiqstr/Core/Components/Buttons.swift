import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView() }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .foregroundStyle(AppColors.background)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .disabled(!isEnabled || isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading { ProgressView() } else if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.extraLarge)
        .disabled(isLoading)
    }
}

struct PillButton: View {
    let title: String
    var systemImage: String? = nil
    var filled = true
    let action: () -> Void

    var body: some View {
        if filled {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .foregroundStyle(AppColors.background)
                .buttonBorderShape(.capsule)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
    }

    private var label: some View {
        Group {
            if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
        }
        .font(.subheadline.weight(.semibold))
    }
}

struct GlassIconButton: View {
    let systemImage: String
    var size: CGFloat = 44
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct IconTile: View {
    let systemImage: String
    var size: CGFloat = 56
    var tint: Color = AppColors.textPrimary

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.38))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(AppColors.tile, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}
