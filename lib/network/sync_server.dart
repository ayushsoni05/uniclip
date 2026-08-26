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
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      debugPrint('Sync Server listening on ${InternetAddress.anyIPv4.address}:${_server?.port}');

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

        // Handle Direct HTTP Clipboard Push Endpoint (Zero-Drop Guaranteed Delivery)
        if (request.uri.path == '/api/clipboard' && request.method == 'POST') {
          await _handleDirectClipboardEndpoint(request);
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
            ..statusCode = HttpStatus.ok
            ..write('Global Clipboard Server Running')
            ..close();
        }
      });
    } catch (e) {
      debugPrint('Error starting Sync Server on port $port: $e');
    }
  }

  /// Handles direct HTTP POST /api/clipboard pushes.
  Future<void> _handleDirectClipboardEndpoint(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final senderDeviceId = json['deviceId'] as String? ?? '';
      final senderDeviceName = json['deviceName'] as String? ?? 'Remote Device';
      final encryptedPayload = json['encryptedPayload'] as String?;
      final contentHash = json['contentHash'] as String?;

      if (encryptedPayload != null && encryptedPayload.isNotEmpty) {
        debugPrint('SyncServer: Received direct HTTP clipboard push from $senderDeviceName ($senderDeviceId)');
        onClipboardReceived(encryptedPayload, senderDeviceId, senderDeviceName, contentHash);

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'received'}))
          ..close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'Missing encryptedPayload'}))
        ..close();
    } catch (e) {
      debugPrint('Error handling direct clipboard HTTP endpoint: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': e.toString()}))
        ..close();
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
      final json = jsonDecode(body) as Map<String, dynamic>;

      final sourceDeviceId = json['sourceDeviceId'] as String?;
      final sourceDeviceName = json['sourceDeviceName'] as String?;
      final sourceIpAddress = json['sourceIpAddress'] as String? ?? remoteIp;
      final sourcePort = json['sourcePort'] as int? ?? 9876;
      final sharedSecret = json['sharedSecret'] as String?;
      final salt = json['salt'] as String?;
      final timestamp = json['timestamp'] as int? ?? 0;

      if (sourceDeviceId == null ||
          sourceDeviceName == null ||
          sharedSecret == null ||
          salt == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Missing required pairing fields'}))
          ..close();
        return;
      }

      if (!AuthService.isTimestampValid(timestamp)) {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Pairing handshake expired'}))
          ..close();
        return;
      }

      if (onPairingConfirmation != null) {
        final confirmed = await onPairingConfirmation!(
            sourceDeviceName, sourceDeviceId, sourceIpAddress);
        if (!confirmed) {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'error': 'Pairing rejected by user'}))
            ..close();
          return;
        }
      }

      if (onPairingHandshakeReceived != null) {
        final success = await onPairingHandshakeReceived!(
          sourceDeviceId: sourceDeviceId,
          sourceDeviceName: sourceDeviceName,
          sourceIpAddress: sourceIpAddress,
          sourcePort: sourcePort,
          sharedSecret: sharedSecret,
          salt: salt,
          timestamp: timestamp,
        );

        if (success) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({
              'status': 'paired',
              'targetDeviceId': localDeviceId,
              'targetDeviceName': localDeviceName,
            }))
            ..close();
          debugPrint('Completed 2-way pairing handshake for $sourceDeviceName');
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

    socket.listen(
      (data) async {
        try {
          final json = jsonDecode(data as String);
          final message = SyncMessage.fromJson(json);

          if (message.type == MessageType.deviceInfo) {
            connectedDeviceId = message.deviceId;
            _activeConnections[message.deviceId] = socket;
            debugPrint('Device ${message.deviceName} (${message.deviceId}) connected via WebSocket');

            // Acknowledge connection
            final successMsg = SyncMessage(
              type: MessageType.authSuccess,
              deviceId: localDeviceId,
              deviceName: localDeviceName,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            );
            socket.add(jsonEncode(successMsg.toJson()));
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
          debugPrint('SyncServer: Received clipboard update from ${message.deviceName}');
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
        debugPrint('Unhandled message type: ${message.type}');
    }
  }

  /// Broadcasts a clipboard update to all currently connected WebSocket clients.
  void broadcastClipboardUpdate(String encryptedPayload, String contentHash) {
    if (_activeConnections.isEmpty) {
      return;
    }

    final msg = SyncMessage.clipboardUpdate(
      deviceId: localDeviceId,
      deviceName: localDeviceName,
      encryptedPayload: encryptedPayload,
      contentHash: contentHash,
    );
    final jsonStr = jsonEncode(msg.toJson());

    for (var entry in _activeConnections.entries) {
      try {
        entry.value.add(jsonStr);
        debugPrint('SyncServer: Broadcasted clipboard update to client ${entry.key}');
      } catch (e) {
        debugPrint('SyncServer: Error sending to client ${entry.key}: $e');
      }
    }
  }
}
