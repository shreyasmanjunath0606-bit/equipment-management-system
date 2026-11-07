import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/status.dart';
import '../../data/equipment_repo.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/session.dart';

final _adminEquipmentProvider = FutureProvider<List<Equipment>>((ref) async {
  final rows = await ref.watch(supabaseProvider).from('equipment').select(Equipment.columns).order('created_at', ascending: false).limit(1000);
  return rows.map(Equipment.fromJson).toList();
});

/// Register, bulk-import, retire and restore machines. Codes are unique; blank = auto-generated.
class AdminEquipmentScreen extends ConsumerStatefulWidget {
  const AdminEquipmentScreen({super.key});

  @override
  ConsumerState<AdminEquipmentScreen> createState() => _AdminEquipmentScreenState();
}

class _AdminEquipmentScreenState extends ConsumerState<AdminEquipmentScreen> {
  String _q = '';
  bool _showRetired = false;

  String _err(Object e) {
    if (e is PostgrestException && e.code == '23505') return 'That code is already used by another machine.';
    return 'Could not save. Check your connection and try again.';
  }

  Future<void> _add(List<Plant> plants) async {
    final added = await showFormSheet<bool>(context, title: 'Add equipment', subtitle: 'Leave the code blank to generate one, e.g. 101-CNC-0001.', builder: (ctx) => _EquipmentForm(plants: plants, onError: _err));
    if (added == true && mounted) {
      ref.invalidate(_adminEquipmentProvider);
      ref.invalidate(equipmentListProvider);
      showToast(context, 'Equipment added');
    }
  }

  Future<void> _import(List<Plant> plants) async {
    final n = await showFormSheet<int>(context, title: 'Bulk import', subtitle: 'One machine per line: code,name,type (code may be blank). Max 500.', builder: (ctx) => _BulkForm(plants: plants, onError: _err));
    if (n != null && mounted) {
      ref.invalidate(_adminEquipmentProvider);
      ref.invalidate(equipmentListProvider);
      showToast(context, '$n machine${n == 1 ? '' : 's'} imported');
    }
  }

  Future<void> _toggle(Equipment e) async {
    if (e.isActive) {
      final ok = await showConfirmSheet(context,
          title: 'Retire ${e.name}?', message: 'It will be hidden from lists and checks stop being scheduled. Its history stays readable and you can restore it later.', confirmLabel: 'Retire', destructive: true);
      if (!ok) return;
    }
    try {
      await ref.read(equipmentRepositoryProvider).setActive(e.id, !e.isActive);
      ref.invalidate(_adminEquipmentProvider);
      ref.invalidate(equipmentListProvider);
      if (mounted) showToast(context, e.isActive ? '${e.name} retired' : '${e.name} restored');
    } catch (err) {
      if (mounted) showToast(context, _err(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_adminEquipmentProvider);
    final plants = ref.watch(plantsProvider).value ?? const <Plant>[];
    final plantById = {for (final p in plants) p.id: p};
    final p = context.palette;

    return PageBody(
      maxWidth: 960,
      onRefresh: () async => ref.invalidate(_adminEquipmentProvider),
      children: [
        PageHeader(
          title: 'Manage equipment',
          subtitle: list.value == null ? null : '${list.value!.where((e) => e.isActive).length} active · ${list.value!.where((e) => !e.isActive).length} retired',
          actions: [
            if (plants.isNotEmpty) OutlinedButton.icon(onPressed: () => _import(plants), icon: const Icon(Icons.upload_rounded, size: 18), label: const Text('Bulk import')),
            if (plants.isNotEmpty) FilledButton.icon(onPressed: () => _add(plants), icon: const Icon(Icons.add_rounded, size: 20), label: const Text('Add equipment')),
          ],
        ),
        Row(children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: const InputDecoration(hintText: 'Search name or code…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
            ),
          ),
          const Gap(Space.md),
          FilterChip(label: const Text('Show retired'), selected: _showRetired, onSelected: (v) => setState(() => _showRetired = v)),
        ]),
        const Gap(Space.lg),
        AsyncBody<List<Equipment>>(
          value: list,
          onRetry: () => ref.invalidate(_adminEquipmentProvider),
          data: (all) {
            if (plants.isEmpty) return const Card(child: EmptyState(icon: Icons.factory_outlined, title: 'No plants yet', message: 'An admin must create a plant before equipment can be added.'));
            final rows = all.where((e) => (_showRetired || e.isActive) && (_q.isEmpty || e.name.toLowerCase().contains(_q) || e.tagCode.toLowerCase().contains(_q))).toList();
            if (rows.isEmpty) {
              return Card(
                child: EmptyState(
                  icon: Icons.precision_manufacturing_outlined,
                  title: all.isEmpty ? 'No equipment yet' : 'No matches',
                  message: all.isEmpty ? 'Add your first machine or bulk-import a list.' : 'Try another search.',
                  action: all.isEmpty ? FilledButton(onPressed: () => _add(plants), child: const Text('Add equipment')) : null,
                ),
              );
            }
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.border),
                  Opacity(
                    opacity: rows[i].isActive ? 1 : 0.6,
                    child: ListTile(
                      minTileHeight: 64,
                      onTap: () => context.push('/equipment/${rows[i].id}'),
                      title: Text(rows[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([rows[i].tagCode, rows[i].type, plantById[rows[i].plantId]?.name].whereType<String>().join(' · ')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (!rows[i].isActive) const Padding(padding: EdgeInsets.only(right: Space.sm), child: Pill('Retired')),
                        IconButton(tooltip: 'QR label', onPressed: () => context.push('/equipment/${rows[i].id}/qr'), icon: const Icon(Icons.qr_code_2_rounded)),
                        PopupMenuButton<String>(
                          tooltip: 'More',
                          onSelected: (_) => _toggle(rows[i]),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'toggle',
                              child: Text(rows[i].isActive ? 'Retire' : 'Restore', style: TextStyle(color: rows[i].isActive ? p.danger : null)),
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ],
              ]),
            );
          },
        ),
      ],
    );
  }
}

class _EquipmentForm extends ConsumerStatefulWidget {
  const _EquipmentForm({required this.plants, required this.onError});
  final List<Plant> plants;
  final String Function(Object) onError;

