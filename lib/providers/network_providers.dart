import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/discovery_service.dart';
import '../network/sync_server.dart';
import '../network/sync_client.dart';
import '../core/config.dart';
import 'device_providers.dart';

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

  final server = SyncServer(
    port: config.port,
    localDeviceId: config.deviceId ?? 'device-id',
    localDeviceName: config.deviceName ?? 'Global Clipboard',
    isDevicePaired: (deviceId) => pairedNotifier.isPaired(deviceId),
    onClipboardReceived: (encryptedPayload, senderId, senderName, hash) {
      // Handled by ClipboardMonitor
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
