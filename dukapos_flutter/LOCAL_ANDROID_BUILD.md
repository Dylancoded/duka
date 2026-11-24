# Build and install DukaPOS locally without Android Studio

Android Studio is not required. You need Flutter, a JDK, the Android SDK command-line tools, and a physical Android phone or an emulator. A physical phone is the lightest option for a computer with limited memory.

## 1. Install the command-line tools

Install Flutter from the official Flutter SDK archive and add its `bin` directory to `PATH`. Install a full JDK, not only a Java runtime. JDK 17 or 21 is suitable for the generated project.

Set `ANDROID_SDK_ROOT` to your Android SDK directory:

```bash
# Linux/macOS
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$PATH:$HOME/flutter/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin"

# Windows PowerShell example
$env:ANDROID_SDK_ROOT="$env:LOCALAPPDATA\Android\Sdk"
$env:Path += ";$env:USERPROFILE\flutter\bin;$env:ANDROID_SDK_ROOT\platform-tools;$env:ANDROID_SDK_ROOT\cmdline-tools\latest\bin"
```

If you downloaded the command-line tools ZIP, extract it so this file exists:

```text
$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager
```

Install the packages required by this project:

```bash
sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
```

Verify the environment:

```bash
flutter doctor -v
flutter doctor --android-licenses
```

You may see a warning about Android Studio; it is safe to proceed if the Android toolchain is otherwise healthy.

## 2. Get the project and point it at your SDK

Copy or clone the project to your computer. In the Flutter project directory, `/dukapos_flutter`, run:

```bash
flutter pub get
flutter config --jdk-dir "$JAVA_HOME"
```

If Flutter cannot find the SDK, create or edit `android/local.properties`:

```properties
flutter.sdk=/absolute/path/to/flutter
sdk.dir=/absolute/path/to/Android/Sdk
```

Use Windows paths with escaped backslashes or forward slashes, for example:

```properties
flutter.sdk=C:/src/flutter
sdk.dir=C:/Users/YourName/AppData/Local/Android/Sdk
```

Do not commit `android/local.properties`; it is machine-specific.

## 3. Test and build the debug APK

```bash
flutter clean
flutter pub get
flutter test
flutter analyze
flutter build apk --debug
```

The APK will be written to:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Install it on a connected Android phone:

```bash
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

On the phone, enable **Developer options** and **USB debugging**, then accept the computer authorization prompt. If `adb devices` shows `unauthorized`, unlock the phone and accept the prompt. If it shows no device, use another USB cable/port and install the phone manufacturer's USB driver on Windows.

For a low-memory computer, use a real Android phone instead of an emulator. You can also build without keeping a Dart VM or Android emulator running; `flutter build apk --debug` is a one-shot command.

## 4. Release APK or Google Play AAB

For direct sideload testing, a release APK can be built after release signing is configured:

```bash
flutter build apk --release
```

For Google Play, build an Android App Bundle, not a debug APK:

```bash
flutter build appbundle --release
```

The bundle is written to:

```text
build/app/outputs/bundle/release/app-release.aab
```

Before using a release build, create an upload keystore, keep it outside the repository, configure `android/key.properties` locally, and use Play App Signing. Never commit the keystore or passwords. Google Play internal testing is the correct way to test subscriptions because Play Billing products are not fully testable from a sideloaded APK.

## 5. M-Pesa Till and Paybill customer prompting

The Flutter app now supports an offline customer-prompt flow:

1. Open **More > M-Pesa Till / Paybill**.
2. Enter the merchant Till number, Paybill number, and Paybill account/reference.
3. Add items and choose **Checkout > M-Pesa**.
4. The app shows the amount and the configured Till or Paybill instructions.
5. Ask the customer to complete payment and show the M-Pesa confirmation message.
6. Tap **Customer has paid** only after checking the confirmation. The sale is then recorded locally as `M-Pesa Till` or `M-Pesa Paybill` and remains in the offline sync queue.

This is a merchant-presented payment prompt and manual confirmation flow. It does not claim that money was received automatically. The app must not contain Safaricom consumer keys, passkeys or callback secrets.

For automatic confirmation or STK Push, deploy the existing server-side Daraja adapter through Firebase Functions or another backend. The backend must obtain Daraja credentials from Secret Manager, create the STK request, verify the callback's `CheckoutRequestID` against a pending payment, and only then mark the sale paid. Do not move these credentials into Flutter or Firestore.

A Till flow normally uses **Buy Goods and Services**. A Paybill flow normally uses the Paybill number plus the configured account/reference. Confirm the exact merchant instructions with Safaricom before publishing, and do not display a test shortcode in production.

## 6. Common failures

**`SDK location not found`:** set `sdk.dir` in `android/local.properties` or `ANDROID_SDK_ROOT`.

**`cmdline-tools component is missing`:** put the command-line tools under `cmdline-tools/latest`, then run `sdkmanager --list`.

**`License not accepted`:** run `flutter doctor --android-licenses` and accept the licenses.

**`AAPT2`, CMake or Ninja syntax errors:** the SDK contains binaries for the wrong CPU architecture. Remove that SDK installation and install the SDK command-line tools and packages on the target machine's native architecture.

**No device:** use `adb devices`, enable USB debugging, or use a physical phone rather than an emulator.

**Billing products not found:** install the app from a Play Console internal/closed testing track, use a license tester account, and make sure the package name and product IDs match exactly.
