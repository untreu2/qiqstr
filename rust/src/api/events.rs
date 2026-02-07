use anyhow::Result;
use flutter_rust_bridge::frb;
use nostr::prelude::*;

#[frb(sync)]
pub fn create_signed_event(
    kind: u16,
    content: String,
    tags: Vec<Vec<String>>,
    private_key_hex: String,
) -> Result<String> {
    let secret_key = SecretKey::parse(&private_key_hex)?;
    let keys = Keys::new(secret_key);

    let nostr_tags: Vec<Tag> = tags
        .iter()
        .filter(|t| !t.is_empty())
        .map(|t| Tag::custom(TagKind::custom(&t[0]), t[1..].to_vec()))
        .collect();

    let builder = EventBuilder::new(Kind::from(kind), &content).tags(nostr_tags);
    let event = builder.sign_with_keys(&keys)?;
    Ok(event.as_json())
}

#[frb(sync)]
pub fn create_note_event(
    content: String,
    tags: Vec<Vec<String>>,
    private_key_hex: String,
) -> Result<String> {
    create_signed_event(1, content, tags, private_key_hex)
}

#[frb(sync)]
pub fn create_reaction_event(
    target_event_id: String,
    target_author: String,
    content: String,
    private_key_hex: String,
    relay_url: String,
    target_kind: u16,
) -> Result<String> {
    let tags = vec![
        vec!["e".into(), target_event_id, relay_url],
        vec!["p".into(), target_author],
        vec!["k".into(), target_kind.to_string()],
    ];
    create_signed_event(7, content, tags, private_key_hex)
}

#[frb(sync)]
pub fn create_reply_event(
    content: String,
    tags: Vec<Vec<String>>,
    private_key_hex: String,
) -> Result<String> {
    create_signed_event(1, content, tags, private_key_hex)
}

#[frb(sync)]
pub fn create_repost_event(
    note_id: String,
    note_author: String,
    content: String,
    private_key_hex: String,
    relay_url: String,
) -> Result<String> {
    let tags = vec![
        vec!["e".into(), note_id, relay_url],
        vec!["p".into(), note_author],
    ];
    create_signed_event(6, content, tags, private_key_hex)
}

#[frb(sync)]
pub fn create_deletion_event(
    event_ids: Vec<String>,
    reason: String,
    private_key_hex: String,
) -> Result<String> {
    let tags: Vec<Vec<String>> = event_ids
        .iter()
        .map(|id| vec!["e".into(), id.clone()])
        .collect();
    create_signed_event(5, reason, tags, private_key_hex)
}

#[frb(sync)]
pub fn create_profile_event(profile_json: String, private_key_hex: String) -> Result<String> {
    create_signed_event(0, profile_json, vec![], private_key_hex)
}

#[frb(sync)]
pub fn create_follow_event(
    following_pubkeys: Vec<String>,
    private_key_hex: String,
) -> Result<String> {
    let tags: Vec<Vec<String>> = following_pubkeys
        .iter()
        .map(|pk| vec!["p".into(), pk.clone(), String::new()])
        .collect();
    create_signed_event(3, String::new(), tags, private_key_hex)
}

#[frb(sync)]
pub fn create_mute_event(muted_pubkeys: Vec<String>, private_key_hex: String) -> Result<String> {
    let tags: Vec<Vec<String>> = muted_pubkeys
        .iter()
        .map(|pk| vec!["p".into(), pk.clone()])
        .collect();
    create_signed_event(10000, String::new(), tags, private_key_hex)
}

#[frb(sync)]
pub fn create_zap_request_event(
    tags: Vec<Vec<String>>,
    content: String,
    private_key_hex: String,
) -> Result<String> {
    create_signed_event(9734, content, tags, private_key_hex)
}

#[frb(sync)]
pub fn create_quote_event(
    content: String,
    quoted_event_id: String,
    quoted_event_pubkey: Option<String>,
    relay_url: String,
    private_key_hex: String,
    additional_tags: Vec<Vec<String>>,
) -> Result<String> {
    let mut tags = Vec::new();
    if let Some(ref pk) = quoted_event_pubkey {
        tags.push(vec![
            "q".into(),
            quoted_event_id.clone(),
            relay_url,
            pk.clone(),
        ]);
        tags.push(vec!["p".into(), pk.clone()]);
    } else {
        tags.push(vec!["q".into(), quoted_event_id, relay_url]);
    }
    tags.extend(additional_tags);
    create_signed_event(1, content, tags, private_key_hex)
}

#[frb(sync)]
pub fn create_blossom_auth_event(
    content: String,
    sha256_hash: String,
    expiration: i64,
    private_key_hex: String,
) -> Result<String> {
    let tags = vec![
        vec!["t".into(), "upload".into()],
        vec!["x".into(), sha256_hash],
        vec!["expiration".into(), expiration.to_string()],
    ];
    create_signed_event(24242, content, tags, private_key_hex)
}

#[frb(sync)]
pub fn create_relay_list_event(relay_urls: Vec<String>, private_key_hex: String) -> Result<String> {
    let tags: Vec<Vec<String>> = relay_urls
        .iter()
        .map(|url| vec!["r".into(), url.clone()])
        .collect();
    create_signed_event(10002, String::new(), tags, private_key_hex)
}

#[frb(sync)]
pub fn create_coinos_auth_event(challenge: String, private_key_hex: String) -> Result<String> {
    let tags = vec![vec!["challenge".into(), challenge]];
    create_signed_event(27235, String::new(), tags, private_key_hex)
}
