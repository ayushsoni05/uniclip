import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// Exception thrown for any cryptographic errors.
class CryptoException implements Exception {
  final String message;
  CryptoException(this.message);

  @override
  String toString() => 'CryptoException: $message';
}

/// Payload containing the Initialization Vector, Ciphertext, and Authentication Tag.
class CryptoPayload {
  final String iv;
  final String ciphertext;
  final String tag;

  CryptoPayload({
    required this.iv,
    required this.ciphertext,
    required this.tag,
  });

  Map<String, dynamic> toJson() => {
        'iv': iv,
        'ciphertext': ciphertext,
        'tag': tag,
      };

  factory CryptoPayload.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('iv') || !json.containsKey('ciphertext') || !json.containsKey('tag')) {
      throw CryptoException('Invalid JSON payload for CryptoPayload');
    }
    return CryptoPayload(
      iv: json['iv'] as String,
      ciphertext: json['ciphertext'] as String,
      tag: json['tag'] as String,
    );
  }
}

/// Service providing AES-256-GCM encryption and decryption.
class CryptoService {
  final FortunaRandom _secureRandom;

  CryptoService() : _secureRandom = FortunaRandom() {
    final seed = _generateSeed();
    _secureRandom.seed(KeyParameter(seed));
  }

  Uint8List _generateSeed() {
    final random = Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < seed.length; i++) {
      seed[i] = random.nextInt(256);
    }
    return seed;
  }

  /// Generates a random sequence of bytes of the specified [length].
  Uint8List generateRandomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextUint8();
    }
    return bytes;
  }

  /// Encrypts the given [plaintext] using AES-256-GCM with the provided [key].
  CryptoPayload encrypt(String plaintext, List<int> key) {
    try {
      if (key.length != 32) {
        throw CryptoException('Invalid key length. AES-256 requires a 32-byte key.');
      }
      // Generate 96-bit (12-byte) IV/nonce for GCM
      final iv = generateRandomBytes(12);
      final keyBytes = Uint8List.fromList(key);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(keyBytes), 128, iv, Uint8List(0)));

      final plainBytes = utf8.encode(plaintext);
      final cipherText = cipher.process(Uint8List.fromList(plainBytes));

      // In pointycastle, GCM appends the MAC (tag) to the end of the ciphertext.
      // 128-bit MAC tag is 16 bytes.
      final actualCipherText = cipherText.sublist(0, cipherText.length - 16);
      final tag = cipherText.sublist(cipherText.length - 16);

      return CryptoPayload(
        iv: base64Encode(iv),
        ciphertext: base64Encode(actualCipherText),
        tag: base64Encode(tag),
      );
    } catch (e) {
      throw CryptoException('Encryption failed: $e');
    }
  }

  /// Decrypts the given [payload] using AES-256-GCM with the provided [key].
  String decrypt(CryptoPayload payload, List<int> key) {
    try {
      if (key.length != 32) {
        throw CryptoException('Invalid key length. AES-256 requires a 32-byte key.');
      }
      final iv = base64Decode(payload.iv);
      final ciphertext = base64Decode(payload.ciphertext);
      final tag = base64Decode(payload.tag);
      final keyBytes = Uint8List.fromList(key);

      // Reassemble ciphertext + tag for pointycastle decryption
      final cipherTextWithTag = Uint8List(ciphertext.length + tag.length);
      cipherTextWithTag.setAll(0, ciphertext);
      cipherTextWithTag.setAll(ciphertext.length, tag);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(keyBytes), 128, iv, Uint8List(0)));

      final plainBytes = cipher.process(cipherTextWithTag);
      return utf8.decode(plainBytes);
    } catch (e) {
      throw CryptoException('Decryption failed: $e');
    }
  }
}
