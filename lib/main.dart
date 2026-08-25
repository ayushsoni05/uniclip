import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'core/config.dart';
import 'core/app.dart';
import 'ui/theme/ios_theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/overlays/banner_overlay.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows / Desktop: configure window size and behavior
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      await windowManager.ensureInitialized();

      const windowOptions = WindowOptions(
        size: Size(400, 700),
        minimumSize: Size(360, 600),
        center: true,
        backgroundColor: Color(0xFFF2F2F7),
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: 'Global Clipboard',
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('WindowManager initialization error: $e');
    }
  }

  // Initialize configuration
  final config = await Config.init();

  // Initialize overlay manager with root navigator key
  BannerOverlayManager.instance.init(rootNavigatorKey);

  final container = ProviderContainer(
    overrides: [
      configProvider.overrideWithValue(config),
    ],
  );

  // Start all real-time background services (mDNS, SyncServer, SyncClient, ClipboardMonitor)
  // Wrap in try-catch so startup errors don't crash the app
  try {
    final app = container.read(appProvider);
    await app.start();
  } catch (e) {
    debugPrint('Error starting background services: $e');
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GlobalClipboardApp(),
    ),
  );
}

/// Root application widget using Cupertino (iOS) design system.
class GlobalClipboardApp extends ConsumerWidget {
  const GlobalClipboardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoApp(
      title: 'Global Clipboard',
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: IOSTheme.theme,
      home: const HomeScreen(),
    );
  }
}
