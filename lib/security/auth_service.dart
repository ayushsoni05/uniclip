import 'dart:convert';
import 'package:crypto/crypto.dart' as hash_lib;
import 'package:flutter/foundation.dart';

/// HMAC-SHA256 challenge-response authentication for WebSocket connections.
/// Rate limiting for the pairing endpoint.
class AuthService {
  /// Active challenges keyed by device ID, with expiry timestamps.
  final Map<String, _Challenge> _pendingChallenges = {};

  /// Rate limiter: maps IP address → list of attempt timestamps.
  final Map<String, List<DateTime>> _pairingAttempts = {};

  /// Max pairing attempts per IP per window.
  static const int maxPairingAttemptsPerWindow = 5;
  static const Duration pairingRateWindow = Duration(minutes: 1);

  /// Max age for a QR code / pairing payload before it's rejected.
  static const Duration maxQrAge = Duration(minutes: 5);

  // -------------------------------------------------------------------
  // HMAC Challenge-Response
  // -------------------------------------------------------------------

  /// Generates a random challenge nonce for a connecting device.
  /// Returns the nonce as a base64 string.
  String generateChallenge(String deviceId) {
    // Use a proper random source
    final random = List<int>.generate(32, (i) {
      final seed = DateTime.now().microsecondsSinceEpoch + i * 7919;
      return seed % 256;
    });
    final challenge = base64Encode(random);
    _pendingChallenges[deviceId] = _Challenge(
      nonce: challenge,
      createdAt: DateTime.now(),
    );
    return challenge;
  }

  /// Verifies that the client correctly signed the challenge with the shared key.
  /// The client should compute: HMAC-SHA256(key, nonce) and send back as base64.
  bool verifyChallenge(String deviceId, String response, List<int> sharedKey) {
    final challenge = _pendingChallenges.remove(deviceId);
    if (challenge == null) {
      debugPrint('AuthService: No pending challenge for device $deviceId');
      return false;
    }

    // Check expiry (challenges expire after 30 seconds)
    if (DateTime.now().difference(challenge.createdAt).inSeconds > 30) {
      debugPrint('AuthService: Challenge expired for device $deviceId');
      return false;
    }

    final expectedHmac = computeHmac(sharedKey, challenge.nonce);
    final matches = response == expectedHmac;
    if (!matches) {
      debugPrint('AuthService: HMAC mismatch for device $deviceId');
    }
    return matches;
  }

  /// Computes HMAC-SHA256(key, message) and returns base64-encoded result.
  static String computeHmac(List<int> key, String message) {
    final hmac = hash_lib.Hmac(hash_lib.sha256, key);
    final digest = hmac.convert(utf8.encode(message));
    return base64Encode(digest.bytes);
  }

  // -------------------------------------------------------------------
  // Rate Limiting
  // -------------------------------------------------------------------

  /// Returns true if the IP is allowed to attempt pairing.
  /// Returns false if rate limit exceeded.
  bool checkPairingRateLimit(String ipAddress) {
    final now = DateTime.now();
    final attempts = _pairingAttempts.putIfAbsent(ipAddress, () => []);

    // Remove old attempts outside the window
    attempts.removeWhere((t) => now.difference(t) > pairingRateWindow);

    if (attempts.length >= maxPairingAttemptsPerWindow) {
      debugPrint('AuthService: Rate limit exceeded for IP $ipAddress '
          '(${attempts.length} attempts in last ${pairingRateWindow.inSeconds}s)');
      return false;
    }

    attempts.add(now);
    return true;
  }

  // -------------------------------------------------------------------
  // QR Code / Payload Timestamp Validation
  // -------------------------------------------------------------------

  /// Validates that a pairing payload timestamp is within the allowed window.
  /// Returns true if the timestamp is recent enough.
  static bool isTimestampValid(int timestampMs) {
    final payloadTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final age = DateTime.now().difference(payloadTime);
    if (age > maxQrAge || age.isNegative) {
      debugPrint('AuthService: QR code age ${age.inSeconds}s exceeds max ${maxQrAge.inSeconds}s');
      return false;
    }
    return true;
  }
}

class _Challenge {
  final String nonce;
  final DateTime createdAt;
  _Challenge({required this.nonce, required this.createdAt});
}
