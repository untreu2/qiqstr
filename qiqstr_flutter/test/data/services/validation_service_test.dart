import 'package:flutter_test/flutter_test.dart';

import '../../../lib/data/services/validation_service.dart';

void main() {
  final validation = ValidationService.instance;
  const publicKey =
      '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798';

  test('accepts a full-width hexadecimal public and private key', () {
    expect(validation.validatePublicKeyHex(publicKey).isSuccess, isTrue);
    expect(validation.validatePrivateKeyHex(publicKey).isSuccess, isTrue);
    expect(validation.validateNpub(publicKey).isSuccess, isTrue);
  });

  test('rejects zero and out-of-range private keys', () {
    expect(validation.validatePrivateKeyHex('0' * 64).isError, isTrue);
    expect(validation.validatePrivateKeyHex('f' * 64).isError, isTrue);
    expect(validation.validatePrivateKeyHex('g' * 64).isError, isTrue);
  });

  test('rejects arbitrary text passed as a public key', () {
    expect(validation.validateNpub('not-a-public-key').isError, isTrue);
  });

  test('requires a host in an HTTP URL', () {
    expect(validation.validateUrl('https:').isError, isTrue);
    expect(validation.validateUrl('https:///image.png').isError, isTrue);
    expect(validation.validateUrl('https://example.com/image.png').isSuccess,
        isTrue);
    expect(validation.validateUrl('').isSuccess, isTrue);
  });
}
