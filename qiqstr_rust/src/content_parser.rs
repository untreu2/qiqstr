use std::collections::HashSet;

use nostr::prelude::*;

const MEDIA_EXTENSIONS: [&str; 7] = [".jpg", ".jpeg", ".png", ".webp", ".gif", ".mp4", ".mov"];

#[inline]
fn normalize_content_url(url: &str) -> &str {
    url.trim_end_matches(['.', ',', ';', ':', '!', '?', ')', ']', '}'])
}

#[inline]
fn is_media_url(url: &str) -> bool {
    let path = url.split(['?', '#']).next().unwrap_or(url).as_bytes();
    MEDIA_EXTENSIONS.iter().any(|ext| {
        let ext = ext.as_bytes();
        path.len() >= ext.len() && path[path.len() - ext.len()..].eq_ignore_ascii_case(ext)
    })
}

#[inline]
fn starts_with_ignore_ascii_case(haystack: &[u8], pos: usize, needle: &[u8]) -> bool {
    haystack.len() >= pos + needle.len()
        && haystack[pos..pos + needle.len()].eq_ignore_ascii_case(needle)
}

#[inline]
fn is_url_stop_byte(b: u8) -> bool {
    b.is_ascii_whitespace() || matches!(b, 0x0B | b'<' | b'>' | b'"' | b'\'')
}

#[inline]
fn is_bech32_body_byte(b: u8) -> bool {
    b.is_ascii_lowercase() || b.is_ascii_uppercase() || b.is_ascii_digit()
}

