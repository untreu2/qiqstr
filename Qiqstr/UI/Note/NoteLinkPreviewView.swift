import SwiftUI

nonisolated struct NoteLinkMetadata: Hashable, Sendable {
    var url: String
    var title: String
    var summary: String?
    var image: String?
    var site: String
}

actor NoteLinkPreviewService {
    static let shared = NoteLinkPreviewService()
    private var cache: [String: NoteLinkMetadata] = [:]
    private var misses: Set<String> = []
    private var inflight: [String: Task<NoteLinkMetadata?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1", "Accept": "text/html"]
        return URLSession(configuration: config)
    }()

    func cached(_ url: String) -> NoteLinkMetadata? { cache[url] }

    func metadata(for url: String) async -> NoteLinkMetadata? {
        if let hit = cache[url] { return hit }
        if misses.contains(url) { return nil }
        if let task = inflight[url] { return await task.value }
        let task = Task<NoteLinkMetadata?, Never> { await fetch(url) }
        inflight[url] = task
        let result = await task.value
        inflight[url] = nil
        if let result { cache[url] = result } else { misses.insert(url) }
        return result
    }

    private func fetch(_ string: String) async -> NoteLinkMetadata? {
        guard let url = URL(string: string), url.scheme?.hasPrefix("http") == true else { return nil }
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        if let mime = (response as? HTTPURLResponse)?.mimeType, !mime.contains("html") { return nil }
        let html = String(decoding: data.prefix(400_000), as: UTF8.self)
        let meta = Self.metaTags(html)
        let title = meta["og:title"] ?? meta["twitter:title"] ?? Self.titleTag(html)
        guard let title, !title.isEmpty else { return nil }
        var image = meta["og:image"] ?? meta["og:image:url"] ?? meta["twitter:image"]
        if let raw = image, let resolved = URL(string: raw, relativeTo: url)?.absoluteString { image = resolved }
        let site = meta["og:site_name"] ?? url.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        return NoteLinkMetadata(url: string, title: Self.decode(title), summary: (meta["og:description"] ?? meta["description"] ?? meta["twitter:description"]).map(Self.decode), image: image, site: Self.decode(site))
    }

    nonisolated private static func metaTags(_ html: String) -> [String: String] {
        guard let tagRegex = try? NSRegularExpression(pattern: "<meta\\s[^>]*>", options: [.caseInsensitive]),
              let attrRegex = try? NSRegularExpression(pattern: "(property|name|content)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')", options: [.caseInsensitive]) else { return [:] }
        let ns = html as NSString
        var result: [String: String] = [:]
        for match in tagRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            let tns = tag as NSString
            var key: String?
            var content: String?
            for attr in attrRegex.matches(in: tag, range: NSRange(location: 0, length: tns.length)) {
                let name = tns.substring(with: attr.range(at: 1)).lowercased()
                let valueRange = attr.range(at: 3).location != NSNotFound ? attr.range(at: 3) : attr.range(at: 4)
                let value = valueRange.location != NSNotFound ? tns.substring(with: valueRange) : ""
                if name == "content" { content = value } else { key = value.lowercased() }
            }
            if let key, let content, !content.isEmpty, result[key] == nil { result[key] = content }
        }
        return result
    }

    nonisolated private static func titleTag(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>([^<]*)</title>", options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func decode(_ s: String) -> String {
        var out = s
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#x27;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (k, v) in entities { out = out.replacingOccurrences(of: k, with: v) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NoteLinkPreviewView: View {
    let url: String
    @State private var metadata: NoteLinkMetadata?
    @State private var loaded = false

    var body: some View {
        Group {
            if let metadata {
                Button {
                    if let u = URL(string: url) { Router.shared.sheet = .url(u) }
                } label: {
                    card(metadata)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("note-link-preview")
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .task(id: url) {
            if let hit = await NoteLinkPreviewService.shared.cached(url) { metadata = hit; return }
            metadata = await NoteLinkPreviewService.shared.metadata(for: url)
            loaded = true
        }
    }

    private func card(_ m: NoteLinkMetadata) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = m.image {
                Color.clear
                    .frame(height: 170)
                    .overlay {
                        RemoteImage(url: image, maxPixel: 900) { Rectangle().fill(AppColors.tile) }
                    }
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(m.site)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(m.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let summary = m.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColors.inputFill)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AppColors.border, lineWidth: 0.5))
    }
}
