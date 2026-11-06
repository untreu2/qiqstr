import SwiftUI

struct NoteRowView: View {
    let note: Note
    var showsThreadContext = true
    var body: some View { Text(note.content) }
}
