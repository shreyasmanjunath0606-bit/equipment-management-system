import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/status.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/session.dart';

typedef _UsersData = ({List<Profile> users, Map<String, Set<String>> plantsByUser, List<Json> invites, Map<String, String> equipmentByWorker});

final _usersProvider = FutureProvider<_UsersData>((ref) async {
  final db = ref.watch(supabaseProvider);
  final results = await Future.wait([
    db.from('profiles').select('id,name,email,role,active').order('name'),
    db.from('user_plants').select('user_id,plant_id'),
    db.from('invites').select('id,email,name,role,expires_at').isFilter('used_at', null).order('created_at', ascending: false),
    db.from('equipment').select('name,tag_code,assigned_worker').not('assigned_worker', 'is', null),
  ]);
  final byUser = <String, Set<String>>{};
  for (final r in results[1]) {
    byUser.putIfAbsent(r['user_id'] as String, () => {}).add(r['plant_id'] as String);
  }
  final equipmentByWorker = {for (final r in results[3]) r['assigned_worker'] as String: '${r['name']} (${r['tag_code']})'};
  return (users: results[0].map(Profile.fromJson).toList(), plantsByUser: byUser, invites: results[2], equipmentByWorker: equipmentByWorker);
});

/// Calls the admin-users Edge Function (service-role work happens server-side only).
Future<void> _callAdmin(WidgetRef ref, Map<String, dynamic> body) async {
  final res = await ref.read(supabaseProvider).functions.invoke('admin-users', body: body);
  final data = res.data;
  if (res.status >= 400 || (data is Map && data['error'] != null)) {
    throw Exception(data is Map ? data['error'] : 'Request failed');
  }
}

String _errText(Object e) {
  if (e is FunctionException) {
    final d = e.details;
    if (d is Map && d['error'] != null) return d['error'].toString();
    return 'Server error (${e.status})';
  }
  return e.toString().replaceFirst('Exception: ', '');
}

class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  Future<void> _invite(BuildContext context, WidgetRef ref, List<Plant> plants) async {
    final ok = await showFormSheet<bool>(context, title: 'Invite a person', subtitle: "They'll get an email link to set a password.", builder: (_) => _InviteForm(plants: plants));
    if (ok == true && context.mounted) {
      ref.invalidate(_usersProvider);
      showToast(context, 'Invite sent');
    }
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, Profile u) async {
    if (u.active) {
      final ok = await showConfirmSheet(context,
          title: 'Deactivate ${u.name}?', message: "They will be signed out everywhere and can't sign in until reactivated. Their history stays.", confirmLabel: 'Deactivate', destructive: true);
      if (!ok) return;
    }
    try {
      await _callAdmin(ref, {'action': 'set_active', 'id': u.id, 'active': !u.active});
      ref.invalidate(_usersProvider);
      if (context.mounted) showToast(context, u.active ? '${u.name} deactivated' : '${u.name} reactivated');
    } catch (e) {
      if (context.mounted) showToast(context, _errText(e));
    }
  }

  Future<void> _editPlants(BuildContext context, WidgetRef ref, Profile u, Set<String> current, List<Plant> plants) async {
    final selected = await showFormSheet<Set<String>>(context, title: 'Plants for ${u.name}', subtitle: 'They can only see and report on equipment in these plants.', builder: (_) => _PlantPicker(plants: plants, initial: current));
    if (selected == null) return;
    try {
      final db = ref.read(supabaseProvider);
      await db.from('user_plants').delete().eq('user_id', u.id);
      if (selected.isNotEmpty) await db.from('user_plants').insert([for (final p in selected) {'user_id': u.id, 'plant_id': p}]);
      ref.invalidate(_usersProvider);
      if (context.mounted) showToast(context, 'Plants updated');
    } catch (_) {
      if (context.mounted) showToast(context, 'Could not save — check your connection');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_usersProvider);
    final plants = ref.watch(plantsProvider).value ?? const <Plant>[];
    final plantById = {for (final p in plants) p.id: p};
    final me = ref.watch(profileProvider);
    final pal = context.palette;

    Color roleColor(Role r) => switch (r) { Role.admin => const Color(0xFF7C3AED), Role.manager => pal.primary, Role.worker => pal.muted };

    return PageBody(
      maxWidth: 960,
      onRefresh: () async => ref.invalidate(_usersProvider),
      children: [
        PageHeader(
          title: 'Users',
          subtitle: data.value == null ? null : '${data.value!.users.where((u) => u.active).length} active · ${data.value!.invites.length} pending invite${data.value!.invites.length == 1 ? '' : 's'}',
          actions: [FilledButton.icon(onPressed: () => _invite(context, ref, plants), icon: const Icon(Icons.person_add_alt_rounded, size: 20), label: const Text('Invite person'))],
        ),
        AsyncBody<_UsersData>(
          value: data,
          onRetry: () => ref.invalidate(_usersProvider),
          data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (d.invites.isNotEmpty) ...[
              SectionCard(
                title: 'Pending invites',
                child: Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                  for (final i in d.invites) Pill('${i['email']} · ${i['role']}', icon: Icons.mail_outline_rounded),
                ]),
              ),
              const Gap(Space.lg),
            ],
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var i = 0; i < d.users.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: pal.border),
                  Builder(builder: (context) {
                    final u = d.users[i];
                    final mine = d.plantsByUser[u.id] ?? const <String>{};
                    final plantText = u.role == Role.admin
                        ? 'All plants'
                        : (mine.isEmpty ? 'No plants assigned' : mine.map((id) => plantById[id]?.name).whereType<String>().join(', '));
                    return Opacity(
                      opacity: u.active ? 1 : 0.6,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                        child: Row(children: [
                          CircleAvatar(
                            radius: 19,
                            backgroundColor: u.active ? pal.primarySoft : pal.surfaceMuted,
                            child: Text(u.initials, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: u.active ? pal.primary : pal.muted)),
                          ),
                          const Gap(Space.md),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Wrap(spacing: Space.sm, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                Text(u.name, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                Pill(u.role.label, color: roleColor(u.role)),
                                if (!u.active) Pill('Deactivated', color: pal.danger),
                                if (u.id == me.id) Text('(you)', style: context.text.bodySmall),
                              ]),
                              const SizedBox(height: 2),
                              Text(u.email, style: context.text.bodySmall, overflow: TextOverflow.ellipsis),
                              Text(plantText, style: context.text.bodySmall?.copyWith(color: mine.isEmpty && u.role != Role.admin ? pal.warning : null), overflow: TextOverflow.ellipsis),
                              if (u.role == Role.worker && u.active)
                                Text(
                                  d.equipmentByWorker[u.id] == null ? 'No equipment — assign one under Assignments' : 'Looks after ${d.equipmentByWorker[u.id]}',
                                  style: context.text.bodySmall?.copyWith(color: d.equipmentByWorker[u.id] == null ? pal.warning : null),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ]),
                          ),
                          if (u.id != me.id)
                            PopupMenuButton<String>(
                              tooltip: 'Actions',
                              onSelected: (v) => v == 'plants' ? _editPlants(context, ref, u, mine, plants) : _toggle(context, ref, u),
                              itemBuilder: (_) => [
                                if (u.role != Role.admin) const PopupMenuItem(value: 'plants', child: Text('Change plants')),
                                PopupMenuItem(value: 'toggle', child: Text(u.active ? 'Deactivate' : 'Reactivate', style: TextStyle(color: u.active ? pal.danger : null))),
                              ],
                            ),
                        ]),
                      ),
                    );
                  }),
                ],
              ]),
            ),
          ]),
        ),
      ],
    );
  }
}

