import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Optional photo: dashed "add photo" box, or a preview with a remove button.
/// Photos are shrunk to ~1280px JPEG so they upload quickly on mobile data.
class PhotoPickerField extends StatelessWidget {
  const PhotoPickerField({super.key, required this.photo, required this.onChanged, this.hint = 'Helps maintenance diagnose faster'});

  final Uint8List? photo;
  final ValueChanged<Uint8List?> onChanged;
  final String hint;

  Future<void> _pick(BuildContext context) async {
    ImageSource? source = ImageSource.gallery;
    if (!kIsWeb) {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
            const SizedBox(height: Space.sm),
          ]),
        ),
      );
      if (source == null) return;
    }
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
    if (file == null) return;
    onChanged(await file.readAsBytes());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (photo != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Stack(clipBehavior: Clip.none, children: [
          ClipRRect(borderRadius: Radii.inputAll, child: Image.memory(photo!, height: 160, fit: BoxFit.cover)),
          Positioned(
            right: -10,
            top: -10,
            child: Material(
              color: p.surface,
              shape: CircleBorder(side: BorderSide(color: p.border)),
              child: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove photo',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => onChanged(null),
              ),
            ),
          ),
        ]),
      );
    }
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: Radii.cardAll,
      child: CustomPaint(
        painter: _DashedBorder(p.border),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xl, horizontal: Space.lg),
          child: Column(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: p.primarySoft, shape: BoxShape.circle),
              child: Icon(Icons.photo_camera_outlined, color: p.primary, size: 20),
            ),
            const SizedBox(height: Space.sm),
            Text('Take or upload a photo', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            Text(hint, style: context.text.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(Radii.card));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
