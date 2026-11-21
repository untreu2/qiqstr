use anyhow::Result;
use nostr::prelude::*;

use super::crypto::Secret;

/// An event's kind, content and tags, before it is signed.
pub(crate) struct Draft {
    pub kind: u16,
    pub content: String,
    pub tags: Vec<Vec<String>>,
}

impl Draft {
    pub(crate) fn new(kind: u16, content: String, tags: Vec<Vec<String>>) -> Self {
        Self {
            kind,
            content,
            tags,
        }
    }

    pub(crate) fn sign(self, keys: &Keys) -> Result<String> {
        let tags: Vec<Tag> = self
            .tags
            .iter()
            .filter(|t| !t.is_empty())
            .map(|t| Tag::custom(TagKind::custom(&t[0]), t[1..].to_vec()))
            .collect();
        let event = EventBuilder::new(Kind::from(self.kind), &self.content)
            .tags(tags)
            .sign_with_keys(keys)?;
        Ok(event.as_json())
    }

    fn sign_with_key(self, private_key_hex: String) -> Result<String> {
        self.sign_with_secret(&Secret::new(private_key_hex))
    }

    fn sign_with_secret(self, private_key_hex: &Secret) -> Result<String> {
        self.sign(&Keys::new(SecretKey::parse(private_key_hex)?))
    }
}

pub(crate) fn reaction_draft(
    target_event_id: String,
    target_author: String,
    content: String,
    relay_url: String,
    target_kind: u16,
) -> Draft {
    let tags = vec![
        vec!["e".into(), target_event_id, relay_url],
        vec!["p".into(), target_author],
        vec!["k".into(), target_kind.to_string()],
    ];
    Draft::new(7, content, tags)
}

pub(crate) fn repost_draft(
    note_id: String,
    note_author: String,
    content: String,
    relay_url: String,
) -> Result<Draft> {
    let note_id = EventId::parse(&note_id)?;
    let note_author = PublicKey::parse(&note_author)?;
    let original = Event::from_json(&content).ok().filter(|event| {
        event.id == note_id
            && event.pubkey == note_author
            && event.kind == Kind::TextNote
            && event.verify().is_ok()
    });
    let content = original.map(|event| event.as_json()).unwrap_or_default();
    let tags = vec![
        vec!["e".into(), note_id.to_hex(), relay_url],
        vec!["p".into(), note_author.to_hex()],
    ];
    Ok(Draft::new(6, content, tags))
}

pub(crate) fn deletion_draft(event_ids: Vec<String>, reason: String) -> Draft {
    let tags = event_ids
        .into_iter()
        .map(|id| vec!["e".into(), id])
        .collect();
    Draft::new(5, reason, tags)
}

pub(crate) fn quote_draft(
    content: String,
    quoted_event_id: String,
    quoted_event_pubkey: Option<String>,
    relay_url: String,
    additional_tags: Vec<Vec<String>>,
) -> Draft {
    let mut tags = Vec::new();
    if let Some(pk) = quoted_event_pubkey {
        tags.push(vec!["q".into(), quoted_event_id, relay_url, pk.clone()]);
        tags.push(vec!["p".into(), pk]);
    } else {
        tags.push(vec!["q".into(), quoted_event_id, relay_url]);
    }
    tags.extend(additional_tags);
    Draft::new(1, content, tags)
}

pub(crate) fn blossom_auth_draft(content: String, sha256_hash: String, expiration: i64) -> Draft {
    let tags = vec![
        vec!["t".into(), "upload".into()],
        vec!["x".into(), sha256_hash],
        vec!["expiration".into(), expiration.to_string()],
    ];
    Draft::new(24242, content, tags)
}

pub(crate) fn relay_list_draft_with_markers(relay_configs: Vec<String>) -> Draft {
    let tags = relay_configs
        .iter()
        .map(|config| {
            if let Some((url, marker)) = config.split_once('|') {
                vec!["r".into(), url.to_string(), marker.to_string()]
            } else {
                vec!["r".into(), config.clone()]
            }
        })
        .collect();
    Draft::new(10002, String::new(), tags)
}

pub fn create_signed_event(
    kind: u16,
    content: String,
    tags: Vec<Vec<String>>,
    private_key_hex: String,
) -> Result<String> {
    Draft::new(kind, content, tags).sign_with_key(private_key_hex)
}

pub fn zap_receipt_summary(event_json: String) -> Result<String> {
    let event = Event::from_json(&event_json)?;
    event.verify()?;
    let sender = super::database::extract_zap_sender(&event)
        .ok_or_else(|| anyhow::anyhow!("Zap request is missing or invalid"))?;
    Ok(serde_json::json!({
        "sender": sender,
        "amount": super::database::extract_zap_amount_sats(&event),
        "comment": super::database::extract_zap_comment(&event),
    })
    .to_string())
}

