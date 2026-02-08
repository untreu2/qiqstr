use anyhow::Result;
use flutter_rust_bridge::frb;
use nostr::nips::nip06::FromMnemonic;
use nostr::prelude::*;
use nostr::secp256k1::Message;
use aes_gcm::{
    aead::{Aead, KeyInit, OsRng, generic_array::GenericArray},
    Aes256Gcm, AesGcm, Nonce,
};
use aes::Aes256;
use rand::RngCore;
use sha2::{Digest, Sha256};
use base64::{Engine as _, engine::general_purpose};
use typenum::U16;

#[frb(sync)]
pub fn generate_keypair() -> (String, String) {
    let keys = Keys::generate();
    (
        keys.secret_key().to_secret_hex(),
        keys.public_key().to_hex(),
    )
}

#[frb(sync)]
pub fn get_public_key(private_key_hex: String) -> Result<String> {
    let secret_key = SecretKey::parse(&private_key_hex)?;
    let keys = Keys::new(secret_key);
    Ok(keys.public_key().to_hex())
}

#[frb(sync)]
pub fn sign_event_id(event_id_hex: String, private_key_hex: String) -> Result<String> {
    let secret_key = SecretKey::parse(&private_key_hex)?;
    let keys = Keys::new(secret_key);
    let event_id = EventId::parse(&event_id_hex)?;
    let message = Message::from_digest(*event_id.as_bytes());
    let sig = keys.sign_schnorr(&message);
    Ok(sig.to_string())
}

#[frb(sync)]
pub fn verify_event(event_json: String) -> bool {
    match Event::from_json(&event_json) {
        Ok(event) => event.verify().is_ok(),
        Err(_) => false,
    }
}

#[frb(sync)]
pub fn generate_mnemonic() -> Result<String> {
    let m = bip39::Mnemonic::generate(12)?;
    Ok(m.to_string())
}

#[frb(sync)]
pub fn validate_mnemonic(mnemonic: String) -> bool {
    bip39::Mnemonic::parse_normalized(&mnemonic).is_ok()
}

#[frb(sync)]
pub fn mnemonic_to_private_key(mnemonic: String) -> Result<String> {
    let keys = Keys::from_mnemonic(mnemonic.as_str(), None)?;
    Ok(keys.secret_key().to_secret_hex())
}

#[frb(sync)]
pub fn generate_aes_key() -> String {
    let mut key = [0u8; 32];
    OsRng.fill_bytes(&mut key);
    hex::encode(key)
}

#[frb(sync)]
pub fn generate_aes_nonce() -> String {
    let mut nonce = [0u8; 12];
    OsRng.fill_bytes(&mut nonce);
    hex::encode(nonce)
}

#[frb(sync)]
pub fn aes_gcm_encrypt(data: Vec<u8>, key_hex: String, nonce_hex: String) -> Result<String> {
    let key_bytes = hex::decode(&key_hex)
        .map_err(|e| anyhow::anyhow!("Invalid key hex: {}", e))?;
    let nonce_bytes = hex::decode(&nonce_hex)
        .map_err(|e| anyhow::anyhow!("Invalid nonce hex: {}", e))?;

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

#[frb(sync)]
pub fn aes_gcm_decrypt(encrypted_base64: String, key_hex: String, nonce_hex: String) -> Result<Vec<u8>> {
    let key_bytes = hex::decode(&key_hex)
        .map_err(|e| anyhow::anyhow!("Invalid key hex: {}", e))?;
    let nonce_bytes = hex::decode(&nonce_hex)
        .map_err(|e| anyhow::anyhow!("Invalid nonce hex: {}", e))?;
    let ciphertext = general_purpose::STANDARD.decode(&encrypted_base64)
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
        },
        16 => {
            type Aes256Gcm16 = AesGcm<Aes256, U16>;
            let cipher = Aes256Gcm16::new_from_slice(&key_bytes)
                .map_err(|e| anyhow::anyhow!("Failed to create cipher: {}", e))?;
            let nonce = GenericArray::from_slice(&nonce_bytes);
            cipher
                .decrypt(nonce, ciphertext.as_ref())
                .map_err(|e| anyhow::anyhow!("Decryption failed (16-byte nonce): {}", e))?
        },
        _ => {
            return Err(anyhow::anyhow!(
                "Nonce must be either 12 bytes (standard) or 16 bytes (Android/Amethyst). Got {} bytes",
                nonce_bytes.len()
            ));
        }
    };

    Ok(plaintext)
}

#[frb(sync)]
pub fn sha256_hash(data: Vec<u8>) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let result = hasher.finalize();
    hex::encode(result)
}
