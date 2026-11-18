import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kDebugMode;
import 'main.dart' show MainShell, burgundy;
import 'chat.dart' show ChatThread;
import 'task_reminders.dart';
import 'cloud.dart';

// Set at build time: --dart-define=API_BASE_URL=https://your-api.example.com
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
bool get apiUrlAllowed => apiBaseUrl.startsWith('https://') || (kDebugMode && (apiBaseUrl == 'http://127.0.0.1:8081' || apiBaseUrl == 'http://127.0.0.1:8082'));
const secureStorage = FlutterSecureStorage();

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Map<String, dynamic>? account;
  bool loading = true;
  String? token;
  StreamSubscription<String>? pushRefresh;
  Future<void>? pushSetup;
  String? registeredDevice;
  StreamSubscription<RemoteMessage>? pushOpened;
  StreamSubscription<RemoteMessage>? foregroundPush;
  OverlayEntry? chatPreview;
  Timer? previewTimer;
  int previewRequest = 0;
  RemoteMessage? pendingChat;
  Future<FirebaseApp>? firebaseSetup;

  ({String kind, String thread, String target})? chatDestination(RemoteMessage message) {
    final data = message.data;
    final kind = data['chatKind'];
    final thread = data['threadId'];
    final target = data['messageId'];
    final uuid = RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');
    if ((kind != 'direct' && kind != 'group') ||
        thread is! String || !uuid.hasMatch(thread) ||
        target is! String || !uuid.hasMatch(target)) return null;
    return (kind: kind as String, thread: thread, target: target);
  }

  void dismissChatPreview() {
    previewTimer?.cancel();
    chatPreview?.remove();
    chatPreview = null;
  }

  Future<void> showChatPreview(RemoteMessage message) async {
    final destination = chatDestination(message);
    final session = token;
    if (destination == null || session == null || !canPreviewChat) return;
    final request = ++previewRequest;
    try {
      final path = destination.kind == 'group' ? 'groups' : 'direct';
      final messages = await CloudApi().list('chat/$path/${destination.thread}?focus=${destination.target}');
      if (request != previewRequest || token != session || !canPreviewChat) return;
      final index = messages.indexWhere((item) => item['id'] == destination.target);
      if (index < 0) return;
      final text = (messages[index]['text'] as String? ?? '').trim();
      if (text.isEmpty) return;
      final preview = text.characters.take(25).join();
      final overlay = Overlay.of(context);
      dismissChatPreview();
      chatPreview = OverlayEntry(builder: (context) => Positioned(
        top: 8,
        left: 16,
        right: 16,
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: burgundy,
                elevation: 8,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                  title: const Text('New message', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(preview == text ? preview : '$preview…',
                    style: const TextStyle(color: Colors.white), maxLines: 2),
                  onTap: () {
                    dismissChatPreview();
                    openNotification(message);
                  },
                ),
              ),
            ),
          ),
        ),
      ));
      overlay.insert(chatPreview!);
      previewTimer = Timer(const Duration(seconds: 2), dismissChatPreview);
    } catch (_) {
      // The conversation remains available if its preview cannot load.
    }
  }

  bool get canPreviewChat => mounted && !loading && account != null &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      View.of(context).viewInsets.bottom == 0;

  void openNotification(RemoteMessage message) {
    if (!mounted) return;
    final destination = chatDestination(message);
    if (destination == null) return;
    final (:kind, :thread, :target) = destination;
    final user = account;
    if (loading || user == null || token == null) {
      pendingChat = message;
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThread(
      id: thread, title: kind == 'group' ? 'Group conversation' : 'Private conversation',
      isGroup: kind == 'group', currentUserId: user['id'].toString(), focusedMessageId: target,
    )));
  }

  Future<void> watchNotificationTaps() async {
    if (defaultTargetPlatform != TargetPlatform.android || !apiUrlAllowed) return;
    try {
      await (firebaseSetup ??= Firebase.initializeApp());
      if (!mounted) return;
      pushOpened = FirebaseMessaging.onMessageOpenedApp.listen(openNotification);
      foregroundPush = FirebaseMessaging.onMessage.listen(showChatPreview);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) openNotification(initial);
    } catch (_) {
      // Chat remains available if Firebase initialization fails.
    }
  }

  void startPush(String session) {
    pushSetup = configurePush(session);
    final pending = pendingChat;
    pendingChat = null;
    if (pending != null) openNotification(pending);
  }

  Future<void> configurePush(String session) async {
    if (!apiUrlAllowed || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await (firebaseSetup ??= Firebase.initializeApp());
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission();
      if (token != session || !mounted ||
          permission.authorizationStatus != AuthorizationStatus.authorized) return;
      pushRefresh = messaging.onRegistered.listen((device) {
        pushSetup = registerPush(session, device);
      });
      await messaging.register().timeout(const Duration(seconds: 8));
    } catch (_) {
      // Sign-in still works when push is unavailable.
    }
  }

  Future<void> registerPush(String session, String device) async {
    if (token != session || !mounted) return;
    try {
      final response = await http.post(Uri.parse('$apiBaseUrl/api/devices'),
        headers: {'Authorization': 'Bearer $session', 'Content-Type': 'application/json'},
        body: jsonEncode({'platform': 'android-fid', 'token': device}),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 204) registeredDevice = device;
    } catch (_) {
      // The device registers again when the app starts.
    }
  }

  @override
  void initState() {
    super.initState();
    watchNotificationTaps();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) restore();
    });
  }

  @override
  void dispose() {
    dismissChatPreview();
    foregroundPush?.cancel();
    pushOpened?.cancel();
    pushRefresh?.cancel();
    super.dispose();
  }

  Future<void> restore() async {
    try {
      final stored = await secureStorage.read(key: 'access_token');
      if (stored != null && apiBaseUrl.isNotEmpty) {
        final response = await http.get(Uri.parse('$apiBaseUrl/api/account/me'), headers: {'Authorization': 'Bearer $stored'}).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          if (mounted) {
            setState(() { token = stored; account = jsonDecode(response.body) as Map<String, dynamic>; });
          }
        } else if (response.statusCode == 401) {
          await secureStorage.delete(key: 'access_token');
        }
      }
    } catch (_) { /* Offline/error: login is required until refresh-token support is added. */ }
    if (!mounted) return;
    setState(() => loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = token;
      if (mounted && session != null) startPush(session);
    });
  }

  Future<void> signOut() async {
    final session = token;
    if (session == null) return;
    token = null;
    dismissChatPreview();
    await pushRefresh?.cancel();
    await pushSetup;
    final device = registeredDevice;
    registeredDevice = null;
    if (session != null && device != null) {
      try {
        await http.delete(Uri.parse('$apiBaseUrl/api/devices'),
          headers: {'Authorization': 'Bearer $session', 'Content-Type': 'application/json'},
          body: jsonEncode({'platform': 'android-fid', 'token': device}),
        ).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Also invalidate the local registration below.
      }
    }
    if (Firebase.apps.isNotEmpty) {
      try { await FirebaseMessaging.instance.unregister().timeout(const Duration(seconds: 5)); } catch (_) {}
    }
    if (taskRemindersSupported) await taskReminders.invokeMethod<void>('clear');
    await secureStorage.delete(key: 'access_token');
    if (mounted) setState(() { token = null; account = null; });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (account != null) return MainShell(account: account!, onSignOut: signOut);
    return LoginPage(onAuthenticated: (newToken, newAccount) async {
      await secureStorage.write(key: 'access_token', value: newToken);
      if (mounted) {
        setState(() { token = newToken; account = newAccount; });
        startPush(newToken);
      }
    });
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onAuthenticated});
  final Future<void> Function(String, Map<String, dynamic>) onAuthenticated;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool registering = false;
  bool busy = false;
  bool showPassword = false;
  String? error;

  @override
  void dispose() { name.dispose(); email.dispose(); password.dispose(); super.dispose(); }

  Future<void> submit() async {
    if (!apiUrlAllowed) {
      setState(() => error = 'Configure an HTTPS API_BASE_URL to connect to the server.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final path = registering ? '/api/auth/register' : '/api/auth/login';
      final response = await http.post(Uri.parse('$apiBaseUrl$path'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({
        if (registering) 'name': name.text.trim(), 'email': email.text.trim(), 'password': password.text,
      })).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        if (!registering && response.statusCode == 401) {
          throw Exception('Email or password is incorrect.');
        }
        Object? details;
        try {
          details = jsonDecode(response.body);
        } on FormatException {
          // Error responses may have an empty body or a plain-text message.
        }
        final message = details is Map ? details['error'] : null;
        throw Exception(message is String && message.isNotEmpty
            ? message
            : registering ? 'Could not create your account. Try again.' : 'Could not sign in. Try again.');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      await widget.onAuthenticated(body['token'] as String, body['account'] as Map<String, dynamic>);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> resetPassword() async {
    final resetEmail = email.text.trim();
    if (!apiUrlAllowed || !resetEmail.contains('@')) {
      setState(() => error = 'Enter your account email address first.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _PasswordResetDialog(email: resetEmail),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Icon(Icons.check_circle_rounded, size: 64, color: burgundy),
    const SizedBox(height: 12),
    const Text('CatchIt Pro', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: burgundy)),
    const SizedBox(height: 8),
    Text(registering ? 'Start your 30-day Premium trial' : 'Welcome back', textAlign: TextAlign.center),
    const SizedBox(height: 28),
    if (registering) ...[TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name')), const SizedBox(height: 12)],
    TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Email address')),
    const SizedBox(height: 12),
    TextField(
      controller: password,
      obscureText: !showPassword,
      autofillHints: [registering ? AutofillHints.newPassword : AutofillHints.password],
      decoration: InputDecoration(
        labelText: 'Password',
        helperText: registering ? 'At least 12 characters' : null,
        suffixIcon: IconButton(
          tooltip: showPassword ? 'Hide password' : 'Show password',
          icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => showPassword = !showPassword),
        ),
      ),
    ),
    if (error != null) ...[const SizedBox(height: 12), Text(error!, style: const TextStyle(color: Colors.red))],
    const SizedBox(height: 22),
    FilledButton(onPressed: busy ? null : submit, child: Padding(padding: const EdgeInsets.all(12), child: Text(busy ? 'Please wait…' : registering ? 'Create free account' : 'Sign in'))),
    if (!registering)
      TextButton(onPressed: busy ? null : resetPassword, child: const Text('Forgot password?')),
    const SizedBox(height: 12),
    TextButton(onPressed: busy ? null : () => setState(() { registering = !registering; error = null; }), child: Text(registering ? 'Already have an account? Sign in' : 'New to CatchIt Pro? Create account')),
    const SizedBox(height: 16),
    const Text('30 days of full-feature access. No payment method required. Then continue on Free or upgrade to Premium.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
  ]))))));
}

