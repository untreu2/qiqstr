//! Signing and encryption with the signed-in account's key, which the core keeps after
//! `init_client` or `update_signer`. Apps call these instead of holding the key themselves.

use std::sync::RwLock;

use anyhow::{anyhow, Result};
use nostr::prelude::*;

use super::events::{self, Draft};

static SESSION_KEYS: RwLock<Option<Keys>> = RwLock::new(None);

pub(crate) fn set_session_keys(keys: Option<Keys>) {
    let mut slot = SESSION_KEYS
        .write()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    *slot = keys;
}

pub(crate) fn session_keys() -> Result<Keys> {
    SESSION_KEYS
        .read()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .clone()
        .ok_or_else(|| anyhow!("No signer configured"))
}

pub fn session_can_sign() -> bool {
    session_keys().is_ok()
}

pub fn session_public_key() -> Result<String> {
    Ok(session_keys()?.public_key().to_hex())
}

pub fn sign_event(kind: u16, content: String, tags: Vec<Vec<String>>) -> Result<String> {
    Draft::new(kind, content, tags).sign(&session_keys()?)
}

pub fn sign_reaction_event(
    target_event_id: String,
    target_author: String,
    content: String,
    relay_url: String,
    target_kind: u16,
) -> Result<String> {
    events::reaction_draft(
        target_event_id,
        target_author,
        content,
        relay_url,
        target_kind,
    )
    .sign(&session_keys()?)
}

pub fn sign_repost_event(
    note_id: String,
    note_author: String,
    content: String,
    relay_url: String,
) -> Result<String> {
    events::repost_draft(note_id, note_author, content, relay_url)?.sign(&session_keys()?)
}

pub fn sign_deletion_event(event_ids: Vec<String>, reason: String) -> Result<String> {
    events::deletion_draft(event_ids, reason).sign(&session_keys()?)
}

pub fn sign_quote_event(
    content: String,
    quoted_event_id: String,
    quoted_event_pubkey: Option<String>,
    relay_url: String,
    additional_tags: Vec<Vec<String>>,
) -> Result<String> {
    events::quote_draft(
        content,
        quoted_event_id,
        quoted_event_pubkey,
        relay_url,
        additional_tags,
    )
    .sign(&session_keys()?)
}

pub fn sign_blossom_auth_event(
    content: String,
    sha256_hash: String,
    expiration: i64,
) -> Result<String> {
    events::blossom_auth_draft(content, sha256_hash, expiration).sign(&session_keys()?)
}

pub fn sign_relay_list_event_with_markers(relay_configs: Vec<String>) -> Result<String> {
    events::relay_list_draft_with_markers(relay_configs).sign(&session_keys()?)
}

/// The key that receives nutzaps (NIP-61) for this account, derived from the account key so it
/// can be recovered on any device.
pub fn session_nutzap_lock_secret() -> Result<String> {
    use sha2::{Digest, Sha256};
    let keys = session_keys()?;
    let key_hex = super::crypto::Secret::new(keys.secret_key().to_secret_hex());
    let mut hasher = Sha256::new();
    hasher.update(b"qiqstr-nutzap-p2pk:");
    hasher.update(key_hex.as_bytes());
    Ok(hex::encode(hasher.finalize()))
}

pub fn session_nip44_encrypt(content: String, receiver_pk_hex: String) -> Result<String> {
    let keys = session_keys()?;
    let receiver = PublicKey::parse(&receiver_pk_hex)?;
    Ok(nostr::nips::nip44::encrypt(
        keys.secret_key(),
        &receiver,
        &content,
        nostr::nips::nip44::Version::default(),
    )?)
}

pub fn session_nip44_decrypt(payload: String, sender_pk_hex: String) -> Result<String> {
    let keys = session_keys()?;
    let sender = PublicKey::parse(&sender_pk_hex)?;
    Ok(nostr::nips::nip44::decrypt(
        keys.secret_key(),
        &sender,
        &payload,
    )?)
}

pub fn session_nip04_decrypt(payload: String, sender_pk_hex: String) -> Result<String> {
    let keys = session_keys()?;
    let sender = PublicKey::parse(&sender_pk_hex)?;
    Ok(nostr::nips::nip04::decrypt(
        keys.secret_key(),
        &sender,
        payload,
    )?)
}

