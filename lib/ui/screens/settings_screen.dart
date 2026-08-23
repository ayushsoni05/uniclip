import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pairing_screen.dart';
import 'device_detail_screen.dart';
import '../../providers/device_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/clipboard_providers.dart';
import '../../core/config.dart';

/// iOS-style settings screen connected to real providers.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    final isEnabled = ref.watch(globalClipboardEnabledProvider);
    final keepHistory = ref.watch(keepHistoryProvider);
    final deviceName = ref.watch(deviceNameProvider);
    final historyLength = ref.watch(maxHistoryProvider);
    final pairedDevices = ref.watch(pairedDevicesProvider);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Settings'),
        previousPageTitle: 'Back',
      ),
      child: SafeArea(
        child: ListView(
          children: [
            _buildGlobalClipboardSection(config, isEnabled),
            _buildThisDeviceSection(config, deviceName),
            _buildPairedDevicesSection(pairedDevices),
            _buildHistorySection(config, keepHistory, historyLength),
            _buildAboutSection(config),
            const SizedBox(height: 40),
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

  Widget _buildSectionFooter(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 6.0, right: 16.0),
      child: Text(
        text,
        style: const TextStyle(
          color: CupertinoColors.secondaryLabel,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildGlobalClipboardSection(Config config, bool isEnabled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('GLOBAL CLIPBOARD'),
        CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          children: [
            CupertinoListTile(
              title: const Text('Global Clipboard'),
              trailing: CupertinoSwitch(
                value: isEnabled,
                onChanged: (val) async {
                  await config.setGlobalClipboardEnabled(val);
                  ref.read(globalClipboardEnabledProvider.notifier).state = val;
                  if (val) {
                    ref.read(clipboardMonitorProvider).start();
                  } else {
                    ref.read(clipboardMonitorProvider).stop();
                  }
                },
              ),
            ),
          ],
        ),
        _buildSectionFooter(
            'Copy on one device and instantly paste on another over your local network.'),
      ],
    );
  }

  Widget _buildThisDeviceSection(Config config, String deviceName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('THIS DEVICE'),
        CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          children: [
            CupertinoListTile(
              title: const Text('Device Name'),
              additionalInfo: Text(deviceName),
              trailing: const CupertinoListTileChevron(),
              onTap: () {
                _showEditNameDialog(config, deviceName);
              },
            ),
          ],
        ),
      ],
    );
  }

  void _showEditNameDialog(Config config, String currentName) {
    final controller = TextEditingController(text: currentName);
    showCupertinoDialog(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Device Name'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: CupertinoTextField(
              controller: controller,
              autofocus: true,
              clearButtonMode: OverlayVisibilityMode.editing,
            ),
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('Save'),
              onPressed: () async {
                final nav = Navigator.of(context);
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  await config.setDeviceName(newName);
                  ref.read(deviceNameProvider.notifier).state = newName;
                }
                nav.pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildPairedDevicesSection(List<dynamic> pairedDevices) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('PAIRED DEVICES'),
        CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          children: [
            ...pairedDevices.map((device) {
              return CupertinoListTile(
                title: Text(device.deviceName),
                subtitle: Text(device.isActive ? 'Connected' : 'Offline'),
                leading: Icon(
                  device.deviceName.toLowerCase().contains('phone') ||
                          device.deviceName.toLowerCase().contains('android')
                      ? CupertinoIcons.device_phone_portrait
                      : CupertinoIcons.desktopcomputer,
                  color: CupertinoColors.activeBlue,
                ),
                trailing: const Icon(CupertinoIcons.info_circle),
                onTap: () {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (context) => DeviceDetailScreen(device: device),
                    ),
                  );
                },
              );
            }),
            CupertinoListTile(
              title: const Text(
                'Pair New Device...',
                style: TextStyle(color: CupertinoColors.activeBlue),
              ),
              leading: const Icon(CupertinoIcons.add, color: CupertinoColors.activeBlue),
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(builder: (context) => const PairingScreen()),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHistorySection(Config config, bool keepHistory, int historyLength) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('CLIPBOARD HISTORY'),
        CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          children: [
            CupertinoListTile(
              title: const Text('Keep History'),
              trailing: CupertinoSwitch(
                value: keepHistory,
                onChanged: (val) async {
                  await config.setKeepHistory(val);
                  ref.read(keepHistoryProvider.notifier).state = val;
                },
              ),
            ),
            CupertinoListTile(
              title: const Text('History Length'),
              additionalInfo: Text('$historyLength items'),
              trailing: const CupertinoListTileChevron(),
              onTap: () {
                _showHistoryLengthPicker(config);
              },
            ),
            CupertinoListTile(
              title: const Text(
                'Clear History',
                style: TextStyle(color: CupertinoColors.destructiveRed),
              ),
              onTap: _showClearHistoryConfirmation,
            ),
          ],
        ),
      ],
    );
  }

  void _showHistoryLengthPicker(Config config) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: const Text('History Length'),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () async {
                final nav = Navigator.of(context);
                await config.setMaxHistory(100);
                ref.read(maxHistoryProvider.notifier).state = 100;
                nav.pop();
              },
              child: const Text('100 items'),
            ),
            CupertinoActionSheetAction(
              onPressed: () async {
                final nav = Navigator.of(context);
                await config.setMaxHistory(500);
                ref.read(maxHistoryProvider.notifier).state = 500;
                nav.pop();
              },
              child: const Text('500 items'),
            ),
            CupertinoActionSheetAction(
              onPressed: () async {
                final nav = Navigator.of(context);
                await config.setMaxHistory(1000);
                ref.read(maxHistoryProvider.notifier).state = 1000;
                nav.pop();
              },
              child: const Text('1000 items'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        );
      },
    );
  }

  void _showClearHistoryConfirmation() {
    showCupertinoDialog(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Clear History'),
          content: const Text(
              'Are you sure you want to clear all clipboard history? This cannot be undone.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('Clear'),
              onPressed: () async {
                final nav = Navigator.of(context);
                await ref.read(clipboardHistoryListProvider.notifier).clear();
                nav.pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildAboutSection(Config config) {
    final devId = config.deviceId ?? 'Unknown';
    final truncatedId = devId.length > 8 ? '${devId.substring(0, 8)}...' : devId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('ABOUT'),
        CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          children: [
            const CupertinoListTile(
              title: Text('Version'),
              trailing: Text('1.0.0',
                  style: TextStyle(color: CupertinoColors.secondaryLabel)),
            ),
            CupertinoListTile(
              title: const Text('Device ID'),
              trailing: Text(truncatedId,
                  style: const TextStyle(color: CupertinoColors.secondaryLabel)),
            ),
          ],
        ),
      ],
    );
  }
}
