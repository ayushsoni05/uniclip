import 'package:flutter/cupertino.dart';
import '../theme/ios_theme.dart';

class HistoryTile extends StatelessWidget {
  final String contentPreview;
  final String deviceName;
  final bool isWindowsSource;
  final String timestamp;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const HistoryTile({
    super.key,
    required this.contentPreview,
    required this.deviceName,
    required this.isWindowsSource,
    required this.timestamp,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // We use the generic Dismissible to avoid Material dependency
    return Dismissible(
      key: ValueKey(contentPreview.hashCode ^ timestamp.hashCode),
      direction: DismissDirection.endToStart,
      onDismissed: (direction) => onDelete(),
      background: Container(
        color: IOSTheme.systemRed,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: const Icon(CupertinoIcons.trash, color: CupertinoColors.white),
      ),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: const BoxDecoration(
            color: IOSTheme.secondarySystemGroupedBackground,
            border: Border(
              bottom: BorderSide(
                color: IOSTheme.separator,
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contentPreview,
                style: const TextStyle(
                  color: IOSTheme.label,
                  fontSize: IOSTheme.bodySize,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    isWindowsSource ? CupertinoIcons.desktopcomputer : CupertinoIcons.device_phone_portrait,
                    size: 14,
                    color: IOSTheme.systemGray,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    deviceName,
                    style: const TextStyle(
                      color: IOSTheme.systemGray,
                      fontSize: IOSTheme.caption1Size,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timestamp,
                    style: const TextStyle(
                      color: IOSTheme.systemGray2,
                      fontSize: IOSTheme.caption1Size,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
