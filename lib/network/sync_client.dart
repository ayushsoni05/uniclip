import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'discovery_service.dart';
import 'message_protocol.dart';
import 'sync_server.dart'; // for ClipboardReceivedCallback

enum ConnectionStatus { disconnected, connecting, connected }

class SyncClient {
  final String localDeviceId;
  final String localDeviceName;
  final ClipboardReceivedCallback onClipboardReceived;

  final Map<String, WebSocketChannel> _channels = {};
  final Map<String, ConnectionStatus> _statuses = {};
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, Timer> _heartbeatTimers = {};
  final Map<String, DiscoveredPeer> _peers = {};

  SyncClient({
    required this.localDeviceId,
    required this.localDeviceName,
    required this.onClipboardReceived,
  });

  void connectToPeer(DiscoveredPeer peer) {
    if (_statuses[peer.deviceId] == ConnectionStatus.connected ||
        _statuses[peer.deviceId] == ConnectionStatus.connecting) {
      return;
    }
    _peers[peer.deviceId] = peer;
    _statuses[peer.deviceId] = ConnectionStatus.connecting;
    _reconnectAttempts.putIfAbsent(peer.deviceId, () => 0);

    final wsUrl = Uri.parse('ws://${peer.ipAddress}:${peer.port}');
    debugPrint('Connecting to peer ${peer.deviceName} at $wsUrl');

    try {
      final channel = IOWebSocketChannel.connect(wsUrl);
      _channels[peer.deviceId] = channel;

      // Send deviceInfo as first message
      final infoMsg = SyncMessage.deviceInfo(
        deviceId: localDeviceId,
        deviceName: localDeviceName,
      );
      channel.sink.add(jsonEncode(infoMsg.toJson()));

      channel.stream.listen(
        (data) {
          if (_statuses[peer.deviceId] != ConnectionStatus.connected) {
             _statuses[peer.deviceId] = ConnectionStatus.connected;
             _reconnectAttempts[peer.deviceId] = 0;
             debugPrint('Connected to peer ${peer.deviceName}');
             _startHeartbeat(peer.deviceId);
          }
          _handleMessage(data as String, peer.deviceId);
        },
        onDone: () => _handleDisconnect(peer.deviceId),
        onError: (e) {
          debugPrint('WebSocket client error for ${peer.deviceName}: $e');
          _handleDisconnect(peer.deviceId);
        },
      );
    } catch (e) {
      debugPrint('Error connecting to peer ${peer.deviceName}: $e');
      _handleDisconnect(peer.deviceId);
    }
  }

  void _handleMessage(String data, String peerId) {
    try {
      final json = jsonDecode(data);
      final message = SyncMessage.fromJson(json);

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
          // Received heartbeat response
          break;
        default:
          debugPrint('Unhandled message type on client: ${message.type}');
      }
    } catch (e) {
      debugPrint('Error parsing message from server $peerId: $e');
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
      debugPrint('Disconnected from peer ${peer.deviceName}');
      _scheduleReconnect(peer);
    }
  }

  void _scheduleReconnect(DiscoveredPeer peer) {
    final attempts = _reconnectAttempts[peer.deviceId] ?? 0;
    final delaySeconds = min(pow(2, attempts).toInt(), 30);
    _reconnectAttempts[peer.deviceId] = attempts + 1;

    debugPrint('Scheduling reconnect to ${peer.deviceName} in $delaySeconds seconds (Attempt ${attempts + 1})');
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

    _channels.forEach((deviceId, channel) {
      if (_statuses[deviceId] == ConnectionStatus.connected) {
        try {
          channel.sink.add(payload);
        } catch (e) {
          debugPrint('Error sending update to $deviceId: $e');
        }
      }
    });
  }

  void disconnectFromPeer(String deviceId) {
    _peers.remove(deviceId); // Prevent reconnect
    _heartbeatTimers[deviceId]?.cancel();
    _statuses[deviceId] = ConnectionStatus.disconnected;
    _channels.remove(deviceId)?.sink.close();
    debugPrint('Disconnected from peer $deviceId manually');
  }

  void disconnectAll() {
    final deviceIds = _peers.keys.toList();
    for (var id in deviceIds) {
      disconnectFromPeer(id);
    }
  }
}
