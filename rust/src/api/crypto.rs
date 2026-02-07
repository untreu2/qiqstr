use anyhow::Result;
use flutter_rust_bridge::frb;
use nostr::nips::nip06::FromMnemonic;
use nostr::prelude::*;
use nostr::secp256k1::Message;

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
