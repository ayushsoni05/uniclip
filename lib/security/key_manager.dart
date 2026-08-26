import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final Map<String, List<int>> _memoryCache = {};

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

  /// Stores a key securely using `flutter_secure_storage` + memory cache + prefs backup.
  Future<void> storeKey(String deviceId, List<int> key) async {
    _memoryCache[deviceId] = key;
    final keyString = base64Encode(key);
    try {
      await _storage.write(key: 'key_$deviceId', value: keyString);
    } catch (e) {
      debugPrint('KeyManager: Secure storage write warning: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_key_$deviceId', keyString);
    } catch (_) {}
  }

  /// Retrieves a previously stored key for a given [deviceId].
  Future<List<int>?> getKey(String deviceId) async {
    if (_memoryCache.containsKey(deviceId)) {
      return _memoryCache[deviceId];
    }
    try {
      final keyString = await _storage.read(key: 'key_$deviceId');
      if (keyString != null) {
        final key = base64Decode(keyString);
        _memoryCache[deviceId] = key;
        return key;
      }
    } catch (e) {
      debugPrint('KeyManager: Secure storage read warning: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final backupString = prefs.getString('cached_key_$deviceId');
      if (backupString != null) {
        final key = base64Decode(backupString);
        _memoryCache[deviceId] = key;
        return key;
      }
    } catch (_) {}

    return null;
  }

  /// Deletes the key associated with the given [deviceId].
  Future<void> deleteKey(String deviceId) async {
    _memoryCache.remove(deviceId);
    try {
      await _storage.delete(key: 'key_$deviceId');
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_key_$deviceId');
    } catch (_) {}
  }

  /// Checks whether a key exists for the given [deviceId].
  Future<bool> hasKey(String deviceId) async {
    if (_memoryCache.containsKey(deviceId)) return true;
    return (await getKey(deviceId)) != null;
  }
}
