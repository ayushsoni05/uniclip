import 'dart:io';
import 'package:flutter/foundation.dart';

class NetworkUtils {
  static const List<String> _virtualKeywords = [
    'warp', 'cloudflare', 'vpn', 'virtual', 'vbox', 'vmware',
    'wsl', 'vethernet', 'tap', 'tun', 'ppp', 'pseudo', 'tailscale', 'zerotier'
  ];

  /// Resolves the actual physical LAN IPv4 address (e.g. Wi-Fi: 10.x.x.x or 192.168.x.x).
  /// Excludes virtual adapters like Cloudflare WARP, WSL, VirtualBox, VMware.
  static Future<String> getLocalIpAddress() async {
    final ips = await getAllCandidateIpAddresses();
    return ips.isNotEmpty ? ips.first : '127.0.0.1';
  }

  /// Returns all valid physical LAN IPv4 addresses, sorted with Wi-Fi and Ethernet first.
  static Future<List<String>> getAllCandidateIpAddresses() async {
    if (kIsWeb) return ['127.0.0.1'];

    final candidateIps = <String>[];

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // 1. First priority: Physical Wi-Fi & Ethernet interfaces
      for (final iface in interfaces) {
        final nameLower = iface.name.toLowerCase();
        final isVirtual = _virtualKeywords.any((k) => nameLower.contains(k));
        if (isVirtual) continue;

        final isWifiOrEth = nameLower.contains('wi-fi') ||
            nameLower.contains('wifi') ||
            nameLower.contains('wlan') ||
            nameLower.contains('ethernet') ||
            nameLower.contains('eth') ||
            nameLower.contains('en0') ||
            nameLower.contains('lan');

        if (isWifiOrEth) {
          for (final addr in iface.addresses) {
            final ip = addr.address;
            if (!addr.isLoopback && !addr.isLinkLocal && !ip.startsWith('169.254.')) {
              if (!candidateIps.contains(ip)) {
                candidateIps.add(ip);
              }
            }
          }
        }
      }

      // 2. Second priority: Other non-virtual physical interfaces with private IPs
      for (final iface in interfaces) {
        final nameLower = iface.name.toLowerCase();
        final isVirtual = _virtualKeywords.any((k) => nameLower.contains(k));
        if (isVirtual) continue;

        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (!addr.isLoopback && !addr.isLinkLocal && !ip.startsWith('169.254.')) {
            if (!candidateIps.contains(ip)) {
              candidateIps.add(ip);
            }
          }
        }
      }

      // 3. Fallback: Any non-loopback IP if nothing found
      if (candidateIps.isEmpty) {
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            final ip = addr.address;
            if (!addr.isLoopback && !addr.isLinkLocal && !ip.startsWith('169.254.')) {
              if (!candidateIps.contains(ip)) {
                candidateIps.add(ip);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error resolving candidate LAN IPs: $e');
    }

    if (candidateIps.isEmpty) {
      candidateIps.add('127.0.0.1');
    }

    debugPrint('NetworkUtils: Resolved LAN candidate IPs: $candidateIps');
    return candidateIps;
  }
}
