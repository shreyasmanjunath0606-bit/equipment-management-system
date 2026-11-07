import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'data/offline_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy(); // clean web URLs: /equipment/abc instead of /#/equipment/abc

  if (!Env.isConfigured) {
    runApp(const _MissingConfig());
    return;
  }

  // Invite / password-reset e-mails land on the web app as #access_token=...&type=invite|recovery.
  final fromAuthLink = kIsWeb && RegExp(r'type=(invite|recovery)').hasMatch(Uri.base.fragment);

  await OfflineQueue.initStorage();
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  runApp(ProviderScope(child: EquipmentPortalApp(needsPasswordFromLink: fromAuthLink)));
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();
  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Missing configuration.\nRun with: flutter run --dart-define-from-file=env.json', textAlign: TextAlign.center),
            ),
          ),
        ),
      );
}
