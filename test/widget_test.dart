import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:global_clipboard/main.dart';
import 'package:global_clipboard/core/config.dart';

void main() {
  testWidgets('GlobalClipboardApp builds smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'device_name': 'Test iPhone',
      'device_id': 'test-uuid-1234',
      'port': 9876,
      'poll_interval': 500,
      'max_history': 500,
      'global_clipboard_enabled': true,
      'keep_history': true,
    });

    final prefs = await SharedPreferences.getInstance();
    final config = Config(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configProvider.overrideWithValue(config),
        ],
        child: const GlobalClipboardApp(),
      ),
    );

    expect(find.text('Global Clipboard'), findsWidgets);
    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
  });
}
