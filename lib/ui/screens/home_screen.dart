import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'settings_screen.dart';
import 'pairing_screen.dart';
import 'history_screen.dart';
import 'device_detail_screen.dart';
import '../../providers/device_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/network_providers.dart';
import '../../providers/clipboard_providers.dart';
import '../../network/discovery_service.dart';
import '../../network/network_utils.dart';
import '../../data/models/paired_device.dart';
import '../../core/config.dart';

/// Main home screen for Global Clipboard with real-time state.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnabled = ref.watch(globalClipboardEnabledProvider);
    final pairedDevices = ref.watch(pairedDevicesProvider);
    final discoveredPeers = ref.watch(discoveredPeersStreamProvider).value ?? [];

    final activeCount = pairedDevices.where((d) => d.isActive).length;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Global Clipboard'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Icon(CupertinoIcons.settings),
          onPressed: () {
            Navigator.of(context).push(
              CupertinoPageRoute(builder: (context) => const SettingsScreen()),
            );
          },
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildStatusCard(isEnabled, activeCount, pairedDevices.length),
            const SizedBox(height: 24),
            _buildQuickActions(context, ref),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
              child: Text(
                'PAIRED DEVICES',
                style: TextStyle(
                  color: CupertinoColors.secondaryLabel,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _buildDeviceList(context, pairedDevices),
            if (discoveredPeers.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                child: Text(
                  'DISCOVERED ON LAN',
                  style: TextStyle(
                    color: CupertinoColors.secondaryLabel,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildDiscoveredList(context, ref, discoveredPeers, pairedDevices),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(bool isEnabled, int activeCount, int totalCount) {
    final statusColor = isEnabled
        ? (activeCount > 0 ? CupertinoColors.activeGreen : CupertinoColors.activeBlue)
        : CupertinoColors.systemGrey;

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        children: [
          Icon(
            CupertinoIcons.doc_on_clipboard,
            size: 64,
            color: statusColor,
          ),
          const SizedBox(height: 16),
          Text(
            !isEnabled
                ? 'Global Clipboard Disabled'
                : (totalCount > 0
                    ? '$activeCount of $totalCount devices active'
                    : 'Ready to Pair'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            !isEnabled
                ? 'Turn on in Settings to sync'
                : (totalCount > 0
                    ? 'Seamlessly syncing clipboard across LAN'
                    : 'Pair your Android or Windows PC to sync'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CupertinoColors.secondaryLabel,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            color: CupertinoColors.activeGreen,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.arrow_2_circlepath, size: 20, color: CupertinoColors.white),
                SizedBox(width: 8),
                Text(
                  'Sync Clipboard Now',
                  style: TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            onPressed: () async {
              await ref.read(clipboardServiceProvider).forceCheck();
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.qrcode, size: 20, color: CupertinoColors.white),
                    SizedBox(width: 8),
                    Text(
                      'Pair Device',
                      style: TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    CupertinoPageRoute(builder: (context) => const PairingScreen()),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CupertinoButton(
                color: CupertinoColors.systemGrey5,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.clock, size: 20, color: CupertinoColors.activeBlue),
                    SizedBox(width: 8),
                    Text(
                      'History',
                      style: TextStyle(
                        color: CupertinoColors.activeBlue,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    CupertinoPageRoute(builder: (context) => const HistoryScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDeviceList(BuildContext context, List<PairedDevice> devices) {
    if (devices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground,
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: const Center(
          child: Text(
            'No paired devices yet.\nTap "Pair Device" to connect another device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: CupertinoColors.secondaryLabel, height: 1.4),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Column(
        children: devices.asMap().entries.map((entry) {
          final isLast = entry.key == devices.length - 1;
          final device = entry.value;

          return Column(
            children: [
              CupertinoListTile(
                title: Text(device.deviceName),
                subtitle: Text(
                  '${device.ipAddress ?? "LAN"} • ${device.isActive ? "Connected" : "Saved"}',
                  style: TextStyle(
                    color: device.isActive
                        ? CupertinoColors.activeGreen
                        : CupertinoColors.secondaryLabel,
                    fontSize: 13,
                  ),
                ),
                leading: Icon(
                  device.deviceName.toLowerCase().contains('phone') ||
                          device.deviceName.toLowerCase().contains('android')
                       ? CupertinoIcons.device_phone_portrait
                      : CupertinoIcons.desktopcomputer,
                  color: CupertinoColors.activeBlue,
                ),
                trailing: const Icon(
                  CupertinoIcons.right_chevron,
                  color: CupertinoColors.systemGrey3,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (context) => DeviceDetailScreen(device: device),
                    ),
                  );
                },
              ),
              if (!isLast)
                const Padding(
                  padding: EdgeInsets.only(left: 48.0),
                  child: SizedBox(
                    height: 0.5,
                    child: ColoredBox(color: CupertinoColors.systemGrey5),
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDiscoveredList(
      BuildContext context, WidgetRef ref, List<DiscoveredPeer> peers, List<PairedDevice> paired) {
    final unpaired = peers
        .where((p) => !paired.any((pairedDev) => pairedDev.deviceId == p.deviceId))
        .toList();

    if (unpaired.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Column(
        children: unpaired.asMap().entries.map((entry) {
          final isLast = entry.key == unpaired.length - 1;
          final peer = entry.value;

          return Column(
            children: [
              CupertinoListTile(
                title: Text(peer.deviceName),
                subtitle: Text('${peer.ipAddress}:${peer.port}'),
                leading: const Icon(
                  CupertinoIcons.radiowaves_right,
                  color: CupertinoColors.activeOrange,
                ),
                trailing: CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: const Text(
                    'Pair',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: CupertinoColors.white),
                  ),
                  onPressed: () async {
                    await _quickPairPeer(context, ref, peer);
                  },
                ),
              ),
              if (!isLast)
                const Padding(
                  padding: EdgeInsets.only(left: 48.0),
                  child: SizedBox(
                    height: 0.5,
                    child: ColoredBox(color: CupertinoColors.systemGrey5),
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Future<void> _quickPairPeer(BuildContext context, WidgetRef ref, DiscoveredPeer peer) async {
    try {
      final config = ref.read(configProvider);
      final pairingService = ref.read(pairingServiceProvider);
      final syncClient = ref.read(syncClientProvider);

      // Generate shared secret and salt for this peer handshake
      final payloadString = pairingService.generatePairingPayload(
        peer.deviceId,
        peer.deviceName,
        peer.port,
        peer.ipAddress,
      );

      final pairingInfo = pairingService.parsePairingPayload(payloadString);
      final pairedDevice = await pairingService.completePairing(pairingInfo);

      // Save locally
      ref.read(pairedDevicesProvider.notifier).addDevice(pairedDevice);

      // Send Two-Way Handshake to the discovered peer
      final localIp = await NetworkUtils.getLocalIpAddress();
      await pairingService.sendPairingHandshake(
        targetInfo: pairingInfo,
        localDeviceId: config.deviceId ?? 'device-id',
        localDeviceName: config.deviceName ?? 'Global Clipboard',
        localPort: config.port,
        localIpAddress: localIp,
      );

      // Connect sync client
      syncClient.connectToPeer(peer);

      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Paired Successfully!'),
            content: Text('Your device is now synced with ${peer.deviceName}.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Pairing Failed'),
            content: Text('Could not complete pairing with ${peer.deviceName}: $e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      }
    }
  }
}
