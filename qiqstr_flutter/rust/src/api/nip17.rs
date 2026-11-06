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
pub fn unwrap_gift_wrap_dm(
    receiver_private_key_hex: String,
    gift_wrap_json: String,
    current_user_pubkey_hex: String,
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

    let sender = unwrapped.sender.to_hex();
    let rumor_kind = unwrapped.rumor.kind.as_u16();

    if rumor_kind != 14 && rumor_kind != 15 {
        return Err(anyhow::anyhow!("Not a DM rumor kind: {}", rumor_kind));
    }

    let content = &unwrapped.rumor.content;
    let created_at = unwrapped.rumor.created_at.as_secs();
    let rumor_id = unwrapped
        .rumor
        .id
        .map(|id| id.to_hex())
        .unwrap_or_default();

    let mut recipient_pubkey: Option<String> = None;
    let mut mime_type: Option<String> = None;
    let mut encryption_key: Option<String> = None;
    let mut encryption_nonce: Option<String> = None;
    let mut encrypted_hash: Option<String> = None;
    let mut original_hash: Option<String> = None;
    let mut file_size: Option<u64> = None;

    for tag in unwrapped.rumor.tags.iter() {
        let parts: Vec<String> = tag.as_slice().iter().map(|s| s.to_string()).collect();
        if parts.len() < 2 {
            continue;
        }
        match parts[0].as_str() {
            "p" => recipient_pubkey = Some(parts[1].clone()),
            "file-type" => mime_type = Some(parts[1].clone()),
            "decryption-key" => encryption_key = Some(parts[1].clone()),
            "decryption-nonce" => encryption_nonce = Some(parts[1].clone()),
            "x" => encrypted_hash = Some(parts[1].clone()),
            "ox" => original_hash = Some(parts[1].clone()),
            "size" => file_size = parts[1].parse::<u64>().ok(),
            _ => {}
        }
    }

    let is_from_current_user = sender == current_user_pubkey_hex;
    let other_user = if is_from_current_user {
        recipient_pubkey.as_deref().unwrap_or("")
    } else {
        &sender
    };

    if other_user.is_empty() {
        return Err(anyhow::anyhow!("Cannot determine other user"));
    }

    let mut msg = serde_json::json!({
        "id": rumor_id,
        "senderPubkeyHex": sender,
        "recipientPubkeyHex": other_user,
        "content": content,
        "createdAt": created_at,
        "isFromCurrentUser": is_from_current_user,
        "kind": rumor_kind,
    });

    if rumor_kind == 15 {
        if let Some(ref v) = mime_type { msg["mimeType"] = serde_json::json!(v); }
        if let Some(ref v) = encryption_key { msg["encryptionKey"] = serde_json::json!(v); }
        if let Some(ref v) = encryption_nonce { msg["encryptionNonce"] = serde_json::json!(v); }
        if let Some(ref v) = encrypted_hash { msg["encryptedHash"] = serde_json::json!(v); }
        if let Some(ref v) = original_hash { msg["originalHash"] = serde_json::json!(v); }
        if let Some(v) = file_size { msg["fileSize"] = serde_json::json!(v); }
    }

    Ok(msg.to_string())
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
