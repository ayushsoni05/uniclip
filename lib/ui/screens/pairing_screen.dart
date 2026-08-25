import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/clipboard_providers.dart';
import '../../providers/device_providers.dart';
import '../../providers/network_providers.dart';
import '../../network/network_utils.dart';
import '../../network/discovery_service.dart';
import '../../core/config.dart';

/// Pairing screen for scanning and displaying QR codes with automatic two-way handshake.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  int _segmentedControlValue = 0;
  bool _isPaired = false;
  bool _isProcessing = false;
  String _pairedDeviceName = '';
  String? _errorMessage;
  String _localIp = '127.0.0.1';
  String _qrPayload = '';

  MobileScannerController? _scannerController;

  bool get _isCameraSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _initLocalIpAndQr();

    if (_isCameraSupported) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        autoStart: false,
      );
    }
  }

  Future<void> _initLocalIpAndQr() async {
    final candidateIps = await NetworkUtils.getAllCandidateIpAddresses();
    final primaryIp = candidateIps.isNotEmpty ? candidateIps.first : '127.0.0.1';
    if (!mounted) return;

    final config = ref.read(configProvider);
    final pairingService = ref.read(pairingServiceProvider);

    final payload = pairingService.generatePairingPayload(
      config.deviceId ?? 'device-id',
      config.deviceName ?? 'Global Clipboard',
      config.port,
      primaryIp,
      candidateIps: candidateIps,
    );

    setState(() {
      _localIp = primaryIp;
      _qrPayload = payload;
    });
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  void _onTabChanged(int? value) {
    if (value != null) {
      setState(() {
        _segmentedControlValue = value;
        _errorMessage = null;
        _isProcessing = false;
      });

      if (_isCameraSupported) {
        if (value == 1 && !_isPaired) {
          _scannerController?.start();
        } else {
          _scannerController?.stop();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);

    // Listen for incoming two-way remote pairing handshakes
    ref.listen<dynamic>(recentPairingEventProvider, (prev, next) {
      if (next != null && !_isPaired) {
        setState(() {
          _isPaired = true;
          _pairedDeviceName = next.deviceName;
        });
      }
    });

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Pair Device'),
        previousPageTitle: 'Back',
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _segmentedControlValue,
                  children: const {
                    0: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text('Show QR Code'),
                    ),
                    1: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text('Scan QR Code'),
                    ),
                  },
                  onValueChanged: _onTabChanged,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _isPaired
                  ? _buildSuccessView()
                  : (_segmentedControlValue == 0
                      ? _buildShowQrView(config)
                      : _buildScanQrView()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShowQrView(Config config) {
    if (_qrPayload.isEmpty) {
      return const Center(child: CupertinoActivityIndicator());
    }

    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(20.0),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x15000000),
                      blurRadius: 20.0,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: _qrPayload,
                  version: QrVersions.auto,
                  size: 220.0,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: CupertinoColors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: CupertinoColors.black,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                config.deviceName ?? 'This Device',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'LAN IP: $_localIp : ${config.port}',
                style: const TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Scan this QR code from your other device to connect.\nBoth devices will pair automatically in two-way sync.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CupertinoColors.secondaryLabel,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanQrView() {
    if (!_isCameraSupported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(CupertinoIcons.qrcode_viewfinder, size: 64, color: CupertinoColors.activeBlue),
              SizedBox(height: 16),
              Text(
                'Scan from your Mobile Device',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
              ),
              SizedBox(height: 8),
              Text(
                'Open Global Clipboard on your phone, select "Scan QR Code", and scan the code displayed on this PC\'s "Show QR Code" tab.\n\nBoth devices will pair automatically with two-way sync.',
                textAlign: TextAlign.center,
                style: TextStyle(color: CupertinoColors.secondaryLabel, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 56,
                color: CupertinoColors.systemRed,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: CupertinoColors.secondaryLabel,
                ),
              ),
              const SizedBox(height: 24),
              CupertinoButton.filled(
                child: const Text('Try Again', style: TextStyle(color: CupertinoColors.white)),
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                    _isProcessing = false;
                  });
                  _scannerController?.start();
                },
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.0),
        child: Stack(
          alignment: Alignment.center,
          children: [
            MobileScanner(
              controller: _scannerController,
              onDetect: (capture) {
                if (_isProcessing) return;
                final barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
                    _processScannedData(barcode.rawValue!);
                    break;
                  }
                }
              },
            ),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: CupertinoColors.activeBlue, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
              width: 240,
              height: 240,
            ),
            Positioned(
              bottom: 30,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Align QR code within the frame',
                  style: TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (_isProcessing)
              Container(
                color: const Color(0x80000000),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CupertinoActivityIndicator(radius: 16, color: CupertinoColors.white),
                      SizedBox(height: 12),
                      Text(
                        'Connecting & Pairing...',
                        style: TextStyle(color: CupertinoColors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _processScannedData(String rawData) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });

    // Stop camera capture immediately so no more frames are processed
    await _scannerController?.stop();

    try {
      final config = ref.read(configProvider);
      final pairingService = ref.read(pairingServiceProvider);
      final syncClient = ref.read(syncClientProvider);

      final pairingInfo = pairingService.parsePairingPayload(rawData);

      // Send Two-Way Handshake back to the target device across candidate IPs
      final localIp = await NetworkUtils.getLocalIpAddress();
      final verifiedIp = await pairingService.sendPairingHandshake(
        targetInfo: pairingInfo,
        localDeviceId: config.deviceId ?? 'device-id',
        localDeviceName: config.deviceName ?? 'Global Clipboard',
        localPort: config.port,
        localIpAddress: localIp,
      );

      debugPrint('Pairing handshake result: verified working IP = $verifiedIp');

      // Complete pairing with the verified working IP
      final pairedDevice = await pairingService.completePairing(pairingInfo, verifiedIp: verifiedIp);

      // Save to local paired devices list
      ref.read(pairedDevicesProvider.notifier).addDevice(pairedDevice);

      // Immediately connect WebSocket client to the newly paired device
      final targetIp = verifiedIp ?? pairedDevice.ipAddress ?? pairingInfo.ipAddress;
      syncClient.connectToPeer(DiscoveredPeer(
        deviceId: pairedDevice.deviceId,
        deviceName: pairedDevice.deviceName,
        ipAddress: targetIp,
        port: pairedDevice.port,
        lastSeen: DateTime.now(),
      ));

      if (mounted) {
        setState(() {
          _isPaired = true;
          _isProcessing = false;
          _pairedDeviceName = pairedDevice.deviceName;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Failed to pair: $e';
        });
      }
    }
  }

  Widget _buildSuccessView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: const BoxDecoration(
              color: CupertinoColors.activeGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.check_mark,
              size: 48,
              color: CupertinoColors.white,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Paired with $_pairedDeviceName!',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your clipboards are now synced in real time.',
            style: TextStyle(
              color: CupertinoColors.secondaryLabel,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 32),
          CupertinoButton.filled(
            child: const Text('Done', style: TextStyle(color: CupertinoColors.white)),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
