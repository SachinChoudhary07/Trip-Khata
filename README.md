# TripKhata

Group trip expense splitter. Offline-first, Hinglish voice entry (next build), split with selected people, settle up over UPI.

## First run (once)

```bash
cd tripkhata
flutter create --org com.tripkhata --project-name tripkhata --platforms=android .
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run tool/patch_android.dart
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
| Splash (animated road, car, chips) | Done |
| Home: ongoing trip card, past trips, empty state, sample trip | Done |
| New trip: cover, places, dates, budget, people | Done |
| Trip: totals, expenses by day, "Not in your share" tag | Done |
| Add expense: numpad, category, paid by, Split with sheet | Done (equal split) |
| Balances: your payments, UPI deep link, mark as paid, everyone's bars | Done |
| Split logic, settle-up, Hinglish parser | Done, unit tested |
| Voice screen (speech_to_text + parser) | Next |
| Split by amount / by shares in the UI | Next |
| Route, check-in, summary, settings, login | Later phases |

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
