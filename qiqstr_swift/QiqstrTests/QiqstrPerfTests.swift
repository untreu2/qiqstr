import Foundation
import QiqstrCore
import SwiftUI
import UIKit
import XCTest
@testable import qiqstr

final class QiqstrPerfTests: XCTestCase {
    private static func median(_ samples: [Double]) -> Double {
        let s = samples.sorted()
        return s.isEmpty ? 0 : s[s.count / 2]
    }

    private static func ms(_ work: () -> Void) -> Double {
        let t0 = ContinuousClock.now
        work()
        let d = t0.duration(to: .now)
        return Double(d.components.seconds) * 1000.0 + Double(d.components.attoseconds) / 1e15
    }

    private static func msAsync(_ work: () async -> Void) async -> Double {
        let t0 = ContinuousClock.now
        await work()
        let d = t0.duration(to: .now)
        return Double(d.components.seconds) * 1000.0 + Double(d.components.attoseconds) / 1e15
    }

    @MainActor
    func testIOSCoreAndSwiftBenchmarks() async throws {
        var metrics: [String: Double] = [:]

        // 1. Generate realistic hydrated notes JSON (200 notes with URLs, media, hashtags, mentions, quotes)
        let keypairs = (0..<40).map { _ in generateKeypair() }
        let sampleNpub = (try? nip19EncodePubkey(pubkeyHex: keypairs[1].publicKey)) ?? "npub1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq92l2j3"
        let fakeEventId = String(repeating: "a1", count: 32)
        let sampleNevent = (try? nip19EncodeNevent(eventIdHex: fakeEventId, authorHex: keypairs[2].publicKey)) ?? ""

        var noteObjects: [JSONObject] = []
        for i in 0..<200 {
            let pk = keypairs[i % keypairs.count].publicKey
            let content: String
            switch i % 4 {
            case 0:
                content = "Shipping faster iOS performance #nostr #ios #swift! Read https://example.com/posts/\(i)?ref=feed and check https://cdn.example.com/media/\(i).jpg cc nostr:\(sampleNpub)"
            case 1:
                content = "Longer note body #\(i) discussing relay pooling, WebSocket multiplexing, LMDB hydration, and native SwiftUI scrolling performance. Mentioning nostr:\(sampleNpub) with #bitcoin #lightning and :fire: emoji!"
            case 2:
                content = "Quoting a great thread #\(i) nostr:\(sampleNevent) https://cdn.example.com/photo/\(i).png #dev"
            default:
                content = "Quick thought #\(i) on decentralized social networks and keeping mobile clients silky smooth at 120Hz."
            }
            let tags: [[String]] = [
                ["t", "nostr"],
                ["t", "ios"],
                ["emoji", "fire", "https://cdn.example.com/emoji/fire.png"],
                ["imeta", "url https://cdn.example.com/media/\(i).jpg", "m image/jpeg", "dim 1200x800"],
            ]
            let idHex = String(format: "%064x", i + 1)
            noteObjects.append([
                "id": idHex,
                "kind": 1,
                "pubkey": pk,
                "content": content,
                "created_at": 1_700_000_000 + i * 30,
                "tags": tags,
                "isRepost": false,
                "isReply": false,
                "isQuote": i % 4 == 2,
                "quotedNoteId": i % 4 == 2 ? fakeEventId : NSNull(),
                "authorName": "User \(i % 40)",
                "authorImage": "https://cdn.example.com/avatar/\(i % 40).jpg",
                "authorNip05": "user\(i % 40)@example.com",
                "reactionCount": i % 25,
                "repostCount": i % 7,
                "replyCount": i % 11,
                "zapCount": (i % 5) * 210,
                "hasReacted": i % 3 == 0,
                "hasReposted": false,
                "hasZapped": false,
            ])
        }
        let notesJson = JSON.string(noteObjects)

        // Benchmark 1: Note JSON parsing (200 hydrated notes)
        var jsonSamples: [Double] = []
        var parsedNotes: [Note] = []
        for _ in 0..<15 {
            jsonSamples.append(Self.ms {
                parsedNotes = Note.list(notesJson)
            })
        }
        XCTAssertEqual(parsedNotes.count, 200)
        metrics["swift_note_json_parse_200_ms"] = Self.median(jsonSamples)

        // Benchmark 2: NoteContent parsing (100 notes, uncached cold)
        let first100 = Array(parsedNotes.prefix(100))
        var contentSamples: [Double] = []
        var builtContents: [NoteContent] = []
        for _ in 0..<5 {
            contentSamples.append(Self.ms {
                builtContents = first100.map { NoteContent(content: $0.content, tags: $0.tags) }
            })
        }
        XCTAssertEqual(builtContents.count, 100)
        metrics["swift_note_content_parse_100_ms"] = Self.median(contentSamples)

        // Benchmark 3: NoteContent.attributed rendering (100 notes x 5 SwiftUI body re-renders)
        let cache = ProfileCache.shared
        var attrSamples: [Double] = []
        for _ in 0..<5 {
            attrSamples.append(Self.ms {
                for _ in 0..<5 {
                    for c in builtContents {
                        _ = c.attributed(c.truncatedSegments ?? c.segments, font: .body, cache: cache)
                    }
                }
            })
        }
        metrics["swift_attributed_render_500_ms"] = Self.median(attrSamples)

        // Benchmark 4: ExploreService.isSensitive screening on 200 notes
        var sensitiveSamples: [Double] = []
        for _ in 0..<15 {
            sensitiveSamples.append(Self.ms {
                _ = parsedNotes.filter { !ExploreService.isSensitive($0) }
            })
        }
        metrics["swift_explore_sensitive_200_ms"] = Self.median(sensitiveSamples)

        // Benchmark 5: ImagePipeline downsample (20 x 1024x1024 JPEG -> 132px avatar)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024))
        let syntheticImage = renderer.image { ctx in
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 200, y: 200, width: 624, height: 624))
        }
        let jpegData = syntheticImage.jpegData(compressionQuality: 0.85)!
        var imgSamples: [Double] = []
        for _ in 0..<5 {
            imgSamples.append(Self.ms {
                for _ in 0..<20 {
                    let img = ImagePipeline.downsample(jpegData, maxPixel: 132)
                    XCTAssertNotNil(img)
                }
            })
        }
        metrics["ios_image_downsample_20_ms"] = Self.median(imgSamples)

        // Benchmark 6: Live PrimalCache (3 sequential + 3 concurrent requests)
        let primalSeq1 = await Self.msAsync {
            _ = await PrimalCache.request("explore_topics", args: [:], timeout: 10)
        }
        let primalSeq2 = await Self.msAsync {
            _ = await PrimalCache.request("trending_hashtags_4h", args: [:], timeout: 10)
        }
        let primalSeq3 = await Self.msAsync {
            _ = await PrimalCache.request("explore_global_trending_24h", args: ["limit": 30], timeout: 10)
        }
        metrics["live_primal_req1_ms"] = primalSeq1
        metrics["live_primal_req2_ms"] = primalSeq2
        metrics["live_primal_req3_ms"] = primalSeq3
        metrics["live_primal_seq_3_total_ms"] = primalSeq1 + primalSeq2 + primalSeq3

        let primalConcurrent = await Self.msAsync {
            async let a = PrimalCache.request("explore_global_trending_24h", args: ["limit": 40], timeout: 10)
            async let b = PrimalCache.request("explore_global_mostzapped_4h", args: ["limit": 40], timeout: 10)
            async let c = PrimalCache.request("explore_topics", args: [:], timeout: 10)
            _ = await (a, b, c)
        }
        metrics["live_primal_concurrent_3_ms"] = primalConcurrent

        // Benchmark 7: iOS QiqstrCoreFFI LMDB + Live Relays end-to-end
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("qiqstr-ios-bench-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let me = keypairs[0]
        let connectMs = await Self.msAsync {
            try? await initClient(relayUrls: RelayConfig.defaultMainRelays, privateKeyHex: me.privateKey, dbPath: tmpDir.path, discoveryRelays: [])
            try? await connectRelays()
            _ = try? await waitForReady(timeoutSecs: 5)
        }
        metrics["ios_live_connect_ready_ms"] = connectMs

        let connected = (try? await getConnectedRelayCount()) ?? 0
        metrics["ios_live_connected_relays"] = Double(connected)

        if connected > 0 {
            var fetchedLive: [JSONObject] = []
            let fetchFeedMs = await Self.msAsync {
                fetchedLive = await SyncService.shared.fetchEvents(["kinds": [1], "limit": 50], timeout: 8)
            }
            metrics["ios_live_fetch_feed_50_ms"] = fetchFeedMs
            metrics["ios_live_fetch_feed_count"] = Double(fetchedLive.count)

            let ids = Array(fetchedLive.compactMap { $0.str("id") }.prefix(20))
            if let firstId = ids.first {
                let fetchOneMs = await Self.msAsync {
                    _ = try? await fetchEventById(eventId: firstId, timeoutSecs: 6)
                }
                metrics["ios_live_fetch_by_id_ms"] = fetchOneMs
            }
            if !ids.isEmpty {
                let countsColdMs = await Self.msAsync {
                    _ = try? await fetchCountsFromRelays(noteIds: ids, userPubkeyHex: me.publicKey)
                }
                let countsWarmMs = await Self.msAsync {
                    _ = try? await fetchCountsFromRelays(noteIds: ids, userPubkeyHex: me.publicKey)
                }
                metrics["ios_live_counts_cold_ms"] = countsColdMs
                metrics["ios_live_counts_warm_ms"] = countsWarmMs
            }

            // Benchmark dbSaveEvents + hydrated feed through UniFFI on iOS Simulator
            if !fetchedLive.isEmpty {
                let dupSaveMs = await Self.msAsync {
                    _ = try? await dbSaveEvents(eventsJson: JSON.string(fetchedLive))
                }
                metrics["ios_ffi_db_save_dup_ms"] = dupSaveMs

                let authors = Array(Set(fetchedLive.compactMap { $0.str("pubkey") }))
                var hydrateSamples: [Double] = []
                for _ in 0..<8 {
                    let h = await Self.msAsync {
                        let raw = try? await dbGetHydratedFeedNotesSorted(
                            userPubkeyHex: me.publicKey,
                            authorsHex: authors,
                            limit: 50,
                            filterReplies: true,
                            currentUserPubkeyHex: me.publicKey,
                            sortMode: "latest"
                        )
                        _ = await Note.parsed(raw)
                    }
                    hydrateSamples.append(h)
                }
                metrics["ios_ffi_hydrated_feed_50_ms"] = Self.median(hydrateSamples)
            }
        }

        try? await shutdownClient()

        let jsonOut = JSON.string(metrics)
        print("IOS_BENCH_JSON:\(jsonOut)")
    }
}
