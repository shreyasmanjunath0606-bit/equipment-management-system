import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/status.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/session.dart';

final _allPlantsProvider = FutureProvider<List<Plant>>((ref) async {
  final rows = await ref.watch(supabaseProvider).from('plants').select('id,code,name,timezone,active').order('name');
  return rows.map(Plant.fromJson).toList();
});

const _timezones = ['Asia/Kolkata', 'Asia/Dubai', 'Asia/Singapore', 'Asia/Tokyo', 'Europe/London', 'Europe/Berlin', 'America/New_York', 'America/Chicago', 'America/Los_Angeles', 'UTC'];

class AdminPlantsScreen extends ConsumerWidget {
  const AdminPlantsScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final ok = await showFormSheet<bool>(context, title: 'Add plant', builder: (_) => const _PlantForm());
    if (ok == true && context.mounted) {
      ref.invalidate(_allPlantsProvider);
      ref.invalidate(plantsProvider);
      showToast(context, 'Plant added');
    }
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, Plant p) async {
    if (p.active) {
      final ok = await showConfirmSheet(context,
          title: 'Deactivate ${p.name}?', message: 'The plant is hidden from plant pickers and its checks stop being scheduled. Equipment and history are kept.', confirmLabel: 'Deactivate', destructive: true);
      if (!ok) return;
    }
    try {
      await ref.read(supabaseProvider).from('plants').update({'active': !p.active}).eq('id', p.id);
      ref.invalidate(_allPlantsProvider);
      ref.invalidate(plantsProvider);
    } catch (_) {
      if (context.mounted) showToast(context, 'Could not save — check your connection');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_allPlantsProvider);
    final pal = context.palette;
    return PageBody(
      onRefresh: () async => ref.invalidate(_allPlantsProvider),
      children: [
        PageHeader(
          title: 'Plants',
          subtitle: 'Sites that equipment and people belong to.',
          actions: [FilledButton.icon(onPressed: () => _add(context, ref), icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Add plant'))],
        ),
        AsyncBody<List<Plant>>(
          value: list,
          data: (plants) => plants.isEmpty
              ? Card(child: EmptyState(icon: Icons.factory_outlined, title: 'No plants yet', message: 'Add your first plant to start registering equipment.', action: FilledButton(onPressed: () => _add(context, ref), child: const Text('Add plant'))))
              : ResponsiveGrid(minItemWidth: 300, children: [
                  for (final p in plants)
                    Opacity(
                      opacity: p.active ? 1 : 0.65,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(Space.lg),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(color: pal.primarySoft, borderRadius: BorderRadius.circular(10)),
                                child: Icon(Icons.factory_rounded, color: pal.primary, size: 20),
                              ),
                              const Gap(Space.md),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.name, style: context.text.titleSmall),
                                  Text('Code ${p.code}', style: context.text.bodySmall),
                                ]),
                              ),
                              p.active ? Pill('Active', color: pal.success) : const Pill('Inactive'),
                            ]),
                            const Gap(Space.lg),
                            Row(children: [
                              Icon(Icons.schedule_rounded, size: 15, color: pal.muted),
                              const SizedBox(width: 6),
                              Text(p.timezone, style: context.text.bodySmall),
                              const Spacer(),
                              TextButton(
                                style: TextButton.styleFrom(foregroundColor: p.active ? pal.danger : pal.primary, visualDensity: VisualDensity.compact),
                                onPressed: () => _toggle(context, ref, p),
                                child: Text(p.active ? 'Deactivate' : 'Reactivate'),
                              ),
                            ]),
                          ]),
                        ),
                      ),
                    ),
                ]),
        ),
      ],
    );
  }
}

class _PlantForm extends ConsumerStatefulWidget {
  const _PlantForm();
  @override
  ConsumerState<_PlantForm> createState() => _PlantFormState();
}

class _PlantFormState extends ConsumerState<_PlantForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _code = TextEditingController();
  String _tz = 'Asia/Kolkata';
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(supabaseProvider).from('plants').insert({'name': _name.text.trim(), 'code': _code.text.trim().toUpperCase(), 'timezone': _tz});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _busy = false; _error = e is PostgrestException && e.code == '23505' ? 'That plant code is already used.' : 'Could not save. Try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: Space.md), child: Text(_error!, style: TextStyle(color: context.palette.danger))),
          TextFormField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Plant name', hintText: 'Pune Assembly'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
          const Gap(Space.lg),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Code', hintText: 'PUNE', helperText: 'Prefix for equipment codes'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
            ),
            const Gap(Space.md),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _tz,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Timezone'),
                items: [for (final t in _timezones) DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _tz = v!),
              ),
            ),
          ]),
          const Gap(Space.xl),
          BusyButton(busy: _busy, label: 'Add plant', icon: Icons.add_rounded, onPressed: _save),
        ]),
      );
}
