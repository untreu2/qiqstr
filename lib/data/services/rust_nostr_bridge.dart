import 'dart:convert';
import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../src/rust/api/nip19.dart' as rust_nip19;

class Bip340 {
  static String getPublicKey(String privateKey) {
    return rust_crypto.getPublicKey(privateKeyHex: privateKey);
  }

  static String sign(String eventId, String privateKey) {
    return rust_crypto.signEventId(
        eventIdHex: eventId, privateKeyHex: privateKey);
  }

  static ({String? privateKey, String publicKey}) generatePrivateKey() {
    final (privKey, pubKey) = rust_crypto.generateKeypair();
    return (privateKey: privKey, publicKey: pubKey);
  }
}

class Nip19 {
  static String decode(String bech32) {
    return rust_nip19.nip19Decode(bech32Str: bech32);
  }

  static String encodePubKey(String hex) {
    return rust_nip19.nip19EncodePubkey(pubkeyHex: hex);
  }

  static String encodePrivateKey(String hex) {
    return rust_nip19.nip19EncodePrivkey(privkeyHex: hex);
  }
}

String encodeBasicBech32(String hex, String prefix) {
  return rust_nip19.encodeBasicBech32(hexStr: hex, prefix: prefix);
}

String decodeBasicBech32(String bech32, [String? prefix]) {
  return rust_nip19.nip19Decode(bech32Str: bech32);
}

Map<String, dynamic> decodeTlvBech32Full(String bech32, [String? prefix]) {
  final jsonStr = rust_nip19.nip19DecodeTlv(bech32Str: bech32);
  return jsonDecode(jsonStr) as Map<String, dynamic>;
}

class Bip39Bridge {
  static String generateMnemonic() {
    return rust_crypto.generateMnemonic();
  }

  static bool validateMnemonic(String mnemonic) {
    return rust_crypto.validateMnemonic(mnemonic: mnemonic);
  }

  static String mnemonicToPrivateKey(String mnemonic) {
    return rust_crypto.mnemonicToPrivateKey(mnemonic: mnemonic);
  }
}

class EventVerifierBridge {
  static bool verify(String eventJson) {
    return rust_crypto.verifyEvent(eventJson: eventJson);
  }
}
