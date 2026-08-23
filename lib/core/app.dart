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

    // 1. Load paired devices
    final pairedNotifier = container.read(pairedDevicesProvider.notifier);
    await pairedNotifier.loadDevices();

    // 2. Start mDNS Advertising and Discovery (Native Android / Windows only)
    if (!kIsWeb) {
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

      // 3. Start Sync WebSocket Server
      try {
        final server = container.read(syncServerProvider);
        await server.start();
      } catch (e) {
        debugPrint('Sync server start error (non-fatal): $e');
      }

      // 4. Auto-connect Sync Client to any discovered peers
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
        debugPrint('Sync client error (non-fatal): $e');
      }
    }

    // 5. Start Clipboard Monitor
    try {
      final monitor = container.read(clipboardMonitorProvider);
      if (config.globalClipboardEnabled) {
        monitor.start();
      }
    } catch (e) {
      debugPrint('Clipboard monitor error (non-fatal): $e');
    }

    _log.info('All Global Clipboard real-time services started successfully.');
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