pub fn create_note_event(
    content: String,
    tags: Vec<Vec<String>>,
    private_key_hex: String,
) -> Result<String> {
    Draft::new(1, content, tags).sign_with_key(private_key_hex)
}

pub fn create_reaction_event(
    target_event_id: String,
    target_author: String,
    content: String,
    private_key_hex: String,
    relay_url: String,
    target_kind: u16,
) -> Result<String> {
    reaction_draft(
        target_event_id,
        target_author,
        content,
        relay_url,
        target_kind,
    )
    .sign_with_key(private_key_hex)
}

pub fn create_reply_event(
    content: String,
    tags: Vec<Vec<String>>,
    private_key_hex: String,
) -> Result<String> {
    Draft::new(1, content, tags).sign_with_key(private_key_hex)
}

pub fn create_repost_event(
    note_id: String,
    note_author: String,
    content: String,
    private_key_hex: String,
    relay_url: String,
) -> Result<String> {
    let private_key_hex = Secret::new(private_key_hex);
    repost_draft(note_id, note_author, content, relay_url)?.sign_with_secret(&private_key_hex)
}

pub fn create_deletion_event(
    event_ids: Vec<String>,
    reason: String,
    private_key_hex: String,
) -> Result<String> {
    deletion_draft(event_ids, reason).sign_with_key(private_key_hex)
}

pub fn create_profile_event(profile_json: String, private_key_hex: String) -> Result<String> {
    Draft::new(0, profile_json, vec![]).sign_with_key(private_key_hex)
}

pub fn create_follow_event(
    following_pubkeys: Vec<String>,
    private_key_hex: String,
) -> Result<String> {
    let tags = following_pubkeys
        .into_iter()
        .map(|pk| vec!["p".into(), pk, String::new()])
        .collect();
    Draft::new(3, String::new(), tags).sign_with_key(private_key_hex)
}

pub fn create_mute_event(muted_pubkeys: Vec<String>, private_key_hex: String) -> Result<String> {
    let tags = muted_pubkeys
        .into_iter()
        .map(|pk| vec!["p".into(), pk])
        .collect();
    Draft::new(10000, String::new(), tags).sign_with_key(private_key_hex)
}

pub fn create_zap_request_event(
    tags: Vec<Vec<String>>,
    content: String,
    private_key_hex: String,
) -> Result<String> {
    Draft::new(9734, content, tags).sign_with_key(private_key_hex)
}

pub fn create_quote_event(
    content: String,
    quoted_event_id: String,
    quoted_event_pubkey: Option<String>,
    relay_url: String,
    private_key_hex: String,
    additional_tags: Vec<Vec<String>>,
) -> Result<String> {
    quote_draft(
        content,
        quoted_event_id,
        quoted_event_pubkey,
        relay_url,
        additional_tags,
    )
    .sign_with_key(private_key_hex)
}

pub fn create_blossom_auth_event(
    content: String,
    sha256_hash: String,
    expiration: i64,
    private_key_hex: String,
) -> Result<String> {
    blossom_auth_draft(content, sha256_hash, expiration).sign_with_key(private_key_hex)
}

pub fn create_relay_list_event(relay_urls: Vec<String>, private_key_hex: String) -> Result<String> {
    let tags = relay_urls
        .into_iter()
        .map(|url| vec!["r".into(), url])
        .collect();
    Draft::new(10002, String::new(), tags).sign_with_key(private_key_hex)
}

pub fn create_relay_list_event_with_markers(
    relay_configs: Vec<String>,
    private_key_hex: String,
) -> Result<String> {
    relay_list_draft_with_markers(relay_configs).sign_with_key(private_key_hex)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reposts_embed_only_the_matching_verified_original_event() {
        let author = Keys::generate();
        let original = EventBuilder::text_note("original")
            .sign_with_keys(&author)
            .unwrap();
        let reposter = Keys::generate();
        for (content, embedded) in [
            (original.as_json(), true),
            ("{\"content\":\"hydrated note\"}".to_string(), false),
        ] {
            let repost = create_repost_event(
                original.id.to_hex(),
                author.public_key().to_hex(),
                content,
                reposter.secret_key().to_secret_hex(),
                "wss://relay.example".into(),
            )
            .unwrap();
            let repost = Event::from_json(repost).unwrap();
            repost.verify().unwrap();
            assert_eq!(!repost.content.is_empty(), embedded);
            if embedded {
                assert_eq!(Event::from_json(&repost.content).unwrap(), original);
            }
        }
    }
}
