import SwiftUI

enum NavigationBarItem {
    enum TitleDisplayMode { case automatic, inline, large }
}

enum TextInputAutocapitalization { case never, words, sentences, characters }

enum UIKeyboardType { case `default`, asciiCapable, numberPad, decimalPad, URL, emailAddress, phonePad, twitter, webSearch, numbersAndPunctuation }

extension View {
    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View { self }
    func textInputAutocapitalization(_ style: TextInputAutocapitalization?) -> some View { self }
    func keyboardType(_ type: UIKeyboardType) -> some View { self }
    func statusBarHidden(_ hidden: Bool = true) -> some View { self }
    func listSectionSpacing(_ spacing: CGFloat) -> some View { self }
    func listSectionSpacing(_ spacing: MacListSectionSpacing) -> some View { self }

    func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) { content().frame(minWidth: 860, minHeight: 640) }
    }

    func fullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, onDismiss: onDismiss) { content($0).frame(minWidth: 860, minHeight: 640) }
    }
}

extension ListStyle where Self == InsetListStyle {
    static var insetGrouped: InsetListStyle { .inset }
}

extension ToolbarItemPlacement {
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var bottomBar: ToolbarItemPlacement { .automatic }
}

enum MacListSectionSpacing { case compact, `default` }

extension ToolbarPlacement {
    static var navigationBar: ToolbarPlacement { .windowToolbar }
    static var tabBar: ToolbarPlacement { .accessoryBar(id: "ios-tab-bar") }
}

extension ContentShapeKinds {
    static var contextMenuPreview: ContentShapeKinds { .interaction }
}

enum MacSearchDrawerMode { case always, automatic }

extension SearchFieldPlacement {
    static func navigationBarDrawer(displayMode: MacSearchDrawerMode) -> SearchFieldPlacement { .toolbar }
}

extension PickerStyle where Self == MenuPickerStyle {
    static var navigationLink: MenuPickerStyle { .menu }
}

struct Form<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        SwiftUI.Form { content }.formStyle(.grouped)
    }
}
