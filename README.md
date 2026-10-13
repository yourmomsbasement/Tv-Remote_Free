# TV Remote Free

A free, open-source smart TV remote for Android and iOS, built with Flutter.
It works entirely on your local Wi-Fi: no accounts, ads, tracking or paid
features. Its main feature is typing into TV text fields with the phone's own
keyboard.

The full design is in [`docs/TECHNICAL_DESIGN.md`](docs/TECHNICAL_DESIGN.md);
what works on which TV is in [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md).

## Status

This is the first milestone (design phases 1–2, plus the keyboard, touchpad and
app-launcher work from phases 3–4) for **Roku** and **LG webOS**. Android TV,
Samsung Tizen, Fire TV and Apple TV are not implemented yet.

**Nothing has been tested on a physical TV yet.** Both adapters are tested
against mock protocol servers only. See the compatibility matrix.

| Area | State |
|---|---|
| Flutter app (Android + iOS), Riverpod, Material 3 light/dark themes | ✅ |
| Unified adapter contract with capability gating and structured errors | ✅ |
| SSDP discovery, manual IP entry, saved TVs, favorites, rooms | ✅ |
| SQLite metadata storage; pairing secrets in Keychain/Keystore | ✅ |
| Roku ECP adapter | ✅ (mock-tested) |
| LG webOS adapter (pairing prompt, pointer, IME text, focus events) | ✅ (mock-tested) |
| Keyboard subsystem: diffed edits, batching, state machine, live/manual send | ✅ |
| Touchpad (pointer on webOS, swipe-to-arrows elsewhere) | ✅ |
| App launcher | ✅ |
| Wake-on-LAN power on, auto-reconnect with backoff | ✅ |
| Haptics, left-handed layout, TalkBack/VoiceOver labels | ✅ |
| Android TV, Samsung, Fire TV, Apple TV adapters | — |
| mDNS discovery (needed for Android TV) | — |
| Widgets, Quick Settings tile, macros, IR, voice | — |

## Architecture

```
lib/
  app/              App shell and top-level providers
  core/
    adapter/        SmartTVAdapter contract, ProtocolDriver (discovery + factory)
    capabilities/   DeviceCapabilities, RemoteKey
    connection/     Backoff, Wake-on-LAN
    discovery/      SSDP client, DiscoveryService
    security/       CredentialStore (flutter_secure_storage)
    storage/        SQLite DeviceRepository
  protocols/
    roku/           ECP over HTTP :8060
    lg_webos/       SSAP over WebSocket :3001 (wss) / :3000 (ws)
    registry.dart   The drivers this build ships
  features/
    remote/         RemoteSession (unified controller) and the remote screen
    keyboard/       TextEdit diff, KeyboardController state machine, panel
    touchpad/  applications/  devices/  settings/
  ui/               Shared components (RemoteButton, DPad) and themes
```

- **Adapters** (`SmartTVAdapter`) speak one protocol. Every method is
  capability-gated and throws `TvRemoteException` with a `TvErrorCode` instead
  of failing silently.
- **Drivers** (`ProtocolDriver`) tell discovery how to find a protocol's TVs
  and build adapters for them. Adding a platform means adding a driver to
  `protocols/registry.dart`; the UI needs no changes.
- **`RemoteSession`** is the unified controller. It owns the active adapter,
  checks capabilities before routing commands, saves pairing keys to the
  secure store, persists device info, and reconnects with backoff.
- **The UI hides controls** that the connected TV does not report as
  supported.

### Keyboard

`KeyboardController` implements the design's state machine (`disconnected →
connected → textFieldDetected → keyboardActive → textEditing → textSubmitted →
keyboardClosed`). It remembers what it has already sent and transmits only the
difference (`TextEdit.between`, computed on Unicode code points), batched over
a configurable 20–75 ms window. That works for append-only TVs (Roku `Lit_`
keypresses plus Backspace) and for text APIs (webOS IME insert/delete) alike,
and it never resends the whole buffer. Edits are serialized so they arrive in
order. Text is never logged, and buffers are cleared on submit, focus loss
and disconnect.

## Development

Requires Flutter 3.47 or later.

```sh
flutter pub get
flutter analyze
flutter test
flutter run            # on a device or emulator on the same Wi-Fi as the TV
```

Tests run the real adapters against local mock servers: an HTTP server for
Roku ECP and a WebSocket server for webOS SSAP, including the pairing prompt,
the pointer socket and IME focus events. Repository tests use in-memory
SQLite through `sqflite_common_ffi`, which needs the system `libsqlite3`
(`apt install libsqlite3-dev` on Debian/Ubuntu).

### Platform notes

- **Android:** cleartext traffic is allowed because Roku ECP and webOS
  port 3000 are plain HTTP/WS on the LAN (see
  `android/app/src/main/res/xml/network_security_config.xml`). The app makes
  no internet requests.
- **iOS:** `NSLocalNetworkUsageDescription` and `NSAllowsLocalNetworking`
  are set. SSDP discovery also needs the
  `com.apple.developer.networking.multicast` entitlement, which Apple must
  grant to your team. Add it to `Runner.entitlements` once you have it. Until
  then, use *Add by IP*.

## License

[Apache License 2.0](LICENSE). Roku, LG and webOS are trademarks of their
respective owners. This project is not affiliated with or endorsed by them.
