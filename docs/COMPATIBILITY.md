# Compatibility matrix

**Status key:** ✅ implemented and covered by mock-server tests · ⚠️ implemented
with a caveat · ❌ not supported by the protocol · — not yet implemented

> **Physical-device results so far (October 2026):** a user confirmed the
> app working with a Roku and an LG webOS TV, including phone-keyboard
> typing. Models and firmware weren't recorded, and the rest of the matrix
> is still verified only against mock protocol servers. Android TV hasn't
> been tried on hardware yet, and neither has Samsung. Contributions of test results (model,
> firmware, result) are welcome.

| Feature | Roku (ECP) | LG webOS (SSAP) | Android TV / Google TV (Remote v2) | Samsung Tizen (2016+) |
|---|---|---|---|---|
| Discovery | ✅ `roku:ecp` | ✅ `webos-second-screen` | ✅ mDNS `_androidtvremote2._tcp` | ✅ SSDP `RemoteControlReceiver` + REST `:8001/api/v2/` |
| Manual IP entry | ✅ | ✅ | ✅ | ✅ |
| Pairing | ❌ none needed | ✅ on-screen prompt → client key | ✅ 6-character code on screen, TLS client certificate | ✅ Allow prompt on screen → token (2018+); older models just allow |
| Secure credential storage | n/a | ✅ Keychain / Keystore | ✅ client key + pinned TV certificate | ✅ token in Keychain / Keystore |
| D-pad, OK, Back, Home | ✅ | ✅ | ✅ | ✅ |
| Volume up/down, mute | ⚠️ Roku TVs only | ✅ | ✅ (controls the TV or the connected audio device) | ✅ |
| Set exact volume | ❌ | ✅ | ❌ (level is reported but cannot be set) | ❌ |
| Channel up/down | ⚠️ Roku TVs only | ✅ | ⚠️ only on TVs with a tuner | ✅ |
| Media keys | ✅ play/pause toggle, rew, ffwd, replay | ✅ play, pause, stop, rew, ffwd | ✅ play, pause, play/pause, stop, rew, ffwd | ✅ play, pause, stop, rew, ffwd (no toggle) |
| Power off | ⚠️ Roku TVs and players reporting `supports-suspend` | ✅ | ✅ `KEYCODE_SLEEP` | ✅ `KEY_POWER` |
| Power on | ⚠️ `PowerOn` key (needs Fast TV Start) or Wake-on-LAN | ⚠️ Wake-on-LAN (TV setting must allow it) | ⚠️ `KEYCODE_WAKEUP` while the remote service is reachable in standby | ⚠️ Wake-on-LAN (needs *Power On with Mobile* enabled) |
| Text input | ✅ character events (append-only) | ✅ IME insert/delete API | ⚠️ IME edit API; replace-whole-field semantics unverified on hardware | ⚠️ `SendInputString`; replace-whole-field semantics unverified on hardware |
| Text-field focus detection | ❌ | ✅ IME `registerRemoteKeyboard` | ⚠️ IME show request (unverified on hardware) | ✅ `ms.remote.imeStart` / `imeEnd` |
| Auto-open keyboard | ❌ (manual) | ✅ | ⚠️ as above | ✅ |
| Password fields | ⚠️ typed like any text | ✅ flagged as sensitive by the TV | ⚠️ not flagged by the protocol | ⚠️ not flagged by the protocol |
| Pointer / touchpad cursor | ❌ (swipe → arrows) | ✅ | ❌ (swipe → arrows) | ⚠️ `ProcessMouseDevice` (web browser only) |
| App list and launch | ✅ | ✅ | ⚠️ no list; opens well-known app links if installed | ✅ installed apps, icons, links open in the TV browser |
| Input switching | — | ⚠️ opens the input hub | ✅ `KEYCODE_TV_INPUT` | ✅ `KEY_SOURCE` |

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
- **Samsung "Access notification".** Under *Settings › General › External
  Device Manager › Device Connection Manager*, *Access Notification* must be
  on (or the phone already allowed) for the prompt to appear. A phone
  denied once stays blocked until it is removed from the *Device List*
  there.
- **Samsung typing** sends the whole field each time (the protocol's
  `SendInputString`), starting from what the TV reports. Some apps ignore
  it; the TV's on-screen keyboard always works.
- **Demo TV.** "Try the demo TV" on the TVs screen is a simulated TV for
  trying the app (and for app-store review). It is never found on the
  network and supports every feature.

## Other TV platforms (research)

| Platform | Local protocol | Status |
|---|---|---|
| Samsung Tizen 2016+ | WebSocket `:8001`/`:8002` | ✅ implemented (above) |
| Samsung pre-2016 (Orsay) | Legacy TCP `:55000` | Not planned: few in use, no encryption |
| Amazon Fire TV / Fire TV smart TVs | No public LAN remote API; the Fire TV app uses an Amazon-signed protocol. ADB over network works but needs Developer Options and is unsafe to expose | Not planned. Fire TV *Omni* / Toshiba / Insignia Fire TVs are reachable only through ADB |
| Google TV / Android TV TVs (Sony, TCL, Hisense, Philips, Sharp) | Android TV Remote v2 | ✅ already supported |
| Sony Bravia | Android TV Remote v2, plus Bravia REST/IRCC (`/sony/…`, pre-shared key) | ✅ via Android TV; a Bravia adapter could add exact volume and inputs |
| Vizio SmartCast | HTTPS REST `:7345`/`:9000`, PIN pairing | Candidate for next adapter |
| Hisense / Toshiba VIDAA | MQTT over TLS `:36669` with a client certificate extracted from the vendor app | Not planned: needs vendor keys |
| Philips (Saphi) / JointSpace | REST `:1925` (HTTPS, digest auth after PIN) | Candidate |
| Panasonic Viera | SOAP `:55000` (encrypted pairing on 2019+) | Candidate |
| Apple TV | Companion / MRP over AirPlay, HAP-style pairing | Not planned: undocumented and changes with tvOS |
| Chromecast (no remote) | Cast protocol (needs Google receiver ids) | Not planned |
| Xbox / PlayStation | Proprietary (SmartGlass retired) | Not planned |
