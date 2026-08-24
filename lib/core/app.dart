import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'config.dart';
import '../providers/network_providers.dart';
import '../providers/clipboard_providers.dart';
import '../providers/device_providers.dart';

final appProvider = Provider<App>((ref) {
  return App(ref.container);
});

class App {
  final ProviderContainer container;
  final Logger _log = Logger('App');

  App(this.container);

  Future<void> start() async {
    _log.info('Starting Global Clipboard application services...');

    final config = container.read(configProvider);
    _log.info('Config loaded for device: ${config.deviceName} (${config.deviceId})');

    // 1. Load paired devices from storage
    final pairedNotifier = container.read(pairedDevicesProvider.notifier);
    await pairedNotifier.loadDevices();

    // 2. Initialize the ClipboardSyncBridge (just creates the instance)
    container.read(clipboardSyncBridgeProvider);

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

      // 3c. Initialize SyncClient (reads the bridge, registers its callback)
      container.read(syncClientProvider);

      // 3d. Auto-connect SyncClient to any discovered paired peers
      try {
        final discovery = container.read(discoveryServiceProvider);
        final syncClient = container.read(syncClientProvider);
        discovery.events.listen((event) {
          if (pairedNotifier.isPaired(event.peer.deviceId)) {
            syncClient.connectToPeer(event.peer);
            pairedNotifier.updateLastSeen(event.peer.deviceId);
          }
        });
      } catch (e) {
        debugPrint('Sync client auto-connect error (non-fatal): $e');
      }
    }

    // 4. Start Clipboard Monitor — this MUST happen AFTER SyncServer and
    //    SyncClient are initialized because the monitor registers itself
    //    as the bridge handler for incoming clipboard data.
    try {
      final monitor = container.read(clipboardMonitorProvider);
      if (config.globalClipboardEnabled) {
        monitor.start();
        debugPrint('ClipboardMonitor started (polling every 500ms)');
      }
    } catch (e) {
      debugPrint('Clipboard monitor error (non-fatal): $e');
    }

    _log.info('All Global Clipboard real-time services started successfully.');
    debugPrint('=== Global Clipboard is LIVE ===');
    debugPrint('  Device: ${config.deviceName} (${config.deviceId})');
    debugPrint('  Port: ${config.port}');
    debugPrint('  Paired devices: ${pairedNotifier.deviceCount}');
  }

  Future<void> stop() async {
    _log.info('Stopping application services...');

    try { container.read(clipboardMonitorProvider).stop(); } catch (_) {}
    try { await container.read(discoveryServiceProvider).stopAdvertising(); } catch (_) {}
    try { await container.read(discoveryServiceProvider).stopDiscovery(); } catch (_) {}
    try { await container.read(syncServerProvider).stop(); } catch (_) {}
    try { container.read(syncClientProvider).disconnectAll(); } catch (_) {}

    _log.info('Application services stopped successfully.');
  }
}
