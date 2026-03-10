# LostKit Mobile

Android client for [2004.lostcity.rs](https://2004.lostcity.rs) — the Greatest Runescape preservation server in history.

Runs the game in a WebView with a few quality-of-life features built on top.

---

## Features

- Fullscreen WebView with zoom control
- World switcher
- Hiscores lookup
- AFK timer with sound and vibration alert
- Screenshot to gallery

---

## Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install) — version 3.0 or higher
- Android Studio or VS Code (for the Android toolchain)
- An Android device or emulator running Android 6.0+
- Java 17 (comes with Android Studio)

Once Flutter is installed, run `flutter doctor` and make sure there are no errors under the Android section.

---

## Build

Clone the repo:
```
git clone https://github.com/yourusername/losthq_client.git
cd losthq_client
```

Get dependencies:
```
flutter pub get
```

Plug in your Android device (enable USB debugging in Developer Options), then build and install:
```
flutter build apk --debug
flutter install
```

The APK will also be saved to `build/app/outputs/flutter-apk/app-debug.apk` if you want to transfer it manually.

---

## Notes

- The `VIBRATE` permission is already declared in `AndroidManifest.xml` — no extra steps needed for vibration to work
- AFK timer is always disabled on startup regardless of what you had it set to last session
- Sound file lives at `assets/sounds/afk_alert.mp3` — swap it out if you want a different alert sound, just keep the same filename
- **Battery saver mode** on Android can silence audio and block vibration. If sound or vibration isn't working, check that battery saver is off. The red screen flash should always fire regardless.
