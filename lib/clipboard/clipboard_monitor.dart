import 'dart:async';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'clipboard_service.dart';
import 'clipboard_history.dart';
import '../data/models/clipboard_entry.dart';

class ClipboardMonitor {
  final ClipboardService _clipboardService;
  final ClipboardHistory _clipboardHistory;
  
  final Future<String> Function(String content) encryptContent;
  final Future<String> Function(String content) decryptContent;
  final void Function(String encryptedContent, String hash) broadcastToPeers;
  final void Function(String deviceName) showPasteBanner;
  final String localDeviceId;
  final String localDeviceName;

  String? _lastRemoteHash;
  bool _isRunning = false;

  ClipboardMonitor({
    required ClipboardService clipboardService,
    required ClipboardHistory clipboardHistory,
    required this.encryptContent,
    required this.decryptContent,
    required this.broadcastToPeers,
    required this.showPasteBanner,
    required this.localDeviceId,
    required this.localDeviceName,
  })  : _clipboardService = clipboardService,
        _clipboardHistory = clipboardHistory;

  void start() {
    if (_isRunning) return;
    _clipboardService.addListener(_onLocalClipboardChanged);
    _isRunning = true;
  }

  void stop() {
    if (!_isRunning) return;
    _clipboardService.removeListener(_onLocalClipboardChanged);
    _isRunning = false;
  }

  String _computeHash(String text) {
    return sha256.convert(utf8.encode(text)).toString();
  }

  void _onLocalClipboardChanged(String content) async {
    final hash = _computeHash(content);

    if (hash == _lastRemoteHash) {
      // Echo prevention
      _lastRemoteHash = null;
      return;
    }

    final entry = ClipboardEntry(
      content: content,
      contentHash: hash,
      sourceDeviceId: localDeviceId,
      sourceDeviceName: localDeviceName,
      isLocal: true,
      timestamp: DateTime.now(),
    );

    await _clipboardHistory.addEntry(entry);

    final encrypted = await encryptContent(content);
    broadcastToPeers(encrypted, hash);
  }

  Future<void> onRemoteClipboardReceived(
    String encryptedContent,
    String senderDeviceId,
    String senderDeviceName,
  ) async {
    final content = await decryptContent(encryptedContent);
    final hash = _computeHash(content);

    _lastRemoteHash = hash;
    await _clipboardService.setText(content);

    final entry = ClipboardEntry(
      content: content,
      contentHash: hash,
      sourceDeviceId: senderDeviceId,
      sourceDeviceName: senderDeviceName,
      isLocal: false,
      timestamp: DateTime.now(),
    );

    await _clipboardHistory.addEntry(entry);
    showPasteBanner(senderDeviceName);
  }
}