class _PlantPicker extends StatefulWidget {
  const _PlantPicker({required this.plants, required this.initial});
  final List<Plant> plants;
  final Set<String> initial;
  @override
  State<_PlantPicker> createState() => _PlantPickerState();
}

class _PlantPickerState extends State<_PlantPicker> {
  late final Set<String> _sel = {...widget.initial};
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final p in widget.plants)
          CheckboxListTile(
            value: _sel.contains(p.id),
            title: Text(p.name),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => setState(() => v! ? _sel.add(p.id) : _sel.remove(p.id)),
          ),
        const Gap(Space.lg),
        FilledButton(onPressed: () => Navigator.pop(context, _sel), child: const Text('Save')),
      ]);
}

class _InviteForm extends ConsumerStatefulWidget {
  const _InviteForm({required this.plants});
  final List<Plant> plants;
  @override
  ConsumerState<_InviteForm> createState() => _InviteFormState();
}

class _InviteFormState extends ConsumerState<_InviteForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController();
  Role _role = Role.worker;
  late final Set<String> _plants = {if (widget.plants.length == 1) widget.plants.first.id};
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    if (_role != Role.admin && _plants.isEmpty) {
      setState(() => _error = 'Choose at least one plant.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _callAdmin(ref, {
        'action': 'invite',
        'email': _email.text.trim(),
        'name': _name.text.trim(),
        'role': _role.name,
        'plant_ids': _plants.toList(),
        // Invite links open the web app, which works on any device.
        'redirect_to': kIsWeb ? Uri.base.origin : Env.siteUrl,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = _errText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final descr = {Role.worker: 'Does checks and reports status', Role.manager: 'Dashboard, alerts, equipment, check sheets', Role.admin: 'Everything, all plants, users'};
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: Space.md), child: Text(_error!, style: TextStyle(color: context.palette.danger))),
        TextFormField(controller: _name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
        const Gap(Space.lg),
        TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email'), validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email'),
        const Gap(Space.lg),
        Text('Role', style: context.text.labelMedium),
        const Gap(Space.sm),
        RadioGroup<Role>(
          groupValue: _role,
          onChanged: (v) => setState(() => _role = v!),
          child: Column(children: [
            for (final r in Role.values)
              RadioListTile<Role>(
                value: r,
                contentPadding: EdgeInsets.zero,
                title: Text(r.label),
                subtitle: Text(descr[r]!),
              ),
          ]),
        ),
        if (_role != Role.admin) ...[
          const Gap(Space.sm),
          Text('Plants', style: context.text.labelMedium),
          const Gap(Space.sm),
          Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
            for (final p in widget.plants)
              FilterChip(label: Text(p.name), selected: _plants.contains(p.id), onSelected: (v) => setState(() => v ? _plants.add(p.id) : _plants.remove(p.id))),
          ]),
        ],
        const Gap(Space.xl),
        BusyButton(busy: _busy, label: 'Send invite', icon: Icons.send_rounded, onPressed: _send),
      ]),
    );
  }
}
