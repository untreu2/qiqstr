use anyhow::Result;
use nostr::prelude::*;

pub fn nip44_encrypt(
    content: String,
    sender_sk_hex: String,
    receiver_pk_hex: String,
) -> Result<String> {
    let sender_sk = SecretKey::parse(&sender_sk_hex)?;
    let receiver_pk = PublicKey::parse(&receiver_pk_hex)?;
    let encrypted = nostr::nips::nip44::encrypt(
        &sender_sk,
        &receiver_pk,
        &content,
        nostr::nips::nip44::Version::default(),
    )?;
    Ok(encrypted)
}

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

pub fn nip04_decrypt(
    payload: String,
    receiver_sk_hex: String,
    sender_pk_hex: String,
) -> Result<String> {
    let receiver_sk = SecretKey::parse(&receiver_sk_hex)?;
    let sender_pk = PublicKey::parse(&sender_pk_hex)?;
    let decrypted = nostr::nips::nip04::decrypt(&receiver_sk, &sender_pk, payload)?;
    Ok(decrypted)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_nip04_payloads_decrypt() {
        let alice = Keys::generate();
        let bob = Keys::generate();
        let payload = nostr::nips::nip04::encrypt(alice.secret_key(), &bob.public_key(), "legacy").unwrap();
        let plain = nip04_decrypt(payload.clone(), bob.secret_key().to_secret_hex(), alice.public_key().to_hex()).unwrap();
        assert_eq!(plain, "legacy");
        assert!(nip04_decrypt("not a payload".into(), bob.secret_key().to_secret_hex(), alice.public_key().to_hex()).is_err());
    }

    #[test]
    fn round_trips_between_two_keys() {
        let alice = Keys::generate();
        let bob = Keys::generate();
        let payload = nip44_encrypt("secret".into(), alice.secret_key().to_secret_hex(), bob.public_key().to_hex()).unwrap();
        let plain = nip44_decrypt(payload.clone(), bob.secret_key().to_secret_hex(), alice.public_key().to_hex()).unwrap();
        assert_eq!(plain, "secret");
        assert!(nip44_decrypt(payload, Keys::generate().secret_key().to_secret_hex(), alice.public_key().to_hex()).is_err());
    }
}
