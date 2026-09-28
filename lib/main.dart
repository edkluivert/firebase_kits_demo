// firebase_kits_demo: firebase_auth_kit + firestore_kit + dartnative_firebase
// running together against your own Firebase project (see README.md).
//
//   dn run -d <ios-simulator-id> --dart-define=FIREBASE_KITS_AUTORUN=1
//
// The autorun walks through every automated step at start-up and mirrors the
// log to the console; the buttons cover the steps that need a person (Google
// sign-in page, SMS code).
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dartnative/dartnative.dart';
import 'package:dartnative_firebase/dartnative_firebase.dart' as dn_firebase;
import 'package:dartnative_secure_storage/dartnative_secure_storage.dart';
import 'package:dartnative_webview/dartnative_webview.dart';
import 'package:firebase_auth_kit/firebase_auth_kit.dart';
import 'package:firebase_auth_kit/firebase_core.dart' as auth_core;
import 'package:firestore_kit/firestore_kit.dart' hide FirebaseOptions;

import 'dartnative_plugin_registrant.dart';

const String _autorunFlag = String.fromEnvironment('FIREBASE_KITS_AUTORUN');
const bool _autorun = _autorunFlag == 'true' || _autorunFlag == '1';
const String _testPhone = String.fromEnvironment('FIREBASE_KITS_TEST_PHONE');
const String _testSms = String.fromEnvironment('FIREBASE_KITS_TEST_SMS');

void main() {
  DartNativePluginRegistrant.registerAll();
  SystemChrome.defaultStyle = const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  );
  runApp(const KitsDemo());
}

class KitsDemo extends StatefulWidget {
  const KitsDemo({super.key});

  @override
  State<KitsDemo> createState() => _KitsDemoState();
}

class _KitsDemoState extends State<KitsDemo> {
  static const _brand = Color(0xFFDD6B20);
  static const _ink = Color(0xFF16191F);
  static const _muted = Color(0xFF6B7280);

  final List<String> _log = [];
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController(text: _testPhone);
  final _smsController = TextEditingController(text: _testSms);
  String? _verificationId;
  bool _busy = false;
  bool _initialized = false;
  StreamSubscription<User?>? _authSub;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _emailController.text =
        'kits-${DateTime.now().millisecondsSinceEpoch}@example.com';
    _passwordController.text = 'secret123';
    unawaited(_initialize().then((_) {
      if (_autorun) _runAutomatedSteps();
    }));
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _add(String line) {
    // ignore: avoid_print
    print('[kits-demo] $line');
    if (mounted) setState(() => _log.insert(0, line));
  }

