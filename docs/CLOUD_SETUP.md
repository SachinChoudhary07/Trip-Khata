# Cloud sync setup

**Status:** Firebase project `flutter-apps-975a6`, Android app `com.trip_khata.trip_khata`.
The Firebase settings are built into the app (`lib/features/cloud/cloud_sync.dart`) and CI
builds are signed with the shared test key in `keystore/`, so no GitHub secrets are needed.

Three things must be done once in the Firebase console:

1. **Project settings → Your apps → `com.trip_khata.trip_khata` → Add fingerprint**
   - SHA-1: `88:53:46:7E:EB:AF:B0:9D:66:19:2E:E6:E7:9E:92:EC:2F:6C:0E:39`
   - SHA-256: `D2:7E:0D:45:7F:5C:17:FB:D9:EC:86:0C:1A:FB:24:A1:E4:C8:7F:8D:FF:9E:05:8B:D7:9B:C1:5F:79:8E:EA:2E`
   (Keep your existing debug SHA-1 too, for local `flutter run`.)
2. **Authentication → Sign-in method → Google** is enabled.
3. **Firestore Database** exists, and its **Rules** contain the TripKhata block from
   [`firestore.rules`](../firestore.rules). The project is shared with other apps:
   add the block, don't replace their rules. TripKhata only uses the
   `tripkhata_trips` collection.

4. **Push notifications (Blaze plan)**: deploy the Cloud Function once from your laptop.
   It pushes "Rahul added ₹1,500 · Petrol · Manali · your share ₹375" to everyone else
   in a shared trip, even when their app is closed.

   ```bash
   npm install -g firebase-tools
   firebase login
   cd Trip-Khata/functions && npm ci && cd ..
   firebase deploy --only functions:tripkhata --project flutter-apps-975a6
   ```

   - Always deploy with `--only functions:tripkhata`. The project is shared with other
     apps, and this keeps their functions untouched.
   - The first deploy asks for `FIRESTORE_REGION`: use the location shown at the top of
     Firebase console → Firestore (e.g. `asia-south1`; `nam5` → `us-central1`,
     `eur3` → `europe-west1`). It's saved in `functions/.env.flutter-apps-975a6`.
   - If it asks to enable APIs (Cloud Functions, Cloud Build, Artifact Registry,
     Eventarc), say yes.
   - Re-publish the Firestore rules: the block now also covers `tripkhata_users`
     (each phone's push token).
   - Cost: a few function runs per expense. This is far inside Blaze's free monthly
     quota (2 million invocations), so a normal group trip costs ₹0. Setting a
     budget alert in Google Cloud Billing is still a good idea.

   Without the function the app still works: friends get a notification while their app
   is open, and on the next open for anything that came in while it was closed.

5. **v0.5.0 (security, bill photos, account deletion, Crashlytics)**
   - **Firestore → Rules**: replace the TripKhata block with the new one from
     [`firestore.rules`](../firestore.rules) and Publish. Trips are now readable only by
     their members; join codes live in `tripkhata_codes`. Old shared trips get their code
     doc the next time anyone in them opens the app.
   - **Storage → Get started** (if Storage isn't on yet), then **Rules**: add the block from
     [`storage.rules`](../storage.rules) and Publish. Allow the prompt that lets Storage
     rules read Firestore.
   - **Redeploy the functions** (same command as above). New: cleanup on trip delete and
     account delete, and old bill photos are removed when replaced.
   - **Crashlytics**: open Firebase console → Crashlytics once. Reports show up after the
     first crash (or first launch) of a release build.
   - **GitHub Pages** (privacy policy): repo → Settings → Pages → Source "Deploy from a
     branch" → Branch `main`, folder `/docs` → Save. The policy is then at
     https://sachinchoudhary07.github.io/Trip-Khata/privacy/ (use this URL in Play Console,
     and `…/privacy/#delete` as the account deletion URL).

---

## Using your own Firebase project or a private release key later

The rest of this guide is for moving off the shared test key (do this before a Play Store release)
or onto a different Firebase project.

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
