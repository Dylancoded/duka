# Firebase setup for DukaPOS

DukaPOS uses Drift/SQLite as the local source of truth for the cashier. Firebase is the cloud replica and coordination layer. A sale is committed locally first, then a queue entry is uploaded when connectivity returns. Firestore document IDs are stable, so retries are idempotent.

## 1. Create or select the Firebase project

On the computer used to build the Android app:

```bash
npm install -g firebase-tools
firebase login
firebase use --add YOUR_FIREBASE_PROJECT_ID

# Install FlutterFire CLI if it is not already installed
dart pub global activate flutterfire_cli
```

Enable **Authentication → Sign-in providers → Anonymous**. For production, replace anonymous sign-in with the business’s chosen sign-in provider and create a membership document at:

```text
businesses/{BUSINESS_ID}/members/{AUTH_UID}
```

The member document must contain a role such as `owner`, `manager`, or `cashier`. The current app uses anonymous sign-in as a bootstrap so the offline sync path can be exercised; anonymous accounts still need a membership record before Firestore rules permit business data access.

## 2. Register the Android app and generate options

From the Flutter project directory:

```bash
cd dukapos_flutter
flutterfire configure --project=YOUR_FIREBASE_PROJECT_ID
```

Select Android and the package ID shown in `android/app/build.gradle.kts`. This creates `lib/firebase_options.dart` and downloads the Android Firebase configuration. Do not commit a configuration file containing credentials or a machine-specific `android/app/google-services.json` unless that is part of your team’s approved source-control policy.

If FlutterFire asks for the Android application ID, use the value in `android/app/build.gradle.kts` (`applicationId`). Keep this ID unchanged after publishing to Google Play.
The Google Services Gradle plugin reads `android/app/google-services.json`; ensure its Android client package name matches the app ID (`duka.pos`).

## 3. Build with the business ID

The app reads the business ID from a compile-time Dart define. Example:

```bash
flutter pub get
flutter run --dart-define=DUKAPOS_BUSINESS_ID=your-business-document-id
flutter build apk --debug --dart-define=DUKAPOS_BUSINESS_ID=your-business-document-id
```

The app still opens and keeps local sales working if Firebase has not been configured. In that state, uploads are intentionally skipped and the Drift queue remains pending.

## 4. Firestore data model

The client sync service writes:

```text
businesses/{businessId}/sales/{saleId}
businesses/{businessId}/products/{productId}
businesses/{businessId}/syncQueue/{operationId}
```

Sales contain the receipt, totals, payment method, customer ID, timestamps, and line items. Product writes contain the current product snapshot and version. Use the existing `firebase/firestore.rules` as the starting point; deploy it from the Firebase directory:

```bash
cd ../dukapos/firebase
firebase deploy --only firestore:rules
```

The backend Functions in the parent project remain the right place for privileged billing verification, RTDN processing, Daraja credentials, conflict resolution, and administrative operations. Never place Daraja secrets in the Flutter app.

## 5. Local Firebase Emulator Suite

Install the Firebase CLI, then from the Firebase directory run:

```bash
firebase init emulators
firebase emulators:start --only auth,firestore,functions
```

For emulator development, point the FlutterFire clients at the emulator before `FirebaseBootstrap.initialize()` completes. Keep emulator host selection platform-aware: Android emulator uses `10.0.2.2`, while a physical device uses the development machine’s LAN IP. Do not ship emulator settings in a release build.

## 6. Sync and conflict behavior

The local queue is acknowledged only after a Firestore write succeeds. Temporary failures leave the entry pending and increment its attempt count. Sale and product document IDs are deterministic. Firestore writes use merge semantics, so repeating a successful operation does not create a duplicate document.

The current product sync uses the latest local product snapshot. A production conflict-resolution Function should compare the uploaded `version` with the cloud version, write a `sync/conflicts` or `auditEvents` record when both sides changed, and return the authoritative snapshot for a later client pull. The cashier remains able to sell during this process because all sales are recorded locally first.

## 7. Production checklist

Before release, replace anonymous bootstrap with a real authenticated session and membership onboarding; add a pull/reconciliation job for products, customers, and settings; deploy and test Firestore rules in the emulator; add App Check; configure Functions and billing service accounts; replace placeholder terms/privacy URLs; and validate offline, reconnect, duplicate retry, account switching, and conflict scenarios on a physical Android device.
