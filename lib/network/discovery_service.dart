import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

enum DiscoveryEventType { peerAdded, peerRemoved, peerUpdated }

class DiscoveryEvent {
  final DiscoveryEventType type;
  final DiscoveredPeer peer;

  DiscoveryEvent({required this.type, required this.peer});
}

class DiscoveredPeer {
  final String deviceId;
  final String deviceName;
  final String ipAddress;
  final int port;
  final DateTime lastSeen;

  DiscoveredPeer({
    required this.deviceId,
    required this.deviceName,
    required this.ipAddress,
    required this.port,
    required this.lastSeen,
  });

  DiscoveredPeer copyWith({DateTime? lastSeen}) {
    return DiscoveredPeer(
      deviceId: deviceId,
      deviceName: deviceName,
      ipAddress: ipAddress,
      port: port,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class DiscoveryService {
  static const String _serviceType = '_globalclip._tcp';

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  final Map<String, DiscoveredPeer> _livePeers = {};

  final StreamController<DiscoveryEvent> _eventController =
      StreamController<DiscoveryEvent>.broadcast();

  Stream<DiscoveryEvent> get events => _eventController.stream;
  Map<String, DiscoveredPeer> get livePeers => Map.unmodifiable(_livePeers);

  Future<void> startAdvertising({
    required String deviceName,
    required String deviceId,
    required int port,
  }) async {
    try {
      BonsoirService service = BonsoirService(
        name: deviceName,
        type: _serviceType,
        port: port,
        attributes: {
          'device_name': deviceName,
          'device_id': deviceId,
          'version': '1.0.0',
        },
      );

      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.ready;
      await _broadcast!.start();
      debugPrint('Started mDNS advertising as $deviceName on port $port');
    } catch (e) {
      debugPrint('Error starting mDNS advertising: $e');
    }
  }

  Future<void> stopAdvertising() async {
    if (_broadcast != null) {
      await _broadcast!.stop();
      _broadcast = null;
      debugPrint('Stopped mDNS advertising');
    }
  }

  Future<void> startDiscovery() async {
    try {
      _discovery = BonsoirDiscovery(type: _serviceType);
      await _discovery!.ready;
      
      _discovery!.eventStream!.listen((event) {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          event.service?.resolve(_discovery!.serviceResolver);
        } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
          _handleServiceResolved(event.service as ResolvedBonsoirService);
        } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
          _handleServiceLost(event.service);
        }
      });
      
      await _discovery!.start();
      debugPrint('Started mDNS discovery');
    } catch (e) {
      debugPrint('Error starting mDNS discovery: $e');
    }
  }

  void _handleServiceResolved(ResolvedBonsoirService service) {
    final attributes = service.attributes;
    if (!attributes.containsKey('device_id')) return;

    final deviceId = attributes['device_id']!;
    final deviceName = attributes['device_name'] ?? service.name;
    final ipAddress = service.host ?? '';
    final port = service.port;

    if (ipAddress.isEmpty) return;

    final peer = DiscoveredPeer(
      deviceId: deviceId,
      deviceName: deviceName,
      ipAddress: ipAddress,
      port: port,
      lastSeen: DateTime.now(),
    );

    if (_livePeers.containsKey(deviceId)) {
      _livePeers[deviceId] = peer;
      _eventController.add(DiscoveryEvent(type: DiscoveryEventType.peerUpdated, peer: peer));
      debugPrint('Peer updated: $deviceName ($deviceId)');
    } else {
      _livePeers[deviceId] = peer;
      _eventController.add(DiscoveryEvent(type: DiscoveryEventType.peerAdded, peer: peer));
      debugPrint('Peer added: $deviceName ($deviceId)');
    }
  }

  void _handleServiceLost(BonsoirService? service) {
    if (service == null) return;
    
    // We might not have attributes in lost event, so we try to find by name
    String? deviceIdToRemove;
    _livePeers.forEach((id, peer) {
      if (peer.deviceName == service.name) {
        deviceIdToRemove = id;
      }
    });

    if (deviceIdToRemove != null) {
      final removedPeer = _livePeers.remove(deviceIdToRemove!);
      if (removedPeer != null) {
        _eventController.add(
            DiscoveryEvent(type: DiscoveryEventType.peerRemoved, peer: removedPeer));
        debugPrint('Peer removed: ${removedPeer.deviceName} (${removedPeer.deviceId})');
      }
    }
  }

  Future<void> stopDiscovery() async {
    if (_discovery != null) {
      await _discovery!.stop();
      _discovery = null;
      _livePeers.clear();
      debugPrint('Stopped mDNS discovery');
    }
  }

  void dispose() {
    stopAdvertising();
    stopDiscovery();
    _eventController.close();
  }
}
