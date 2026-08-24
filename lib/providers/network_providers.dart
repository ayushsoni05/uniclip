import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/discovery_service.dart';
import '../network/sync_server.dart';
import '../network/sync_client.dart';
import '../core/config.dart';
import '../data/models/paired_device.dart';
import 'device_providers.dart';
import 'clipboard_providers.dart';

// ---------------------------------------------------------------------------
// ClipboardSyncBridge — breaks the circular dependency between
// ClipboardMonitor ↔ SyncServer/SyncClient.
//
// Both SyncServer and SyncClient call bridge.onRemoteClipboard when they
// receive a clipboard update over WebSocket.  ClipboardMonitor registers
// itself as the handler via bridge.onRemoteClipboard = monitor.onRemoteClipboardReceived.
//
// When ClipboardMonitor detects a LOCAL clipboard change, it calls
// broadcastToPeers (which fires syncClient.sendClipboardUpdate) AND also
// bridge.serverBroadcast (which fires syncServer.broadcastClipboardUpdate).
// ---------------------------------------------------------------------------

class ClipboardSyncBridge {
  /// Called by SyncServer/SyncClient when a remote clipboard update arrives.
  /// ClipboardMonitor registers its onRemoteClipboardReceived here.
  void Function(String encryptedPayload, String senderId, String senderName)? onRemoteClipboard;

  /// Called by ClipboardMonitor when a local clipboard change should also be
  /// broadcast to all inbound server-side WebSocket connections.
  void Function(String encryptedPayload, String contentHash)? serverBroadcast;
}

final clipboardSyncBridgeProvider = Provider<ClipboardSyncBridge>((ref) {
  return ClipboardSyncBridge();
});

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final service = DiscoveryService();
  ref.onDispose(() => service.dispose());
  return service;
});

final discoveredPeersStreamProvider = StreamProvider<List<DiscoveredPeer>>((ref) {
  final discovery = ref.watch(discoveryServiceProvider);
  return discovery.events.map((_) => discovery.livePeers.values.toList());
});

// ---------------------------------------------------------------------------
// Sync Server
// ---------------------------------------------------------------------------

final syncServerProvider = Provider<SyncServer>((ref) {
  final config = ref.watch(configProvider);
  final pairedNotifier = ref.read(pairedDevicesProvider.notifier);
  final keyManager = ref.read(keyManagerProvider);
  final bridge = ref.read(clipboardSyncBridgeProvider);

  final server = SyncServer(
    port: config.port,
    localDeviceId: config.deviceId ?? 'device-id',
    localDeviceName: config.deviceName ?? 'Global Clipboard',
    isDevicePaired: (deviceId) => pairedNotifier.isPaired(deviceId),

    // *** CRITICAL FIX: Route received clipboard data through the bridge ***
    onClipboardReceived: (encryptedPayload, senderId, senderName, hash) {
      debugPrint('SyncServer: Received clipboard from $senderName, routing through bridge');
      bridge.onRemoteClipboard?.call(encryptedPayload, senderId, senderName);
    },

    // Key retriever for HMAC challenge-response authentication
    getKeyForDevice: (deviceId) async {
      return keyManager.getKey(deviceId);
    },

    // Two-way pairing handshake
    onPairingHandshakeReceived: ({
      required sourceDeviceId,
      required sourceDeviceName,
      required sourceIpAddress,
      required sourcePort,
      required sharedSecret,
      required salt,
      required timestamp,
    }) async {
      try {
        final saltBytes = base64Decode(salt);
        final key = await keyManager.deriveKeyAsync(sharedSecret, saltBytes);
        await keyManager.storeKey(sourceDeviceId, key);

        final pairedDevice = PairedDevice(
          deviceId: sourceDeviceId,
          deviceName: sourceDeviceName,
          pairedAt: DateTime.now(),
          lastSeen: DateTime.now(),
          isActive: true,
          ipAddress: sourceIpAddress,
          port: sourcePort,
        );

        pairedNotifier.addDevice(pairedDevice);
        ref.read(recentPairingEventProvider.notifier).state = pairedDevice;

        // Auto-connect SyncClient to the newly paired peer
        final syncClient = ref.read(syncClientProvider);
        syncClient.connectToPeer(DiscoveredPeer(
          deviceId: sourceDeviceId,
          deviceName: sourceDeviceName,
          ipAddress: sourceIpAddress,
          port: sourcePort,
          lastSeen: DateTime.now(),
        ));

        return true;
      } catch (e) {
        debugPrint('Error completing incoming pairing handshake: $e');
        return false;
      }
    },
  );

  // Register server broadcast into the bridge so ClipboardMonitor can
  // push updates to all inbound server connections.
  bridge.serverBroadcast = (encryptedPayload, contentHash) {
    server.broadcastClipboardUpdate(encryptedPayload, contentHash);
  };

  ref.onDispose(() => server.stop());
  return server;
});

// ---------------------------------------------------------------------------
// Sync Client
// ---------------------------------------------------------------------------

final syncClientProvider = Provider<SyncClient>((ref) {
  final config = ref.watch(configProvider);
  final keyManager = ref.read(keyManagerProvider);
  final bridge = ref.read(clipboardSyncBridgeProvider);

  final client = SyncClient(
    localDeviceId: config.deviceId ?? 'device-id',
    localDeviceName: config.deviceName ?? 'Global Clipboard',

    // *** CRITICAL FIX: Route received clipboard data through the bridge ***
    onClipboardReceived: (encryptedPayload, senderId, senderName, hash) {
      debugPrint('SyncClient: Received clipboard from $senderName, routing through bridge');
      bridge.onRemoteClipboard?.call(encryptedPayload, senderId, senderName);
    },

    // Key retriever for HMAC authentication
    getKeyForDevice: (deviceId) async {
      return keyManager.getKey(deviceId);
    },
  );

  ref.onDispose(() => client.disconnectAll());
  return client;
});
