import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_clipboard/security/crypto_service.dart';
import 'package:global_clipboard/security/key_manager.dart';

void main() {
  group('CryptoService Tests', () {
    late CryptoService cryptoService;
    late Uint8List testKey;

    setUp(() {
      cryptoService = CryptoService();
      testKey = cryptoService.generateRandomBytes(32);
    });

    test('generateRandomBytes returns correct length', () {
      final bytes = cryptoService.generateRandomBytes(16);
      expect(bytes.length, equals(16));
    });

    test('AES-256-GCM encrypt and decrypt round trip preserves text', () {
      const originalText = 'Hello from iOS Universal Clipboard replica! 🚀 12345';
      final payload = cryptoService.encrypt(originalText, testKey);

      expect(payload.iv.isNotEmpty, isTrue);
      expect(payload.ciphertext.isNotEmpty, isTrue);
      expect(payload.tag.isNotEmpty, isTrue);

      final decrypted = cryptoService.decrypt(payload, testKey);
      expect(decrypted, equals(originalText));
    });

    test('CryptoPayload JSON serialization round trip', () {
      final payload = CryptoPayload(
        iv: 'iv_test_base64',
        ciphertext: 'ciphertext_test_base64',
        tag: 'tag_test_base64',
      );

      final json = payload.toJson();
      final fromJson = CryptoPayload.fromJson(json);

      expect(fromJson.iv, equals(payload.iv));
      expect(fromJson.ciphertext, equals(payload.ciphertext));
      expect(fromJson.tag, equals(payload.tag));
    });
  });

  group('KeyManager Tests', () {
    late KeyManager keyManager;

    setUp(() {
      keyManager = KeyManager();
    });

    test('generateSalt returns 32 bytes', () {
      final salt = keyManager.generateSalt();
      expect(salt.length, equals(32));
    });

    test('deriveKey produces consistent 32-byte key for same passphrase and salt', () {
      final salt = keyManager.generateSalt();
      const passphrase = 'MySecretPassphrase123!';

      final key1 = keyManager.deriveKey(passphrase, salt);
      final key2 = keyManager.deriveKey(passphrase, salt);

      expect(key1.length, equals(32));
      expect(key1, equals(key2));
    });
  });
}
