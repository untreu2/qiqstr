import SwiftUI

enum ReaderLineSpacing: String, CaseIterable, Identifiable {
    case compact, standard, relaxed

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .compact: 0.5
        case .standard: 1
        case .relaxed: 1.7
        }
    }

    var title: String {
        switch self {
        case .compact: L("readerSpacingCompact")
        case .standard: L("readerSpacingStandard")
        case .relaxed: L("readerSpacingRelaxed")
        }
    }
}

enum ReaderSettingsKey {
    static let textSize = "reader_text_size_offset"
    static let serif = "reader_serif"
    static let lineSpacing = "reader_line_spacing"
    static let sizeRange = -3...5
}

struct ReaderTypographyModifier: ViewModifier {
    @AppStorage(ReaderSettingsKey.textSize) private var offset = 0
    @AppStorage(ReaderSettingsKey.serif) private var serif = false
    @AppStorage(ReaderSettingsKey.lineSpacing) private var spacing = ReaderLineSpacing.standard.rawValue
    @Environment(\.dynamicTypeSize) private var base

    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(shifted)
            .fontDesign(serif ? .serif : .default)
            .environment(\.markdownLineSpacingScale, (ReaderLineSpacing(rawValue: spacing) ?? .standard).scale)
    }

    private var shifted: DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        let index = all.firstIndex(of: base) ?? all.firstIndex(of: .large) ?? 0
        return all[min(max(index + offset, 0), all.count - 1)]
    }
}

extension View {
    func readerTypography() -> some View { modifier(ReaderTypographyModifier()) }
}

struct ReaderSettingsPopover: View {
    @AppStorage(ReaderSettingsKey.textSize) private var offset = 0
    @AppStorage(ReaderSettingsKey.serif) private var serif = false
    @AppStorage(ReaderSettingsKey.lineSpacing) private var spacing = ReaderLineSpacing.standard.rawValue

    private var sizeBinding: Binding<Double> {
        Binding(get: { Double(offset) }, set: { offset = Int($0.rounded()) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("readerTextSize")).font(.subheadline).foregroundStyle(.secondary)
                Slider(value: sizeBinding, in: Double(ReaderSettingsKey.sizeRange.lowerBound)...Double(ReaderSettingsKey.sizeRange.upperBound), step: 1) {
                    Text(L("readerTextSize"))
                } minimumValueLabel: {
                    Image(systemName: "textformat.size.smaller").accessibilityHidden(true)
                } maximumValueLabel: {
                    Image(systemName: "textformat.size.larger").accessibilityHidden(true)
                }
                .accessibilityIdentifier("reader-text-size")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("readerFont")).font(.subheadline).foregroundStyle(.secondary)
                Picker(L("readerFont"), selection: $serif) {
                    Text(L("readerFontSans")).fontDesign(.default).tag(false)
                    Text(L("readerFontSerif")).fontDesign(.serif).tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("reader-font")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("readerLineSpacing")).font(.subheadline).foregroundStyle(.secondary)
                Picker(L("readerLineSpacing"), selection: $spacing) {
                    ForEach(ReaderLineSpacing.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("reader-line-spacing")
            }
            if offset != 0 || serif || spacing != ReaderLineSpacing.standard.rawValue {
                Button(L("readerReset")) {
                    offset = 0
                    serif = false
                    spacing = ReaderLineSpacing.standard.rawValue
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
                .accessibilityIdentifier("reader-reset")
            }
        }
        .padding(20)
        .frame(width: 320)
        .sensoryFeedback(.selection, trigger: offset)
        .sensoryFeedback(.selection, trigger: serif)
        .sensoryFeedback(.selection, trigger: spacing)
    }
}
