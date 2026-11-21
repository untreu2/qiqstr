use std::time::{Duration, Instant};

use futures::{SinkExt, StreamExt};
use nostr_sdk::prelude::*;
use qiqstr::api::{database, relay};
use tokio::net::TcpListener;
use tokio_tungstenite::{accept_async, tungstenite::Message};

fn stats_ms(samples: &[f64]) -> (f64, f64, f64) {
    let mut sorted = samples.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mean = sorted.iter().sum::<f64>() / sorted.len() as f64;
    let median = sorted[sorted.len() / 2];
    let min = sorted[0];
    (median, mean, min)
}

async fn spawn_mock_relay(delay_ms: u64, events: Vec<Event>, hang: bool) -> String {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("ws://{}", listener.local_addr().unwrap());
    tokio::spawn(async move {
        while let Ok((stream, _)) = listener.accept().await {
            let events = events.clone();
            tokio::spawn(async move {
                if hang {
                    // Accept TCP but stall before completing WebSocket or never answer REQ
                    tokio::time::sleep(Duration::from_secs(30)).await;
                    return;
                }
                let Ok(mut socket) = accept_async(stream).await else {
                    return;
                };
                while let Some(Ok(frame)) = socket.next().await {
                    let Message::Text(text) = frame else {
                        continue;
                    };
                    let Ok(msg) = serde_json::from_str::<serde_json::Value>(&text) else {
                        continue;
                    };
                    if msg[0] == "REQ" {
                        let sub = msg[1].as_str().unwrap_or("s").to_string();
                        if delay_ms > 0 {
                            tokio::time::sleep(Duration::from_millis(delay_ms)).await;
                        }
                        let filter = msg
                            .get(2)
                            .and_then(|v| Filter::from_json(v.to_string()).ok());
                        let mut sent = 0usize;
                        let limit = filter.as_ref().and_then(|f| f.limit).unwrap_or(usize::MAX);
                        for ev in &events {
                            if sent >= limit {
                                break;
                            }
                            if let Some(ref f) = filter {
                                if !f.match_event(ev, MatchEventOptions::new()) {
                                    continue;
                                }
                            }
                            let frame = serde_json::json!([
                                "EVENT",
                                &sub,
                                serde_json::from_str::<serde_json::Value>(&ev.as_json()).unwrap()
                            ])
                            .to_string();
                            if socket.send(Message::Text(frame)).await.is_err() {
                                return;
                            }
                            sent += 1;
                        }
                        let eose = serde_json::json!(["EOSE", &sub]).to_string();
                        let _ = socket.send(Message::Text(eose)).await;
                    }
                }
            });
        }
    });
    url
}

fn make_zap_receipt(
    zapper_keys: &Keys,
    sender_keys: &Keys,
    recipient: PublicKey,
    target_note: EventId,
    sats: u64,
    ts: u64,
) -> Event {
    let msats = sats * 1000;
    let zap_req = EventBuilder::new(Kind::ZapRequest, "great post!")
        .tags([
            Tag::public_key(recipient),
            Tag::event(target_note),
            Tag::custom(TagKind::Custom("amount".into()), vec![msats.to_string()]),
        ])
        .custom_created_at(Timestamp::from(ts))
        .sign_with_keys(sender_keys)
        .unwrap();
    // Valid bolt11 hrp encoding: lnbc<sats*10>n1... (1n = 0.000000001 BTC = 0.1 sat -> 10n = 1 sat)
    // Simpler: lnbc<sats>0n1qqqq -> sats*10 * 100 msats / 1000 = sats
    let bolt11 = format!("lnbc{}0n1p0testinvoice", sats);
    EventBuilder::new(Kind::ZapReceipt, "")
        .tags([
            Tag::public_key(recipient),
            Tag::event(target_note),
            Tag::custom(TagKind::Description, vec![zap_req.as_json()]),
            Tag::custom(TagKind::Bolt11, vec![bolt11]),
        ])
        .custom_created_at(Timestamp::from(ts))
        .sign_with_keys(zapper_keys)
        .unwrap()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore]
