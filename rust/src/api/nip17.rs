use flutter_rust_bridge::frb;
use nostr::prelude::*;
use nostr::nips::nip59;
use anyhow::Result;

#[frb(sync)]
pub fn create_gift_wrap_dm(
    sender_private_key_hex: String,
    receiver_pubkey_hex: String,
    message: String,
) -> Result<String> {
    let sender_sk = SecretKey::parse(&sender_private_key_hex)?;
    let sender_keys = Keys::new(sender_sk);
    let receiver_pk = PublicKey::parse(&receiver_pubkey_hex)?;

    let rumor: UnsignedEvent = EventBuilder::private_msg_rumor(receiver_pk, &message)
        .build(sender_keys.public_key());

    let gift_wrap: Event =
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()?
            .block_on(async {
                EventBuilder::gift_wrap(&sender_keys, &receiver_pk, rumor, []).await
            })?;

    Ok(gift_wrap.as_json())
}

#[frb(sync)]
pub fn create_gift_wrap_dm_for_sender(
    sender_private_key_hex: String,
    receiver_pubkey_hex: String,
    message: String,
) -> Result<String> {
    let sender_sk = SecretKey::parse(&sender_private_key_hex)?;
    let sender_keys = Keys::new(sender_sk);
    let receiver_pk = PublicKey::parse(&receiver_pubkey_hex)?;

    let rumor: UnsignedEvent = EventBuilder::private_msg_rumor(receiver_pk, &message)
        .build(sender_keys.public_key());

    let self_wrap: Event =
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()?
            .block_on(async {
                EventBuilder::gift_wrap(
                    &sender_keys,
                    &sender_keys.public_key(),
                    rumor,
                    [],
                )
                .await
            })?;

    Ok(self_wrap.as_json())
}

#[frb(sync)]
pub fn create_gift_wrap_file_message(
    sender_private_key_hex: String,
    receiver_pubkey_hex: String,
    file_url: String,
    mime_type: String,
    encryption_key_hex: String,
    encryption_nonce_hex: String,
    encrypted_hash: String,
    original_hash: String,
    file_size: Option<u64>,
) -> Result<String> {
    let sender_sk = SecretKey::parse(&sender_private_key_hex)?;
    let sender_keys = Keys::new(sender_sk);
    let receiver_pk = PublicKey::parse(&receiver_pubkey_hex)?;

    let mut event_builder = EventBuilder::new(Kind::from(15), file_url);
    event_builder = event_builder.tag(Tag::public_key(receiver_pk));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("file-type".into()), vec![mime_type]));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("encryption-algorithm".into()), vec!["aes-gcm".to_string()]));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("decryption-key".into()), vec![encryption_key_hex]));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("decryption-nonce".into()), vec![encryption_nonce_hex]));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("x".into()), vec![encrypted_hash]));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("ox".into()), vec![original_hash]));
    
    if let Some(size) = file_size {
        event_builder = event_builder.tag(Tag::custom(TagKind::Custom("size".into()), vec![size.to_string()]));
    }

    let rumor = event_builder.build(sender_keys.public_key());

    let gift_wrap: Event =
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()?
            .block_on(async {
                EventBuilder::gift_wrap(&sender_keys, &receiver_pk, rumor, []).await
            })?;

    Ok(gift_wrap.as_json())
}

#[frb(sync)]
pub fn create_gift_wrap_file_message_for_sender(
    sender_private_key_hex: String,
    receiver_pubkey_hex: String,
    file_url: String,
    mime_type: String,
    encryption_key_hex: String,
    encryption_nonce_hex: String,
    encrypted_hash: String,
    original_hash: String,
    file_size: Option<u64>,
) -> Result<String> {
    let sender_sk = SecretKey::parse(&sender_private_key_hex)?;
    let sender_keys = Keys::new(sender_sk);
    let receiver_pk = PublicKey::parse(&receiver_pubkey_hex)?;

    let mut event_builder = EventBuilder::new(Kind::from(15), file_url);
    event_builder = event_builder.tag(Tag::public_key(receiver_pk));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("file-type".into()), vec![mime_type]));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("encryption-algorithm".into()), vec!["aes-gcm".to_string()]));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("decryption-key".into()), vec![encryption_key_hex]));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("decryption-nonce".into()), vec![encryption_nonce_hex]));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("x".into()), vec![encrypted_hash]));
    event_builder = event_builder.tag(Tag::custom(TagKind::Custom("ox".into()), vec![original_hash]));
    
    if let Some(size) = file_size {
        event_builder = event_builder.tag(Tag::custom(TagKind::Custom("size".into()), vec![size.to_string()]));
    }

    let rumor = event_builder.build(sender_keys.public_key());

    let self_wrap: Event =
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()?
            .block_on(async {
                EventBuilder::gift_wrap(
                    &sender_keys,
                    &sender_keys.public_key(),
                    rumor,
                    [],
                )
                .await
            })?;

    Ok(self_wrap.as_json())
}

#[frb(sync)]
pub fn unwrap_gift_wrap(
    receiver_private_key_hex: String,
    gift_wrap_json: String,
) -> Result<String> {
    let receiver_sk = SecretKey::parse(&receiver_private_key_hex)?;
    let receiver_keys = Keys::new(receiver_sk);
    let gift_wrap = Event::from_json(&gift_wrap_json)?;

    let unwrapped: nip59::UnwrappedGift =
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()?
            .block_on(async {
                nip59::UnwrappedGift::from_gift_wrap(&receiver_keys, &gift_wrap).await
            })?;

    let tags: Vec<Vec<String>> = unwrapped
        .rumor
        .tags
        .iter()
        .map(|t| t.as_slice().iter().map(|s| s.to_string()).collect())
        .collect();

    Ok(serde_json::json!({
        "sender": unwrapped.sender.to_hex(),
        "rumor": {
            "id": unwrapped.rumor.id.map(|id| id.to_hex()).unwrap_or_default(),
            "pubkey": unwrapped.rumor.pubkey.to_hex(),
            "created_at": unwrapped.rumor.created_at.as_secs(),
            "kind": unwrapped.rumor.kind.as_u16(),
            "tags": tags,
            "content": unwrapped.rumor.content,
        }
    })
    .to_string())
}

#[frb(sync)]
pub fn is_gift_wrap(event_json: String) -> bool {
    match Event::from_json(&event_json) {
        Ok(event) => event.kind == Kind::GiftWrap,
        Err(_) => false,
    }
}

#[frb(sync)]
pub fn nip44_encrypt(
    content: String,
    sender_sk_hex: String,
    receiver_pk_hex: String,
) -> Result<String> {
    let sender_sk = SecretKey::parse(&sender_sk_hex)?;
    let receiver_pk = PublicKey::parse(&receiver_pk_hex)?;
    let encrypted =
        nostr::nips::nip44::encrypt(&sender_sk, &receiver_pk, &content, nostr::nips::nip44::Version::default())?;
    Ok(encrypted)
}

#[frb(sync)]
pub fn nip44_decrypt(
    payload: String,
    receiver_sk_hex: String,
    sender_pk_hex: String,
) -> Result<String> {
    let receiver_sk = SecretKey::parse(&receiver_sk_hex)?;
    let sender_pk = PublicKey::parse(&sender_pk_hex)?;
    let decrypted = nostr::nips::nip44::decrypt(&receiver_sk, &sender_pk, &payload)?;
    Ok(decrypted)
}
