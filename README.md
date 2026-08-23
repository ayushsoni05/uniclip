# UniClip (Global Clipboard) 📋✨

> **Seamless, real-time, cross-platform clipboard synchronization like Apple's iOS Universal Clipboard — built for Android, Windows, and Web with end-to-end encryption.**

---

## 🚀 Features

* **⚡ Real-Time Zero-Config Sync**: Automatically discovers devices on your local network (LAN) via **Bonjour / mDNS (`_globalclip._tcp`)** and syncs clipboard changes with low-latency WebSockets.
* **📱 Pixel-Perfect iOS UI**: Crafted with 100% Cupertino design system components (`CupertinoPageScaffold`, `CupertinoListSection.insetGrouped`, `CupertinoSwitch`, and custom frosted glass blur effects).
* **🔔 Signature "Pasting from..." Dropdown Banner**: Animated pill banner with a progress indicator and completion checkmark whenever clipboard data is received from a paired device.
* **🔒 End-to-End Encryption**: Authenticated **AES-256-GCM** encryption with unique 96-bit IVs and **PBKDF2-HMAC-SHA256** key derivation (600,000 iterations).
* **📷 QR Code Pairing**: Simple one-tap cryptographic handshake via dynamic QR generation and camera scanning.
* **📚 Clipboard History**: Searchable clipboard history with device origin tags and tap-to-copy.
* **🤖 Android Background Foreground Service**: Android 14+ compliant foreground service (`dataSync` type) with native `ClipboardManager` MethodChannel bridge.
* **💻 Windows System Tray & Native Window Manager**: Minimize-to-tray and native Win32 clipboard monitoring.

---

## 🏗️ Architecture

```
                                  ┌───────────────────────────┐
                                  │   System Clipboard (OS)   │
                                  └─────────────┬─────────────┘
                                                │ (poll / change listener)
                                                ▼
                                  ┌───────────────────────────┐
                                  │     ClipboardMonitor      │
                                  │   (SHA-256 echo detect)   │
                                  └─────────────┬─────────────┘
                                                │
                      ┌─────────────────────────┴─────────────────────────┐
                      │ (when local copy)                                 │ (when remote payload)
                      ▼                                                   ▼
        ┌───────────────────────────┐                       ┌───────────────────────────┐
        │       CryptoService       │                       │       CryptoService       │
        │       (AES-256-GCM)       │                       │       (AES-256-GCM)       │
        └─────────────┬─────────────┘                       └─────────────┬─────────────┘
                      │                                                   │
                      ▼                                                   ▼
        ┌───────────────────────────┐                       ┌───────────────────────────┐
        │   SyncClient (WebSocket)  │                       │   Signature Dropdown      │
        │   (broadcast to peers)    │                       │   "Pasting from..." Banner│
        └─────────────┬─────────────┘                       └─────────────┬─────────────┘
                      │                                                   │
                      ▼                                                   ▼
        ┌───────────────────────────┐                       ┌───────────────────────────┐
        │  Local Network (Bonjour)  │                       │  Updated System Clipboard │
        │  mDNS Discovery Engine    │                       │  + SQLite History DB      │
        └───────────────────────────┘                       └───────────────────────────┘
```

---

## 📂 Project Structure

```
lib/
├── main.dart                         # Entry point & window/overlay lifecycle
├── core/
│   ├── app.dart                      # Background service orchestrator
│   ├── config.dart                   # SharedPreferences configuration
│   └── constants.dart                # App constants & protocol specs
├── clipboard/
│   ├── clipboard_service.dart        # Platform-agnostic clipboard abstraction
│   ├── clipboard_monitor.dart        # Real-time change listener & echo prevention
│   └── clipboard_history.dart        # SQLite / in-memory history management
├── network/
│   ├── discovery_service.dart        # Bonjour / mDNS zero-config discovery
│   ├── sync_server.dart              # WebSocket server
│   ├── sync_client.dart              # WebSocket client with auto-reconnect
│   └── message_protocol.dart         # Typed SyncMessage protocol
├── security/
│   ├── crypto_service.dart           # AES-256-GCM authenticated encryption
│   ├── key_manager.dart              # PBKDF2 key derivation & secure storage
│   └── pairing_service.dart          # QR code cryptographic pairing
├── providers/
│   ├── clipboard_providers.dart      # Riverpod clipboard & crypto providers
│   ├── device_providers.dart         # Paired device state management
│   ├── network_providers.dart        # Discovery & sync providers
│   └── settings_providers.dart       # App configuration state
└── ui/
    ├── theme/
    │   ├── ios_theme.dart            # iOS 17 Cupertino design system & colors
    │   └── blur_widgets.dart         # Frosted glass blur widgets
    ├── widgets/
    │   ├── paste_banner.dart         # Iconic "Pasting from..." animated banner
    │   ├── ios_settings_group.dart   # Inset grouped settings cells
    │   ├── device_card.dart          # Device card widget
    │   ├── history_tile.dart         # Clipboard history tile
    │   └── status_indicator.dart     # Connection status dot
    ├── overlays/
    │   └── banner_overlay.dart       # Global banner overlay coordinator
    └── screens/
        ├── home_screen.dart          # Home status & paired device manager
        ├── settings_screen.dart      # iOS Settings screen
        ├── pairing_screen.dart       # QR code generator & camera scanner
        ├── history_screen.dart       # Clipboard history list with search
        └── device_detail_screen.dart # Paired device info & unpair screen
```

---

## 🛠️ Getting Started

### Prerequisites
* Flutter SDK (3.29.0 or higher)
* Dart SDK (3.7.1 or higher)
* Java 17 (for Android builds)

### Installation
```bash
# Clone the repository
git clone https://github.com/ayushsoni05/uniclip.git
cd uniclip

# Install dependencies
flutter pub get
```

### Running on Windows
```bash
# Make sure Developer Mode is enabled in Windows Settings
flutter run -d windows
```

### Running on Android
```bash
# Connect device with USB Debugging enabled
flutter run
```

### Running on Web
```bash
flutter run -d chrome --web-port 8080
```

### Running Tests
```bash
flutter test
flutter analyze
```

---

## 📄 License
MIT License