async fn run_core_benchmarks() {
    let mut results = serde_json::Map::new();

    // -----------------------------------------------------------------------
    // 1. Setup synthetic dataset: 50 authors, 200 profiles, 200 notes,
    //    200 replies, 50 reposts, 200 reactions, 60 zap receipts, 100 follow lists
    // -----------------------------------------------------------------------
    let base_ts: u64 = 1_700_000_000;
    let me_keys = Keys::generate();
    let me_pk = me_keys.public_key();
    let me_hex = me_pk.to_hex();
    let zapper_keys = Keys::generate();

    let author_keys: Vec<Keys> = (0..60).map(|_| Keys::generate()).collect();
    let mut all_events: Vec<Event> = Vec::new();
    let mut note_events: Vec<Event> = Vec::new();

    // Contact list for `me` following all 60 authors
    let contact_tags: Vec<Tag> = author_keys
        .iter()
        .map(|k| Tag::public_key(k.public_key()))
        .collect();
    let my_contacts = EventBuilder::new(Kind::ContactList, "")
        .tags(contact_tags)
        .custom_created_at(Timestamp::from(base_ts))
        .sign_with_keys(&me_keys)
        .unwrap();
    all_events.push(my_contacts);

    // Contact lists for each author (for follow score benchmark)
    let target_pk = author_keys[0].public_key();
    for (i, ak) in author_keys.iter().enumerate() {
        let mut tags: Vec<Tag> = Vec::new();
        for j in 0..20 {
            tags.push(Tag::public_key(
                author_keys[(i + j + 1) % author_keys.len()].public_key(),
            ));
        }
        if i % 2 == 0 {
            tags.push(Tag::public_key(target_pk));
        }
        let cl = EventBuilder::new(Kind::ContactList, "")
            .tags(tags)
            .custom_created_at(Timestamp::from(base_ts + i as u64))
            .sign_with_keys(ak)
            .unwrap();
        all_events.push(cl);
    }

    // Profiles (100 metadata events)
    let mut profile_hexes: Vec<String> = Vec::new();
    for (i, ak) in author_keys.iter().enumerate() {
        let meta = Metadata::new()
            .name(format!("user_{i}"))
            .display_name(format!("User Display {i}"))
            .about(format!(
                "Nostr enthusiast #{i} building decentralized apps."
            ))
            .picture(Url::parse(&format!("https://cdn.example.com/avatar/{i}.jpg")).unwrap())
            .nip05(format!("user{i}@example.com"));
        let ev = EventBuilder::metadata(&meta)
            .custom_created_at(Timestamp::from(base_ts + i as u64))
            .sign_with_keys(ak)
            .unwrap();
        profile_hexes.push(ak.public_key().to_hex());
        all_events.push(ev);
    }

    // 200 root text notes (some with media URLs, hashtags, mentions, quotes)
    let sample_npub = author_keys[1].public_key().to_bech32().unwrap();
    for i in 0..200usize {
        let ak = &author_keys[i % author_keys.len()];
        let content = match i % 4 {
            0 => format!(
                "Check out this update #{i} on #nostr and #bitcoin! https://example.com/post/{i} https://cdn.example.com/img/{i}.jpg nostr:{sample_npub}"
            ),
            1 => format!(
                "Building fast native iOS clients with Rust and LMDB #{i}. Thoughts nostr:{sample_npub}? #ios #swift"
            ),
            2 => {
                if let Some(prev) = note_events.last() {
                    let nevent = prev.id.to_bech32().unwrap();
                    format!("Quoting this great note #{i}: nostr:{nevent} https://cdn.example.com/pic/{i}.png")
                } else {
                    format!("First note #{i} #nostr")
                }
            }
            _ => format!("Plain text note number {i} with some reasonable length content for benchmarking hydration and parsing."),
        };
        let mut tags = vec![Tag::hashtag("nostr")];
        if i % 4 == 2 {
            if let Some(prev) = note_events.last() {
                tags.push(Tag::custom(
                    TagKind::SingleLetter(SingleLetterTag::lowercase(Alphabet::Q)),
                    vec![prev.id.to_hex()],
                ));
            }
        }
        let ev = EventBuilder::text_note(content)
            .tags(tags)
            .custom_created_at(Timestamp::from(base_ts + 1000 + i as u64 * 10))
            .sign_with_keys(ak)
            .unwrap();
        note_events.push(ev.clone());
        all_events.push(ev);
    }

    // 250 replies (triggers filter_replies over-fetch 4x)
    for i in 0..250usize {
        let ak = &author_keys[i % author_keys.len()];
        let parent = &note_events[i % note_events.len()];
        let ev = EventBuilder::text_note(format!("Reply #{i} to note"))
            .tags([
                Tag::custom(
                    TagKind::SingleLetter(SingleLetterTag::lowercase(Alphabet::E)),
                    vec![parent.id.to_hex(), String::new(), "root".to_string()],
                ),
                Tag::public_key(me_pk),
            ])
            .custom_created_at(Timestamp::from(base_ts + 3000 + i as u64 * 5))
            .sign_with_keys(ak)
            .unwrap();
        all_events.push(ev);
    }

    // 40 reposts (20 with embedded JSON, 20 referencing by e-tag)
    for i in 0..40usize {
        let ak = &author_keys[(i + 5) % author_keys.len()];
        let orig = &note_events[i * 4];
        let content = if i % 2 == 0 {
            orig.as_json()
        } else {
            String::new()
        };
        let ev = EventBuilder::new(Kind::Repost, content)
            .tags([Tag::event(orig.id), Tag::public_key(orig.pubkey)])
            .custom_created_at(Timestamp::from(base_ts + 3500 + i as u64 * 10))
            .sign_with_keys(ak)
            .unwrap();
        all_events.push(ev);
    }

    // 300 reactions + 80 zap receipts on the latest 60 notes
    let recent_notes: Vec<Event> = note_events[140..200].to_vec();
    for i in 0..300usize {
        let ak = &author_keys[i % author_keys.len()];
        let target = &recent_notes[i % recent_notes.len()];
        let ev = EventBuilder::new(Kind::Reaction, "+")
            .tags([
                Tag::event(target.id),
                Tag::public_key(target.pubkey),
                Tag::public_key(me_pk),
            ])
            .custom_created_at(Timestamp::from(base_ts + 4000 + i as u64))
            .sign_with_keys(ak)
            .unwrap();
        all_events.push(ev);
    }
    for i in 0..80usize {
        let sender = &author_keys[i % author_keys.len()];
        let target = &recent_notes[i % recent_notes.len()];
        let zap = make_zap_receipt(
            &zapper_keys,
            sender,
            me_pk,
            target.id,
            (i as u64 + 1) * 21,
            base_ts + 4500 + i as u64,
        );
        all_events.push(zap);
    }

    // -----------------------------------------------------------------------
    // 2. Initialize LMDB + Mock Relays (3 fast relays 15/30/45ms + 1 hung relay!)
    // -----------------------------------------------------------------------
    let db_dir = std::env::temp_dir().join(format!("qiqstr-bench-{}", rand::random::<u64>()));
    std::fs::create_dir_all(&db_dir).unwrap();

    let relay_events = note_events[150..200].to_vec();
    let r1 = spawn_mock_relay(15, relay_events.clone(), false).await;
    let r2 = spawn_mock_relay(30, relay_events.clone(), false).await;
    let r3 = spawn_mock_relay(45, relay_events.clone(), false).await;
    let r_hang = spawn_mock_relay(0, vec![], true).await;

    let t0 = Instant::now();
    relay::init_client(
        vec![r1.clone(), r2.clone(), r3.clone(), r_hang.clone()],
        Some(me_keys.secret_key().to_secret_hex()),
        Some(db_dir.to_string_lossy().to_string()),
        vec![],
    )
    .await
    .unwrap();
    let init_ms = t0.elapsed().as_secs_f64() * 1000.0;
    results.insert("init_client_ms".into(), serde_json::json!(init_ms));

    // Benchmark connect + wait_for_ready with 1 hung relay out of 4
    let t0 = Instant::now();
    relay::connect_relays().await.unwrap();
    let ready_count = relay::wait_for_ready(3).await.unwrap();
    let wait_ready_ms = t0.elapsed().as_secs_f64() * 1000.0;
    results.insert(
        "mock_wait_for_ready_with_1_hung_ms".into(),
        serde_json::json!(wait_ready_ms),
    );
    results.insert(
        "mock_wait_for_ready_connected".into(),
        serde_json::json!(ready_count),
    );

    // Give fast relays a tiny moment so all 3 fast ones are connected
    tokio::time::sleep(Duration::from_millis(120)).await;

    // -----------------------------------------------------------------------
    // 3. Benchmark mock relay fetches (with 1 hung relay in pool)
    // -----------------------------------------------------------------------
    let target_id_hex = relay_events[0].id.to_hex();
    let mut single_samples = Vec::new();
    for _ in 0..5 {
        let t = Instant::now();
        let ev = relay::fetch_event_by_id(target_id_hex.clone(), 4)
            .await
            .unwrap();
        assert!(ev.is_some());
        single_samples.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    results.insert(
        "mock_fetch_event_by_id_ms".into(),
        serde_json::json!(stats_ms(&single_samples).0),
    );

    let feed_filter_json = serde_json::json!({"kinds": [1], "limit": 50}).to_string();
    let mut feed_fetch_samples = Vec::new();
    for _ in 0..5 {
        let t = Instant::now();
        let raw = relay::fetch_events(feed_filter_json.clone(), 4)
            .await
            .unwrap();
        assert!(raw.len() > 100);
        feed_fetch_samples.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    results.insert(
        "mock_fetch_events_feed_ms".into(),
        serde_json::json!(stats_ms(&feed_fetch_samples).0),
    );

    let multi_filters_json = serde_json::json!([
        {"kinds": [1], "limit": 20},
        {"kinds": [1], "ids": [relay_events[0].id.to_hex(), relay_events[1].id.to_hex()]},
    ])
    .to_string();
    let mut multi_samples = Vec::new();
    for _ in 0..4 {
        let t = Instant::now();
        let _ = relay::fetch_events_multi_filter(multi_filters_json.clone(), 4)
            .await
            .unwrap();
        multi_samples.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    results.insert(
        "mock_fetch_multi_filter_ms".into(),
        serde_json::json!(stats_ms(&multi_samples).0),
    );

    // -----------------------------------------------------------------------
    // 4. Benchmark db_save_events (fresh 200 events + duplicate 200 events)
    // -----------------------------------------------------------------------
    let save_batch_json = format!(
        "[{}]",
        note_events
            .iter()
            .map(|e| e.as_json())
            .collect::<Vec<_>>()
            .join(",")
    );
    let t0 = Instant::now();
    let saved = database::db_save_events(save_batch_json.clone())
        .await
        .unwrap();
    let save_fresh_ms = t0.elapsed().as_secs_f64() * 1000.0;
    results.insert(
        "db_save_200_fresh_ms".into(),
        serde_json::json!(save_fresh_ms),
    );
    results.insert("db_save_200_fresh_count".into(), serde_json::json!(saved));

    let t0 = Instant::now();
    let saved_dup = database::db_save_events(save_batch_json).await.unwrap();
    let save_dup_ms = t0.elapsed().as_secs_f64() * 1000.0;
    results.insert("db_save_200_dup_ms".into(), serde_json::json!(save_dup_ms));
    assert_eq!(saved_dup, 0);

    // Save the rest of the dataset into LMDB
    let rest_json = format!(
        "[{}]",
        all_events
            .iter()
            .map(|e| e.as_json())
            .collect::<Vec<_>>()
            .join(",")
    );
    let _ = database::db_save_events(rest_json).await.unwrap();

    // Configure realistic mute list (50 muted pubkeys, 15 muted words)
    let muted_pks: Vec<String> = (0..50)
        .map(|_| Keys::generate().public_key().to_hex())
        .collect();
    let muted_words: Vec<String> = (0..15).map(|i| format!("spamword{i}")).collect();
    database::set_active_mute_list(muted_pks.clone(), muted_words.clone());

    // -----------------------------------------------------------------------
    // 5. Benchmark LMDB queries & Hydration
    // -----------------------------------------------------------------------
    let mut feed_latest_samples = Vec::new();
    for _ in 0..10 {
        let t = Instant::now();
        let out = database::db_get_hydrated_feed_notes_sorted(
            me_hex.clone(),
            None,
            50,
            true,
            Some(me_hex.clone()),
            "latest".to_string(),
        )
        .await
        .unwrap();
        assert!(out.len() > 1000);
        feed_latest_samples.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    results.insert(
        "db_hydrated_feed_latest_50_ms".into(),
        serde_json::json!(stats_ms(&feed_latest_samples).0),
    );

    let mut feed_interacted_samples = Vec::new();
    for _ in 0..10 {
        let t = Instant::now();
        let out = database::db_get_hydrated_feed_notes_sorted(
            me_hex.clone(),
            None,
            50,
            true,
            Some(me_hex.clone()),
            "most_interacted".to_string(),
        )
        .await
        .unwrap();
        assert!(out.len() > 1000);
        feed_interacted_samples.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    results.insert(
        "db_hydrated_feed_interacted_50_ms".into(),
        serde_json::json!(stats_ms(&feed_interacted_samples).0),
    );

    let recent_ids: Vec<String> = recent_notes.iter().map(|e| e.id.to_hex()).collect();
    let mut batch_int_samples = Vec::new();
    for _ in 0..10 {
        let t = Instant::now();
        let out = database::db_get_batch_interaction_data(recent_ids.clone(), me_hex.clone())
            .await
            .unwrap();
        assert!(out.len() > 100);
        batch_int_samples.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    results.insert(
        "db_batch_interaction_data_60_ms".into(),
        serde_json::json!(stats_ms(&batch_int_samples).0),
    );

    let mut notif_samples = Vec::new();
    for _ in 0..10 {
        let t = Instant::now();
        let out = database::db_get_hydrated_notifications(
            me_hex.clone(),
            100,
            muted_pks.clone(),
            muted_words.clone(),
        )
        .await
        .unwrap();
        assert!(out.len() > 100);
        notif_samples.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    results.insert(
        "db_hydrated_notifications_100_ms".into(),
        serde_json::json!(stats_ms(&notif_samples).0),
    );

    let mut profiles_samples = Vec::new();
    for _ in 0..20 {
        let t = Instant::now();
        let out = database::db_get_profiles(profile_hexes.clone())
            .await
            .unwrap();
        assert!(out.len() > 100);
        profiles_samples.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    results.insert(
        "db_get_profiles_60_ms".into(),
        serde_json::json!(stats_ms(&profiles_samples).0),
    );

    let mut follow_score_samples = Vec::new();
    for _ in 0..10 {
        let t = Instant::now();
        let out = database::db_calculate_follow_score(me_hex.clone(), target_pk.to_hex())
            .await
            .unwrap();
        assert!(out.contains("\"count\":"));
        follow_score_samples.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    results.insert(
        "db_calculate_follow_score_60_ms".into(),
        serde_json::json!(stats_ms(&follow_score_samples).0),
    );

    let mut stats_samples = Vec::new();
    for _ in 0..10 {
        let t = Instant::now();
        let _ = database::db_get_database_stats().await.unwrap();
        stats_samples.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    results.insert(
        "db_get_database_stats_ms".into(),
        serde_json::json!(stats_ms(&stats_samples).0),
    );

    // -----------------------------------------------------------------------
    // 6. Pure CPU benchmarks: parse_note_content + is_event_new_and_track
    // -----------------------------------------------------------------------
    let sample_contents: Vec<String> = note_events.iter().map(|e| e.content.clone()).collect();
    let mut parse_samples = Vec::new();
    for _ in 0..10 {
        let t = Instant::now();
        for c in &sample_contents {
            let _ = database::parse_note_content(c.clone());
        }
        parse_samples.push(t.elapsed().as_secs_f64() * 1000.0);
    }
    results.insert(
        "parse_note_content_200_ms".into(),
        serde_json::json!(stats_ms(&parse_samples).0),
    );

    let fake_ids: Vec<String> = (0..5000).map(|i| format!("{:064x}", i)).collect();
    let t0 = Instant::now();
    for id in &fake_ids {
        let _ = database::is_event_new_and_track(id.clone());
    }
    for id in &fake_ids[3000..5000] {
        let _ = database::is_event_new_and_track(id.clone());
    }
    let track_ms = t0.elapsed().as_secs_f64() * 1000.0;
    results.insert(
        "is_event_new_and_track_7000_ms".into(),
        serde_json::json!(track_ms),
    );

    // -----------------------------------------------------------------------
    // 7. Live Nostr Relays Benchmark (real default iOS relays)
    // -----------------------------------------------------------------------
    let _ = relay::shutdown_client().await;
    let live_dir = std::env::temp_dir().join(format!("qiqstr-live-{}", rand::random::<u64>()));
    std::fs::create_dir_all(&live_dir).unwrap();
    let live_relays = vec![
        "wss://relay.damus.io".to_string(),
        "wss://nos.lol".to_string(),
        "wss://relay.primal.net".to_string(),
        "wss://vitor.nostr1.com".to_string(),
    ];
    let t0 = Instant::now();
    relay::init_client(
        live_relays,
        Some(me_keys.secret_key().to_secret_hex()),
        Some(live_dir.to_string_lossy().to_string()),
        vec![],
    )
    .await
    .unwrap();
    relay::connect_relays().await.unwrap();
    let live_connected = relay::wait_for_ready(5).await.unwrap();
    let live_ready_ms = t0.elapsed().as_secs_f64() * 1000.0;
    results.insert(
        "live_connect_and_ready_ms".into(),
        serde_json::json!(live_ready_ms),
    );
    results.insert(
        "live_connected_count".into(),
        serde_json::json!(live_connected),
    );

    if live_connected > 0 {
        let t0 = Instant::now();
        let live_feed = relay::fetch_events(
            serde_json::json!({"kinds": [1], "limit": 50}).to_string(),
            8,
        )
        .await
        .unwrap();
        let live_feed_ms = t0.elapsed().as_secs_f64() * 1000.0;
        let parsed_live: Vec<serde_json::Value> =
            serde_json::from_str(&live_feed).unwrap_or_default();
        results.insert(
            "live_fetch_feed_50_ms".into(),
            serde_json::json!(live_feed_ms),
        );
        results.insert(
            "live_fetch_feed_count".into(),
            serde_json::json!(parsed_live.len()),
        );

        if let Some(first_id) = parsed_live.first().and_then(|v| v["id"].as_str()) {
            let t0 = Instant::now();
            let _ = relay::fetch_event_by_id(first_id.to_string(), 6).await;
            results.insert(
                "live_fetch_event_by_id_ms".into(),
                serde_json::json!(t0.elapsed().as_secs_f64() * 1000.0),
            );
        }

        let live_ids: Vec<String> = parsed_live
            .iter()
            .take(20)
            .filter_map(|v| v["id"].as_str().map(String::from))
            .collect();
        if !live_ids.is_empty() {
            let t0 = Instant::now();
            let _ = relay::fetch_counts_from_relays(live_ids.clone(), None).await;
            results.insert(
                "live_fetch_counts_cold_ms".into(),
                serde_json::json!(t0.elapsed().as_secs_f64() * 1000.0),
            );
            let t0 = Instant::now();
            let _ = relay::fetch_counts_from_relays(live_ids, None).await;
            results.insert(
                "live_fetch_counts_warm_ms".into(),
                serde_json::json!(t0.elapsed().as_secs_f64() * 1000.0),
            );
        }

        let live_pks: Vec<String> = parsed_live
            .iter()
            .take(10)
            .filter_map(|v| v["pubkey"].as_str().map(String::from))
            .collect();
        if !live_pks.is_empty() {
            let t0 = Instant::now();
            let _ = relay::fetch_follower_counts(live_pks.clone()).await;
            results.insert(
                "live_primal_follower_counts_1_ms".into(),
                serde_json::json!(t0.elapsed().as_secs_f64() * 1000.0),
            );
            let t0 = Instant::now();
            let _ = relay::fetch_follower_counts(live_pks).await;
            results.insert(
                "live_primal_follower_counts_2_ms".into(),
                serde_json::json!(t0.elapsed().as_secs_f64() * 1000.0),
            );
        }
    }

    let _ = relay::shutdown_client().await;
    let _ = std::fs::remove_dir_all(&db_dir);
    let _ = std::fs::remove_dir_all(&live_dir);

    println!("BENCH_JSON:{}", serde_json::Value::Object(results));
}