  @override
  ConsumerState<_EquipmentForm> createState() => _EquipmentFormState();
}

class _EquipmentFormState extends ConsumerState<_EquipmentForm> {
  final _form = GlobalKey<FormState>();
  late String _plant = widget.plants.first.id;
  final _code = TextEditingController(), _name = TextEditingController(), _type = TextEditingController();
  final _mfr = TextEditingController(), _model = TextEditingController(), _serial = TextEditingController();
  bool _more = false, _busy = false;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(equipmentRepositoryProvider).create(
            plantId: _plant,
            tagCode: _code.text,
            name: _name.text,
            type: _type.text,
            manufacturer: _mfr.text,
            model: _model.text,
            serialNo: _serial.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { _busy = false; _error = widget.onError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: Space.md), child: Text(_error!, style: TextStyle(color: context.palette.danger))),
        if (widget.plants.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: _plant,
            decoration: const InputDecoration(labelText: 'Plant'),
            items: [for (final p in widget.plants) DropdownMenuItem(value: p.id, child: Text(p.name))],
            onChanged: (v) => setState(() => _plant = v!),
          ),
          const Gap(Space.lg),
        ],
        TextFormField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Name *', hintText: 'CNC Lathe 1'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
        const Gap(Space.lg),
        Row(children: [
          Expanded(child: TextFormField(controller: _type, decoration: const InputDecoration(labelText: 'Type', hintText: 'Lathe'))),
          const Gap(Space.md),
          Expanded(child: TextFormField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Code', hintText: 'Auto'))),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _more = !_more),
            icon: Icon(_more ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: const Text('More details'),
          ),
        ),
        if (_more) ...[
          TextFormField(controller: _mfr, decoration: const InputDecoration(labelText: 'Manufacturer')),
          const Gap(Space.lg),
          Row(children: [
            Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Model'))),
            const Gap(Space.md),
            Expanded(child: TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'Serial no.'))),
          ]),
          const Gap(Space.lg),
        ],
        const Gap(Space.sm),
        BusyButton(busy: _busy, label: 'Add equipment', icon: Icons.add_rounded, onPressed: _save),
      ]),
    );
  }
}

class _BulkForm extends ConsumerStatefulWidget {
  const _BulkForm({required this.plants, required this.onError});
  final List<Plant> plants;
  final String Function(Object) onError;

  @override
  ConsumerState<_BulkForm> createState() => _BulkFormState();
}

class _BulkFormState extends ConsumerState<_BulkForm> {
  late String _plant = widget.plants.first.id;
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: Space.md), child: Text(_error!, style: TextStyle(color: context.palette.danger))),
      if (widget.plants.length > 1) ...[
        DropdownButtonFormField<String>(
          initialValue: _plant,
          decoration: const InputDecoration(labelText: 'Plant'),
          items: [for (final p in widget.plants) DropdownMenuItem(value: p.id, child: Text(p.name))],
          onChanged: (v) => setState(() => _plant = v!),
        ),
        const Gap(Space.lg),
      ],
      TextField(
        controller: _text,
        maxLines: 8,
        minLines: 6,
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(hintText: 'CNC-01,CNC Lathe 1,Lathe\n,Press 7,Press'),
      ),
      const Gap(Space.lg),
      BusyButton(
        busy: _busy,
        label: 'Import',
        icon: Icons.upload_rounded,
        onPressed: () async {
          setState(() { _busy = true; _error = null; });
          try {
            final n = await ref.read(equipmentRepositoryProvider).bulkImport(_plant, _text.text);
            if (context.mounted) Navigator.pop(context, n);
          } catch (e) {
            setState(() { _busy = false; _error = widget.onError(e); });
          }
        },
      ),
    ]);
  }
}
