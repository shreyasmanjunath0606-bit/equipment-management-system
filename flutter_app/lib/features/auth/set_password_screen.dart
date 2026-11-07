import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../data/session.dart';
import '../shell/nav_items.dart';
import 'auth_shell.dart';

/// Shown after an invite / password-reset link, and from "Change password".
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(supabaseProvider).auth.updateUser(UserAttributes(password: _a.text));
      final session = ref.read(sessionControllerProvider);
      session.passwordSet();
      if (!mounted) return;
      showToast(context, 'Password saved');
      context.go(homeFor(session.role));
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save the password. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Choose a password',
      subtitle: 'At least 8 characters. You will use it to sign in on any device.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) FormError(_error!),
            TextFormField(
              controller: _a,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'New password', prefixIcon: Icon(Icons.lock_outline_rounded, size: 20)),
              validator: (v) => (v ?? '').length < 8 ? 'Use at least 8 characters' : null,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _b,
              obscureText: true,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Repeat password', prefixIcon: Icon(Icons.lock_outline_rounded, size: 20)),
              validator: (v) => v != _a.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Save password'),
            ),
          ],
        ),
      ),
    );
  }
}
