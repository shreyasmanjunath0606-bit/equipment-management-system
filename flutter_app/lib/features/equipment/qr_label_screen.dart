import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../data/equipment_repo.dart';

/// Printable QR label. The QR holds the equipment's unique code as a link: `SITE/e/CODE`.
class QrLabelScreen extends ConsumerStatefulWidget {
  const QrLabelScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<QrLabelScreen> createState() => _QrLabelScreenState();
}

class _QrLabelScreenState extends ConsumerState<QrLabelScreen> {
  final _labelKey = GlobalKey();
  bool _sharing = false;

  static String linkFor(String code) => '${Env.siteUrl}/e/${Uri.encodeComponent(code)}';

  Future<void> _share(String name, String code) async {
    setState(() => _sharing = true);
    try {
      final boundary = _labelKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 4);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png', name: 'QR-$code.png')],
        fileNameOverrides: ['QR-$code.png'],
        title: 'QR label — $name',
      ));
    } catch (_) {
      if (mounted) showToast(context, 'Could not export the label');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(equipmentDetailProvider(widget.id));
    return PageBody(maxWidth: 520, children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: context.palette.muted, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
          onPressed: () => context.canPop() ? context.pop() : context.go('/equipment/${widget.id}'),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Back'),
        ),
      ),
      const Gap(Space.lg),
      AsyncBody<EquipmentDetail?>(
        value: detail,
        data: (d) {
          if (d == null) return const EmptyState(icon: Icons.search_off_rounded, title: 'Equipment not found');
          final e = d.equipment;
          final link = linkFor(e.tagCode);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: RepaintBoundary(
                key: _labelKey,
                child: _Label(name: e.name, code: e.tagCode, link: link, plant: d.plantName),
              ),
            ),
            const Gap(Space.xl),
            FilledButton.icon(
              onPressed: _sharing ? null : () => _share(e.name, e.tagCode),
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              label: const Text('Save / share label'),
            ),
            const Gap(Space.sm),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
                showToast(context, 'Link copied');
              },
              icon: const Icon(Icons.link_rounded, size: 20),
              label: const Text('Copy link'),
            ),
            const Gap(Space.lg),
            Text(
              'Print this and stick it on the machine. Scanning it with the app (or any phone camera) opens this machine.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
          ]);
        },
      ),
    ]);
  }
}

/// Always white / dark text so it prints cleanly whatever the app theme.
class _Label extends StatelessWidget {
  const _Label({required this.name, required this.code, required this.link, this.plant});
  final String name, code, link;
  final String? plant;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF0F172A);
    return Container(
      width: 300,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: ink, width: 2)),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          color: ink,
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 10),
          child: Row(children: [
            const Icon(Icons.factory_rounded, size: 16, color: Colors.white),
            const SizedBox(width: Space.sm),
            const Text('EQUIPMENT PORTAL', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const Spacer(),
            if (plant != null) Text(plant!, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.lg),
          child: Column(children: [
            QrImageView(
              data: link,
              size: 220,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: ink),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: ink),
            ),
            const SizedBox(height: Space.lg),
            Text(name, textAlign: TextAlign.center, style: const TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700, height: 1.2)),
            const SizedBox(height: Space.xs),
            Text(code, style: const TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
            const SizedBox(height: Space.md),
            const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.qr_code_scanner_rounded, size: 14, color: Color(0xFF475569)),
              SizedBox(width: 6),
              Text('Scan to view checks & report status', style: TextStyle(color: Color(0xFF475569), fontSize: 11)),
            ]),
          ]),
        ),
      ]),
    );
  }
}
