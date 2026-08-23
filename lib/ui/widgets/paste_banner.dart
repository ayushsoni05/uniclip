import 'package:flutter/cupertino.dart';
import '../theme/blur_widgets.dart';
import '../theme/ios_theme.dart';

class PasteBanner extends StatefulWidget {
  final String deviceName;
  final Duration duration;
  final VoidCallback onDismissed;

  const PasteBanner({
    super.key,
    required this.deviceName,
    required this.duration,
    required this.onDismissed,
  });

  static void show(BuildContext context, {required String deviceName, Duration? duration}) {
    final effectiveDuration = duration ?? const Duration(seconds: 2);
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 0,
        right: 0,
        child: Center(
          child: PasteBanner(
            deviceName: deviceName,
            duration: effectiveDuration,
            onDismissed: () {
              entry.remove();
            },
          ),
        ),
      ),
    );
    
    overlay.insert(entry);
  }

  @override
  State<PasteBanner> createState() => PasteBannerState();
}

class PasteBannerState extends State<PasteBanner> with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late AnimationController _progressController;
  
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _progressController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    
    _startAnimation();
  }
  
  Future<void> _startAnimation() async {
    await _slideController.forward();
    await _progressController.forward();
    
    if (mounted) {
      setState(() {
        _isComplete = true;
      });
    }
    
    await Future.delayed(const Duration(seconds: 1));
    dismiss();
  }
  
  void dismiss() {
    if (mounted) {
      _slideController.reverse().then((_) {
        widget.onDismissed();
      });
    }
  }
  
  @override
  void dispose() {
    _slideController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: FrostedGlass(
          borderRadius: 14.0,
          color: const Color(0xE6F2F2F7), // slightly more opaque than standard
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.doc_on_clipboard,
                      color: IOSTheme.systemBlue,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pasting from ${widget.deviceName}...',
                        style: const TextStyle(
                          color: IOSTheme.label,
                          fontSize: IOSTheme.footnoteSize,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isComplete)
                      const Icon(CupertinoIcons.check_mark, color: IOSTheme.systemBlue, size: 20)
                    else
                      const CupertinoActivityIndicator(radius: 8),
                  ],
                ),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: _progressController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _ProgressBarPainter(
                        progress: _progressController.value,
                        color: IOSTheme.systemBlue,
                      ),
                      size: const Size(double.infinity, 2.0),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ProgressBarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
      
    final rect = Rect.fromLTWH(0, 0, size.width * progress, size.height);
    
    final bgPaint = Paint()
      ..color = IOSTheme.systemGray5
      ..style = PaintingStyle.fill;
    
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    // Draw background first
    canvas.drawRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(1.0)), bgPaint);
    // Draw progress on top
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(1.0)), paint);
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
