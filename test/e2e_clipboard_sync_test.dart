import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:global_clipboard/security/crypto_service.dart';
import 'package:global_clipboard/security/key_manager.dart';
import 'package:global_clipboard/security/pairing_service.dart';
import 'package:global_clipboard/network/sync_server.dart';
import 'package:global_clipboard/network/sync_client.dart';
import 'package:global_clipboard/network/discovery_service.dart';
import 'package:global_clipboard/network/message_protocol.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('End-to-End Real-Time Clipboard Sync Integration Test (Phone <-> PC)', () {
    late CryptoService cryptoService;
    late KeyManager keyManagerPhone;
    late KeyManager keyManagerPC;
    late PairingService pairingServicePhone;
    late PairingService pairingServicePC;

    late SyncServer serverPhone;
    late SyncServer serverPC;
    late SyncClient clientPhone;
    late SyncClient clientPC;

    final phonePort = 9881;
    final pcPort = 9882;

    String? phoneReceivedText;
    String? pcReceivedText;

    final phonePairedDevices = <String>{};
    final pcPairedDevices = <String>{};

    setUpAll(() async {
      HttpOverrides.global = null;
      cryptoService = CryptoService();
      keyManagerPhone = KeyManager();
      keyManagerPC = KeyManager();
      pairingServicePhone = PairingService(cryptoService, keyManagerPhone);
      pairingServicePC = PairingService(cryptoService, keyManagerPC);

      // --- 1. SETUP PHONE SERVER & CLIENT ---
      serverPhone = SyncServer(
        port: phonePort,
        localDeviceId: 'phone-device-id',
        localDeviceName: 'Pixel Phone',
        isDevicePaired: (id) => phonePairedDevices.contains(id),
        onClipboardReceived: (encryptedPayload, senderId, senderName, contentHash) async {
          try {
            final json = jsonDecode(encryptedPayload);
            final payload = CryptoPayload.fromJson(json);
            final key = await keyManagerPhone.getKey(senderId);
            if (key != null) {
              phoneReceivedText = cryptoService.decrypt(payload, key);
            }
          } catch (e) {
            // Decryption test fallback
          }
        },
        onPairingHandshakeReceived: ({
          required sourceDeviceId,
          required sourceDeviceName,
          required sourceIpAddress,
          required sourcePort,
          required sharedSecret,
          required salt,
          required timestamp,
        }) async {
          phonePairedDevices.add(sourceDeviceId);
          final saltBytes = base64Decode(salt);
          final key = await keyManagerPhone.deriveKeyAsync(sharedSecret, saltBytes);
          await keyManagerPhone.storeKey(sourceDeviceId, key);
          return true;
        },
      );
      await serverPhone.start();

      clientPhone = SyncClient(
        localDeviceId: 'phone-device-id',
        localDeviceName: 'Pixel Phone',
        onClipboardReceived: (encryptedPayload, senderId, senderName, contentHash) async {
          try {
            final json = jsonDecode(encryptedPayload);
            final payload = CryptoPayload.fromJson(json);
            final key = await keyManagerPhone.getKey(senderId);
            if (key != null) {
              phoneReceivedText = cryptoService.decrypt(payload, key);
            }
          } catch (_) {}
        },
      );

      // --- 2. SETUP PC SERVER & CLIENT ---
      serverPC = SyncServer(
        port: pcPort,
        localDeviceId: 'pc-device-id',
        localDeviceName: 'Windows Desktop',
        isDevicePaired: (id) => pcPairedDevices.contains(id),
        onClipboardReceived: (encryptedPayload, senderId, senderName, contentHash) async {
          try {
            final json = jsonDecode(encryptedPayload);
            final payload = CryptoPayload.fromJson(json);
            final key = await keyManagerPC.getKey(senderId);
            if (key != null) {
              pcReceivedText = cryptoService.decrypt(payload, key);
            }
          } catch (e) {
            // Decryption test fallback
          }
        },
        onPairingHandshakeReceived: ({
          required sourceDeviceId,
          required sourceDeviceName,
          required sourceIpAddress,
          required sourcePort,
          required sharedSecret,
          required salt,
          required timestamp,
        }) async {
          pcPairedDevices.add(sourceDeviceId);
          final saltBytes = base64Decode(salt);
          final key = await keyManagerPC.deriveKeyAsync(sharedSecret, saltBytes);
          await keyManagerPC.storeKey(sourceDeviceId, key);
          return true;
        },
      );
      await serverPC.start();

      clientPC = SyncClient(
        localDeviceId: 'pc-device-id',
        localDeviceName: 'Windows Desktop',
        onClipboardReceived: (encryptedPayload, senderId, senderName, contentHash) async {
          try {
            final json = jsonDecode(encryptedPayload);
            final payload = CryptoPayload.fromJson(json);
            final key = await keyManagerPC.getKey(senderId);
            if (key != null) {
              pcReceivedText = cryptoService.decrypt(payload, key);
            }
          } catch (_) {}
        },
      );
    });

    tearDownAll(() async {
      await serverPhone.stop();
      await serverPC.stop();
      clientPhone.disconnectAll();
      clientPC.disconnectAll();
    });

    test('Full End-to-End Pairing Handshake via HTTP & QR Simulation', () async {
      // 1. PC generates QR code payload with its IP (127.0.0.1) and port (pcPort)
      final pcQrPayload = pairingServicePC.generatePairingPayload(
        'pc-device-id',
        'Windows Desktop',
        pcPort,
        '127.0.0.1',
        candidateIps: ['127.0.0.1'],
      );
      expect(pcQrPayload.isNotEmpty, true);

      // 2. Phone scans PC's QR code
      final parsedInfo = pairingServicePhone.parsePairingPayload(pcQrPayload);
      expect(parsedInfo.deviceId, 'pc-device-id');
      expect(parsedInfo.port, pcPort);

      // 3. Phone completes pairing locally and derives identical key
      final phonePairedDevice = await pairingServicePhone.completePairing(parsedInfo, verifiedIp: '127.0.0.1');
      phonePairedDevices.add('pc-device-id');
      expect(phonePairedDevice.deviceId, 'pc-device-id');

      // 4. Phone sends 2-way HTTP Handshake to PC
      final verifiedIp = await pairingServicePhone.sendPairingHandshake(
        targetInfo: parsedInfo,
        localDeviceId: 'phone-device-id',
        localDeviceName: 'Pixel Phone',
        localPort: phonePort,
        localIpAddress: '127.0.0.1',
      );
      expect(verifiedIp, '127.0.0.1');

      // 5. Connect WebSockets both ways
      clientPhone.connectToPeer(DiscoveredPeer(
        deviceId: 'pc-device-id',
        deviceName: 'Windows Desktop',
        ipAddress: '127.0.0.1',
        port: pcPort,
        lastSeen: DateTime.now(),
      ));

      clientPC.connectToPeer(DiscoveredPeer(
        deviceId: 'phone-device-id',
        deviceName: 'Pixel Phone',
        ipAddress: '127.0.0.1',
        port: phonePort,
        lastSeen: DateTime.now(),
      ));

      await Future.delayed(const Duration(milliseconds: 300));
    });

    test('Sync Direction 1: Copy on Phone -> Real-Time Paste on PC', () async {
      const phoneCopiedText = 'Hello from Android Phone! iOS-Style Sync 🚀';

      // Phone encrypts with PC's stored key
      final key = await keyManagerPhone.getKey('pc-device-id');
      expect(key, isNotNull);

      final payload = cryptoService.encrypt(phoneCopiedText, key!);
      final encryptedJson = jsonEncode(payload.toJson());
      final hash = 'hash-phone-123';

      // Phone broadcasts (dual-transport: WebSocket + Direct HTTP push)
      clientPhone.sendClipboardUpdate(encryptedJson, hash);

      // Wait for network delivery & decryption on PC
      await Future.delayed(const Duration(milliseconds: 400));

      expect(pcReceivedText, phoneCopiedText);
    });

    test('Sync Direction 2: Copy on PC -> Real-Time Paste on Phone', () async {
      const pcCopiedText = 'Reply from Windows PC! Real-Time Paste 💻';

      // PC encrypts with Phone's stored key
      final key = await keyManagerPC.getKey('phone-device-id');
      expect(key, isNotNull);

      final payload = cryptoService.encrypt(pcCopiedText, key!);
      final encryptedJson = jsonEncode(payload.toJson());
      final hash = 'hash-pc-456';

      // PC broadcasts (dual-transport: WebSocket + Direct HTTP push)
      clientPC.sendClipboardUpdate(encryptedJson, hash);

      // Wait for network delivery & decryption on Phone
      await Future.delayed(const Duration(milliseconds: 400));

      expect(phoneReceivedText, pcCopiedText);
    });
  });
}
