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

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  final service = DiscoveryService();
  ref.onDispose(() => service.dispose());
  return service;
});

final discoveredPeersStreamProvider = StreamProvider<List<DiscoveredPeer>>((ref) {
  final discovery = ref.watch(discoveryServiceProvider);
  return discovery.events.map((_) => discovery.livePeers.values.toList());
});

final syncServerProvider = Provider<SyncServer>((ref) {
  final config = ref.watch(configProvider);
  final pairedNotifier = ref.read(pairedDevicesProvider.notifier);
  final keyManager = ref.read(keyManagerProvider);
  final syncClient = ref.read(syncClientProvider);

  final server = SyncServer(
    port: config.port,
    localDeviceId: config.deviceId ?? 'device-id',
    localDeviceName: config.deviceName ?? 'Global Clipboard',
    isDevicePaired: (deviceId) => pairedNotifier.isPaired(deviceId),
    onClipboardReceived: (encryptedPayload, senderId, senderName, hash) {
      // Handled by ClipboardMonitor
    },
    onPairingHandshakeReceived: ({
      required sourceDeviceId,
      required sourceDeviceName,
      required sourceIpAddress,
      required sourcePort,
      required sharedSecret,
      required salt,
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

  ref.onDispose(() => server.stop());
  return server;
});

final syncClientProvider = Provider<SyncClient>((ref) {
  final config = ref.watch(configProvider);

  final client = SyncClient(
    localDeviceId: config.deviceId ?? 'device-id',
    localDeviceName: config.deviceName ?? 'Global Clipboard',
    onClipboardReceived: (encryptedPayload, senderId, senderName, hash) {
      // Handled by ClipboardMonitor
    },
  );

  ref.onDispose(() => client.disconnectAll());
  return client;
});
