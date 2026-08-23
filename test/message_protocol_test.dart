import 'package:flutter_test/flutter_test.dart';
import 'package:global_clipboard/network/message_protocol.dart';

void main() {
  group('SyncMessage Protocol Tests', () {
    test('clipboardUpdate message serialization round trip', () {
      final msg = SyncMessage.clipboardUpdate(
        deviceId: 'device-123',
        deviceName: 'iPhone 15 Pro',
        encryptedPayload: 'encrypted_payload_data_base64',
        contentHash: 'hash_abc_123',
      );

      expect(msg.type, equals(MessageType.clipboardUpdate));
      expect(msg.deviceId, equals('device-123'));
      expect(msg.deviceName, equals('iPhone 15 Pro'));

      final json = msg.toJson();
      final deserialized = SyncMessage.fromJson(json);

      expect(deserialized.type, equals(MessageType.clipboardUpdate));
      expect(deserialized.deviceId, equals(msg.deviceId));
      expect(deserialized.deviceName, equals(msg.deviceName));
      expect(deserialized.encryptedPayload, equals(msg.encryptedPayload));
      expect(deserialized.contentHash, equals(msg.contentHash));
    });

    test('heartbeat message serialization', () {
      final msg = SyncMessage.heartbeat(
        deviceId: 'device-456',
        deviceName: 'Windows-PC',
      );

      expect(msg.type, equals(MessageType.heartbeat));
      final json = msg.toJson();
      final deserialized = SyncMessage.fromJson(json);

      expect(deserialized.type, equals(MessageType.heartbeat));
      expect(deserialized.deviceId, equals('device-456'));
    });
  });
}
