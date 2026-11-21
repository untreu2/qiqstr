import QiqstrCore
import XCTest
@testable import qiqstr

final class ProfileCacheTests: XCTestCase {
    @MainActor
    func testLoadingProfilesWaitsUntilTheyAreAvailable() async throws {
        let me = generateKeypair()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("qiqstr-profile-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await initClient(relayUrls: [], privateKeyHex: me.privateKey, dbPath: directory.path, discoveryRelays: [])
        addTeardownBlock {
            try? await shutdownClient()
            try? FileManager.default.removeItem(at: directory)
        }
        try await dbSaveProfile(pubkeyHex: me.publicKey, profileJson: #"{"name":"first"}"#)

        let single = ProfileCache()
        XCTAssertNil(single.profile(me.publicKey))
        await single.load([me.publicKey], fetchMissing: false)
        XCTAssertEqual(single.profile(me.publicKey)?.bestName, "first")

        let unknown = generateKeypair().publicKey
        let several = ProfileCache()
        await several.load([me.publicKey, unknown], fetchMissing: false)
        XCTAssertEqual(several.profile(me.publicKey)?.bestName, "first")
        XCTAssertNil(several.profile(unknown))

        let concurrent = ProfileCache()
        async let first: Void = concurrent.load([me.publicKey], fetchMissing: false)
        async let second: Void = concurrent.load([me.publicKey], fetchMissing: false)
        _ = await (first, second)
        XCTAssertEqual(concurrent.profile(me.publicKey)?.bestName, "first")

        try await Task.sleep(for: .milliseconds(1_100))
        try await dbSaveProfile(pubkeyHex: me.publicKey, profileJson: #"{"name":"second"}"#)
        await single.load([me.publicKey], fetchMissing: false)
        XCTAssertEqual(single.profile(me.publicKey)?.bestName, "first")
        await single.reload([me.publicKey])
        XCTAssertEqual(single.profile(me.publicKey)?.bestName, "second")
    }
}
