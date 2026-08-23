import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

// Ensure this path matches your project structure, or adjust as needed.
// import '../core/constants.dart';

/// Key manager for securely deriving, storing, retrieving, and deleting keys.
class KeyManager {
  final FlutterSecureStorage _storage;

  KeyManager([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  /// Generates a random 32-byte salt using FortunaRandom seeded securely.
  Uint8List generateSalt() {
    final random = FortunaRandom();
    final seed = _generateSeed();
    random.seed(KeyParameter(seed));
    final salt = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      salt[i] = random.nextUint8();
    }
    return salt;
  }

  Uint8List _generateSeed() {
    final random = Random.secure();
    final seed = Uint8List(32);
    for (var i = 0; i < seed.length; i++) {
      seed[i] = random.nextInt(256);
    }
    return seed;
  }

  /// Derives a 256-bit (32-byte) key using PBKDF2-HMAC-SHA256 with 600,000 iterations.
  List<int> deriveKey(String passphrase, List<int> salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(Uint8List.fromList(salt), 600000, 32));
    
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  /// Stores a key securely using `flutter_secure_storage`.
  Future<void> storeKey(String deviceId, List<int> key) async {
    final keyString = base64Encode(key);
    await _storage.write(key: 'key_$deviceId', value: keyString);
  }

  /// Retrieves a previously stored key for a given [deviceId].
  Future<List<int>?> getKey(String deviceId) async {
    final keyString = await _storage.read(key: 'key_$deviceId');
    if (keyString != null) {
      return base64Decode(keyString);
    }
    return null;
  }

  /// Deletes the key associated with the given [deviceId].
  Future<void> deleteKey(String deviceId) async {
    await _storage.delete(key: 'key_$deviceId');
  }

  /// Checks whether a key exists for the given [deviceId].
  Future<bool> hasKey(String deviceId) async {
    return await _storage.containsKey(key: 'key_$deviceId');
  }
}
