import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'data/session.dart';

class EquipmentPortalApp extends ConsumerStatefulWidget {
  const EquipmentPortalApp({super.key, this.needsPasswordFromLink = false});
  final bool needsPasswordFromLink;

  @override
  ConsumerState<EquipmentPortalApp> createState() => _EquipmentPortalAppState();
}

class _EquipmentPortalAppState extends ConsumerState<EquipmentPortalApp> {
  @override
  void initState() {
    super.initState();
    if (widget.needsPasswordFromLink) ref.read(sessionControllerProvider).markNeedsPassword();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Equipment Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en', 'GB'), Locale('en', 'US')],
      builder: (context, child) {
        // Respect the user's text size, but cap it so layouts stay intact.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3)),
          child: child!,
        );
      },
    );
  }
}
