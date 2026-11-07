import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../data/equipment_repo.dart';
import '../../data/session.dart';

/// Scan a machine's QR label (or type its code) to open it.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode]);
  final _code = TextEditingController();
  bool _resolving = false;
  bool _cameraFailed = false;

  @override
  void dispose() {
    _controller.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _open(String raw) async {
    if (_resolving || raw.trim().isEmpty) return;
    setState(() => _resolving = true);
    HapticFeedback.mediumImpact();
    final ref0 = parseScannedValue(raw);
    try {
      String? id = ref0.id;
      if (id == null && ref0.code != null) {
        id = (await findEquipmentByCode(ref.read(supabaseProvider), ref0.code!))?.id;
      }
      if (!mounted) return;
      if (id == null) {
        showToast(context, 'No machine found for "${ref0.code ?? raw}" — or you have no access to its plant.');
      } else {
        context.push('/equipment/$id');
      }
    } catch (_) {
      if (mounted) showToast(context, 'Could not look up that code. Check your connection.');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageBody(maxWidth: 560, children: [
      const PageHeader(title: 'Scan equipment', subtitle: 'Point the camera at the QR label on the machine.'),
      ClipRRect(
        borderRadius: Radii.cardAll,
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            color: Colors.black,
            child: _cameraFailed
                ? const _CameraUnavailable()
                : Stack(fit: StackFit.expand, children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: (capture) {
                        final v = capture.barcodes.firstOrNull?.rawValue;
                        if (v != null) _open(v);
                      },
                      errorBuilder: (context, error) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && !_cameraFailed) setState(() => _cameraFailed = true);
                        });
                        return const _CameraUnavailable();
                      },
                    ),
                    const _Viewfinder(),
                    if (_resolving) const ColoredBox(color: Color(0x88000000), child: Center(child: CircularProgressIndicator(color: Colors.white))),
                    Positioned(
                      right: Space.md,
                      bottom: Space.md,
                      child: IconButton.filled(
                        tooltip: 'Torch',
                        style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                        onPressed: () => _controller.toggleTorch(),
                        icon: const Icon(Icons.flashlight_on_rounded),
                      ),
                    ),
                  ]),
          ),
        ),
      ),
      const Gap(Space.xl),
      Row(children: [
        Expanded(child: Divider(color: p.border)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: Space.md), child: Text('or enter the code', style: context.text.bodySmall)),
        Expanded(child: Divider(color: p.border)),
      ]),
      const Gap(Space.lg),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.go,
            onSubmitted: _open,
            decoration: const InputDecoration(hintText: 'e.g. 101-CNC-0001', prefixIcon: Icon(Icons.tag_rounded, size: 20)),
          ),
        ),
        const Gap(Space.sm),
        SizedBox(height: 50, child: FilledButton(onPressed: _resolving ? null : () => _open(_code.text), child: const Text('Open'))),
      ]),
    ]);
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();
  @override
  Widget build(BuildContext context) => Center(
        child: FractionallySizedBox(
          widthFactor: 0.62,
          heightFactor: 0.62,
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(20)),
          ),
        ),
      );
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(Space.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.no_photography_outlined, color: Colors.white70, size: 36),
            SizedBox(height: Space.md),
            Text('Camera not available', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            SizedBox(height: Space.xs),
            Text('Allow camera access, or type the code below.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
      );
}

/// Target of QR links: /e/<CODE>. Looks the code up and opens the machine.
class CodeLinkScreen extends ConsumerStatefulWidget {
  const CodeLinkScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<CodeLinkScreen> createState() => _CodeLinkScreenState();
}

class _CodeLinkScreenState extends ConsumerState<CodeLinkScreen> {
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final e = await findEquipmentByCode(ref.read(supabaseProvider), widget.code);
      if (!mounted) return;
      if (e == null) {
        setState(() => _notFound = true);
      } else {
        context.replace('/equipment/${e.id}');
      }
    } catch (_) {
      if (mounted) setState(() => _notFound = true);
    }
  }

  @override
  Widget build(BuildContext context) => _notFound
      ? EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No machine with code ${widget.code}',
          message: 'It may have been removed, or you do not have access to its plant.',
          action: OutlinedButton(onPressed: () => context.go('/equipment'), child: const Text('Browse equipment')),
        )
      : const Center(child: CircularProgressIndicator());
}
