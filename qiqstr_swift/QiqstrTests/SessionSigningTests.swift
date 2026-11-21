import QiqstrCore
import XCTest
@testable import qiqstr

final class SessionSigningTests: XCTestCase {
    func testTheCoreSignsAndEncryptsForTheSignedInAccountOnly() async throws {
        let me = generateKeypair()
        let peer = generateKeypair()
        try await initClient(relayUrls: [], privateKeyHex: me.privateKey, dbPath: nil, discoveryRelays: [])
        addTeardownBlock { try? await shutdownClient() }

        XCTAssertTrue(sessionCanSign())
        XCTAssertEqual(try sessionPublicKey(), me.publicKey)
        let event = try XCTUnwrap(JSON.object(try signEvent(kind: 1, content: "hello", tags: [["t", "test"]])))
        XCTAssertEqual(event.str("pubkey"), me.publicKey)
        XCTAssertTrue(verifyEvent(eventJson: JSON.string(event)))
        let reaction = try XCTUnwrap(JSON.object(try signReactionEvent(targetEventId: String(repeating: "a", count: 64), targetAuthor: peer.publicKey, content: "+", relayUrl: "", targetKind: 1)))
        XCTAssertEqual(reaction.int("kind"), 7)
        XCTAssertTrue(verifyEvent(eventJson: JSON.string(reaction)))

        let sealed = try sessionNip44Encrypt(content: "private list", receiverPkHex: me.publicKey)
        XCTAssertEqual(try sessionNip44Decrypt(payload: sealed, senderPkHex: me.publicKey), "private list")
        let lock = try sessionNutzapLockSecret()
        XCTAssertEqual(lock, sha256Hash(data: Data("qiqstr-nutzap-p2pk:\(me.privateKey)".utf8)))

        try await initClient(relayUrls: [], privateKeyHex: nil, dbPath: nil, discoveryRelays: [])
        XCTAssertFalse(sessionCanSign())
        XCTAssertThrowsError(try signEvent(kind: 1, content: "read only", tags: []))

        try await initClient(relayUrls: [], privateKeyHex: peer.privateKey, dbPath: nil, discoveryRelays: [])
        XCTAssertEqual(try sessionPublicKey(), peer.publicKey)
        try await shutdownClient()
        XCTAssertFalse(sessionCanSign())
        XCTAssertThrowsError(try sessionNip44Encrypt(content: "x", receiverPkHex: me.publicKey))
    }
}
