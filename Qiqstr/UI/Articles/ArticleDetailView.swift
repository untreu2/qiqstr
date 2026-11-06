import SwiftUI

struct ArticleDetailView: View {
    var articleId: String? = nil
    var naddr: String? = nil
    init(articleId: String) { self.articleId = articleId }
    init(naddr: String) { self.naddr = naddr }
    var body: some View { Text("Article") }
}
