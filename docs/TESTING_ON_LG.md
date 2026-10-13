# Testing on an LG webOS TV

This guide gets the app onto your phone and walks through checking it
against a real LG TV. Nothing has been verified on real hardware yet, so
what you find here fills in [`COMPATIBILITY.md`](COMPATIBILITY.md).

## 1. Prepare the TV

1. Turn the TV on and connect it to the **same Wi-Fi network** as your
   phone. A guest network, or a router with "AP/client isolation", stops
   the phone from seeing the TV.
2. **Allow phone control.** The menu names vary by year:
   - **webOS 2022 and later:** Settings → General → Devices → External
     Devices → **TV On With Mobile** → *Turn on via Wi-Fi*.
   - **webOS 2018–2021:** Settings → Connection (or General) → Mobile
     Connection Management → **TV On With Mobile**.
   - **webOS 2014–2017:** Settings → Network → **LG Connect Apps** → On.

   This also lets the phone wake the TV from standby (Wake-on-LAN).
3. **Note the TV's IP address** in case automatic discovery doesn't find
   it: Settings → Network → Wi-Fi Connection (or Wired) → Advanced
   Settings. It looks like `192.168.1.23`.
4. Keep the TV's own remote nearby. You'll need it once, to accept the
   pairing prompt.

## 2. Install the app on your phone

### Option A — Android, no tools needed (easiest)

Every push to `master` builds an APK on GitHub.

1. Open the repository on GitHub → **Actions** → **Build Android APK** →
   the latest green run.
2. Under **Artifacts**, download **tv-remote-free-apk**. It's a zip; unzip
   it to get `app-release.apk`. You need to be signed in to GitHub.
3. Copy the APK to your phone, or download it there directly, and open it.
   Android asks you to allow installing from that source (Files or
   Chrome). Allow it.
4. Play Protect may warn that the app is from an unknown developer. That's
   expected for a test build: choose *Install anyway*.

To rebuild without pushing code, use **Run workflow** on the same Actions
page.

### Option B — Android, build it yourself

1. Install [Flutter](https://docs.flutter.dev/get-started/install) (3.47+)
   and Android Studio (for the Android SDK). Run `flutter doctor` until the
   Android section is green.
2. On the phone, enable **Developer options** (tap *Build number* seven
   times in Settings → About phone), then turn on **USB debugging**.
3. Connect the phone by USB and accept the prompt on the phone.
4. In the project folder:

   ```sh
   flutter pub get
   flutter run --release        # installs and starts the app on the phone
   ```

   Or `flutter build apk --release` and install
   `build/app/outputs/flutter-apk/app-release.apk`.

### Option C — iPhone

This needs a Mac with Xcode. A free Apple ID works, but the app stops
launching after 7 days until you reinstall it.

1. Install Flutter and Xcode, then run `cd ios && pod install`.
2. Open `ios/Runner.xcworkspace` in Xcode → Runner target → Signing &
   Capabilities → choose your team, and change the bundle identifier to
   something unique.
3. Connect the iPhone, then run `flutter run --release`. On the phone,
   trust the developer under Settings → General → VPN & Device Management.
4. **Automatic discovery won't work on iPhone** without Apple's multicast
   entitlement, so use **Add by IP**. When iOS asks for *Local Network*
   access, allow it.

## 3. Connect and pair

1. Open the app. The **TVs** screen scans for a few seconds. Your TV should
   appear under *On this network* as "LG webOS". If it doesn't, tap
   **Add by IP**, enter the address from step 1.3, and choose *LG webOS*.
2. Tap the TV. A prompt appears **on the TV** asking to allow the
   connection. Accept it with the TV remote. The app shows "Waiting for
   approval on TV" until you do.
3. The app saves the TV. Next time it connects without a prompt.

## 4. What to test

Tick each item and note anything odd: what you did, what happened, and
what you expected.

**Remote tab**
- [ ] Arrows and OK move around the TV menus.
- [ ] Holding an arrow repeats, then stops when you let go.
- [ ] Back, Home, Menu and Info work.
- [ ] Volume +/–, Mute and the volume slider work, and the slider follows
      changes made with the TV remote.
- [ ] Channel +/– works on live TV.
- [ ] Play/Pause/Stop/Rewind/Fast-forward work in a video app.
- [ ] Power off turns the TV off.
- [ ] With the TV in standby, the **Turn on** button in the banner wakes
      it (needs *TV On With Mobile*, and the app must have connected once
      so it knows the TV's MAC address).

**Touchpad tab**
- [ ] Dragging moves the TV's pointer (magic-remote cursor).
- [ ] Tapping clicks.

**Keyboard tab (the main feature)**
- [ ] Open YouTube's search on the TV. The phone's keyboard should open on
      its own (auto-open).
- [ ] Typing appears on the TV as you type, with no doubled letters.
- [ ] Deleting and editing in the middle of the word end up correct on the
      TV.
- [ ] Emoji and accented letters (é, ñ) arrive correctly, or note what
      happens instead.
- [ ] **Enter** submits the search.
- [ ] Paste from the phone's clipboard works.
- [ ] Repeat in Netflix search, the web browser's address bar and the TV's
      own search.
- [ ] In a password field (e.g. an app login), the phone field hides the
      text.

**Apps tab**
- [ ] The installed apps are listed, and tapping one opens it.

**Connection**
- [ ] Turning the TV off and on again: the app shows *Reconnecting…* and
      recovers.
- [ ] Leaving the app and coming back reconnects without a prompt.
- [ ] Forgetting the TV (⋮ → Forget) and connecting again shows the TV
      prompt again.

## 5. Report results

Include your **TV model** (Settings → General → About This TV, e.g.
`OLED55C1PUB`), the **webOS version**, and your **phone model / OS
version**. Open a GitHub issue with the checklist, or paste it into a
Claude session and ask to update `COMPATIBILITY.md` and fix what failed.

## Troubleshooting

| Symptom | Try |
|---|---|
| TV not found by the scan | Use *Add by IP*. Check both devices are on the same network (not guest Wi-Fi), and that the router doesn't isolate clients. |
| "Cannot reach LG TV" | The TV is off or asleep, *TV On With Mobile* / *LG Connect Apps* is off, or the IP changed. Reserve the TV's IP in your router to stop it changing. |
| No prompt on the TV | The TV may already have a pending prompt behind another screen. Press Home on the TV remote and try again. |
| "Pairing was declined" | The prompt was rejected or timed out. Connect again and accept it. |
| Keyboard types nothing | Make sure a text field on the TV is selected. Some apps use their own keyboard, which may ignore remote text. Note which app this happens in. |
