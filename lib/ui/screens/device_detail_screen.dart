import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/paired_device.dart';
import '../../providers/device_providers.dart';

/// Screen displaying details for a specific connected device.
class DeviceDetailScreen extends ConsumerWidget {
  final PairedDevice device;

  const DeviceDetailScreen({
    super.key,
    required this.device,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairedList = ref.watch(pairedDevicesProvider);
    final currentDevice = pairedList.firstWhere(
      (d) => d.deviceId == device.deviceId,
      orElse: () => device,
    );

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        middle: Text(currentDevice.deviceName),
        previousPageTitle: 'Back',
      ),
      child: SafeArea(
        child: ListView(
          children: [
            _buildStatusSection(currentDevice),
            _buildInfoSection(currentDevice),
            _buildActionsSection(context, ref, currentDevice),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, bottom: 6.0, top: 24.0),
      child: Text(
        title,
        style: const TextStyle(
          color: CupertinoColors.secondaryLabel,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildStatusSection(PairedDevice dev) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('STATUS'),
        CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          children: [
            CupertinoListTile(
              title: const Text('Connection Status'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dev.isActive ? CupertinoColors.activeGreen : CupertinoColors.systemGrey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dev.isActive ? 'Connected' : 'Offline',
                    style: TextStyle(
                      color: dev.isActive ? CupertinoColors.activeGreen : CupertinoColors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoSection(PairedDevice dev) {
    final pairedStr = '${dev.pairedAt.month}/${dev.pairedAt.day}/${dev.pairedAt.year}';
    final lastSeenStr = dev.lastSeen != null
        ? '${dev.lastSeen!.hour.toString().padLeft(2, '0')}:${dev.lastSeen!.minute.toString().padLeft(2, '0')}'
        : 'Never';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('DEVICE INFORMATION'),
        CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          children: [
            CupertinoListTile(
              title: const Text('Device ID'),
              additionalInfo: Text(
                dev.deviceId.length > 12 ? '${dev.deviceId.substring(0, 12)}...' : dev.deviceId,
              ),
            ),
            CupertinoListTile(
              title: const Text('IP Address'),
              additionalInfo: Text(dev.ipAddress ?? 'Auto-discovered (mDNS)'),
            ),
            CupertinoListTile(
              title: const Text('Port'),
              additionalInfo: Text('${dev.port}'),
            ),
            CupertinoListTile(
              title: const Text('Paired Date'),
              additionalInfo: Text(pairedStr),
            ),
            CupertinoListTile(
              title: const Text('Last Seen'),
              additionalInfo: Text(lastSeenStr),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionsSection(BuildContext context, WidgetRef ref, PairedDevice dev) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          children: [
            CupertinoListTile(
              title: const Center(
                child: Text(
                  'Unpair Device',
                  style: TextStyle(color: CupertinoColors.destructiveRed, fontWeight: FontWeight.w600),
                ),
              ),
              onTap: () {
                _showUnpairConfirmation(context, ref, dev);
              },
            ),
          ],
        ),
      ],
    );
  }

  void _showUnpairConfirmation(BuildContext context, WidgetRef ref, PairedDevice dev) {
    showCupertinoDialog(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: Text('Unpair ${dev.deviceName}?'),
          content: const Text(
            'This device will no longer be able to share clipboard data until paired again.',
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('Unpair'),
              onPressed: () {
                ref.read(pairedDevicesProvider.notifier).removeDevice(dev.deviceId);
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close detail screen
              },
            ),
          ],
        );
      },
    );
  }
}
