# Compatibility matrix

**Status key:** ✅ implemented and covered by mock-server tests · ⚠️ implemented
with a caveat · ❌ not supported by the protocol · — not yet implemented

> **No row has been verified on a physical TV yet.** The design requires
> physical-device regression testing before release; until then every entry
> describes what the adapter implements against the protocol, not a tested
> model. Contributions of test results (model, firmware, result) are welcome.

| Feature | Roku (ECP) | LG webOS (SSAP) | Android TV / Google TV (Remote v2) | Samsung Tizen |
|---|---|---|---|---|
| Discovery | ✅ `roku:ecp` | ✅ `webos-second-screen` | ✅ mDNS `_androidtvremote2._tcp` | — |
| Manual IP entry | ✅ | ✅ | ✅ | — |
| Pairing | ❌ none needed | ✅ on-screen prompt → client key | ✅ 6-character code on screen, TLS client certificate | — |
| Secure credential storage | n/a | ✅ Keychain / Keystore | ✅ client key + pinned TV certificate | — |
| D-pad, OK, Back, Home | ✅ | ✅ | ✅ | — |
| Volume up/down, mute | ⚠️ Roku TVs only | ✅ | ✅ (controls the TV or the connected audio device) | — |
| Set exact volume | ❌ | ✅ | ❌ (level is reported but cannot be set) | — |
| Channel up/down | ⚠️ Roku TVs only | ✅ | ⚠️ only on TVs with a tuner | — |
| Media keys | ✅ play/pause toggle, rew, ffwd, replay | ✅ play, pause, stop, rew, ffwd | ✅ play, pause, play/pause, stop, rew, ffwd | — |
| Power off | ⚠️ Roku TVs and players reporting `supports-suspend` | ✅ | ✅ `KEYCODE_SLEEP` | — |
| Power on | ⚠️ `PowerOn` key (needs Fast TV Start) or Wake-on-LAN | ⚠️ Wake-on-LAN (TV setting must allow it) | ⚠️ `KEYCODE_WAKEUP` while the remote service is reachable in standby | — |
| Text input | ✅ character events (append-only) | ✅ IME insert/delete API | ⚠️ IME edit API; replace-whole-field semantics unverified on hardware | — |
| Text-field focus detection | ❌ | ✅ IME `registerRemoteKeyboard` | ⚠️ IME show request (unverified on hardware) | — |
| Auto-open keyboard | ❌ (manual) | ✅ | ⚠️ as above | — |
| Password fields | ⚠️ typed like any text | ✅ flagged as sensitive by the TV | ⚠️ not flagged by the protocol | — |
| Pointer / touchpad cursor | ❌ (swipe → arrows) | ✅ | ❌ (swipe → arrows) | — |
| App list and launch | ✅ | ✅ | ⚠️ no list; opens well-known app links if installed | — |
| Input switching | — | ⚠️ opens the input hub | ✅ `KEYCODE_TV_INPUT` | — |

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
- **Android TV text.** The IME edit message carries the whole field value,
  so the adapter mirrors the field and sends the full value after each edit.
  If the TV reports the field's content, typing continues from it. Clearing
  the field entirely falls back to Delete key presses. Whether every app's
  text field honours this needs checking on real devices.
- **Android TV pairing** needs the "Android TV Remote Service" system app
  (present on Google TV and most Android TV devices). If pairing keeps
  failing, clearing that app's storage on the TV resets it.
