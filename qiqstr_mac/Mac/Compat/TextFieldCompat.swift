import SwiftUI

// The shared screens expect iOS text fields: no border (they draw their own
// backgrounds) and the title as the placeholder. On macOS fields have a bezel,
// and in a grouped Form the title becomes a label with no placeholder. These
// shadow SwiftUI's fields, use the plain style, hide the label and pass the
// title as the prompt.
struct TextField: View {
    private let title: String
    private let text: Binding<String>
    private let axis: Axis?

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self.text = text
        axis = nil
    }

    init(_ title: String, text: Binding<String>, axis: Axis) {
        self.title = title
        self.text = text
        self.axis = axis
    }

    var body: some View {
        Group {
            if let axis {
                SwiftUI.TextField(title, text: text, prompt: Text(title), axis: axis)
            } else {
                SwiftUI.TextField(title, text: text, prompt: Text(title))
            }
        }
        .textFieldStyle(.plain)
        .labelsHidden()
    }
}

struct SecureField: View {
    private let title: String
    private let text: Binding<String>

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self.text = text
    }

    var body: some View {
        SwiftUI.SecureField(title, text: text, prompt: Text(title))
            .textFieldStyle(.plain)
            .labelsHidden()
    }
}
