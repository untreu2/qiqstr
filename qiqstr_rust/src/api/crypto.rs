use aes::Aes256;
use aes_gcm::{
    aead::{generic_array::GenericArray, Aead, KeyInit, OsRng},
    Aes256Gcm, AesGcm, Nonce,
};
use anyhow::Result;
use base64::{engine::general_purpose, Engine as _};
use nostr::nips::nip06::FromMnemonic;
use nostr::prelude::*;
use nostr::secp256k1::Message;
use rand::RngCore;
use sha2::{Digest, Sha256};
use typenum::U16;

fn wipe_in_place(value: &mut str) {
    // SAFETY: every byte is overwritten with zero, which keeps the string valid UTF-8, and each
    // pointer is valid, aligned and uniquely borrowed.
    for b in unsafe { value.as_bytes_mut() } {
        unsafe { std::ptr::write_volatile(b, 0) };
    }
    std::sync::atomic::compiler_fence(std::sync::atomic::Ordering::SeqCst);
}

/// A secret handed over by the app. Its bytes are overwritten when it goes out of scope, on
/// every return path. This is best effort: copies held by the app and the bridge are out of
/// reach from here.
pub(crate) struct Secret(String);

impl Secret {
    pub(crate) fn new(value: String) -> Self {
        Self(value)
    }
}

impl std::ops::Deref for Secret {
    type Target = str;

    fn deref(&self) -> &str {
        &self.0
    }
}

impl Drop for Secret {
    fn drop(&mut self) {
        wipe_in_place(&mut self.0);
    }
}

pub fn generate_keypair() -> (String, String) {
    let keys = Keys::generate();
    (
        keys.secret_key().to_secret_hex(),
        keys.public_key().to_hex(),
    )
}

pub fn get_public_key(private_key_hex: String) -> Result<String> {
    let private_key_hex = Secret::new(private_key_hex);
    let keys = Keys::new(SecretKey::parse(&private_key_hex)?);
    Ok(keys.public_key().to_hex())
}

pub fn sign_event_id(event_id_hex: String, private_key_hex: String) -> Result<String> {
    let private_key_hex = Secret::new(private_key_hex);
    let keys = Keys::new(SecretKey::parse(&private_key_hex)?);
    let event_id = EventId::parse(&event_id_hex)?;
    let message = Message::from_digest(*event_id.as_bytes());
    let sig = keys.sign_schnorr(&message);
    Ok(sig.to_string())
}

pub fn verify_event(event_json: String) -> bool {
    match Event::from_json(&event_json) {
        Ok(event) => event.verify().is_ok(),
        Err(_) => false,
    }
}

pub async fn verify_note_by_id(event_id_hex: String) -> Result<bool> {
    let client = crate::api::relay::get_client_pub().await?;
    let id = EventId::from_hex(&event_id_hex)?;
    let event = client.database().event_by_id(&id)?;

    match event {
        Some(e) => Ok(e.verify().is_ok()),
        None => Ok(false),
    }
}

pub async fn verify_profile_by_pubkey(pubkey_hex: String) -> Result<bool> {
    let client = crate::api::relay::get_client_pub().await?;
    let pk = PublicKey::from_hex(&pubkey_hex)?;
    let filter = Filter::new().author(pk).kind(Kind::Metadata).limit(1);
    let events = client.database().query(&filter)?;

    match events.first() {
        Some(e) => Ok(e.verify().is_ok()),
        None => Ok(false),
    }
}

pub fn generate_mnemonic() -> Result<String> {
    let m = bip39::Mnemonic::generate(12)?;
    Ok(m.to_string())
}

pub fn validate_mnemonic(mnemonic: String) -> bool {
    let mnemonic = Secret::new(mnemonic);
    bip39::Mnemonic::parse_normalized(&mnemonic).is_ok()
}

pub fn mnemonic_to_private_key(mnemonic: String) -> Result<String> {
    let mnemonic = Secret::new(mnemonic);
    let keys = Keys::from_mnemonic(&*mnemonic, None)?;
    Ok(keys.secret_key().to_secret_hex())
}

pub fn generate_aes_key() -> String {
    let mut key = [0u8; 32];
    OsRng.fill_bytes(&mut key);
    hex::encode(key)
}

pub fn generate_aes_nonce() -> String {
    let mut nonce = [0u8; 12];
    OsRng.fill_bytes(&mut nonce);
    hex::encode(nonce)
}

pub fn aes_gcm_encrypt(data: Vec<u8>, key_hex: String, nonce_hex: String) -> Result<String> {
    let key_bytes = hex::decode(&key_hex).map_err(|e| anyhow::anyhow!("Invalid key hex: {}", e))?;
    let nonce_bytes =
        hex::decode(&nonce_hex).map_err(|e| anyhow::anyhow!("Invalid nonce hex: {}", e))?;

    if key_bytes.len() != 32 {
        return Err(anyhow::anyhow!("Key must be 32 bytes (256 bits)"));
    }
    if nonce_bytes.len() != 12 {
        return Err(anyhow::anyhow!("Nonce must be 12 bytes (96 bits)"));
    }

    let cipher = Aes256Gcm::new_from_slice(&key_bytes)
        .map_err(|e| anyhow::anyhow!("Failed to create cipher: {}", e))?;

    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, data.as_ref())
        .map_err(|e| anyhow::anyhow!("Encryption failed: {}", e))?;

    Ok(general_purpose::STANDARD.encode(ciphertext))
}