/// Scans `content` for `http://` or `https://` URLs (case-insensitive) until whitespace or `<>"'`.
fn find_url_spans(content: &str) -> Vec<(usize, usize)> {
    let bytes = content.as_bytes();
    let len = bytes.len();
    let mut spans = Vec::new();
    let mut i = 0;

    while i + 7 < len {
        // Fast skip to 'h' or 'H'
        if !matches!(bytes[i], b'h' | b'H') {
            i += 1;
            continue;
        }
        let scheme_len = if starts_with_ignore_ascii_case(bytes, i, b"https://") {
            8
        } else if starts_with_ignore_ascii_case(bytes, i, b"http://") {
            7
        } else {
            i += 1;
            continue;
        };

        let mut end = i + scheme_len;
        while end < len {
            let b = bytes[end];
            if b < 0x80 {
                if is_url_stop_byte(b) {
                    break;
                }
                end += 1;
            } else {
                // Non-ASCII UTF-8 char: check if it's Unicode whitespace
                let ch = content[end..].chars().next().unwrap();
                if ch.is_whitespace() {
                    break;
                }
                end += ch.len_utf8();
            }
        }

        if end > i + scheme_len {
            spans.push((i, end));
            i = end;
        } else {
            i += scheme_len;
        }
    }

    spans
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Bech32Kind {
    Quote,   // note1 | nevent1
    Article, // naddr1
    Mention, // npub1 | nprofile1
}

struct Bech32Match {
    full_start: usize,
    id_start: usize,
    end: usize,
    kind: Bech32Kind,
}

/// Scans `s` for `(?:nostr:)?(note1|nevent1|naddr1)[0-9a-zA-Z]+` or `nostr:(npub1|nprofile1)[0-9a-zA-Z]+`.
fn scan_bech32(s: &str, mentions_only: bool) -> Vec<Bech32Match> {
    let bytes = s.as_bytes();
    let len = bytes.len();
    let mut matches = Vec::new();
    let mut i = 0;

    while i < len {
        let b = bytes[i];
        if !matches!(b, b'n' | b'N') {
            i += 1;
            continue;
        }

        let has_nostr_prefix = starts_with_ignore_ascii_case(bytes, i, b"nostr:");
        let id_start = if has_nostr_prefix { i + 6 } else { i };

        if mentions_only && !has_nostr_prefix {
            i += 1;
            continue;
        }

        let (kind, prefix_len) = if mentions_only {
            if starts_with_ignore_ascii_case(bytes, id_start, b"nprofile1") {
                (Bech32Kind::Mention, 9)
            } else if starts_with_ignore_ascii_case(bytes, id_start, b"npub1") {
                (Bech32Kind::Mention, 5)
            } else {
                i += if has_nostr_prefix { 6 } else { 1 };
                continue;
            }
        } else if starts_with_ignore_ascii_case(bytes, id_start, b"nevent1") {
            (Bech32Kind::Quote, 7)
        } else if starts_with_ignore_ascii_case(bytes, id_start, b"note1") {
            (Bech32Kind::Quote, 5)
        } else if starts_with_ignore_ascii_case(bytes, id_start, b"naddr1") {
            (Bech32Kind::Article, 6)
        } else {
            i += if has_nostr_prefix { 6 } else { 1 };
            continue;
        };

        let mut end = id_start + prefix_len;
        while end < len && is_bech32_body_byte(bytes[end]) {
            end += 1;
        }

        // Must have at least 1 character after the `1` separator
        if end > id_start + prefix_len {
            matches.push(Bech32Match {
                full_start: i,
                id_start,
                end,
                kind,
            });
            i = end;
        } else {
            i = id_start + prefix_len;
        }
    }

    matches
}

#[inline]
fn inside_any_span(spans: &[(usize, usize)], start: usize, end: usize) -> bool {
    spans.iter().any(|(s, e)| start >= *s && end <= *e)
}

pub fn plain_text_content(content: &str) -> String {
    let text = content.trim();
    let text_parts: Vec<serde_json::Value> = if text.is_empty() {
        Vec::new()
    } else {
        vec![serde_json::json!({ "type": "text", "text": text })]
    };
    serde_json::json!({
        "textParts": text_parts,
        "mediaUrls": [],
        "linkUrls": [],
        "quoteIds": [],
        "articleIds": [],
    })
    .to_string()
}

pub fn parse_note_content_guarded(content: &str, parser: fn(&str) -> String) -> String {
    std::panic::catch_unwind(|| parser(content)).unwrap_or_else(|_| plain_text_content(content))
}

pub fn parse_note_content(content: &str) -> String {
    let mut seen_urls: HashSet<&str> = HashSet::new();
    let mut url_spans: Vec<(usize, usize)> = Vec::new();
    let mut media_urls: Vec<String> = Vec::new();
    let mut link_urls: Vec<String> = Vec::new();
    let mut remove_spans: Vec<(usize, usize)> = Vec::new();

    if content.contains("://") {
        url_spans = find_url_spans(content);
        for &(start, end) in &url_spans {
            let raw = &content[start..end];
            let normalized = normalize_content_url(raw);
            if !normalized.is_empty() && seen_urls.insert(normalized) {
                if is_media_url(normalized) {
                    media_urls.push(normalized.to_string());
                    remove_spans.push((start, start + normalized.len()));
                } else {
                    link_urls.push(normalized.to_string());
                }
            }
        }
    }

    let mut quote_ids: Vec<String> = Vec::new();
    let mut article_ids: Vec<String> = Vec::new();

    if content.contains('1') {
        for m in scan_bech32(content, false) {
            if inside_any_span(&url_spans, m.full_start, m.end) {
                continue;
            }
            let id_str = &content[m.id_start..m.end];
            match m.kind {
                Bech32Kind::Quote => {
                    quote_ids.push(id_str.to_string());
                    remove_spans.push((m.full_start, m.end));
                }
                Bech32Kind::Article => {
                    article_ids.push(id_str.to_string());
                    remove_spans.push((m.full_start, m.end));
                }
                Bech32Kind::Mention => {}
            }
        }
    }

    let cleaned_owned;
    let cleaned: &str = if remove_spans.is_empty() {
        content.trim()
    } else {
        remove_spans.sort_unstable_by_key(|&(s, _)| s);
        let mut buf = String::with_capacity(content.len());
        let mut cursor = 0usize;
        for (start, end) in remove_spans {
            if start >= cursor {
                buf.push_str(&content[cursor..start]);
                cursor = end;
            } else if end > cursor {
                cursor = end;
            }
        }
        buf.push_str(&content[cursor..]);
        cleaned_owned = buf;
        cleaned_owned.trim()
    };

    let mut text_parts: Vec<serde_json::Value> = Vec::new();
    if !cleaned.is_empty() {
        let has_nostr = cleaned
            .as_bytes()
            .windows(6)
            .any(|w| w.eq_ignore_ascii_case(b"nostr:"));
        if has_nostr {
            let mentions = scan_bech32(cleaned, true);
            if mentions.is_empty() {
                text_parts.push(serde_json::json!({
                    "type": "text",
                    "text": cleaned,
                }));
            } else {
                let mut last_end = 0;
                for m in mentions {
                    if m.full_start > last_end {
                        text_parts.push(serde_json::json!({
                            "type": "text",
                            "text": &cleaned[last_end..m.full_start],
                        }));
                    }
                    text_parts.push(serde_json::json!({
                        "type": "mention",
                        "id": &cleaned[m.id_start..m.end],
                    }));
                    last_end = m.end;
                }
                if last_end < cleaned.len() {
                    text_parts.push(serde_json::json!({
                        "type": "text",
                        "text": &cleaned[last_end..],
                    }));
                }
            }
        } else {
            text_parts.push(serde_json::json!({
                "type": "text",
                "text": cleaned,
            }));
        }
    }

    serde_json::json!({
        "textParts": text_parts,
        "mediaUrls": media_urls,
        "linkUrls": link_urls,
        "quoteIds": quote_ids,
        "articleIds": article_ids,
    })
    .to_string()
}

pub fn extract_embedded_ids_batch_typed(contents: Vec<String>) -> (Vec<String>, Vec<String>) {
    let mut quote_event_ids: HashSet<String> = HashSet::new();
    let mut article_author_pubkeys: HashSet<String> = HashSet::new();

    for content in &contents {
        if !content.contains('1') {
            continue;
        }
        for m in scan_bech32(content, false) {
            let bech32 = &content[m.id_start..m.end];
            match m.kind {
                Bech32Kind::Quote => {
                    if bech32.len() >= 5 && bech32[..5].eq_ignore_ascii_case("note1") {
                        if let Ok(id) = EventId::from_bech32(bech32) {
                            quote_event_ids.insert(id.to_hex());
                        }
                    } else if bech32.len() >= 7 && bech32[..7].eq_ignore_ascii_case("nevent1") {
                        if let Ok(nevent) = Nip19Event::from_bech32(bech32) {
                            quote_event_ids.insert(nevent.event_id.to_hex());
                        }
                    }
                }
                Bech32Kind::Article => {
                    if let Ok(coord) = Coordinate::from_bech32(bech32) {
                        if coord.kind == Kind::LongFormTextNote {
                            article_author_pubkeys.insert(coord.public_key.to_hex());
                        }
                    }
                }
                Bech32Kind::Mention => {}
            }
        }
    }

    (
        quote_event_ids.into_iter().collect(),
        article_author_pubkeys.into_iter().collect(),
    )
}

pub fn extract_embedded_ids_batch(contents: Vec<String>) -> String {
    let (quote_event_ids, article_author_pubkeys) = extract_embedded_ids_batch_typed(contents);
    serde_json::json!({
        "quoteEventIds": quote_event_ids,
        "articleAuthorPubkeys": article_author_pubkeys,
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_media_links_mentions_quotes_and_articles() {
        let keys = Keys::generate();
        let npub = keys.public_key().to_bech32().unwrap();
        let note_id = EventBuilder::text_note("x")
            .sign_with_keys(&keys)
            .unwrap()
            .id
            .to_bech32()
            .unwrap();
        let input = format!(
            "Hello NOSTR:{npub}! Look https://cdn.example/photo.JPG?w=800, and https://example.com/path/{note_id}. Quoting nostr:{note_id}"
        );
        let parsed: serde_json::Value = serde_json::from_str(&parse_note_content(&input)).unwrap();
        assert_eq!(
            parsed["mediaUrls"],
            serde_json::json!(["https://cdn.example/photo.JPG?w=800"])
        );
        assert_eq!(
            parsed["linkUrls"],
            serde_json::json!([format!("https://example.com/path/{note_id}")])
        );
        assert_eq!(parsed["quoteIds"], serde_json::json!([note_id]));
        let parts = parsed["textParts"].as_array().unwrap();
        assert!(parts
            .iter()
            .any(|p| p["type"] == "mention" && p["id"] == npub));
    }

    fn parsed(input: &str) -> serde_json::Value {
        serde_json::from_str(&parse_note_content(input)).unwrap()
    }

    #[test]
    fn urls_ending_in_multibyte_characters_do_not_panic() {
        for (input, link) in [
            (
                "見て https://ja.wikipedia.org/wiki/日本",
                "https://ja.wikipedia.org/wiki/日本",
            ),
            (
                "https://example.com/abcを見て",
                "https://example.com/abcを見て",
            ),
            (
                "https://ru.wikipedia.org/wiki/Биткойн",
                "https://ru.wikipedia.org/wiki/Биткойн",
            ),
            (
                "https://example.com/caf\u{e9}s",
                "https://example.com/cafés",
            ),
            ("https://example.com/😀", "https://example.com/😀"),
            ("https://example.com/é", "https://example.com/é"),
        ] {
            let value = parsed(input);
            assert_eq!(value["linkUrls"], serde_json::json!([link]), "{input}");
            assert_eq!(value["mediaUrls"], serde_json::json!([]), "{input}");
        }
        let value = parsed("https://例え.jp/画像.PNG?x=1 と https://example.com/日本.mp4");
        assert_eq!(
            value["mediaUrls"],
            serde_json::json!([
                "https://例え.jp/画像.PNG?x=1",
                "https://example.com/日本.mp4"
            ])
        );
    }

    #[test]
    fn every_unicode_whitespace_ends_a_url() {
        for separator in [
            " ", "\t", "\n", "\u{0B}", "\u{0C}", "\r", "\u{85}", "\u{A0}", "\u{3000}",
        ] {
            let value = parsed(&format!("https://example.com/a{separator}tail"));
            assert_eq!(
                value["linkUrls"],
                serde_json::json!(["https://example.com/a"]),
                "{separator:?}"
            );
        }
    }

    #[test]
    fn random_fragment_mixes_never_panic() {
        use rand::{Rng, SeedableRng};
        let fragments = [
            "https://",
            "http://",
            "HTTPS://",
            "Http://",
            "example.com/a",
            "cdn.x/y",
            ".jpg",
            ".PNG",
            ".mp4",
            ".jpeg",
            ".mov",
            "?x=1",
            "#frag",
            " ",
            "\n",
            "\u{0B}",
            ".",
            ",",
            ")",
            "(",
            "!",
            ":",
            ";",
            "nostr:",
            "NOSTR:",
            "note1",
            "nevent1",
            "naddr1",
            "npub1",
            "nprofile1",
            "qqqsyq9",
            "abc",
            "N",
            "n",
            "h",
            "é",
            "日本",
            "😀",
            "Б",
            "<",
            ">",
            "\"",
            "'",
            "\u{A0}",
            "\u{3000}",
            "x",
            "1",
            "/",
            "://",
            "http",
            "s",
        ];
        let mut rng = rand::rngs::StdRng::seed_from_u64(7);
        for _ in 0..20_000 {
            let mut input = String::new();
            for _ in 0..rng.gen_range(1..12) {
                input.push_str(fragments[rng.gen_range(0..fragments.len())]);
            }
            let output = parse_note_content(&input);
            assert!(serde_json::from_str::<serde_json::Value>(&output).is_ok());
            let _ = extract_embedded_ids_batch_typed(vec![input]);
        }
    }

    #[test]
    fn a_parser_panic_falls_back_to_plain_text() {
        fn exploding(_: &str) -> String {
            panic!("parser bug")
        }
        let value: serde_json::Value = serde_json::from_str(&parse_note_content_guarded(
            "  héllo 日本 https://example.com/日本  ",
            exploding,
        ))
        .unwrap();
        assert_eq!(
            value["textParts"],
            serde_json::json!([{ "type": "text", "text": "héllo 日本 https://example.com/日本" }])
        );
        assert_eq!(value["mediaUrls"], serde_json::json!([]));
        assert_eq!(
            parse_note_content_guarded("plain", parse_note_content),
            parse_note_content("plain")
        );
        let empty: serde_json::Value = serde_json::from_str(&plain_text_content("  ")).unwrap();
        assert_eq!(empty["textParts"], serde_json::json!([]));
    }
}
