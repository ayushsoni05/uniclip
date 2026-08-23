class PairedDevice {
  final String deviceId;
  final String deviceName;
  final DateTime pairedAt;
  final DateTime? lastSeen;
  final bool isActive;
  final String? ipAddress;
  final int port;

  PairedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.pairedAt,
    this.lastSeen,
    required this.isActive,
    this.ipAddress,
    required this.port,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'pairedAt': pairedAt.toIso8601String(),
      'lastSeen': lastSeen?.toIso8601String(),
      'isActive': isActive,
      'ipAddress': ipAddress,
      'port': port,
    };
  }

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    return PairedDevice(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      pairedAt: DateTime.parse(json['pairedAt'] as String),
      lastSeen: json['lastSeen'] != null ? DateTime.parse(json['lastSeen'] as String) : null,
      isActive: json['isActive'] as bool,
      ipAddress: json['ipAddress'] as String?,
      port: json['port'] as int,
    );
  }

  PairedDevice copyWith({
    String? deviceId,
    String? deviceName,
    DateTime? pairedAt,
    DateTime? lastSeen,
    bool? isActive,
    String? ipAddress,
    int? port,
  }) {
    return PairedDevice(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      isActive: isActive ?? this.isActive,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
    );
  }

  @override
  String toString() {
    return 'PairedDevice(deviceId: $deviceId, deviceName: $deviceName, pairedAt: $pairedAt, lastSeen: $lastSeen, isActive: $isActive, ipAddress: $ipAddress, port: $port)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PairedDevice &&
        other.deviceId == deviceId &&
        other.deviceName == deviceName &&
        other.pairedAt == pairedAt &&
        other.lastSeen == lastSeen &&
        other.isActive == isActive &&
        other.ipAddress == ipAddress &&
        other.port == port;
  }

  @override
  int get hashCode {
    return deviceId.hashCode ^
        deviceName.hashCode ^
        pairedAt.hashCode ^
        lastSeen.hashCode ^
        isActive.hashCode ^
        ipAddress.hashCode ^
        port.hashCode;
  }
}
