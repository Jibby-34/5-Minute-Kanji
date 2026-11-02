# Firebase setup

Analytics and Crashlytics are wired in the app. This repository does not contain a Firebase project, `google-services.json`, `GoogleService-Info.plist`, or `firebase_options.dart`. Do not invent those files. Until the steps below are done, `Firebase.initializeApp()` fails quietly, Crashlytics stays off, and the analytics client is a no-op. Study, onboarding, and purchases still run.

## Identifiers already in the app

| Platform | Identifier |
| --- | --- |
| Android application id | `com.blinklabsapps.fiveminutekanji` |
| iOS bundle id | `com.5minutekanji.app` |
| Android min SDK | 24 (Flutter's current minimum) |
| iOS deployment target | 15.0 |

`firebase_core` 5.1 requires iOS 15 and Android 24. The Runner target is already set to 15.0. Register the Firebase apps with the identifiers above. A mismatch makes native initialization fail, and the app will keep launching without analytics.

## 1. Create the Firebase project

1. Open the [Firebase console](https://console.firebase.google.com/) and create a project, or select the existing one for this app.
2. Enable **Google Analytics** for the project and pick or create an Analytics account. Analytics is required for the custom events in this app. Crashlytics can share the same project.
3. Add an **Android** app with package name `com.blinklabsapps.fiveminutekanji`. Download `google-services.json` and place it at `android/app/google-services.json`.
4. Add an **iOS** app with bundle id `com.5minutekanji.app`. Download `GoogleService-Info.plist`, put it in `ios/Runner/`, and add that file to the Runner target in Xcode (the file must be a member of the target, not only present on disk).
5. Leave the SHA-1 field optional for Analytics. Add the Play App Signing SHA-1 later if you enable Auth or other Google APIs. This app does not use Firebase Auth.

The Android Gradle plugins `com.google.gms.google-services` (4.4.2) and `com.google.firebase.crashlytics` (3.0.3) are declared in `android/settings.gradle.kts`. `android/app/build.gradle.kts` applies them only when `android/app/google-services.json` exists, so a checkout without that file still builds.

The app calls `Firebase.initializeApp()` with no Dart options. That uses the native files above. You do not have to generate `lib/firebase_options.dart` unless you want Dart-side options.

### Optional: FlutterFire CLI

If you prefer generated options:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Select the same Firebase project and the Android and iOS apps above. The CLI writes `lib/firebase_options.dart` and the native config files. After that, pass the generated options into `Firebase.initializeApp` in `lib/services/analytics/firebase_startup.dart`:

```dart
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

Keep the existing try/catch. A failed init must still return false and let the app launch.

## 2. What the app does at startup

`lib/main.dart` starts Firebase in parallel with `SharedPreferences`. If initialization succeeds, it installs Crashlytics handlers and uses `FirebaseAnalyticsClient`. If it fails, it uses `NoopAnalyticsClient`. Either way, one `AnalyticsService` is created and passed into the purchase system, the daily workload reader, and `FiveMinuteKanjiApp`.

Crashlytics, after a successful init only:

- `FlutterError.onError` is `FirebaseCrashlytics.instance.recordFlutterFatalError` (that method already presents the error).
- `PlatformDispatcher.instance.onError` records uncaught async errors as fatal and returns true.

Caught errors, including analytics send failures, are not reported as crashes. There is no in-app test-crash button.

## 3. Verify Analytics with DebugView

Events can take a day to appear in standard reports. DebugView shows them within seconds.

### Android emulator or device

```bash
adb shell setprop debug.firebase.analytics.app com.blinklabsapps.fiveminutekanji
```

Run a debug build (`flutter run`). In the Firebase console open **Analytics → DebugView** and select the device. To turn debug mode off:

```bash
adb shell setprop debug.firebase.analytics.app .none.
```

### iOS simulator or device

Edit the Runner scheme in Xcode: **Product → Scheme → Edit Scheme → Run → Arguments → Arguments Passed On Launch**, and add:

```text
-FIRDebugEnabled
```

Run from Xcode or `flutter run` with that argument. Remove `-FIRDebugEnabled` when you are done. `-FIRDebugDisabled` forces it off.

Confirm `onboarding_started` by tapping Get Started, and `study_session_started` by starting a review. Automatic events such as `first_open`, `session_start`, and `user_engagement` come from the SDK. The app does not send duplicates of those.

## 4. Verify Crashlytics

1. Finish the console setup above and install a build that initialized Firebase (the native config files must be present).
2. Crashlytics needs a run after the SDK has uploaded. Force one non-fatal or fatal report from a temporary debug call, then remove it. Do not leave a crash button in the UI. A local check looks like this, placed once behind a debug-only call you delete before committing:

```dart
FirebaseCrashlytics.instance.crash();
```

3. Relaunch the app so the report can upload. Open **Crashlytics** in the console. The first report can take several minutes.
4. Release builds on Android include the Crashlytics Gradle plugin once `google-services.json` is present, so mapping files upload with the release build.
5. iOS release builds need dSYM upload. If you ship with `--split-debug-info` or `--obfuscate`, upload symbols with the Firebase CLI:

```bash
firebase crashlytics:symbols:upload --app=<IOS_APP_ID> <path-to-dsyms>
```

The iOS app id is in `GoogleService-Info.plist` as `GOOGLE_APP_ID`. Xcode's Crashlytics run script is added by the FlutterFire iOS setup when you add the plist and build; if symbolicated traces stay missing, follow the current [Crashlytics iOS get-started](https://firebase.google.com/docs/crashlytics/get-started?platform=flutter) "upload dSYM" section for the Flutter plugin version in `pubspec.lock`.

Debug-mode crashes are less useful. Verify a release or profile build on a device before treating the console as empty.

## 5. Custom events

Names and parameters stay within Analytics limits (40-character names, 100-character strings). Booleans are sent as `1` or `0`. The app does not send the kanji character, meaning, mnemonic, database id, email, or name.

| Event | Parameters |
| --- | --- |
| `onboarding_started` | none |
| `onboarding_completed` | `daily_goal_minutes`, `starting_level`, `starting_method` (`placement_test` or `manual_selection`) |
| `placement_test_started` | none |
| `placement_test_completed` | `questions_answered`, `estimated_level` (rounded difficulty 1–100) |
| `study_session_started` | `session_type` (`normal`, `study_anyway`, `reinforcement`), `available_cards` |
| `kanji_reviewed` | `result` (`again` or `good`), `is_new`, `review_category` (`new`, `due`, or `early`) |
| `study_session_completed` | `duration_seconds`, `cards_reviewed`, `new_cards_learned`, `goal_completed`, `session_type` |
| `study_session_abandoned` | `duration_seconds`, `cards_reviewed`, `session_type` |
| `reinforcement_day_started` | `day_type` (`reinforcement`), `trigger_category` (`average_recall` or `low_recall_fraction`) |
| `paywall_viewed` | `placement` (`settings`, `review_limit`, `review_limit_prompt`) |
| `purchase_started` | `product_id`, `purchase_type` (`lifetime` or `subscription`) |
| `purchase_completed` | `product_id`, `purchase_type` |
| `purchase_failed` | `product_id`, `purchase_type`, `error_category` |
| `purchase_restored` | `product_id`, `purchase_type` |
| `daily_goal_changed` | `daily_goal_minutes` |
| `reminder_settings_changed` | `enabled`, `reminder_hour`, `reminder_minute` |

`purchase_type` matches the existing products: `full_curriculum_unlock` is `lifetime`, `full_curriculum_monthly` is `subscription`.

`error_category` is one of `store_unavailable`, `product_unavailable`, `checkout_failed`, `verification_failed`, `network`, `billing_unavailable`, `store_error`. Raw store messages are not sent.

`starting_level` on `onboarding_completed` is the numeric estimate when the placement test just finished in this process. Otherwise it is `new_user`, `beginner`, `intermediate`, or `expert`.

## 6. Behavior that is easy to misread

- `kanji_reviewed` is sent when the answer can no longer be undone (the sitting ends, the continue prompt opens, or the user leaves). Undo removes that pending event, so the reversed answer is not counted. A later answer is a new event. One card can produce several events if it is answered more than once (Again, then Good).
- `cards_reviewed` on the session events is the unique-card count from the session summary. It can be lower than the number of `kanji_reviewed` events.
- `new_cards_learned` increments when the learn step introduces a new card (`newCard` → `learning`). Mark as Known and the placement test do not increment it.
- `duration_seconds` is this sitting's active time from `DailyReviewClock`, not the day total shown on the summary. Background time is already excluded by that clock.
- Closing the review screen, or system back during an open sitting, sends `study_session_abandoned`. Backgrounding only pauses the clock.
- Declining the continue prompt, or leaving while that prompt is up, sends `study_session_completed`. Choosing to continue does not.
- Killing the process mid-sitting sends nothing for that sitting. Pending reviews that had not been flushed are dropped. A kill while the continue prompt is up can leave `kanji_reviewed` events (the undo window already closed) without `study_session_completed`.
- `review_category` `early` is implemented for a card that is neither new nor due today. Today's queues only contain new and due cards, so production sessions should not emit `early`.
- `reinforcement_day_started` fires when a new daily plan is saved as a reinforcement day, not when an existing plan is read again. Home and the reminder share storage, so they do not double-count.
- `purchase_completed` fires only after a verified `purchased` update newly grants lifetime or subscription access. Opening the paywall, tapping buy, a pending purchase, and a user cancel do not complete a purchase. Cancel is not `purchase_failed`.
- The same store transaction id is stored in SharedPreferences (`analytics_reported_transactions_v1`, last 40 ids) and is not sent again. A `purchased` update followed by a `restored` replay of that id does not also emit `purchase_restored`.
- `purchase_restored` fires when a verified restore newly grants access. Restoring an entitlement the app already has does not emit. Tapping Restore with nothing to restore does not emit.
- A silent store query on launch does not emit purchase events.
- Practice mode (used in tests, not the production study button) emits no study events.
