import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'message_protocol.dart';

typedef PairedDeviceChecker = bool Function(String deviceId);
typedef ClipboardReceivedCallback = void Function(
    String encryptedPayload, String senderId, String senderName, String? contentHash);

class SyncServer {
  HttpServer? _server;
  final int port;
  final String localDeviceId;
  final String localDeviceName;
  final PairedDeviceChecker isDevicePaired;
  final ClipboardReceivedCallback onClipboardReceived;

  final Map<String, WebSocket> _activeConnections = {};

  SyncServer({
    required this.port,
    required this.localDeviceId,
    required this.localDeviceName,
    required this.isDevicePaired,
    required this.onClipboardReceived,
  });

  Future<void> start() async {
    try {
      _server = await HttpServer.bind('0.0.0.0', port);
      debugPrint('Sync Server listening on port ${_server?.port}');

      _server?.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          WebSocketTransformer.upgrade(request).then(_handleWebSocket).catchError((e) {
            debugPrint('WebSocket upgrade error: $e');
          });
        } else {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..close();
        }
      });
    } catch (e) {
      debugPrint('Error starting Sync Server: $e');
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
             message.contentHash
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