class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog({required this.email});
  final String email;

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  final code = TextEditingController();
  final password = TextEditingController();
  bool requested = false;
  bool busy = false;
  bool completed = false;
  String? error;

  @override
  void dispose() {
    code.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (requested && (code.text.trim().isEmpty || password.text.length < 12 || password.text.length > 128)) {
      setState(() => error = 'Enter the code and a password of 12–128 characters.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final action = requested ? 'confirm' : 'request';
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/auth/password-reset/$action'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': widget.email,
          if (requested) 'code': code.text.trim(),
          if (requested) 'password': password.text,
        }),
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        if (!requested && response.statusCode == 202) {
          requested = true;
        } else if (requested && response.statusCode == 204) {
          completed = true;
        } else if (response.statusCode == 429) {
          error = 'Too many attempts. Wait a minute and try again.';
        } else if (requested && response.statusCode == 400) {
          error = 'The reset code is invalid or expired.';
        } else {
          error = 'Password reset is temporarily unavailable.';
        }
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Could not reach CatchIt Pro. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reset password'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(completed
              ? 'Password updated. Sign in with your new password.'
              : requested
                  ? 'If an account exists for ${widget.email}, check your email for a reset code.'
                  : 'Send a reset code to ${widget.email}?'),
          if (requested && !completed) ...[
            TextField(controller: code, autocorrect: false, decoration: const InputDecoration(labelText: 'Reset code')),
            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
          ],
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: Text(completed ? 'Done' : 'Cancel')),
      if (!completed)
        FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait…' : requested ? 'Reset password' : 'Send code')),
    ],
  );
}




