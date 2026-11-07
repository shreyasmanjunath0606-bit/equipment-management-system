import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Compact "All plants ▾" selector used in page headers.
class PlantPicker extends StatelessWidget {
  const PlantPicker({super.key, required this.plants, required this.value, required this.onChanged, this.allowAll = true});

  final List<Plant> plants;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowAll;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final current = plants.where((x) => x.id == value).firstOrNull;
    return PopupMenuButton<String>(
      tooltip: 'Choose plant',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: Radii.cardAll, side: BorderSide(color: p.border)),
      color: p.surface,
      onSelected: (v) => onChanged(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        if (allowAll) CheckedPopupMenuItem(value: '', checked: value == null, child: const Text('All plants')),
        for (final pl in plants) CheckedPopupMenuItem(value: pl.id, checked: pl.id == value, child: Text(pl.name)),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(color: p.surface, borderRadius: Radii.inputAll, border: Border.all(color: p.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.factory_outlined, size: 18, color: p.muted),
          const SizedBox(width: Space.sm),
          Text(current?.name ?? 'All plants', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(width: Space.xs),
          Icon(Icons.expand_more_rounded, size: 18, color: p.muted),
        ]),
      ),
    );
  }
}
