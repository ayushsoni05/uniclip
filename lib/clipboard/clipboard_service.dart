import 'dart:async';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

abstract class ClipboardService {
  factory ClipboardService() => _DefaultClipboardService();
  
  Future<String?> getText();
  Future<void> setText(String text);
  void addListener(void Function(String) onChanged);
  void removeListener(void Function(String) onChanged);
  void dispose();
}

class _DefaultClipboardService implements ClipboardService {
  Timer? _timer;
  String? _lastHash;
  final List<void Function(String)> _listeners = [];

  _DefaultClipboardService() {
    _startPolling();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      final text = await getText();
      if (text != null) {
        final hash = _computeHash(text);
        if (hash != _lastHash) {
          _lastHash = hash;
          for (final listener in _listeners) {
            listener(text);
          }
        }
      }
    });
  }

  String _computeHash(String text) {
    return sha256.convert(utf8.encode(text)).toString();
  }

  @override
  Future<String?> getText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  Future<void> setText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _lastHash = _computeHash(text); // Prevent triggering our own listener
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
    _timer?.cancel();
    _listeners.clear();
  }
}
