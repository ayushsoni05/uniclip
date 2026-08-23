class SyncMessageData {
  final String content;
  final String senderDeviceId;
  final String senderDeviceName;
  final DateTime timestamp;
  final String contentHash;

  const SyncMessageData({
    required this.content,
    required this.senderDeviceId,
    required this.senderDeviceName,
    required this.timestamp,
    required this.contentHash,
  });

  @override
  String toString() {
    return 'SyncMessageData(sender: $senderDeviceName, hash: $contentHash, time: $timestamp)';
  }
}
