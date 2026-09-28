# firebase_kits_demo

End-to-end check of `firebase_auth_kit` and `firestore_kit` running next to
`dartnative_firebase`, against the real **awahymn** Firebase project.

Repository: https://github.com/edkluivert/firebase_auth_kit_demo — the Firebase config files are
not committed; add your own as described below.

## One-time setup

1. Firebase console → project **awahymn** → Project settings → *Your apps* → **Add app → iOS**.
   Bundle ID: `com.jitae.firebaseKitsDemo`. Download `GoogleService-Info.plist` and put it at
   `ios/Runner/GoogleService-Info.plist` (add it to the Runner target in Xcode if it is not picked
   up automatically).
2. Authentication → *Sign-in method*: enable **Email/Password**, **Anonymous**, **Google**
   (the hosted page test), optionally **GitHub**, and **Phone** with a test number, e.g.
   `+1 650-555-1234` → code `123456`.
3. Firestore → Rules: allow signed-in users to write their own demo doc:

   ```
   match /kits_demo/{uid} {
     allow read, write: if request.auth != null && request.auth.uid == uid;
   }
   ```

Android reuses the existing `com.jitae.awa_hymn` registration (`google-services.json` is already in
`android/app/`), so no console work is needed there.

## Run

```sh
dn run -d "iPhone 16" --dart-define=FIREBASE_KITS_AUTORUN=1 \
  --dart-define=FIREBASE_KITS_TEST_PHONE=+16505551234 --dart-define=FIREBASE_KITS_TEST_SMS=123456
```

The autorun signs up, reads tokens, updates the profile, writes and listens to Firestore, checks a
wrong password, signs in, refreshes the token, links an anonymous account, sends a reset mail, logs
to Crashlytics, deletes the account and, if a test number is given, runs phone verification. Every
step is printed as `[kits-demo] …`. The buttons cover Google / GitHub sign-in through the hosted
page and manual phone entry.
