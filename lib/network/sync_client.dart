import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'discovery_service.dart';
import 'message_protocol.dart';
import 'sync_server.dart';
import '../security/auth_service.dart';

enum ConnectionStatus { disconnected, connecting, connected, authenticating }

class SyncClient {
  final String localDeviceId;
  final String localDeviceName;
  final ClipboardReceivedCallback onClipboardReceived;

  /// Callback to retrieve the stored AES key for a device (for HMAC auth).
  final KeyRetriever? getKeyForDevice;

  final Map<String, WebSocketChannel> _channels = {};
  final Map<String, ConnectionStatus> _statuses = {};
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, Timer> _heartbeatTimers = {};
  final Map<String, DiscoveredPeer> _peers = {};

  SyncClient({
    required this.localDeviceId,
    required this.localDeviceName,
    required this.onClipboardReceived,
    this.getKeyForDevice,
  });

  void connectToPeer(DiscoveredPeer peer) {
    if (_statuses[peer.deviceId] == ConnectionStatus.connected ||
        _statuses[peer.deviceId] == ConnectionStatus.connecting ||
        _statuses[peer.deviceId] == ConnectionStatus.authenticating) {
      return;
    }
    _peers[peer.deviceId] = peer;
    _statuses[peer.deviceId] = ConnectionStatus.connecting;
    _reconnectAttempts.putIfAbsent(peer.deviceId, () => 0);

    final wsUrl = Uri.parse('ws://${peer.ipAddress}:${peer.port}');
    debugPrint('SyncClient: Connecting to peer ${peer.deviceName} at $wsUrl');

    try {
      final channel = IOWebSocketChannel.connect(wsUrl);
      _channels[peer.deviceId] = channel;

      // Send deviceInfo as first message
      final infoMsg = SyncMessage.deviceInfo(
        deviceId: localDeviceId,
        deviceName: localDeviceName,
      );
      channel.sink.add(jsonEncode(infoMsg.toJson()));
      _statuses[peer.deviceId] = ConnectionStatus.authenticating;

      channel.stream.listen(
        (data) {
          _handleMessage(data as String, peer.deviceId);
        },
        onDone: () => _handleDisconnect(peer.deviceId),
        onError: (e) {
          debugPrint('SyncClient: WebSocket error for ${peer.deviceName}: $e');
          _handleDisconnect(peer.deviceId);
        },
      );
    } catch (e) {
      debugPrint('SyncClient: Error connecting to peer ${peer.deviceName}: $e');
      _handleDisconnect(peer.deviceId);
    }
  }

  void _handleMessage(String data, String peerId) {
    try {
      final json = jsonDecode(data);
      final message = SyncMessage.fromJson(json);

      switch (message.type) {
        case MessageType.authChallenge:
          // Server sent HMAC challenge — respond with signed nonce
          _handleAuthChallenge(message, peerId);
          break;

        case MessageType.authSuccess:
          // Server confirmed authentication
          _statuses[peerId] = ConnectionStatus.connected;
          _reconnectAttempts[peerId] = 0;
          debugPrint('SyncClient: Authenticated and connected to peer $peerId');
          _startHeartbeat(peerId);
          break;

        case MessageType.clipboardUpdate:
          if (message.encryptedPayload != null) {
            debugPrint('SyncClient: Received clipboard update from ${message.deviceName}');
            onClipboardReceived(
              message.encryptedPayload!,
              message.deviceId,
              message.deviceName,
              message.contentHash,
            );
          }
          break;

        case MessageType.heartbeat:
          // Received heartbeat response — connection is alive
          break;

        default:
          debugPrint('SyncClient: Unhandled message type: ${message.type}');
      }
    } catch (e) {
      debugPrint('SyncClient: Error parsing message from server $peerId: $e');
    }
  }

