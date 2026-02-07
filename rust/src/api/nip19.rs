use anyhow::Result;
use flutter_rust_bridge::frb;
use nostr::prelude::*;

#[frb(sync)]
pub fn nip19_decode(bech32_str: String) -> Result<String> {
    if bech32_str.starts_with("npub1") {
        let pk = PublicKey::from_bech32(&bech32_str)?;
        Ok(pk.to_hex())
    } else if bech32_str.starts_with("nsec1") {
        let sk = SecretKey::from_bech32(&bech32_str)?;
        Ok(sk.to_secret_hex())
    } else if bech32_str.starts_with("note1") {
        let id = EventId::from_bech32(&bech32_str)?;
        Ok(id.to_hex())
    } else if bech32_str.starts_with("nprofile1") {
        let nprofile = Nip19Profile::from_bech32(&bech32_str)?;
        Ok(nprofile.public_key.to_hex())
    } else if bech32_str.starts_with("nevent1") {
        let nevent = Nip19Event::from_bech32(&bech32_str)?;
        Ok(nevent.event_id.to_hex())
    } else if bech32_str.starts_with("naddr1") {
        let coord = Coordinate::from_bech32(&bech32_str)?;
        Ok(serde_json::json!({
            "kind": coord.kind.as_u16(),
            "pubkey": coord.public_key.to_hex(),
            "identifier": coord.identifier,
        })
        .to_string())
    } else {
        anyhow::bail!("Unknown bech32 prefix: {}", bech32_str)
    }
}

#[frb(sync)]
pub fn nip19_decode_tlv(bech32_str: String) -> Result<String> {
    if bech32_str.starts_with("nprofile1") {
        let nprofile = Nip19Profile::from_bech32(&bech32_str)?;
        let relays: Vec<String> = nprofile.relays.into_iter().map(|r| r.to_string()).collect();
        Ok(serde_json::json!({
            "type": "nprofile",
            "pubkey": nprofile.public_key.to_hex(),
            "relays": relays,
        })
        .to_string())
    } else if bech32_str.starts_with("nevent1") {
        let nevent = Nip19Event::from_bech32(&bech32_str)?;
        let relays: Vec<String> = nevent.relays.into_iter().map(|r| r.to_string()).collect();
        Ok(serde_json::json!({
            "type": "nevent",
            "id": nevent.event_id.to_hex(),
            "relays": relays,
            "author": nevent.author.map(|a| a.to_hex()),
        })
        .to_string())
    } else if bech32_str.starts_with("naddr1") {
        let coord = Coordinate::from_bech32(&bech32_str)?;
        Ok(serde_json::json!({
            "type": "naddr",
            "kind": coord.kind.as_u16(),
            "pubkey": coord.public_key.to_hex(),
            "identifier": coord.identifier,
            "relays": [],
        })
        .to_string())
    } else {
        nip19_decode(bech32_str)
    }
}

#[frb(sync)]
pub fn nip19_encode_pubkey(pubkey_hex: String) -> Result<String> {
    let pk = PublicKey::parse(&pubkey_hex)?;
    Ok(pk.to_bech32()?)
}

#[frb(sync)]
pub fn nip19_encode_privkey(privkey_hex: String) -> Result<String> {
    let sk = SecretKey::parse(&privkey_hex)?;
    Ok(sk.to_bech32()?)
}

#[frb(sync)]
pub fn nip19_encode_note(event_id_hex: String) -> Result<String> {
    let id = EventId::parse(&event_id_hex)?;
    Ok(id.to_bech32()?)
}

#[frb(sync)]
pub fn encode_basic_bech32(hex_str: String, prefix: String) -> Result<String> {
    match prefix.as_str() {
        "npub" => nip19_encode_pubkey(hex_str),
        "nsec" => nip19_encode_privkey(hex_str),
        "note" => nip19_encode_note(hex_str),
        _ => anyhow::bail!("Unsupported bech32 prefix: {}", prefix),
    }
}
