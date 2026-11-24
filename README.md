# DukaPOS

DukaPOS is an offline-first point-of-sale app built with Flutter, Drift/SQLite, and Firebase.

## Project layout

- [`dukapos_flutter/`](dukapos_flutter/) — Flutter app and Android project
- [`dukapos/firebase/`](dukapos/firebase/) — Firebase Functions, Firestore rules, indexes, and Storage rules

## Build the Android app

Install Flutter (Dart 3.14 or newer), Java 17, and Android SDK 36. From `dukapos_flutter/`:

```powershell
flutter pub get
flutter build apk --debug
```

The Android Firebase client configuration is in `dukapos_flutter/android/app/google-services.json`. It contains client-side project configuration, not service-account credentials. Keep service-account keys, Play credentials, Daraja secrets, signing keys, and machine-specific `android/local.properties` out of source control.

See [`FIREBASE_SETUP.md`](dukapos_flutter/FIREBASE_SETUP.md) and [`LOCAL_ANDROID_BUILD.md`](dukapos_flutter/LOCAL_ANDROID_BUILD.md) for setup details. Functions dependencies can be installed from `dukapos/firebase/functions/` with `npm ci`.
