# Compatibility matrix

**Status key:** ✅ implemented and covered by mock-server tests · ⚠️ implemented
with a caveat · ❌ not supported by the protocol · — not yet implemented

> **No row has been verified on a physical TV yet.** The design requires
> physical-device regression testing before release; until then every entry
> describes what the adapter implements against the protocol, not a tested
> model. Contributions of test results (model, firmware, result) are welcome.

| Feature | Roku (ECP) | LG webOS (SSAP) | Android TV | Samsung Tizen |
|---|---|---|---|---|
| SSDP discovery | ✅ `roku:ecp` | ✅ `webos-second-screen` | — (mDNS) | — |
| Manual IP entry | ✅ | ✅ | — | — |
| Pairing | ❌ none needed | ✅ on-screen prompt → client key | — | — |
| Secure credential storage | n/a | ✅ Keychain / Keystore | — | — |
| D-pad, OK, Back, Home | ✅ | ✅ | — | — |
| Volume up/down, mute | ⚠️ Roku TVs only | ✅ | — | — |
| Set exact volume | ❌ | ✅ | — | — |
| Channel up/down | ⚠️ Roku TVs only | ✅ | — | — |
| Media keys | ✅ play/pause toggle, rew, ffwd, replay | ✅ play, pause, stop, rew, ffwd | — | — |
| Power off | ⚠️ Roku TVs and players reporting `supports-suspend` | ✅ | — | — |
| Power on | ⚠️ `PowerOn` key (needs Fast TV Start) or Wake-on-LAN | ⚠️ Wake-on-LAN (TV setting must allow it) | — | — |
| Text input | ✅ character events (append-only) | ✅ IME insert/delete API | — | — |
| Text-field focus detection | ❌ | ✅ IME `registerRemoteKeyboard` | — | — |
| Auto-open keyboard | ❌ (manual) | ✅ | — | — |
| Password fields | ⚠️ typed like any text | ✅ flagged as sensitive by the TV | — | — |
| Pointer / touchpad cursor | ❌ (swipe → arrows) | ✅ | — | — |
| App list and launch | ✅ | ✅ | — | — |
| Input switching | — | ⚠️ opens the input hub | — | — |

## Known limitations

- **Roku "Control by mobile apps."** If set to *Limited* or *Disabled*,
  Roku answers HTTP 403. The app explains where to change it.
- **Roku text** is append-only: editing the middle of the phone text
  deletes back to the change and retypes the rest. The app never resends
  the whole buffer.
- **Router client isolation / multicast filtering** can hide TVs from the
  scan. Use *Add by IP* in that case.
- **iOS multicast.** Sending SSDP multicast on iOS 14+ requires the
  `com.apple.developer.networking.multicast` entitlement, which Apple grants
  on request. Without it, use *Add by IP*.
- **webOS TLS.** Newer firmware only accepts `wss://` on port 3001 with a
  self-signed certificate. The app accepts that certificate only for the
  TV's own address.
