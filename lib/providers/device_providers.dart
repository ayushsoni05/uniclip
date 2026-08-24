import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/paired_device.dart';

class PairedDevicesNotifier extends StateNotifier<List<PairedDevice>> {
  static const _prefsKey = 'global_clipboard_paired_devices';

  PairedDevicesNotifier() : super([]) {
    loadDevices();
  }

  Future<void> loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsKey);
    if (jsonString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        state = decoded
            .map((e) => PairedDevice.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        state = [];
      }
    }
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(state.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, jsonString);
  }

  void addDevice(PairedDevice device) {
    state = [...state.where((d) => d.deviceId != device.deviceId), device];
    _saveDevices();
  }

  void removeDevice(String deviceId) {
    state = state.where((d) => d.deviceId != deviceId).toList();
    _saveDevices();
  }

  void updateLastSeen(String deviceId) {
    state = state.map((d) {
      if (d.deviceId == deviceId) {
        return d.copyWith(lastSeen: DateTime.now(), isActive: true);
      }
      return d;
    }).toList();
    _saveDevices();
  }

  bool isPaired(String deviceId) {
    return state.any((d) => d.deviceId == deviceId);
  }
}

final pairedDevicesProvider =
    StateNotifierProvider<PairedDevicesNotifier, List<PairedDevice>>((ref) {
  return PairedDevicesNotifier();
});

/// Exposes the most recent paired device event so PairingScreen can auto-close/confirm
final recentPairingEventProvider = StateProvider<PairedDevice?>((ref) => null);