  Future<void> _handleAuthChallenge(SyncMessage message, String peerId) async {
    final challenge = message.encryptedPayload;
    if (challenge == null) {
      debugPrint('SyncClient: Received empty auth challenge from $peerId');
      return;
    }

    if (getKeyForDevice != null) {
      final key = await getKeyForDevice!(peerId);
      if (key != null) {
        final hmacResponse = AuthService.computeHmac(key, challenge);
        final responseMsg = SyncMessage(
          type: MessageType.authResponse,
          deviceId: localDeviceId,
          deviceName: localDeviceName,
          encryptedPayload: hmacResponse,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        _channels[peerId]?.sink.add(jsonEncode(responseMsg.toJson()));
        debugPrint('SyncClient: Sent HMAC auth response to $peerId');
      } else {
        debugPrint('SyncClient: No key found for peer $peerId, cannot authenticate');
      }
    } else {
      // No key retriever — send empty response (server will fallback)
      debugPrint('SyncClient: No key retriever, skipping auth for $peerId');
    }
  }

  void _startHeartbeat(String deviceId) {
    _heartbeatTimers[deviceId]?.cancel();
    _heartbeatTimers[deviceId] = Timer.periodic(const Duration(seconds: 15), (_) {
      final channel = _channels[deviceId];
      if (channel != null && _statuses[deviceId] == ConnectionStatus.connected) {
        final heartbeat = SyncMessage.heartbeat(
          deviceId: localDeviceId,
          deviceName: localDeviceName,
        );
        channel.sink.add(jsonEncode(heartbeat.toJson()));
      }
    });
  }

  void _handleDisconnect(String deviceId) {
    _statuses[deviceId] = ConnectionStatus.disconnected;
    _heartbeatTimers[deviceId]?.cancel();
    _channels.remove(deviceId)?.sink.close();

    final peer = _peers[deviceId];
    if (peer != null) {
      debugPrint('SyncClient: Disconnected from peer ${peer.deviceName}');
      _scheduleReconnect(peer);
    }
  }

  void _scheduleReconnect(DiscoveredPeer peer) {
    final attempts = _reconnectAttempts[peer.deviceId] ?? 0;
    final delaySeconds = min(pow(2, attempts).toInt(), 30);
    _reconnectAttempts[peer.deviceId] = attempts + 1;

    debugPrint('SyncClient: Scheduling reconnect to ${peer.deviceName} in ${delaySeconds}s (Attempt ${attempts + 1})');
    Timer(Duration(seconds: delaySeconds), () {
      if (_peers.containsKey(peer.deviceId)) {
        connectToPeer(peer);
      }
    });
  }

  void sendClipboardUpdate(String encryptedPayload, String contentHash) {
    final msg = SyncMessage.clipboardUpdate(
      deviceId: localDeviceId,
      deviceName: localDeviceName,
      encryptedPayload: encryptedPayload,
      contentHash: contentHash,
    );
    final payload = jsonEncode(msg.toJson());

    // 1. Send via active WebSockets
    _channels.forEach((deviceId, channel) {
      if (_statuses[deviceId] == ConnectionStatus.connected) {
        try {
          channel.sink.add(payload);
          debugPrint('SyncClient: Sent WebSocket clipboard update to $deviceId');
        } catch (e) {
          debugPrint('SyncClient: Error sending WebSocket update to $deviceId: $e');
        }
      }
    });

    // 2. Guaranteed Delivery: Direct HTTP POST /api/clipboard to all known peer IPs
    _peers.forEach((deviceId, peer) {
      _sendDirectHttpClipboardPush(peer, encryptedPayload, contentHash);
    });
  }

  Future<void> _sendDirectHttpClipboardPush(
    DiscoveredPeer peer,
    String encryptedPayload,
    String contentHash,
  ) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);

      final url = Uri.parse('http://${peer.ipAddress}:${peer.port}/api/clipboard');
      final request = await client.postUrl(url);
      request.headers.contentType = ContentType.json;

      final body = jsonEncode({
        'deviceId': localDeviceId,
        'deviceName': localDeviceName,
        'encryptedPayload': encryptedPayload,
        'contentHash': contentHash,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      request.write(body);
      final response = await request.close();
      debugPrint('SyncClient: Direct HTTP push to ${peer.deviceName} -> HTTP ${response.statusCode}');
    } catch (e) {
      debugPrint('SyncClient: Direct HTTP push to ${peer.deviceName} non-fatal error: $e');
    }
  }

  void disconnectFromPeer(String deviceId) {
    _peers.remove(deviceId); // Prevent reconnect
    _heartbeatTimers[deviceId]?.cancel();
    _statuses[deviceId] = ConnectionStatus.disconnected;
    _channels.remove(deviceId)?.sink.close();
    debugPrint('SyncClient: Disconnected from peer $deviceId manually');
  }

  void disconnectAll() {
    final deviceIds = _peers.keys.toList();
    for (var id in deviceIds) {
      disconnectFromPeer(id);
    }
  }
}
