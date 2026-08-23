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

    // 2. Start mDNS Advertising and Discovery (Native Android / Windows)
    if (!kIsWeb) {
      final discovery = container.read(discoveryServiceProvider);
      await discovery.startAdvertising(
        deviceName: config.deviceName ?? 'Global Clipboard',
        deviceId: config.deviceId ?? 'device-id',
        port: config.port,
      );
      await discovery.startDiscovery();

      // 3. Start Sync WebSocket Server
      final server = container.read(syncServerProvider);
      await server.start();

      // 4. Auto-connect Sync Client to any discovered peers
      final syncClient = container.read(syncClientProvider);
      discovery.events.listen((event) {
        if (pairedNotifier.isPaired(event.peer.deviceId)) {
          syncClient.connectToPeer(event.peer);
          pairedNotifier.updateLastSeen(event.peer.deviceId);
        }
      });
    }

    // 5. Start Clipboard Monitor
    final monitor = container.read(clipboardMonitorProvider);
    if (config.globalClipboardEnabled) {
      monitor.start();
    }

    _log.info('All Global Clipboard real-time services started successfully.');
  }

  Future<void> stop() async {
    _log.info('Stopping application services...');

    container.read(clipboardMonitorProvider).stop();
    await container.read(discoveryServiceProvider).stopAdvertising();
    await container.read(discoveryServiceProvider).stopDiscovery();
    await container.read(syncServerProvider).stop();
    container.read(syncClientProvider).disconnectAll();

    _log.info('Application services stopped successfully.');
  }
}
