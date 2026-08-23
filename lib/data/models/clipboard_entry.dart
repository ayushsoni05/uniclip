class ClipboardEntry {
  final int? id;
  final String content;
  final String contentHash;
  final String sourceDeviceId;
  final String sourceDeviceName;
  final bool isLocal;
  final DateTime timestamp;

  const ClipboardEntry({
    this.id,
    required this.content,
    required this.contentHash,
    required this.sourceDeviceId,
    required this.sourceDeviceName,
    required this.isLocal,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'contentHash': contentHash,
      'sourceDeviceId': sourceDeviceId,
      'sourceDeviceName': sourceDeviceName,
      'isLocal': isLocal,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ClipboardEntry.fromJson(Map<String, dynamic> json) {
    return ClipboardEntry(
      id: json['id'] as int?,
      content: json['content'] as String,
      contentHash: json['contentHash'] as String,
      sourceDeviceId: json['sourceDeviceId'] as String,
      sourceDeviceName: json['sourceDeviceName'] as String,
      isLocal: json['isLocal'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  ClipboardEntry copyWith({
    int? id,
    String? content,
    String? contentHash,
    String? sourceDeviceId,
    String? sourceDeviceName,
    bool? isLocal,
    DateTime? timestamp,
  }) {
    return ClipboardEntry(
      id: id ?? this.id,
      content: content ?? this.content,
      contentHash: contentHash ?? this.contentHash,
      sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      sourceDeviceName: sourceDeviceName ?? this.sourceDeviceName,
      isLocal: isLocal ?? this.isLocal,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'ClipboardEntry(id: $id, content: ${content.substring(0, content.length > 20 ? 20 : content.length)}..., source: $sourceDeviceName, local: $isLocal)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ClipboardEntry &&
        other.id == id &&
        other.contentHash == contentHash &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => id.hashCode ^ contentHash.hashCode ^ timestamp.hashCode;
}
