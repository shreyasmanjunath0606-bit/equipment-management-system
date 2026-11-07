import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../data/session.dart';
import 'auth_shell.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.reason});
  final String? reason;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final status = ref.read(sessionControllerProvider).status;
    if (widget.reason == 'deactivated' || status == SessionStatus.deactivated) {
      _error = 'Your account has been deactivated. Contact your manager.';
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      // The router redirects once the session controller has loaded the profile.
    } on AuthException catch (e) {
      setState(() => _error = RegExp('invalid login credentials', caseSensitive: false).hasMatch(e.message) ? 'Wrong email or password.' : 'Could not sign in: ${e.message}');
    } catch (_) {
      setState(() => _error = "Could not reach the server. Check your connection.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter your email above first, then tap "Forgot password?".');
      return;
    }
    try {
      await ref.read(supabaseProvider).auth.resetPasswordForEmail(email, redirectTo: kIsWeb ? Uri.base.origin : Env.mobileAuthRedirect);
      if (mounted) showToast(context, 'If that email has an account, a reset link is on its way.');
    } catch (_) {
      if (mounted) showToast(context, 'Could not send the reset email. Try again later.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AuthShell(
      title: 'Sign in',
      subtitle: 'Use the email your manager invited.',
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) FormError(_error!),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email', hintText: 'you@company.com', prefixIcon: Icon(Icons.mail_outline_rounded, size: 20)),
                validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
              ),
              const SizedBox(height: Space.lg),
              TextFormField(
                controller: _password,
                obscureText: !_show,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                  suffixIcon: IconButton(
                    tooltip: _show ? 'Hide password' : 'Show password',
                    icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: p.muted),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
                validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _forgot, child: const Text('Forgot password?')),
              ),
              const SizedBox(height: Space.sm),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
