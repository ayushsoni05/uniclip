import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'constants.dart';

final configProvider = Provider<Config>((ref) {
  throw UnimplementedError('Config must be initialized first');
});

class Config {
  final SharedPreferences _prefs;

  Config(this._prefs);

  static Future<Config> init() async {
    final prefs = await SharedPreferences.getInstance();
    final config = Config(prefs);
    
    // Generate UUID on first run if it doesn't exist
    if (config.deviceId == null) {
      await config.setDeviceId(const Uuid().v4());
    }
    
    // Set default device name if not set
    if (config.deviceName == null) {
      final defaultName = kIsWeb ? 'Web Browser' : Platform.localHostname;
      await config.setDeviceName(defaultName);
    }
    
    return config;
  }

  // Device Name
  String? get deviceName => _prefs.getString('device_name');
  Future<void> setDeviceName(String value) => _prefs.setString('device_name', value);

  // Device ID
  String? get deviceId => _prefs.getString('device_id');
  Future<void> setDeviceId(String value) => _prefs.setString('device_id', value);

  // Port
  int get port => _prefs.getInt('port') ?? AppConstants.defaultPort;
  Future<void> setPort(int value) => _prefs.setInt('port', value);

  // Poll Interval (ms)
  int get pollInterval => _prefs.getInt('poll_interval') ?? AppConstants.pollInterval.inMilliseconds;
  Future<void> setPollInterval(int value) => _prefs.setInt('poll_interval', value);

  // Max History
  int get maxHistory => _prefs.getInt('max_history') ?? AppConstants.defaultMaxHistoryEntries;
  Future<void> setMaxHistory(int value) => _prefs.setInt('max_history', value);

  // Global Clipboard Enabled
  bool get globalClipboardEnabled => _prefs.getBool('global_clipboard_enabled') ?? true;
  Future<void> setGlobalClipboardEnabled(bool value) => _prefs.setBool('global_clipboard_enabled', value);

  // Keep History
  bool get keepHistory => _prefs.getBool('keep_history') ?? true;
  Future<void> setKeepHistory(bool value) => _prefs.setBool('keep_history', value);
}
