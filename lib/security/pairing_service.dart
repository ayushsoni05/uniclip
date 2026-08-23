import 'dart:convert';
import 'crypto_service.dart';
import 'key_manager.dart';
import '../data/models/paired_device.dart';

/// Represents the data exchanged during the pairing process.
class PairingInfo {
  final String deviceId;
  final String deviceName;
  final String sharedSecret;
  final int port;
  final String ipAddress;

  PairingInfo({
    required this.deviceId,
    required this.deviceName,
    required this.sharedSecret,
    required this.port,
    required this.ipAddress,
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'shared_secret': sharedSecret,
        'port': port,
        'ip_address': ipAddress,
      };

  factory PairingInfo.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('device_id') || 
        !json.containsKey('device_name') || 
        !json.containsKey('shared_secret') || 
        !json.containsKey('port') || 
        !json.containsKey('ip_address')) {
      throw const FormatException('Missing fields in Pairing Payload JSON');
    }
    
    return PairingInfo(
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String,
      sharedSecret: json['shared_secret'] as String,
      port: json['port'] as int,
      ipAddress: json['ip_address'] as String,
    );
  }
}

/// Service to handle device pairing and secure key exchange.
class PairingService {
  final CryptoService _cryptoService;
  final KeyManager _keyManager;

  PairingService(this._cryptoService, this._keyManager);

  /// Creates a JSON payload containing device info and a randomly generated shared secret.
  /// This string can be encoded into a QR code.
  String generatePairingPayload(String deviceId, String deviceName, int port, String ipAddress) {
    // Generate a random 32-byte shared secret
    final sharedSecretBytes = _cryptoService.generateRandomBytes(32);
    final sharedSecret = base64Encode(sharedSecretBytes);

    final info = PairingInfo(
      deviceId: deviceId,
      deviceName: deviceName,
      sharedSecret: sharedSecret,
      port: port,
      ipAddress: ipAddress,
    );

    return jsonEncode(info.toJson());
  }

  /// Parses the JSON scanned from a QR code back into a [PairingInfo] object.
  PairingInfo parsePairingPayload(String qrData) {
    try {
      final decoded = jsonDecode(qrData) as Map<String, dynamic>;
      return PairingInfo.fromJson(decoded);
    } catch (e) {
      throw Exception('Invalid pairing QR data: $e');
    }
  }

  /// Completes the pairing process by deriving a secure key from the shared secret,
  /// storing it, and creating a [PairedDevice] record.
  Future<PairedDevice> completePairing(PairingInfo info) async {
    try {
      // Generate salt and derive an encryption key from the shared secret
      final salt = _keyManager.generateSalt();
      final key = _keyManager.deriveKey(info.sharedSecret, salt);
      
      // Store the derived key securely
      await _keyManager.storeKey(info.deviceId, key);

      // Create and return the paired device entity
      final device = PairedDevice(
        deviceId: info.deviceId,
        deviceName: info.deviceName,
        pairedAt: DateTime.now(),
        lastSeen: DateTime.now(),
        isActive: true,
        ipAddress: info.ipAddress,
        port: info.port,
      );

      // NOTE: Additional steps to save `device` to the local database 
      // (e.g., using a repository/DAO) should be handled by the caller or injected repository.

      return device;
    } catch (e) {
      throw Exception('Failed to complete pairing: $e');
    }
  }
}
