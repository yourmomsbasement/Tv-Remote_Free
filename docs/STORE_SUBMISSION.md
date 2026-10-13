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
| No permission prompts beyond local network (file import uses the system pickers) | – |
| Remote rows shrink to fit narrow phones (found while making screenshots) | `remote_panel.dart` |
| Store screenshots, feature graphic, listing text | `store/`, `store/LISTING.md` |
| Signed App Store upload without a Mac | `.github/workflows/release-ios.yml` |

## Things only you can do

1. **Apple Developer Program** ($99/year) — needed for App Store and
   TestFlight. No Mac needed: the *Release iOS to App Store Connect*
   workflow signs and uploads from GitHub's macOS runner (see below).
2. **Google Play Console** ($25 once).
3. **Multicast entitlement** (iOS, optional): Android TV discovery uses
   mDNS, which works without it via Bonjour. SSDP discovery of Roku/LG on
   iOS 14+ needs `com.apple.developer.networking.multicast`, requested at
   https://developer.apple.com/contact/request/networking-multicast. Until
   granted, iPhone users can add those TVs by IP address.
4. **Screenshots** are ready in `store/` (the real app on the demo TV).
   Regenerate them after UI changes; see `store/LISTING.md`.

## App Store Connect

- **Bundle ID:** `org.tvremotefree.tvRemoteFree` (change it to one you own
  before registering it, e.g. `com.<you>.tvremotefree`, in
  `project.pbxproj`).
- **Listing text:** copy from `store/LISTING.md` (name, subtitle,
  promotional text, keywords, description, URLs).
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

### Uploading from GitHub (no Mac)

1. In App Store Connect, create the app record with your bundle ID
   (register it first under Certificates, Identifiers & Profiles).
2. Users and Access → Integrations → App Store Connect API → generate a
   key with the **Admin** role (needed for cloud-managed signing). Note the
   Key ID and Issuer ID and download the `.p8` once.
3. Add repository secrets: `APP_STORE_CONNECT_KEY_ID`,
   `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_BASE64`
   (`base64 -w0 AuthKey_XXXX.p8`), and `APPLE_TEAM_ID` (Membership page).
4. Actions → **Release iOS to App Store Connect** → Run. The build number
   is the run number; bump `version:` in `pubspec.yaml` for each new
   release. The build appears in TestFlight after Apple's processing
   (10–30 minutes); then submit it for review.

Apple requires uploads built with the current Xcode SDK; the workflow picks
the newest Xcode on the runner and prints its version. This workflow hasn't
been run against a real account yet, so expect to check the first run's log.

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