  Future<void> _run(String title, Future<Object?> Function() action) async {
    setState(() => _busy = true);
    final started = DateTime.now();
    try {
      final result = await action();
      final ms = DateTime.now().difference(started).inMilliseconds;
      _add('$title → ${result ?? 'ok'} (${ms}ms)');
    } on FirebaseAuthException catch (e) {
      _add('$title failed: [${e.code}] ${e.userMessage} | ${e.message}');
    } catch (e) {
      _add('$title failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Setup: dartnative_firebase first, then the kits.
  // ---------------------------------------------------------------------------

  Future<void> _initialize() async {
    await _run('dartnative_firebase Firebase.initializeApp', () async {
      await dn_firebase.Firebase.initializeApp();
      await dn_firebase.FirebaseCrashlytics.instance.log('kits demo started');
      return 'native Core + Crashlytics up';
    });

    await _run('firebase_auth_kit config discovery', () async {
      FirebaseAuthKit.logger = (m) => print(m); // ignore: avoid_print
      // One screen for hosted sign-in pages (Google/GitHub…, phone reCAPTCHA).
      FirebaseAuthKit.webFlowPresenter = (url, {required isCallback}) {
        return Navigator.of(context).push<Uri?>(
          PageRoute(builder: (_) => AuthWebPage(url: url, isCallback: isCallback)),
        );
      };
      await installSecureAuthPersistence(SecureStorage());
      final app = auth_core.Firebase.app();
      return 'project ${app.options.projectId} from ${app.options.source} '
          '(bundle ${app.options.iosBundleId}), restored user: '
          '${_auth.currentUser?.email ?? _auth.currentUser?.uid ?? 'none'}';
    });

    await _run('firestore_kit config discovery', () async {
      _db.tokenProvider = () async => await _auth.currentUser?.getIdToken();
      return 'project ${_db.projectId}';
    });

    _authSub = _auth.authStateChanges().listen((user) {
      _add('authStateChanges → ${user?.uid ?? 'signed out'}');
    });
    setState(() => _initialized = true);
  }

  // ---------------------------------------------------------------------------
  // Automated steps (no person needed).
  // ---------------------------------------------------------------------------

  Future<void> _runAutomatedSteps() async {
    final email = _emailController.text;
    const password = 'secret123';

    if (_auth.currentUser != null) {
      await _run('sign out previous session', () async {
        await _auth.signOut();
        return null;
      });
    }

    await _run('createUserWithEmailAndPassword', () async {
      final c = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      return '${c.user!.uid} new=${c.additionalUserInfo!.isNewUser}';
    });

    await _run('getIdTokenResult', () async {
      final r = await _auth.currentUser!.getIdTokenResult();
      return 'provider=${r.signInProvider} exp=${r.expirationTime}';
    });

    await _run('updateProfile + reload', () async {
      await _auth.currentUser!.updateProfile(displayName: 'Kits Demo');
      await _auth.currentUser!.reload();
      return _auth.currentUser!.displayName;
    });

    await _run('sendEmailVerification', () async {
      await _auth.currentUser!.sendEmailVerification();
      return 'mail requested';
    });

    await _run('firestore set + get (kits_demo/{uid})', () async {
      final doc = _db.collection('kits_demo').doc(_auth.currentUser!.uid);
      await doc.set({
        'email': email,
        'platform': Platform.operatingSystem,
        'at': FieldValue.serverTimestamp(),
      });
      final snap = await doc.get();
      return 'exists=${snap.exists} email=${snap.get('email')}';
    });

    await _run('firestore snapshots() first event', () async {
      final doc = _db.collection('kits_demo').doc(_auth.currentUser!.uid);
      final snap = await doc.snapshots().first;
      return 'platform=${snap.get('platform')}';
    });

    await _run('signOut + signIn with wrong password', () async {
      await _auth.signOut();
      try {
        await _auth.signInWithEmailAndPassword(email: email, password: 'nope');
        return 'UNEXPECTED success';
      } on FirebaseAuthException catch (e) {
        return 'code=${e.code} invalidCredentials=${e.isInvalidCredentials}';
      }
    });

    await _run('signInWithEmailAndPassword', () async {
      final c = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      return '${c.user!.uid} new=${c.additionalUserInfo!.isNewUser}';
    });

    await _run('force token refresh', () async {
      final a = await _auth.currentUser!.getIdToken();
      final b = await _auth.currentUser!.getIdToken(true);
      return 'refreshed=${a != b}';
    });

    await _run('anonymous sign-in + link email', () async {
      await _auth.signOut();
      final anon = await _auth.signInAnonymously();
      final linked = await anon.user!.linkWithCredential(
        EmailAuthProvider.credential(
            email: 'linked-$email', password: password),
      );
      return 'uid kept=${linked.user!.uid == anon.user!.uid} '
          'anonymous=${_auth.currentUser!.isAnonymous}';
    });

    await _run('sendPasswordResetEmail', () async {
      await _auth.sendPasswordResetEmail(email: email);
      return 'mail requested';
    });

    await _run('Crashlytics recordError (non-fatal)', () async {
      await dn_firebase.FirebaseCrashlytics.instance
          .setUserIdentifier(_auth.currentUser!.uid);
      await dn_firebase.FirebaseCrashlytics.instance.recordError(
        StateError('kits demo test error'),
        StackTrace.current,
      );
      return 'sent';
    });

    await _run('delete linked account', () async {
      await _auth.currentUser!.delete();
      return 'deleted, currentUser=${_auth.currentUser}';
    });

    if (_testPhone.isNotEmpty) {
      await _run('phone: verifyPhoneNumber (test number)', () async {
        if (_testSms.isNotEmpty) {
          await _auth.setSettings(
            phoneNumber: _testPhone,
            smsCode: _testSms,
            appVerificationDisabledForTesting: true,
          );
        }
        final completer = Completer<String>();
        await _auth.verifyPhoneNumber(
          phoneNumber: _testPhone,
          codeSent: (id, _) {
            _verificationId = id;
            if (!completer.isCompleted) completer.complete('code sent');
          },
          verificationCompleted: (credential) async {
            final c = await _auth.signInWithCredential(credential);
            if (!completer.isCompleted) {
              completer.complete('auto-completed → ${c.user!.phoneNumber}');
            }
          },
          verificationFailed: (e) {
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
          },
          codeAutoRetrievalTimeout: (_) {},
        );
        return completer.future;
      });

      if (_verificationId != null && _testSms.isNotEmpty) {
        await _run('phone: signInWithCredential (test code)', () async {
          final c = await _auth.signInWithCredential(
            PhoneAuthProvider.credential(
              verificationId: _verificationId!,
              smsCode: _testSms,
            ),
          );
          final result = '${c.user!.uid} phone=${c.user!.phoneNumber} '
              'new=${c.additionalUserInfo!.isNewUser}';
          await c.user!.delete();
          return '$result (deleted)';
        });
      }
    }

    _add('AUTORUN DONE');
  }

  // ---------------------------------------------------------------------------
  // Manual steps.
  // ---------------------------------------------------------------------------

  Widget _button(String title, Future<Object?> Function() action) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Button(
        title: title,
        variant: ButtonVariant.filled,
        color: _brand,
        foregroundColor: Colors.white,
        width: double.infinity,
        onPressed: _busy || !_initialized ? null : () => _run(title, action),
      ),
    );
  }

  Widget _field(TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(hintText: hint),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      brightness: Brightness.light,
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        title: const Text(
          'firebase kits demo',
          style: TextStyle(
              color: _ink, fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _field(_emailController, 'email'),
                    _field(_passwordController, 'password'),
                    _button('Run automated steps', () async {
                      await _runAutomatedSteps();
                      return 'done';
                    }),
                    _button('Sign up', () async {
                      final c = await _auth.createUserWithEmailAndPassword(
                        email: _emailController.text,
                        password: _passwordController.text,
                      );
                      return c.user!.uid;
                    }),
                    _button('Sign in', () async {
                      final c = await _auth.signInWithEmailAndPassword(
                        email: _emailController.text,
                        password: _passwordController.text,
                      );
                      return c.user!.uid;
                    }),
                    _button('Sign in with Google (hosted page)', () async {
                      final c = await _auth.signInWithProvider(
                        GoogleAuthProvider()..addScope('email'),
                      );
                      return '${c.user!.email} via ${c.additionalUserInfo?.providerId}';
                    }),
                    _button('Sign in with GitHub (hosted page)', () async {
                      final c = await _auth.signInWithProvider(GithubAuthProvider());
                      return '${c.user!.email} via ${c.additionalUserInfo?.providerId}';
                    }),
                    _field(_phoneController, 'phone number (+…)'),
                    _button('Phone: send code', () async {
                      final completer = Completer<String>();
                      await _auth.verifyPhoneNumber(
                        phoneNumber: _phoneController.text,
                        codeSent: (id, _) {
                          _verificationId = id;
                          if (!completer.isCompleted) completer.complete('code sent');
                        },
                        verificationCompleted: (credential) async {
                          await _auth.signInWithCredential(credential);
                          if (!completer.isCompleted) completer.complete('auto-completed');
                        },
                        verificationFailed: (e) {
                          if (!completer.isCompleted) completer.completeError(e);
                        },
                        codeAutoRetrievalTimeout: (_) {},
                      );
                      return completer.future;
                    }),
                    _field(_smsController, 'SMS code'),
                    _button('Phone: confirm code', () async {
                      final c = await _auth.signInWithCredential(
                        PhoneAuthProvider.credential(
                          verificationId: _verificationId!,
                          smsCode: _smsController.text,
                        ),
                      );
                      return c.user!.phoneNumber;
                    }),
                    _button('Firestore: write my doc', () async {
                      final doc = _db.collection('kits_demo').doc(_auth.currentUser!.uid);
                      await doc.set({'tapped': FieldValue.increment(1)},
                          SetOptions(merge: true));
                      return (await doc.get()).data();
                    }),
                    _button('Who am I', () async {
                      final u = _auth.currentUser;
                      return u == null
                          ? 'signed out'
                          : '${u.uid} ${u.email} ${u.phoneNumber} '
                              'providers=${u.providerData.map((p) => p.providerId)}';
                    }),
                    _button('Sign out', () async {
                      await _auth.signOut();
                      return null;
                    }),
                  ],
                ),
              ),
            ),
            const Divider(),
            Expanded(
              flex: 4,
              child: _log.isEmpty
                  ? const Center(
                      child: Text('Results appear here.',
                          style: TextStyle(color: _muted, fontSize: 14)),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final line in _log)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              line,
                              style: TextStyle(
                                color: line.contains('failed')
                                    ? const Color(0xFFB42318)
                                    : _ink,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a Firebase-hosted auth page and pops with the redirect URL the kit
/// expects (the README's web-view screen).
class AuthWebPage extends StatefulWidget {
  const AuthWebPage({super.key, required this.url, required this.isCallback});

  final Uri url;
  final bool Function(Uri) isCallback;

  @override
  State<AuthWebPage> createState() => _AuthWebPageState();
}

String _short(String url) => url.length > 160 ? '${url.substring(0, 160)}…' : url;

class _AuthWebPageState extends State<AuthWebPage> {
  final controller = WebViewController();
  bool done = false;

  @override
  void initState() {
    super.initState();
    controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    controller.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (request) {
        // ignore: avoid_print
        print('[kits-demo] webview navigation request → ${_short(request.url)}');
        if (_finish(request.url)) return NavigationDecision.prevent;
        return NavigationDecision.navigate;
      },
      onPageStarted: (url) {
        // ignore: avoid_print
        print('[kits-demo] webview page started → ${_short(url)}');
        _finish(url);
      },
      onPageFinished: (url) {
        // ignore: avoid_print
        print('[kits-demo] webview page finished → ${_short(url)}');
        _finish(url);
      },
    ));
    controller.loadRequest(widget.url);
  }

  bool _finish(String url) {
    final target = Uri.tryParse(url);
    if (target != null && widget.isCallback(target) && !done) {
      done = true;
      Navigator.of(context).pop(target);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      brightness: Brightness.light,
      appBar: AppBar(
        title: const Text('Sign in',
            style: TextStyle(color: Color(0xFF16191F), fontSize: 17)),
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}
