import 'package:flutter/cupertino.dart';
import '../widgets/paste_banner.dart';

class BannerOverlayManager {
  static final BannerOverlayManager _instance = BannerOverlayManager._internal();
  static BannerOverlayManager get instance => _instance;
  factory BannerOverlayManager() => _instance;
  BannerOverlayManager._internal();

  GlobalKey<NavigatorState>? navigatorKey;
  OverlayEntry? _currentEntry;
  GlobalKey<PasteBannerState>? _bannerKey;

  void init(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
  }

  void showPasteBanner(String deviceName, {Duration? duration, BuildContext? context}) {
    final ctx = context ?? navigatorKey?.currentState?.overlay?.context;
    if (ctx == null) return;
    
    // Attempt graceful hide if exists
    if (_currentEntry != null && _bannerKey?.currentState != null) {
      _bannerKey!.currentState!.dismiss();
    }

    _bannerKey = GlobalKey<PasteBannerState>();
    _currentEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 0,
        right: 0,
        child: Center(
          child: PasteBanner(
            key: _bannerKey,
            deviceName: deviceName,
            duration: duration ?? const Duration(seconds: 2),
            onDismissed: _removeEntry,
          ),
        ),
      ),
    );
    
    Overlay.of(ctx).insert(_currentEntry!);
  }

  void hidePasteBanner() {
    if (_currentEntry != null && _bannerKey?.currentState != null) {
      _bannerKey!.currentState!.dismiss();
    } else {
      _removeEntry();
    }
  }

  void _removeEntry() {
    if (_currentEntry != null) {
      _currentEntry!.remove();
      _currentEntry = null;
      _bannerKey = null;
    }
  }
}
