# Turning on cloud sync (₹0, about 15 minutes)

Until these steps are done, every build is fully offline and the cloud buttons say
"not set up in this build". Nothing breaks.

## 1. Make a release signing key (once, on your laptop)

Google sign-in only works when Firebase knows the app's signing fingerprint, so the
CI must always sign with the same key.

```bash
keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
keytool -list -v -keystore upload.jks -alias upload     # copy the SHA1 line
base64 -w0 upload.jks > upload.jks.b64                  # macOS: base64 -i upload.jks -o upload.jks.b64
```

Keep `upload.jks` and its passwords safe and out of git. Losing it means a new key
(and a new SHA-1 in Firebase).

## 2. Firebase project (Spark plan, no card)

1. https://console.firebase.google.com → **Add project** → name `TripKhata`. Analytics is optional.
2. **Add app → Android**
   - Package name: `com.tripkhata.tripkhata`
   - SHA-1: the one from step 1 (add your debug SHA-1 too if you run locally:
     `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`)
   - Download `google-services.json`. You only need a few values from it (below); don't commit it.
3. **Build → Authentication → Sign-in method → Google → Enable → Save.**
   Then download `google-services.json` again: it now contains the web client ID.
4. **Build → Firestore Database → Create database** → production mode → location
   `asia-south1 (Mumbai)`.
5. Firestore → **Rules** → paste the contents of [`firestore.rules`](../firestore.rules) → Publish.

## 3. GitHub secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Where to find it |
| --- | --- |
| `FIREBASE_API_KEY` | `google-services.json` → `client[0].api_key[0].current_key` |
| `FIREBASE_APP_ID` | `client[0].client_info.mobilesdk_app_id` |
| `FIREBASE_PROJECT_ID` | `project_info.project_id` |
| `FIREBASE_SENDER_ID` | `project_info.project_number` |
| `GOOGLE_WEB_CLIENT_ID` | `client[0].oauth_client[]` entry with `"client_type": 3` → `client_id` |
| `KEYSTORE_BASE64` | contents of `upload.jks.b64` |
| `KEYSTORE_PASSWORD` | store password from step 1 |
| `KEY_ALIAS` | `upload` |
| `KEY_PASSWORD` | key password from step 1 |

## 4. Build

Push any commit (or Actions → build → **Run workflow**). The new APK has cloud sync on.
Uninstall the old APK first: it was signed with a different (debug) key.

## How sync works

- The phone's database stays the source of truth. A trip goes to the cloud only when you
  tap the cloud button on the trip and share it.
- Edits to a shared trip are queued and pushed; with no signal, Firestore holds them and
  sends them later. Friends' edits arrive through live listeners.
- Friends join with the 6-character code (+ → Join a friend's trip), pick which member
  they are, and their balance shows as "You".
- Conflicts: the latest edit to an expense wins. Deleted expenses are kept as a
  `deleted` marker so every phone removes them.

## Free-tier limits

Spark plan: 1 GiB stored, 50,000 reads and 20,000 writes per day. A 6-person trip with
100 expenses is a few hundred writes in total. With no card on file, going over can only
pause sync for the day; it can never create a bill.

To run locally with cloud on:

```bash
flutter run --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_SENDER_ID=... \
  --dart-define=GOOGLE_WEB_CLIENT_ID=...
```
