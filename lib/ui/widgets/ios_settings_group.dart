import 'package:flutter/cupertino.dart';
import '../theme/ios_theme.dart';

class IOSSettingsGroup extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<IOSSettingsCell> children;

  const IOSSettingsGroup({
    super.key,
    this.header,
    this.footer,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.only(left: IOSTheme.horizontalPadding, bottom: 8.0, top: IOSTheme.sectionSpacing),
            child: Text(
              header!.toUpperCase(),
              style: const TextStyle(
                color: IOSTheme.systemGray,
                fontSize: IOSTheme.footnoteSize,
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: IOSTheme.horizontalPadding),
          decoration: BoxDecoration(
            color: IOSTheme.secondarySystemGroupedBackground,
            borderRadius: BorderRadius.circular(10.0),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10.0),
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 44.0 + 16.0), // icon size + padding
                      child: Container(
                        height: 0.5,
                        color: IOSTheme.separator,
                      ),
                    )
                ]
              ],
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(left: IOSTheme.horizontalPadding, top: 8.0),
            child: Text(
              footer!,
              style: const TextStyle(
                color: IOSTheme.systemGray,
                fontSize: IOSTheme.caption1Size,
              ),
            ),
          ),
      ],
    );
  }
}

class IOSSettingsCell extends StatefulWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isToggle;
  final bool toggleValue;
  final ValueChanged<bool>? onToggleChanged;

  const IOSSettingsCell({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  })  : isToggle = false,
        toggleValue = false,
        onToggleChanged = null;

  const IOSSettingsCell.toggle({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    required this.toggleValue,
    required this.onToggleChanged,
  })  : isToggle = true,
        trailing = null,
        onTap = null;

  @override
  State<IOSSettingsCell> createState() => _IOSSettingsCellState();
}

class _IOSSettingsCellState extends State<IOSSettingsCell> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    Widget cell = Container(
      height: IOSTheme.cellHeight,
      color: _isPressed ? IOSTheme.systemGray5 : const Color(0x00FFFFFF),
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 16.0),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: IOSTheme.label,
                    fontSize: IOSTheme.bodySize,
                  ),
                ),
                if (widget.subtitle != null)
                  Text(
                    widget.subtitle!,
                    style: const TextStyle(
                      color: IOSTheme.systemGray,
                      fontSize: IOSTheme.caption1Size,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.isToggle)
            CupertinoSwitch(
              value: widget.toggleValue,
              onChanged: widget.onToggleChanged,
              activeTrackColor: IOSTheme.systemGreen,
            )
          else if (widget.trailing != null)
            widget.trailing!
          else if (widget.onTap != null)
            const Icon(
              CupertinoIcons.chevron_forward,
              color: IOSTheme.systemGray3,
              size: 20,
            ),
        ],
      ),
    );

    if (widget.onTap != null) {
      return GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: cell,
      );
    }

    return cell;
  }
}
