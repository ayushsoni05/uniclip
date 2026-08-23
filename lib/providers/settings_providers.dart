import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config.dart';

final globalClipboardEnabledProvider = StateProvider<bool>((ref) {
  final config = ref.watch(configProvider);
  return config.globalClipboardEnabled;
});

final keepHistoryProvider = StateProvider<bool>((ref) {
  final config = ref.watch(configProvider);
  return config.keepHistory;
});

final deviceNameProvider = StateProvider<String>((ref) {
  final config = ref.watch(configProvider);
  return config.deviceName ?? 'Global Clipboard Device';
});

final maxHistoryProvider = StateProvider<int>((ref) {
  final config = ref.watch(configProvider);
  return config.maxHistory;
});
