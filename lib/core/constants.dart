/// App-wide constants for the Global Clipboard application.
class AppConstants {
  static const String appName = 'Global Clipboard';
  static const String appVersion = '1.5.0';
  
  // mDNS service configuration
  static const String serviceType = '_globalclip._tcp';
  static const int defaultPort = 9876;
  
  // Clipboard monitoring
  static const Duration pollInterval = Duration(milliseconds: 500);
  
  // WebSocket
  static const Duration heartbeatInterval = Duration(seconds: 15);
  static const Duration reconnectBaseDelay = Duration(seconds: 1);
  static const Duration reconnectMaxDelay = Duration(seconds: 30);
  
  // History
  static const int defaultMaxHistoryEntries = 500;
  
  // Security
  static const int pbkdf2Iterations = 10000;
  static const int aesKeyLength = 256;
  static const int ivLength = 12; // 96-bit for GCM
  
  // Method channels
  static const String clipboardChannel = 'com.globalclipboard/clipboard';
  
  // Banner display
  static const Duration bannerDisplayDuration = Duration(milliseconds: 1500);
}
