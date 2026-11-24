# DukaPOS source bundle

This bundle contains the offline-first Flutter Android app in `dukapos_flutter/` and the Firebase Functions/rules in `firebase/`.

Start with `dukapos_flutter/FIREBASE_SETUP.md` and `dukapos_flutter/LOCAL_ANDROID_BUILD.md`. Run FlutterFire configuration on the developer machine; no Firebase project configuration, service account, Daraja secret, keystore, or `android/local.properties` is included in this archive.

The Android app writes sales to local Drift/SQLite first. Firebase synchronization is enabled after FlutterFire configuration and a `DUKAPOS_BUSINESS_ID` Dart define is supplied. The Firebase Functions remain server-side for subscription verification and future M-Pesa/Daraja callbacks.
