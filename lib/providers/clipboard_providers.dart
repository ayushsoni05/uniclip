import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../clipboard/clipboard_service.dart';
import '../clipboard/clipboard_monitor.dart';
import '../clipboard/clipboard_history.dart';
import '../data/models/clipboard_entry.dart';
import '../security/crypto_service.dart';
import '../security/key_manager.dart';
import '../security/pairing_service.dart';
import '../core/config.dart';
import '../ui/overlays/banner_overlay.dart';
import 'network_providers.dart';
import 'device_providers.dart';

final cryptoServiceProvider = Provider<CryptoService>((ref) {
  return CryptoService();
});

final keyManagerProvider = Provider<KeyManager>((ref) {
  return KeyManager();
});

final pairingServiceProvider = Provider<PairingService>((ref) {
  final crypto = ref.watch(cryptoServiceProvider);
  final keyManager = ref.watch(keyManagerProvider);
  return PairingService(crypto, keyManager);
});

final clipboardServiceProvider = Provider<ClipboardService>((ref) {
  final service = ClipboardService();
  ref.onDispose(() => service.dispose());
  return service;
});

final clipboardHistoryProvider = Provider<ClipboardHistory>((ref) {
  return ClipboardHistory();
});

class ClipboardHistoryNotifier extends StateNotifier<List<ClipboardEntry>> {
  final ClipboardHistory _history;

  ClipboardHistoryNotifier(this._history) : super([]) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    state = await _history.getHistory(limit: 500);
  }

  Future<void> refresh() async {
    await _loadHistory();
  }

  Future<void> delete(int id) async {
    await _history.deleteEntry(id);
    await _loadHistory();
  }

  Future<void> clear() async {
    await _history.clearHistory();
    state = [];
  }
}

final clipboardHistoryListProvider =
    StateNotifierProvider<ClipboardHistoryNotifier, List<ClipboardEntry>>((ref) {
  final history = ref.watch(clipboardHistoryProvider);
  return ClipboardHistoryNotifier(history);
});

final clipboardMonitorProvider = Provider<ClipboardMonitor>((ref) {
  final service = ref.watch(clipboardServiceProvider);
  final history = ref.watch(clipboardHistoryProvider);
  final crypto = ref.watch(cryptoServiceProvider);
  final keyManager = ref.watch(keyManagerProvider);
  final syncClient = ref.watch(syncClientProvider);
  final config = ref.watch(configProvider);
  final pairedDevices = ref.watch(pairedDevicesProvider);
  final bridge = ref.watch(clipboardSyncBridgeProvider);

  final monitor = ClipboardMonitor(
    clipboardService: service,
    clipboardHistory: history,
    encryptContent: (content) async {
      // Use the first paired device's key for encryption.
      // Both devices derived the same key from the shared secret + salt,
      // so whichever device encrypts, the other can decrypt.
      List<int>? key;
      if (pairedDevices.isNotEmpty) {
        key = await keyManager.getKey(pairedDevices.first.deviceId);
      }
      if (key == null) {
        debugPrint('ClipboardMonitor: No device key found, using fallback key');
        key = keyManager.deriveKey('global_clipboard_shared_key', [1, 2, 3, 4, 5, 6, 7, 8]);
      }

      final payload = crypto.encrypt(content, key);
      return jsonEncode(payload.toJson());
    },
    decryptContent: (encryptedPayloadString, senderDeviceId) async {
      try {
        final json = jsonDecode(encryptedPayloadString) as Map<String, dynamic>;
        final payload = CryptoPayload.fromJson(json);

        // 1. Try sender's key first
        if (senderDeviceId.isNotEmpty) {
          final key = await keyManager.getKey(senderDeviceId);
          if (key != null) {
            try {
              return crypto.decrypt(payload, key);
            } catch (_) {}
          }
        }

        // 2. Try all paired devices' stored keys
        for (final device in pairedDevices) {
          final key = await keyManager.getKey(device.deviceId);
          if (key != null) {
            try {
              return crypto.decrypt(payload, key);
            } catch (_) {}
          }
        }

        // 3. Fallback shared key
        final fallbackKey = keyManager.deriveKey('global_clipboard_shared_key', [1, 2, 3, 4, 5, 6, 7, 8]);
        try {
          return crypto.decrypt(payload, fallbackKey);
        } catch (_) {}

        return encryptedPayloadString;
      } catch (e) {
        debugPrint('ClipboardMonitor: Decryption exception: $e');
        return encryptedPayloadString;
      }
    },
    broadcastToPeers: (encrypted, hash) {
      // Send via SyncClient to all outbound WebSocket connections
      syncClient.sendClipboardUpdate(encrypted, hash);
      // Also broadcast via SyncServer to all inbound WebSocket connections
      bridge.serverBroadcast?.call(encrypted, hash);
    },
    showPasteBanner: (deviceName) {
      BannerOverlayManager.instance.showPasteBanner(deviceName);
    },
    localDeviceId: config.deviceId ?? 'device-id',
    localDeviceName: config.deviceName ?? 'Global Clipboard',
  );

  // *** CRITICAL FIX: Register this monitor as the handler for incoming
  // clipboard data from both SyncServer and SyncClient ***
  bridge.onRemoteClipboard = (encryptedPayload, senderId, senderName) {
    debugPrint('Bridge: Routing clipboard from $senderName to ClipboardMonitor');
    monitor.onRemoteClipboardReceived(encryptedPayload, senderId, senderName);
  };

  ref.onDispose(() => monitor.stop());
  return monitor;
});

final accessibilityStatusProvider = FutureProvider.autoDispose<bool>((ref) async {
  final service = ref.watch(clipboardServiceProvider);
  return await service.isAccessibilityEnabled();
});
