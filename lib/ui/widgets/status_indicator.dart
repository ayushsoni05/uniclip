import 'package:flutter/cupertino.dart';
import '../theme/ios_theme.dart';

enum DeviceConnectionState { connected, disconnected, connecting }

class StatusIndicator extends StatefulWidget {
  final DeviceConnectionState state;

  const StatusIndicator({
    super.key,
    required this.state,
  });

  @override
  State<StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<StatusIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.state == DeviceConnectionState.connected || widget.state == DeviceConnectionState.connecting) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (widget.state) {
      case DeviceConnectionState.connected:
        color = IOSTheme.systemGreen;
        break;
      case DeviceConnectionState.disconnected:
        color = IOSTheme.systemRed;
        break;
      case DeviceConnectionState.connecting:
        color = IOSTheme.systemYellow;
        break;
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: widget.state == DeviceConnectionState.disconnected ? 1.0 : _animation.value,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
