import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import '../core/constants.dart';

/// Top-level function for background isolate execution of PBKDF2
Uint8List _pbkdf2Compute(Map<String, dynamic> params) {
  final passphrase = params['passphrase'] as String;
  final salt = params['salt'] as Uint8List;
  final iterations = params['iterations'] as int;

  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, iterations, 32));

  return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
}

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

  /// Derives a 256-bit (32-byte) key using PBKDF2-HMAC-SHA256 synchronously.
  List<int> deriveKey(String passphrase, List<int> salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(
        Uint8List.fromList(salt),
        AppConstants.pbkdf2Iterations,
        32,
      ));

    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  /// Derives a 256-bit key in a background isolate to keep UI 60fps smooth.
  Future<List<int>> deriveKeyAsync(String passphrase, List<int> salt) async {
    return compute(_pbkdf2Compute, {
      'passphrase': passphrase,
      'salt': Uint8List.fromList(salt),
      'iterations': AppConstants.pbkdf2Iterations,
    });
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
