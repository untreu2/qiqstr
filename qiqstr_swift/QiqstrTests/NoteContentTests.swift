import QiqstrCore
import SwiftUI
import XCTest
@testable import qiqstr

final class NoteContentTests: XCTestCase {
    func testLinksEndingInNonLatinCharactersAreParsed() {
        let links = [
            "https://ja.wikipedia.org/wiki/日本",
            "https://example.com/abcを見て",
            "https://ru.wikipedia.org/wiki/Биткойн",
            "https://example.com/cafés",
            "https://example.com/😀",
        ]
        for link in links {
            let parsed = NoteRepository.parse("見て \(link)")
            XCTAssertEqual(parsed.linkUrls, [link])
            XCTAssertEqual(parsed.mediaUrls, [])
            XCTAssertEqual(parsed.parts, [.text("見て \(link)")])
        }
        let media = NoteRepository.parse("https://example.com/日本.PNG?size=large")
        XCTAssertEqual(media.mediaUrls, ["https://example.com/日本.PNG?size=large"])
        let content = NoteContent(content: "見て https://ja.wikipedia.org/wiki/日本", tags: [])
        XCTAssertEqual(content.linkUrls, ["https://ja.wikipedia.org/wiki/日本"])
    }

    @MainActor
    func testMentionsKeepTheFontTheyWereRenderedWith() throws {
        let npub = try nip19EncodePubkey(pubkeyHex: generateKeypair().publicKey)
        let content = NoteContent(content: "hello nostr:\(npub) again", tags: [])
        XCTAssertEqual(content.mentionPubkeys.count, 1)
        let fonts: [Font] = [.body, .subheadline, .title3, .body, .footnote, .subheadline]
        for font in fonts {
            let text = content.attributed(content.segments, font: font, cache: ProfileCache.shared)
            let mention = text.runs.first { $0.link != nil }
            XCTAssertNotNil(mention)
            XCTAssertEqual(mention?[AttributeScopes.SwiftUIAttributes.FontAttribute.self], font.weight(.medium))
        }
    }

    func testAForgedNewerCandidateIsNeverPickedAsAnEditBase() throws {
        let me = generateKeypair()
        let follow = generateKeypair().publicKey
        let attacker = generateKeypair().publicKey
        let realJson = try createSignedEvent(kind: 3, content: "", tags: [["p", follow]], privateKeyHex: me.privateKey)
        let real = try XCTUnwrap(JSON.object(realJson))

        var forged = real
        forged["created_at"] = real.int("created_at") + 10_000
        forged["tags"] = [["p", attacker]]

        var unsigned = real
        unsigned["created_at"] = real.int("created_at") + 20_000
        unsigned["sig"] = String(repeating: "0", count: 128)

        let picked = try XCTUnwrap(SyncService.newestVerified([forged, real, unsigned]))
        XCTAssertEqual(picked.int("created_at"), real.int("created_at"))
        XCTAssertEqual(picked.tags(), [["p", follow]])
        XCTAssertNil(SyncService.newestVerified([forged, unsigned]))
        XCTAssertNil(SyncService.newestVerified([]))
    }
}
