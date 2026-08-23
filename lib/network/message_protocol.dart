// Message protocol for Global Clipboard sync

enum MessageType {
  clipboardUpdate,
  pairingRequest,
  pairingResponse,
  heartbeat,
  deviceInfo
}

class SyncMessage {
  final MessageType type;
  final String deviceId;
  final String deviceName;
  final String? encryptedPayload; // Base64 encoded CryptoPayload JSON
  final int timestamp; // milliseconds since epoch
  final String? contentHash; // SHA-256 hash for dedup & echo prevention

  SyncMessage({
    required this.type,
    required this.deviceId,
    required this.deviceName,
    this.encryptedPayload,
    required this.timestamp,
    this.contentHash,
  });

  factory SyncMessage.clipboardUpdate({
    required String deviceId,
    required String deviceName,
    required String encryptedPayload,
    required String contentHash,
  }) {
    return SyncMessage(
      type: MessageType.clipboardUpdate,
      deviceId: deviceId,
      deviceName: deviceName,
      encryptedPayload: encryptedPayload,
      contentHash: contentHash,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory SyncMessage.heartbeat({
    required String deviceId,
    required String deviceName,
  }) {
    return SyncMessage(
      type: MessageType.heartbeat,
      deviceId: deviceId,
      deviceName: deviceName,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory SyncMessage.deviceInfo({
    required String deviceId,
    required String deviceName,
  }) {
    return SyncMessage(
      type: MessageType.deviceInfo,
      deviceId: deviceId,
      deviceName: deviceName,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'deviceId': deviceId,
      'deviceName': deviceName,
      if (encryptedPayload != null) 'encryptedPayload': encryptedPayload,
      'timestamp': timestamp,
      if (contentHash != null) 'contentHash': contentHash,
    };
  }

  factory SyncMessage.fromJson(Map<String, dynamic> json) {
    return SyncMessage(
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.deviceInfo,
      ),
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      encryptedPayload: json['encryptedPayload'] as String?,
      timestamp: json['timestamp'] as int,
      contentHash: json['contentHash'] as String?,
    );
  }
}
