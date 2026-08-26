import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'config.dart';
import '../providers/network_providers.dart';
import '../providers/clipboard_providers.dart';
import '../providers/device_providers.dart';
import '../network/discovery_service.dart';

final appProvider = Provider<App>((ref) {
  return App(ref.container);
});

class App {
  final ProviderContainer container;
  final Logger _log = Logger('App');
  Timer? _reconnectTimer;

  App(this.container);

  Future<void> start() async {
    _log.info('Starting Global Clipboard application services...');

    final config = container.read(configProvider);
    _log.info('Config loaded for device: ${config.deviceName} (${config.deviceId})');

    // 1. Load paired devices from storage
    final pairedNotifier = container.read(pairedDevicesProvider.notifier);
    await pairedNotifier.loadDevices();

    // 2. Initialize ClipboardSyncBridge and ClipboardMonitor
    container.read(clipboardSyncBridgeProvider);
    final monitor = container.read(clipboardMonitorProvider);
    if (config.globalClipboardEnabled) {
      monitor.start();
      debugPrint('ClipboardMonitor started and bound to bridge');
    }

    // 3. Start platform-specific services (mDNS, WebSocket server, client)
    if (!kIsWeb) {
      // 3a. Start mDNS Advertising and Discovery
      try {
        final discovery = container.read(discoveryServiceProvider);
        await discovery.startAdvertising(
          deviceName: config.deviceName ?? 'Global Clipboard',
          deviceId: config.deviceId ?? 'device-id',
          port: config.port,
        );
        await discovery.startDiscovery();
      } catch (e) {
        debugPrint('mDNS discovery error (non-fatal): $e');
      }

      // 3b. Start Sync WebSocket Server
      try {
        final server = container.read(syncServerProvider);
        await server.start();
        debugPrint('SyncServer started on port ${config.port}');
      } catch (e) {
        debugPrint('Sync server start error (non-fatal): $e');
      }

      // 3c. Initialize SyncClient
      final syncClient = container.read(syncClientProvider);

      // 3d. DIRECT IP AUTO-CONNECT (Crucial: Connect immediately without waiting for mDNS)
      _connectToAllPairedDevices();

      // 3e. Auto-connect when mDNS discovers paired peers (handles dynamic IP changes)
      try {
        final discovery = container.read(discoveryServiceProvider);
        discovery.events.listen((event) {
          if (pairedNotifier.isPaired(event.peer.deviceId)) {
            debugPrint('mDNS discovered paired peer: ${event.peer.deviceName} at ${event.peer.ipAddress}:${event.peer.port}');
            syncClient.connectToPeer(event.peer);
            pairedNotifier.updateLastSeen(event.peer.deviceId);
          }
        });
      } catch (e) {
        debugPrint('Sync client auto-connect error (non-fatal): $e');
      }

      // 3f. Persistent Keep-Alive Reconnect Loop (every 8 seconds)
      _reconnectTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        _connectToAllPairedDevices();
      });
    }

    _log.info('All Global Clipboard real-time services started successfully.');
    debugPrint('=== Global Clipboard is LIVE ===');
    debugPrint('  Device: ${config.deviceName} (${config.deviceId})');
    debugPrint('  Port: ${config.port}');
    debugPrint('  Paired devices: ${pairedNotifier.deviceCount}');
  }

  /// Connects SyncClient directly to all known paired devices using their stored IP addresses.
  void _connectToAllPairedDevices() {
    try {
      final pairedDevices = container.read(pairedDevicesProvider);
      final syncClient = container.read(syncClientProvider);

      for (final device in pairedDevices) {
        if (device.ipAddress != null && device.ipAddress!.isNotEmpty) {
          syncClient.connectToPeer(DiscoveredPeer(
            deviceId: device.deviceId,
            deviceName: device.deviceName,
            ipAddress: device.ipAddress!,
            port: device.port,
            lastSeen: device.lastSeen ?? DateTime.now(),
          ));
        }
      }
    } catch (e) {
      debugPrint('Error in direct IP auto-connect: $e');
    }
  }

  Future<void> stop() async {
    _log.info('Stopping application services...');
    _reconnectTimer?.cancel();

    try { container.read(clipboardMonitorProvider).stop(); } catch (_) {}
    try { await container.read(discoveryServiceProvider).stopAdvertising(); } catch (_) {}
    try { await container.read(discoveryServiceProvider).stopDiscovery(); } catch (_) {}
    try { await container.read(syncServerProvider).stop(); } catch (_) {}
    try { container.read(syncClientProvider).disconnectAll(); } catch (_) {}

    _log.info('Application services stopped successfully.');
  }
}
