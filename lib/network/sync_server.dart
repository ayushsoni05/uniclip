import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'message_protocol.dart';
import '../security/auth_service.dart';

/// Callback type for received clipboard data.
typedef ClipboardReceivedCallback = void Function(
    String encryptedPayload, String senderId, String senderName, String? contentHash);

/// Callback type for pairing handshake.
typedef PairingHandshakeCallback = Future<bool> Function({
  required String sourceDeviceId,
  required String sourceDeviceName,
  required String sourceIpAddress,
  required int sourcePort,
  required String sharedSecret,
  required String salt,
  required int timestamp,
});

/// Callback to check if a device is paired.
typedef PairedDeviceChecker = bool Function(String deviceId);

/// Callback to retrieve a stored key for HMAC verification.
typedef KeyRetriever = Future<List<int>?> Function(String deviceId);

/// Callback for pairing confirmation UI.
typedef PairingConfirmationCallback = Future<bool> Function(
    String deviceName, String deviceId, String ipAddress);

class SyncServer {
  HttpServer? _server;
  final int port;
  final String localDeviceId;
  final String localDeviceName;
  final PairedDeviceChecker isDevicePaired;
  final ClipboardReceivedCallback onClipboardReceived;
  final PairingHandshakeCallback? onPairingHandshakeReceived;
  final KeyRetriever? getKeyForDevice;
  final PairingConfirmationCallback? onPairingConfirmation;

  final AuthService _authService = AuthService();
  final Map<String, WebSocket> _activeConnections = {};

  SyncServer({
    required this.port,
    required this.localDeviceId,
    required this.localDeviceName,
    required this.isDevicePaired,
    required this.onClipboardReceived,
    this.onPairingHandshakeReceived,
    this.getKeyForDevice,
    this.onPairingConfirmation,
  });

