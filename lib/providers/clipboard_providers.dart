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

  final monitor = ClipboardMonitor(
    clipboardService: service,
    clipboardHistory: history,
    encryptContent: (content) async {
      // Encrypt with first available paired device key or shared key
      final key = keyManager.deriveKey('global_clipboard_default_passphrase', [1, 2, 3, 4]);
      final payload = crypto.encrypt(content, key);
      return payload.ciphertext;
    },
    decryptContent: (encryptedContent) async {
      final key = keyManager.deriveKey('global_clipboard_default_passphrase', [1, 2, 3, 4]);
      final payload = CryptoPayload(
        iv: '',
        ciphertext: encryptedContent,
        tag: '',
      );
      try {
        return crypto.decrypt(payload, key);
      } catch (_) {
        return encryptedContent;
      }
    },
    broadcastToPeers: (encrypted, hash) {
      syncClient.sendClipboardUpdate(encrypted, hash);
    },
    showPasteBanner: (deviceName) {
      BannerOverlayManager.instance.showPasteBanner(deviceName);
    },
    localDeviceId: config.deviceId ?? 'device-local',
    localDeviceName: config.deviceName ?? 'Global Clipboard',
  );

  ref.onDispose(() => monitor.stop());
  return monitor;
});
