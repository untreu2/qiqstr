import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).font(.system(size: 17, weight: .semibold)).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(AppColors.background) }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(AppColors.background)
            .background(AppColors.textPrimary, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.4)
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
                Text(title).font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(AppColors.textPrimary)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .disabled(isLoading)
    }
}

struct PillButton: View {
    let title: String
    var systemImage: String? = nil
    var filled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 14, weight: .semibold)) }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .frame(height: 38)
            .foregroundStyle(filled ? AppColors.background : AppColors.textPrimary)
            .background {
                if filled { Capsule().fill(AppColors.textPrimary) }
            }
            .glassEffect(filled ? .identity : .regular.interactive(), in: .capsule)
        }
        .buttonStyle(PressableStyle())
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
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
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
            .font(.system(size: size * 0.38, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(AppColors.tile, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}
