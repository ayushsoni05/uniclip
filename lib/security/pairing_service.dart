import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'crypto_service.dart';
import 'key_manager.dart';
import 'auth_service.dart';
import '../data/models/paired_device.dart';

/// Represents the data exchanged during the pairing process.
class PairingInfo {
  final String deviceId;
  final String deviceName;
  final String sharedSecret;
  final String salt;
  final int port;
  final String ipAddress;
  final List<String> candidateIps;
  final int timestamp;

  PairingInfo({
    required this.deviceId,
    required this.deviceName,
    required this.sharedSecret,
    required this.salt,
    required this.port,
    required this.ipAddress,
    this.candidateIps = const [],
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'shared_secret': sharedSecret,
        'salt': salt,
        'port': port,
        'ip_address': ipAddress,
        'candidate_ips': candidateIps,
        'timestamp': timestamp,
      };

  factory PairingInfo.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('device_id') || 
        !json.containsKey('device_name') || 
        !json.containsKey('shared_secret') || 
        !json.containsKey('port') || 
        !json.containsKey('ip_address')) {
      throw const FormatException('Missing fields in Pairing Payload JSON');
    }
    
    final salt = json['salt'] as String? ?? base64Encode(utf8.encode(json['shared_secret'] as String));
    final timestamp = json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final candidateIps = (json['candidate_ips'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return PairingInfo(
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String,
      sharedSecret: json['shared_secret'] as String,
      salt: salt,
      port: json['port'] as int,
      ipAddress: json['ip_address'] as String,
      candidateIps: candidateIps,
      timestamp: timestamp,
    );
  }
}

/// Service to handle device pairing, deterministic key derivation, and multi-IP 2-way network handshake.
class PairingService {
  final CryptoService _cryptoService;
  final KeyManager _keyManager;

  PairingService(this._cryptoService, this._keyManager);

  /// Creates a JSON payload containing device info, shared secret, deterministic salt, and candidate IPs.
  String generatePairingPayload(
    String deviceId,
    String deviceName,
    int port,
    String primaryIp, {
    List<String> candidateIps = const [],
  }) {
    final sharedSecretBytes = _cryptoService.generateRandomBytes(32);
    final sharedSecret = base64Encode(sharedSecretBytes);

    final saltBytes = _keyManager.generateSalt();
    final salt = base64Encode(saltBytes);

    final allIps = {primaryIp, ...candidateIps}.toList();

    final info = PairingInfo(
      deviceId: deviceId,
      deviceName: deviceName,
      sharedSecret: sharedSecret,
      salt: salt,
      port: port,
      ipAddress: primaryIp,
      candidateIps: allIps,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    return jsonEncode(info.toJson());
  }

  /// Parses the JSON scanned from a QR code back into a [PairingInfo] object.
  PairingInfo parsePairingPayload(String qrData) {
    try {
      final decoded = jsonDecode(qrData) as Map<String, dynamic>;
      final info = PairingInfo.fromJson(decoded);

      if (!AuthService.isTimestampValid(info.timestamp)) {
        throw Exception('QR code has expired. Please refresh the QR code on the other device.');
      }

      return info;
    } catch (e) {
      throw Exception('Invalid or expired pairing QR data: $e');
    }
  }

  /// Completes the pairing process by deriving a secure key using the shared secret and salt.
  Future<PairedDevice> completePairing(PairingInfo info, {String? verifiedIp}) async {
    try {
      final saltBytes = base64Decode(info.salt);
      final key = await _keyManager.deriveKeyAsync(info.sharedSecret, saltBytes);
      
      await _keyManager.storeKey(info.deviceId, key);

      final device = PairedDevice(
        deviceId: info.deviceId,
        deviceName: info.deviceName,
        pairedAt: DateTime.now(),
        lastSeen: DateTime.now(),
        isActive: true,
        ipAddress: verifiedIp ?? info.ipAddress,
        port: info.port,
      );

      return device;
    } catch (e) {
      throw Exception('Failed to complete pairing: $e');
    }
  }

  /// Sends a two-way network handshake trying candidate IPs in order.
  /// Returns the verified working IP address upon success.
  Future<String?> sendPairingHandshake({
    required PairingInfo targetInfo,
    required String localDeviceId,
    required String localDeviceName,
    required int localPort,
    required String localIpAddress,
  }) async {
    final targets = {targetInfo.ipAddress, ...targetInfo.candidateIps}.toList();

    for (final ip in targets) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);

        final url = Uri.parse('http://$ip:${targetInfo.port}/api/pair');
        debugPrint('Attempting pairing handshake to $url');

        final request = await client.postUrl(url);
        request.headers.contentType = ContentType.json;

        final body = jsonEncode({
          'sourceDeviceId': localDeviceId,
          'sourceDeviceName': localDeviceName,
          'sourceIpAddress': localIpAddress,
          'sourcePort': localPort,
          'sharedSecret': targetInfo.sharedSecret,
          'salt': targetInfo.salt,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        request.write(body);
        final response = await request.close();

        if (response.statusCode == HttpStatus.ok) {
          debugPrint('Pairing handshake succeeded with target IP: $ip');
          return ip;
        }
      } catch (e) {
        debugPrint('Pairing handshake attempt to $ip failed: $e');
      }
    }

    return null;
  }
}
