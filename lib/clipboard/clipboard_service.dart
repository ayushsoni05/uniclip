import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

abstract class ClipboardService {
  factory ClipboardService() => _DefaultClipboardService();
  
  Future<String?> getText();
  Future<void> setText(String text);
  void addListener(void Function(String) onChanged);
  void removeListener(void Function(String) onChanged);
  Future<void> forceCheck();
  Future<bool> isAccessibilityEnabled();
  Future<void> openAccessibilitySettings();
  Future<void> openBatteryOptimizationSettings();
  void dispose();
}

class _DefaultClipboardService with WidgetsBindingObserver implements ClipboardService {
  Timer? _timer;
  String? _lastHash;
  final List<void Function(String)> _listeners = [];
  static const MethodChannel _androidChannel = MethodChannel('com.globalclipboard/clipboard');

  _DefaultClipboardService() {
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
    _initNativeAndroidChannels();
  }

  void _initNativeAndroidChannels() {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        _androidChannel.setMethodCallHandler((call) async {
          if (call.method == 'onClipboardChanged') {
            final text = call.arguments['text'] as String?;
            if (text != null && text.isNotEmpty) {
              _notifyListenersIfChanged(text);
            }
          }
        });

        // Start native clipboard listener & foreground service
        _androidChannel.invokeMethod('startListening').catchError((e) {
          debugPrint('Native clipboard startListening error: $e');
        });
        _androidChannel.invokeMethod('startForegroundService').catchError((e) {
          debugPrint('Native clipboard startForegroundService error: $e');
        });
      } catch (e) {
        debugPrint('Error initializing Android clipboard channel: $e');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed: performing instant clipboard check');
      forceCheck();
    }
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      await forceCheck();
    });
  }

  @override
  Future<void> forceCheck() async {
    try {
      final text = await getText();
      if (text != null && text.isNotEmpty) {
        _notifyListenersIfChanged(text);
      }
    } catch (e) {
      // Ignore transient clipboard errors
    }
  }

  void _notifyListenersIfChanged(String text) {
    final hash = _computeHash(text);
    if (hash != _lastHash) {
      _lastHash = hash;
      debugPrint('Local clipboard change detected: ${text.length > 30 ? '${text.substring(0, 30)}...' : text}');
      for (final listener in List.of(_listeners)) {
        try {
          listener(text);
        } catch (e) {
          debugPrint('Error in clipboard listener: $e');
        }
      }
    }
  }

  String _computeHash(String text) {
    return sha256.convert(utf8.encode(text)).toString();
  }

  @override
  Future<String?> getText() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> setText(String text) async {
    try {
      _lastHash = _computeHash(text); // Set hash first to prevent echo
      await Clipboard.setData(ClipboardData(text: text));

      // Also update native Android clipboard if on Android
      if (!kIsWeb && Platform.isAndroid) {
        _androidChannel.invokeMethod('setClipboardText', {'text': text}).catchError((_) {});
      }
    } catch (e) {
      debugPrint('Error setting clipboard text: $e');
    }
  }

  @override
  Future<bool> isAccessibilityEnabled() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _androidChannel.invokeMethod<bool>('isAccessibilityServiceEnabled');
        return res ?? false;
      } catch (e) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> openAccessibilitySettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _androidChannel.invokeMethod('openAccessibilitySettings');
      } catch (e) {
        debugPrint('Error opening accessibility settings: $e');
      }
    }
  }

  @override
  Future<void> openBatteryOptimizationSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _androidChannel.invokeMethod('openBatteryOptimizationSettings');
      } catch (e) {
        debugPrint('Error opening battery optimization settings: $e');
      }
    }
  }

  @override
  void addListener(void Function(String) onChanged) {
    if (!_listeners.contains(onChanged)) {
      _listeners.add(onChanged);
    }
  }

  @override
  void removeListener(void Function(String) onChanged) {
    _listeners.remove(onChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _listeners.clear();
    if (!kIsWeb && Platform.isAndroid) {
      _androidChannel.invokeMethod('stopListening').catchError((_) {});
      _androidChannel.invokeMethod('stopForegroundService').catchError((_) {});
    }
  }
}