  Future<void> start() async {
    try {
      _server = await HttpServer.bind('0.0.0.0', port);
      debugPrint('Sync Server listening on port ${_server?.port}');

      _server?.listen((HttpRequest request) async {
        // Handle CORS
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        // Handle Two-Way Pairing Handshake HTTP Endpoint
        if (request.uri.path == '/api/pair' && request.method == 'POST') {
          await _handlePairingEndpoint(request);
          return;
        }

        // Handle WebSocket Upgrade
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          try {
            final socket = await WebSocketTransformer.upgrade(request);
            _handleWebSocket(socket);
          } catch (e) {
            debugPrint('WebSocket upgrade error: $e');
          }
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Global Clipboard Server Running')
            ..close();
        }
      });
    } catch (e) {
      debugPrint('Error starting Sync Server: $e');
    }
  }

  Future<void> _handlePairingEndpoint(HttpRequest request) async {
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';

    // Rate limiting
    if (!_authService.checkPairingRateLimit(remoteIp)) {
      request.response
        ..statusCode = HttpStatus.tooManyRequests
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Too many pairing attempts. Try again later.'}))
        ..close();
      return;
    }

    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final sourceDeviceId = data['sourceDeviceId'] as String?;
      final sourceDeviceName = data['sourceDeviceName'] as String?;
      final sourceIp = data['sourceIpAddress'] as String? ?? remoteIp;
      final sourcePort = data['sourcePort'] as int? ?? 9876;
      final sharedSecret = data['sharedSecret'] as String?;
      final salt = data['salt'] as String?;
      final timestamp = data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

      if (sourceDeviceId == null || sourceDeviceName == null || sharedSecret == null || salt == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Missing pairing parameters'}))
          ..close();
        return;
      }

      // Validate timestamp — reject QR codes older than 5 minutes
      if (!AuthService.isTimestampValid(timestamp)) {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Pairing request expired. Generate a new QR code.'}))
          ..close();
        return;
      }

      debugPrint('Received pairing handshake from $sourceDeviceName ($sourceDeviceId) at $sourceIp:$sourcePort');

      // Pairing confirmation (if a UI callback is provided)
      if (onPairingConfirmation != null) {
        final confirmed = await onPairingConfirmation!(sourceDeviceName, sourceDeviceId, sourceIp);
        if (!confirmed) {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'error': 'Pairing request rejected by user'}))
            ..close();
          return;
        }
      }

      if (onPairingHandshakeReceived != null) {
        final paired = await onPairingHandshakeReceived!(
          sourceDeviceId: sourceDeviceId,
          sourceDeviceName: sourceDeviceName,
          sourceIpAddress: sourceIp,
          sourcePort: sourcePort,
          sharedSecret: sharedSecret,
          salt: salt,
          timestamp: timestamp,
        );

        if (paired) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'status': 'paired',
              'deviceId': localDeviceId,
              'deviceName': localDeviceName,
            }))
            ..close();
          return;
        }
      }

      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Failed to complete pairing'}))
        ..close();
    } catch (e) {
      debugPrint('Error handling pairing endpoint: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': e.toString()}))
        ..close();
    }
  }

  Future<void> stop() async {
    for (var ws in _activeConnections.values) {
      await ws.close();
    }
    _activeConnections.clear();
    await _server?.close(force: true);
    _server = null;
    debugPrint('Sync Server stopped');
  }

  void _handleWebSocket(WebSocket socket) {
    String? connectedDeviceId;
    bool authenticated = false;

    socket.listen(
      (data) async {
        try {
          final json = jsonDecode(data as String);
          final message = SyncMessage.fromJson(json);

          // Step 1: First message must be deviceInfo
          if (connectedDeviceId == null) {
            if (message.type == MessageType.deviceInfo) {
              if (isDevicePaired(message.deviceId)) {
                connectedDeviceId = message.deviceId;
                debugPrint('Device ${message.deviceName} (${message.deviceId}) requesting auth...');

                // Send HMAC challenge
                if (getKeyForDevice != null) {
                  final challenge = _authService.generateChallenge(message.deviceId);
                  final challengeMsg = SyncMessage(
                    type: MessageType.authChallenge,
                    deviceId: localDeviceId,
                    deviceName: localDeviceName,
                    encryptedPayload: challenge,
                    timestamp: DateTime.now().millisecondsSinceEpoch,
                  );
                  socket.add(jsonEncode(challengeMsg.toJson()));
                } else {
                  // No key retriever set — auto-authenticate (fallback)
                  authenticated = true;
                  _activeConnections[message.deviceId] = socket;
                  debugPrint('Device ${message.deviceName} connected (no auth required)');
                }
              } else {
                debugPrint('Rejected unauthorized device: ${message.deviceId}');
                socket.close(WebSocketStatus.policyViolation, 'Unauthorized device');
              }
            } else {
              socket.close(WebSocketStatus.policyViolation, 'First message must be deviceInfo');
            }
            return;
          }

          // Step 2: Verify HMAC response before allowing any other messages
          if (!authenticated) {
            if (message.type == MessageType.authResponse) {
              final hmacResponse = message.encryptedPayload;
              if (hmacResponse != null && getKeyForDevice != null) {
                final key = await getKeyForDevice!(connectedDeviceId!);
                if (key != null && _authService.verifyChallenge(connectedDeviceId!, hmacResponse, key)) {
                  authenticated = true;
                  _activeConnections[connectedDeviceId!] = socket;
                  debugPrint('Device $connectedDeviceId authenticated successfully via HMAC');
                  
                  // Send auth success
                  final successMsg = SyncMessage(
                    type: MessageType.authSuccess,
                    deviceId: localDeviceId,
                    deviceName: localDeviceName,
                    timestamp: DateTime.now().millisecondsSinceEpoch,
                  );
                  socket.add(jsonEncode(successMsg.toJson()));
                } else {
                  debugPrint('HMAC verification failed for device $connectedDeviceId');
                  socket.close(WebSocketStatus.policyViolation, 'Authentication failed');
                }
              } else {
                socket.close(WebSocketStatus.policyViolation, 'Invalid auth response');
              }
            } else {
              debugPrint('Expected authResponse, got ${message.type}');
              socket.close(WebSocketStatus.policyViolation, 'Expected auth response');
            }
            return;
          }

          // Step 3: Only process messages from authenticated devices
          if (message.deviceId != connectedDeviceId) {
            debugPrint('Spoofed device ID detected. Expected $connectedDeviceId, got ${message.deviceId}');
            socket.close(WebSocketStatus.policyViolation, 'Spoofed device ID');
            return;
          }

          _processMessage(message, socket);
        } catch (e) {
          debugPrint('Error parsing message from client: $e');
        }
      },
      onDone: () {
        if (connectedDeviceId != null) {
          _activeConnections.remove(connectedDeviceId);
          debugPrint('Device $connectedDeviceId disconnected from server');
        }
      },
      onError: (e) {
        debugPrint('WebSocket server error for $connectedDeviceId: $e');
        if (connectedDeviceId != null) {
          _activeConnections.remove(connectedDeviceId);
        }
      },
    );
  }

  void _processMessage(SyncMessage message, WebSocket socket) {
    switch (message.type) {
      case MessageType.clipboardUpdate:
        if (message.encryptedPayload != null) {
          onClipboardReceived(
            message.encryptedPayload!,
            message.deviceId,
            message.deviceName,
            message.contentHash,
          );
        }
        break;
      case MessageType.heartbeat:
        final response = SyncMessage.heartbeat(
          deviceId: localDeviceId,
          deviceName: localDeviceName,
        );
        socket.add(jsonEncode(response.toJson()));
        break;
      default:
        debugPrint('Unhandled message type on server: ${message.type}');
    }
  }

  /// Broadcasts a clipboard update to ALL connected inbound WebSocket clients.
  void broadcastToAll(SyncMessage message) {
    final payload = jsonEncode(message.toJson());
    for (var entry in _activeConnections.entries) {
      try {
        entry.value.add(payload);
        debugPrint('Server broadcast clipboard to ${entry.key}');
      } catch (e) {
        debugPrint('Error broadcasting message to ${entry.key}: $e');
      }
    }
  }

  /// Broadcasts a raw clipboard update to all server-connected peers.
  void broadcastClipboardUpdate(String encryptedPayload, String contentHash) {
    final msg = SyncMessage.clipboardUpdate(
      deviceId: localDeviceId,
      deviceName: localDeviceName,
      encryptedPayload: encryptedPayload,
      contentHash: contentHash,
    );
    broadcastToAll(msg);
  }
}