pub fn aes_gcm_decrypt(
    encrypted_base64: String,
    key_hex: String,
    nonce_hex: String,
) -> Result<Vec<u8>> {
    let key_bytes = hex::decode(&key_hex).map_err(|e| anyhow::anyhow!("Invalid key hex: {}", e))?;
    let nonce_bytes =
        hex::decode(&nonce_hex).map_err(|e| anyhow::anyhow!("Invalid nonce hex: {}", e))?;
    let ciphertext = general_purpose::STANDARD
        .decode(&encrypted_base64)
        .map_err(|e| anyhow::anyhow!("Invalid base64: {}", e))?;

    if key_bytes.len() != 32 {
        return Err(anyhow::anyhow!("Key must be 32 bytes (256 bits)"));
    }

    let plaintext = match nonce_bytes.len() {
        12 => {
            let cipher = Aes256Gcm::new_from_slice(&key_bytes)
                .map_err(|e| anyhow::anyhow!("Failed to create cipher: {}", e))?;
            let nonce = Nonce::from_slice(&nonce_bytes);
            cipher
                .decrypt(nonce, ciphertext.as_ref())
                .map_err(|e| anyhow::anyhow!("Decryption failed (12-byte nonce): {}", e))?
        }
        16 => {
            type Aes256Gcm16 = AesGcm<Aes256, U16>;
            let cipher = Aes256Gcm16::new_from_slice(&key_bytes)
                .map_err(|e| anyhow::anyhow!("Failed to create cipher: {}", e))?;
            let nonce = GenericArray::from_slice(&nonce_bytes);
            cipher
                .decrypt(nonce, ciphertext.as_ref())
                .map_err(|e| anyhow::anyhow!("Decryption failed (16-byte nonce): {}", e))?
        }
        _ => {
            return Err(anyhow::anyhow!(
                "Nonce must be either 12 bytes (standard) or 16 bytes (Android/Amethyst). Got {} bytes",
                nonce_bytes.len()
            ));
        }
    };

    Ok(plaintext)
}

pub fn sha256_hash(data: Vec<u8>) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let result = hasher.finalize();
    hex::encode(result)
}

pub fn ncryptsec_encrypt(private_key_hex: String, password: String) -> Result<String> {
    let private_key_hex = Secret::new(private_key_hex);
    let password = Secret::new(password);
    let sk = SecretKey::parse(&private_key_hex)?;
    let encrypted = EncryptedSecretKey::new(&sk, &password, 16, KeySecurity::Medium)?;
    Ok(encrypted.to_bech32()?)
}

pub fn ncryptsec_decrypt(ncryptsec: String, password: String) -> Result<String> {
    let password = Secret::new(password);
    let encrypted = EncryptedSecretKey::from_bech32(ncryptsec.trim())?;
    Ok(encrypted.decrypt(&password)?.to_secret_hex())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secrets_are_overwritten_in_place_and_stay_usable_until_dropped() {
        let mut value = "nsec1 correct horse battery staple é".to_string();
        let length = value.len();
        wipe_in_place(&mut value);
        assert_eq!(value.len(), length);
        assert!(value.bytes().all(|byte| byte == 0));

        let keys = Keys::generate();
        let secret = Secret::new(keys.secret_key().to_secret_hex());
        assert_eq!(secret.len(), 64);
        assert_eq!(
            get_public_key(secret.to_string()).unwrap(),
            keys.public_key().to_hex()
        );
        assert!(get_public_key("not a key".into()).is_err());
        assert!(sign_event_id("zz".into(), keys.secret_key().to_secret_hex()).is_err());
        assert!(mnemonic_to_private_key("not a mnemonic".into()).is_err());
        assert!(ncryptsec_encrypt("not a key".into(), "password".into()).is_err());
        assert!(ncryptsec_decrypt("not ncryptsec".into(), "password".into()).is_err());
        let encrypted =
            ncryptsec_encrypt(keys.secret_key().to_secret_hex(), "password".into()).unwrap();
        assert_eq!(
            ncryptsec_decrypt(encrypted, "password".into()).unwrap(),
            keys.secret_key().to_secret_hex()
        );
    }

    #[test]
    fn encrypted_files_round_trip_and_reject_tampering() {
        let key = generate_aes_key();
        let nonce = generate_aes_nonce();
        let plaintext = b"private file contents".to_vec();
        let encrypted = aes_gcm_encrypt(plaintext.clone(), key.clone(), nonce.clone()).unwrap();
        assert_eq!(
            aes_gcm_decrypt(encrypted.clone(), key.clone(), nonce.clone()).unwrap(),
            plaintext
        );
        let mut bytes = general_purpose::STANDARD.decode(encrypted).unwrap();
        bytes[0] ^= 1;
        assert!(aes_gcm_decrypt(general_purpose::STANDARD.encode(bytes), key, nonce).is_err());
    }

    #[test]
    fn amethyst_sixteen_byte_nonce_is_supported() {
        let key = [7u8; 32];
        let nonce = [8u8; 16];
        let cipher = AesGcm::<Aes256, U16>::new_from_slice(&key).unwrap();
        let encrypted = cipher
            .encrypt(
                GenericArray::from_slice(&nonce),
                b"compatible file".as_ref(),
            )
            .unwrap();
        assert_eq!(
            aes_gcm_decrypt(
                general_purpose::STANDARD.encode(encrypted),
                hex::encode(key),
                hex::encode(nonce)
            )
            .unwrap(),
            b"compatible file"
        );
    }

    #[test]
    fn malformed_file_keys_and_nonces_return_errors() {
        for length in [0, 1, 8, 13, 17, 64] {
            assert!(aes_gcm_decrypt("AA==".into(), "11".repeat(32), "22".repeat(length)).is_err());
        }
        assert!(aes_gcm_encrypt(vec![], "11".repeat(31), "22".repeat(12)).is_err());
        assert!(aes_gcm_decrypt("not base64".into(), "11".repeat(32), "22".repeat(12)).is_err());
    }
}
