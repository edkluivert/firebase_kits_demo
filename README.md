# firebase_kits_demo

A small DartNative app that runs three packages together against **your own** Firebase project:

- [firebase_auth_kit](https://github.com/edkluivert/firebase_auth_kit) — sign-in (email/password,
  anonymous, phone, Google through Firebase's hosted page), tokens, profile, sessions
- [firestore_kit](https://github.com/edkluivert/firestore_kit) — a Firestore document written and
  read with the signed-in user's token, rules enforced
- [dartnative_firebase](https://dartpub.dev/plugins/dartnative_firebase) — the native Firebase
  Core and Crashlytics

It has two modes: an **automated run** that walks through every feature and prints a line per
step, and **buttons** for the parts that need a person (Google login, typing an SMS code). Use it
to check your Firebase setup, or copy pieces into your own app; the `AuthWebPage` screen at the
bottom of `lib/main.dart` is the web-view screen the `firebase_auth_kit` README describes.

No Firebase configuration is committed. `ios/Runner/GoogleService-Info.plist` and
`android/app/google-services.json` are in `.gitignore`; you add your own in step 2.

## 1. Get the code

```sh
git clone https://github.com/edkluivert/firebase_auth_kit_demo.git firebase_kits_demo
cd firebase_kits_demo
dn pub get
```

`pubspec.yaml` points `firebase_auth_kit` and `firestore_kit` at sibling folders (`../firebase_auth_kit`,
`../firestore_kit`). Either clone those two next to this folder, or replace the `path:` entries with
the published versions from dartpub.dev.

## 2. Create a Firebase project and register the app

1. Go to [console.firebase.google.com](https://console.firebase.google.com) and create a project
   (any name).
2. **iOS**: Project settings → *Your apps* → **Add app → iOS**. Bundle ID: `com.jitae.firebaseKitsDemo`
   (or change `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj` to your own and use that).
   Download `GoogleService-Info.plist` into `ios/Runner/`, then run
   `ruby tool/add_google_service_plist.rb` once to add it to the Xcode target.
3. **Android** (optional): **Add app → Android** with package name `com.jitae.firebase_kits_demo`
   (or change `applicationId` in `android/app/build.gradle.kts`). Download `google-services.json`
   into `android/app/`. The Google Services Gradle plugin is already applied.

## 3. Turn on the sign-in methods

Build → **Authentication** → *Get started*, then in the **Sign-in method** tab enable:

- **Email/Password**
- **Anonymous**
- **Google** (for the "hosted page" button)
- **Phone**, and under *Phone numbers for testing* add `+1 650-555-1234` with code `123456`

Phone also needs the **SMS region policy** (Authentication → Settings) to allow a region, for
example the United States, even for test numbers. Test numbers never send a real SMS.

## 4. Allow the demo document in Firestore

Build → **Firestore Database** → create the database if needed → **Rules**:

```
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    match /kits_demo/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

## 5. Run it

```sh
# list simulators / devices
dn devices

# automated run: every step prints as "[kits-demo] …"
dn run -d "iPhone 16" \
  --dart-define=FIREBASE_KITS_AUTORUN=true \
  --dart-define=FIREBASE_KITS_TEST_PHONE=+16505551234 \
  --dart-define=FIREBASE_KITS_TEST_SMS=123456

# or just the buttons
dn run -d "iPhone 16"
```

The automated run: signs up with a fresh email, reads the ID token, updates the profile, sends a
verification email, writes and listens to `kits_demo/{uid}` in Firestore, checks the wrong-password
error, signs in, forces a token refresh, links an anonymous account to an email, sends a
password-reset mail, logs a non-fatal error to Crashlytics, deletes the account, then verifies the
test phone number and signs in with its code.

Expected end of the console log:

```
[kits-demo] phone: verifyPhoneNumber (test number) → code sent
[kits-demo] phone: signInWithCredential (test code) → … phone=+16505551234 … (deleted)
[kits-demo] AUTORUN DONE
```

Then tap **Sign in with Google (hosted page)**: Google's login opens inside the app and you land
back on the demo with your address in the log.

## What each error means

| Log line contains | Cause | Fix |
| --- | --- | --- |
| `core/no-options` | no `GoogleService-Info.plist` in the bundle (or no `google-services.json` compiled in) | step 2 |
| `configuration-not-found` | Authentication was never enabled | step 3, *Get started* |
| `operation-not-allowed` | the sign-in method is off, or (for phone) the SMS region is not allowed | step 3 |
| `permission-denied` on the Firestore steps | rules not updated | step 4 |
| `user-cancelled` after a hosted page | the web view was closed before the flow finished | try again |

## Files worth reading

- `lib/main.dart` — the whole demo: setup, automated steps, buttons, and the `AuthWebPage` screen.
- `ios/Podfile` — pins the Firebase iOS SDK version so `pod install` is reproducible.
- `tool/add_google_service_plist.rb` — adds the plist to the Xcode target.
