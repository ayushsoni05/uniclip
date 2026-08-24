import 'dart:io';
import 'package:flutter/foundation.dart';

class NetworkUtils {
  /// Resolves the actual LAN IPv4 address of this device (e.g., 192.168.x.x or 10.x.x.x).
  static Future<String> getLocalIpAddress() async {
    if (kIsWeb) return '127.0.0.1';

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // Prioritize standard private Wi-Fi / Ethernet subnets (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
            return ip;
          }
          if (ip.startsWith('172.')) {
            final parts = ip.split('.');
            if (parts.length >= 2) {
              final second = int.tryParse(parts[1]) ?? 0;
              if (second >= 16 && second <= 31) {
                return ip;
              }
            }
          }
        }
      }

      // Fallback to first non-loopback IPv4 address
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Error resolving local IP: $e');
    }

    return '127.0.0.1';
  }
}
