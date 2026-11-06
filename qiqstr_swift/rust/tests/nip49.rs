use qiqstr_core::api::crypto::{ncryptsec_decrypt, ncryptsec_encrypt};

#[test]
fn spec_vector_decrypts() {
    let hex = ncryptsec_decrypt("ncryptsec1qgg9947rlpvqu76pj5ecreduf9jxhselq2nae2kghhvd5g7dgjtcxfqtd67p9m0w57lspw8gsq6yphnm8623nsl8xn9j4jdzz84zm3frztj3z7s35vpzmqf6ksu8r89qk5z2zxfmu5gv8th8wclt0h4p".to_string(), "nostr".to_string()).unwrap();
    assert_eq!(hex, "3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683");
}

#[test]
fn roundtrip() {
    let key = "3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683".to_string();
    let enc = ncryptsec_encrypt(key.clone(), "correct horse".to_string()).unwrap();
    assert!(enc.starts_with("ncryptsec1"));
    assert_eq!(ncryptsec_decrypt(enc.clone(), "correct horse".to_string()).unwrap(), key);
    assert!(ncryptsec_decrypt(enc, "wrong".to_string()).is_err());
}
