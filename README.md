# TripKhata

Group trip expense splitter. Offline-first, Hinglish voice entry, split with selected people, settle up over UPI, route log.

## First run (once)

```bash
cd tripkhata
flutter create --org com.tripkhata --project-name tripkhata --platforms=android .
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run tool/patch_android.dart
dart run flutter_launcher_icons
flutter test
flutter run
```

- `flutter create .` only adds the `android/` folder and keeps the code in `lib/` as it is.
- `build_runner` generates `lib/db/app_database.g.dart` (Drift). Run it again whenever you change a table.
- `tool/patch_android.dart` adds the UPI `<queries>` entry to `AndroidManifest.xml`, so `upi://pay` opens GPay, PhonePe or Paytm on Android 11+.

On first launch, tap **Try a sample trip** to see the Indore → Udaipur demo data.

## What's in this build

| Area | Status |
| --- | --- |
| Splash, onboarding, login (offline), profile setup | Done |
| Home, new trip (with contacts), add people to a trip | Done |
| Trip: totals, expenses by day, "Not in your share" tag | Done |
| Add / edit expense: numpad, category, payer, split equally / by amount / by shares | Done |
| Speak to add: on-device speech + Hinglish parser | Done |
| Expense detail with bill photo, delete | Done |
| Balances, UPI deep link, mark as paid, payment sent | Done |
| Route map (OpenStreetMap), GPS check-in linked to expenses | Done |
| Trip summary: donut, highlights, share text, PDF | Done |
| Settings: voice language, daily 9 PM reminder, CSV export | Done |
| Google sign-in, share trip by code, join, offline-first cloud sync | Done, off until Firebase is set up: see [docs/CLOUD_SETUP.md](docs/CLOUD_SETUP.md) |

## Structure

```
lib/
  core/          theme, router, categories, money, shared widgets, trip cover painter
  db/            Drift tables (source of truth, amounts in paise)
  features/
    splash/
    trips/       data/trip_repository.dart, presentation/ (home, create, trip, cubits)
    expenses/    domain/split_calculator.dart, presentation/ (add expense, split with)
    settle/      domain/settlement_calculator.dart, presentation/balances_page.dart
    voice/       domain/hinglish_parser.dart
test/domain_test.dart
```

## Cost

₹0. No paid APIs, no server. See the plan doc for the free stack and the traps (Play Store fee, SMS OTP).
