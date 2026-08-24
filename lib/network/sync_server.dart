import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'message_protocol.dart';

typedef PairedDeviceChecker = bool Function(String deviceId);
typedef ClipboardReceivedCallback = void Function(
    String encryptedPayload, String senderId, String senderName, String? contentHash);
typedef PairingHandshakeCallback = Future<bool> Function({
  required String sourceDeviceId,
  required String sourceDeviceName,
  required String sourceIpAddress,
  required int sourcePort,
  required String sharedSecret,
  required String salt,
});

class SyncServer {
  HttpServer? _server;
  final int port;
  final String localDeviceId;
  final String localDeviceName;
  final PairedDeviceChecker isDevicePaired;
  final ClipboardReceivedCallback onClipboardReceived;
  final PairingHandshakeCallback? onPairingHandshakeReceived;

  final Map<String, WebSocket> _activeConnections = {};

  SyncServer({
    required this.port,
    required this.localDeviceId,
    required this.localDeviceName,
    required this.isDevicePaired,
    required this.onClipboardReceived,
    this.onPairingHandshakeReceived,
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
    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final sourceDeviceId = data['sourceDeviceId'] as String?;
      final sourceDeviceName = data['sourceDeviceName'] as String?;
      final sourceIp = data['sourceIpAddress'] as String? ?? request.connectionInfo?.remoteAddress.address ?? '127.0.0.1';
      final sourcePort = data['sourcePort'] as int? ?? 9876;
      final sharedSecret = data['sharedSecret'] as String?;
      final salt = data['salt'] as String?;

      if (sourceDeviceId == null || sourceDeviceName == null || sharedSecret == null || salt == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'error': 'Missing pairing parameters'}))
          ..close();
        return;
      }

      debugPrint('Received pairing handshake from $sourceDeviceName ($sourceDeviceId) at $sourceIp:$sourcePort');

      if (onPairingHandshakeReceived != null) {
        final paired = await onPairingHandshakeReceived!(
          sourceDeviceId: sourceDeviceId,
          sourceDeviceName: sourceDeviceName,
          sourceIpAddress: sourceIp,
          sourcePort: sourcePort,
          sharedSecret: sharedSecret,
          salt: salt,
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
        ..write(jsonEncode({'error': 'Failed to complete pairing'}))
        ..close();
    } catch (e) {
      debugPrint('Error handling pairing endpoint: $e');
      request.response
        ..statusCode = HttpStatus.internalServerError
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
      (data) {
        try {
          final json = jsonDecode(data as String);
          final message = SyncMessage.fromJson(json);

          if (connectedDeviceId == null) {
            if (message.type == MessageType.deviceInfo) {
              if (isDevicePaired(message.deviceId)) {
                connectedDeviceId = message.deviceId;
                _activeConnections[message.deviceId] = socket;
                debugPrint('Device ${message.deviceName} (${message.deviceId}) connected to server');
              } else {
                debugPrint('Rejected unauthorized device: ${message.deviceId}');
                socket.close(WebSocketStatus.policyViolation, 'Unauthorized device');
              }
            } else {
              socket.close(WebSocketStatus.policyViolation, 'First message must be deviceInfo');
            }
            return;
          }

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

  void broadcastToAll(SyncMessage message) {
    final payload = jsonEncode(message.toJson());
    for (var ws in _activeConnections.values) {
      try {
        ws.add(payload);
      } catch (e) {
        debugPrint('Error broadcasting message: $e');
      }
    }
  }
}
