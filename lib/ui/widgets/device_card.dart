import 'package:flutter/cupertino.dart';
import '../theme/ios_theme.dart';
import 'status_indicator.dart';

class DeviceCard extends StatelessWidget {
  final String name;
  final bool isWindows;
  final String status;
  final DeviceConnectionState state;
  final VoidCallback? onTap;

  const DeviceCard({
    super.key,
    required this.name,
    required this.isWindows,
    required this.status,
    required this.state,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: IOSTheme.secondarySystemGroupedBackground,
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Row(
          children: [
            Icon(
              isWindows ? CupertinoIcons.desktopcomputer : CupertinoIcons.device_phone_portrait,
              size: 28,
              color: IOSTheme.systemBlue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: IOSTheme.label,
                      fontSize: IOSTheme.bodySize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    style: const TextStyle(
                      color: IOSTheme.systemGray,
                      fontSize: IOSTheme.caption1Size,
                    ),
                  ),
                ],
              ),
            ),
            StatusIndicator(state: state),
          ],
        ),
      ),
    );
  }
}
