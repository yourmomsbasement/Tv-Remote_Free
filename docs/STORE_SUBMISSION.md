# Submitting to the App Store and Google Play

The repository is ready for review. This checklist covers what the code
already handles and the steps only the account owner can take.

## Already done in the code

| Requirement | Where |
|---|---|
| Original app icon, no alpha (iOS), adaptive + monochrome (Android) | `assets/icon/`, `tool/make_icon.py` |
| Privacy manifest (no tracking, required-reason APIs declared) | `ios/Runner/PrivacyInfo.xcprivacy` |
| Local network usage text + Bonjour services | `ios/Runner/Info.plist` |
| Export compliance (`ITSAppUsesNonExemptEncryption` = NO) | `ios/Runner/Info.plist` |
| iPhone only (no iPad screenshots required) | `TARGETED_DEVICE_FAMILY = 1` |
| Privacy policy in app and by URL | Settings → Privacy, `docs/PRIVACY.md` |
| Demo mode for reviewers without a TV | TVs screen → "Try the demo TV" |
| Release signing for Play (upload key from CI secrets) | `android/app/build.gradle.kts`, `.github/workflows/release-android.yml` |
| Target SDK 36, no backup of pairing keys | Flutter defaults, `AndroidManifest.xml` |
| No ads, purchases, accounts or analytics | – |

## Things only you can do

1. **Apple Developer Program** ($99/year) — needed for App Store and
   TestFlight. Requires a Mac or a cloud Mac (e.g. GitHub's macOS runner,
   Codemagic) to sign and upload.
2. **Google Play Console** ($25 once).
3. **Multicast entitlement** (iOS, optional): Android TV discovery uses
   mDNS, which works without it via Bonjour. SSDP discovery of Roku/LG on
   iOS 14+ needs `com.apple.developer.networking.multicast`, requested at
   https://developer.apple.com/contact/request/networking-multicast. Until
   granted, iPhone users can add those TVs by IP address.
4. **Screenshots** from a real device (or the demo TV): iPhone 6.9" (1320 ×
   2868) and Android phone. Do not show other companies' logos prominently.

## App Store Connect

- **Bundle ID:** `org.tvremotefree.tvRemoteFree` (change it to one you own
  before registering it, e.g. `com.<you>.tvremotefree`, in
  `project.pbxproj`).
- **Name:** TV Remote Free. **Subtitle:** Roku, Samsung, LG, Android TV (30-character limit).
- **Category:** Utilities. **Price:** Free. **Age rating:** 4+.
- **Privacy policy URL:**
  https://github.com/yourmomsbasement/Tv-Remote_Free/blob/master/docs/PRIVACY.md
- **App Privacy:** "Data Not Collected".
- **Export compliance:** uses only standard encryption (TLS) — exempt.
- **Review notes** (paste):

  > This app controls smart TVs on the user's Wi-Fi network (Roku, LG
  > webOS, Samsung Tizen, Android TV / Google TV). If no TV is available, tap "Try the
  > demo TV" on the first screen: it simulates a TV so every feature
  > (remote, keyboard, touchpad, apps, watchlist, macros, profiles,
  > themes, custom remotes) can be tried. No account or login is needed.
  > The app does not connect to the internet.

- **Trademarks:** describe compatibility as "works with Roku / Samsung / LG
  webOS / Android TV"; do not use their logos in the icon or as the app name
  (guideline 5.2).

## Google Play

1. Create the upload key once (keep a backup — losing it needs Play
   support to reset):

   ```sh
   keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 \
     -validity 10000 -alias upload
   base64 -w0 upload.jks > upload.jks.b64
   ```

2. Add repository secrets: `ANDROID_KEYSTORE_BASE64` (contents of
   `upload.jks.b64`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`
   (`upload`), `ANDROID_KEY_PASSWORD`.
3. Run **Actions → Release Android App Bundle**, download the `.aab` and
   upload it to an internal-testing track. Enable Play App Signing.
4. Change `applicationId` in `android/app/build.gradle.kts` first if you
   want an ID under your own name — it can never change after upload.
5. Bump `version:` in `pubspec.yaml` (`1.0.0+1` → `1.0.1+2`) for every
   upload.

**Store listing answers**

- **Data safety:** no data collected, no data shared. Data is not
  encrypted in transit to the developer because nothing is sent.
- **Ads:** no. **App access:** all functionality available without
  special access (mention the demo TV).
- **Target audience:** 13 and over (keeps the app out of the Families
  programme; it is not designed for children).
- **Content rating:** complete the IARC questionnaire — Utility, no
  violence, no user-to-user communication → Everyone.
- **New personal accounts:** Google requires a closed test with at least
  12 testers for 14 days before production access.
