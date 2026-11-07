import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

enum SessionStatus { loading, signedOut, signedIn, deactivated, needsPassword }

/// Tracks the signed-in user and their profile. Drives router redirects (it is a Listenable)
/// and is exposed to widgets through [sessionProvider].
class SessionController extends ChangeNotifier {
  SessionController(SupabaseClient client) : _client = client {
    _sub = client.auth.onAuthStateChange.listen(_onAuth);
    _load(client.auth.currentSession);
  }

  /// For tests / previews: a fixed signed-in profile with no backend.
  SessionController.fixed(Profile profile)
      : _client = null,
        _status = SessionStatus.signedIn,
        _profile = profile;

  final SupabaseClient? _client;
  StreamSubscription<AuthState>? _sub;

  SessionStatus _status = SessionStatus.loading;
  Profile? _profile;

  SessionStatus get status => _status;
  Profile? get profile => _profile;
  Role get role => _profile?.role ?? Role.worker;

  /// Set after an invite / recovery link: the user must choose a password before continuing.
  bool _needsPassword = false;

  void _onAuth(AuthState s) {
    if (s.event == AuthChangeEvent.passwordRecovery) _needsPassword = true;
    if (s.event == AuthChangeEvent.signedOut) _needsPassword = false;
    if (s.event == AuthChangeEvent.tokenRefreshed && _profile != null) return;
    _load(s.session);
  }

  Future<void> _load(Session? session) async {
    final client = _client;
    if (client == null) return;
    if (session == null) {
      _profile = null;
      _set(SessionStatus.signedOut);
      return;
    }
    try {
      final row = await client.from('profiles').select('id,name,email,role,active').eq('id', session.user.id).maybeSingle();
      final p = row == null ? null : Profile.fromJson(row);
      if (p == null || !p.active) {
        _profile = null;
        _set(SessionStatus.deactivated);
        await client.auth.signOut();
        return;
      }
      _profile = p;
      _set(_needsPassword ? SessionStatus.needsPassword : SessionStatus.signedIn);
    } catch (_) {
      // Offline at start-up: keep the user in with whatever we last knew.
      if (_profile != null) _set(SessionStatus.signedIn);
    }
  }

  void passwordSet() {
    _needsPassword = false;
    if (_profile != null) _set(SessionStatus.signedIn);
  }

  void markNeedsPassword() {
    _needsPassword = true;
    if (_profile != null) _set(SessionStatus.needsPassword);
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
  }

  void _set(SessionStatus s) {
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// ChangeNotifierProvider so that widgets watching it rebuild on sign-in/out and profile changes.
final sessionControllerProvider = ChangeNotifierProvider<SessionController>(
  (ref) => SessionController(ref.watch(supabaseProvider)),
);

/// The current profile. Widgets inside the signed-in shell can assume it is non-null.
final profileProvider = Provider<Profile>((ref) {
  final c = ref.watch(sessionControllerProvider);
  return c.profile ?? const Profile(id: '', name: '', email: '', role: Role.worker, active: false);
});