#[cfg(test)]
pub(crate) static SESSION_TEST_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn the_session_key_follows_sign_in_account_switches_and_sign_out() {
        let _guard = SESSION_TEST_LOCK.lock().await;
        let first = Keys::generate();
        let second = Keys::generate();

        crate::api::relay::init_client(
            vec![],
            Some(first.secret_key().to_secret_hex()),
            None,
            vec![],
        )
        .await
        .unwrap();
        assert!(session_can_sign());
        assert_eq!(session_public_key().unwrap(), first.public_key().to_hex());
        let event = Event::from_json(
            sign_event(1, "hello".into(), vec![vec!["t".into(), "x".into()]]).unwrap(),
        )
        .unwrap();
        event.verify().unwrap();
        assert_eq!(event.pubkey, first.public_key());
        assert_eq!(event.kind, Kind::TextNote);

        crate::api::relay::update_signer(second.secret_key().to_secret_hex())
            .await
            .unwrap();
        assert_eq!(session_public_key().unwrap(), second.public_key().to_hex());

        crate::api::relay::init_client(vec![], None, None, vec![])
            .await
            .unwrap();
        assert!(!session_can_sign());
        assert!(sign_event(1, "read only".into(), vec![]).is_err());

        crate::api::relay::init_client(
            vec![],
            Some(first.secret_key().to_secret_hex()),
            None,
            vec![],
        )
        .await
        .unwrap();
        assert!(session_can_sign());
        crate::api::relay::shutdown_client().await.unwrap();
        assert!(!session_can_sign());
        assert!(session_nip44_encrypt("x".into(), second.public_key().to_hex()).is_err());
    }

    #[tokio::test]
    async fn session_signing_matches_signing_with_the_key() {
        let _guard = SESSION_TEST_LOCK.lock().await;
        let keys = Keys::generate();
        let peer = Keys::generate();
        set_session_keys(Some(keys.clone()));
        let hex = || keys.secret_key().to_secret_hex();
        let id = EventId::all_zeros().to_hex();
        let author = peer.public_key().to_hex();
        let original = EventBuilder::text_note("original")
            .sign_with_keys(&peer)
            .unwrap();

        let pairs: Vec<(String, String)> = vec![
            (
                sign_reaction_event(
                    id.clone(),
                    author.clone(),
                    "+".into(),
                    "wss://r.example".into(),
                    1,
                )
                .unwrap(),
                events::create_reaction_event(
                    id.clone(),
                    author.clone(),
                    "+".into(),
                    hex(),
                    "wss://r.example".into(),
                    1,
                )
                .unwrap(),
            ),
            (
                sign_repost_event(
                    original.id.to_hex(),
                    author.clone(),
                    original.as_json(),
                    "wss://r.example".into(),
                )
                .unwrap(),
                events::create_repost_event(
                    original.id.to_hex(),
                    author.clone(),
                    original.as_json(),
                    hex(),
                    "wss://r.example".into(),
                )
                .unwrap(),
            ),
            (
                sign_deletion_event(vec![id.clone()], "why".into()).unwrap(),
                events::create_deletion_event(vec![id.clone()], "why".into(), hex()).unwrap(),
            ),
            (
                sign_quote_event(
                    "q".into(),
                    id.clone(),
                    Some(author.clone()),
                    "wss://r.example".into(),
                    vec![vec!["t".into(), "a".into()]],
                )
                .unwrap(),
                events::create_quote_event(
                    "q".into(),
                    id.clone(),
                    Some(author.clone()),
                    "wss://r.example".into(),
                    hex(),
                    vec![vec!["t".into(), "a".into()]],
                )
                .unwrap(),
            ),
            (
                sign_blossom_auth_event("Upload".into(), "ab".repeat(32), 99).unwrap(),
                events::create_blossom_auth_event("Upload".into(), "ab".repeat(32), 99, hex())
                    .unwrap(),
            ),
            (
                sign_relay_list_event_with_markers(vec![
                    "wss://a.example|read".into(),
                    "wss://b.example".into(),
                ])
                .unwrap(),
                events::create_relay_list_event_with_markers(
                    vec!["wss://a.example|read".into(), "wss://b.example".into()],
                    hex(),
                )
                .unwrap(),
            ),
            (
                sign_event(9734, "zap".into(), vec![vec!["p".into(), author.clone()]]).unwrap(),
                events::create_zap_request_event(
                    vec![vec!["p".into(), author.clone()]],
                    "zap".into(),
                    hex(),
                )
                .unwrap(),
            ),
        ];
        for (session, direct) in pairs {
            let session = Event::from_json(session).unwrap();
            let direct = Event::from_json(direct).unwrap();
            session.verify().unwrap();
            assert_eq!(session.pubkey, keys.public_key());
            assert_eq!(session.kind, direct.kind);
            assert_eq!(session.content, direct.content);
            assert_eq!(session.tags, direct.tags);
        }

        let secret =
            session_nip44_encrypt("private list".into(), keys.public_key().to_hex()).unwrap();
        assert_eq!(
            session_nip44_decrypt(secret, keys.public_key().to_hex()).unwrap(),
            "private list"
        );
        let from_peer = nostr::nips::nip44::encrypt(
            peer.secret_key(),
            &keys.public_key(),
            "hi",
            nostr::nips::nip44::Version::default(),
        )
        .unwrap();
        assert_eq!(
            session_nip44_decrypt(from_peer, author.clone()).unwrap(),
            "hi"
        );
        let legacy =
            nostr::nips::nip04::encrypt(peer.secret_key(), &keys.public_key(), "old").unwrap();
        assert_eq!(session_nip04_decrypt(legacy, author).unwrap(), "old");
        let derived = session_nutzap_lock_secret().unwrap();
        assert_eq!(
            derived,
            super::super::crypto::sha256_hash(format!("qiqstr-nutzap-p2pk:{}", hex()).into_bytes())
        );
        set_session_keys(None);
        assert!(session_nutzap_lock_secret().is_err());
    }
}
