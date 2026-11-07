// Sample data for screenshot (golden) tests — no backend needed.
import 'dart:math' as math;

import 'package:equipment_portal/data/checks.dart';
import 'package:equipment_portal/data/equipment_repo.dart';
import 'package:equipment_portal/data/models.dart';

const manager = Profile(id: 'u1', name: 'Shreyas Manjunath', email: 'shreyas@example.com', role: Role.admin, active: true);
const worker = Profile(id: 'u2', name: 'Ravi Kumar', email: 'ravi@example.com', role: Role.worker, active: true);

const plants = [
  Plant(id: 'p1', code: '101', name: 'Bengaluru', timezone: 'Asia/Kolkata'),
  Plant(id: 'p2', code: '201', name: 'Mumbai', timezone: 'Asia/Kolkata'),
];

const statusTypes = [
  StatusType(id: 's1', key: 'running', label: 'Running', colorHex: '#16a34a', isFailure: false, sortOrder: 1),
  StatusType(id: 's2', key: 'degraded', label: 'Degraded', colorHex: '#d97706', isFailure: true, sortOrder: 2),
  StatusType(id: 's3', key: 'down', label: 'Down', colorHex: '#dc2626', isFailure: true, sortOrder: 3),
  StatusType(id: 's4', key: 'maintenance', label: 'Under Maintenance', colorHex: '#2563eb', isFailure: false, sortOrder: 4),
];

final _now = DateTime.now();

final _machines = <(String, String, String)>[
  ('101-CNC-0001', 'CNC Lathe 1', 'p1'),
  ('101-CNC-0002', 'CNC Lathe 2', 'p1'),
  ('101-PRS-0001', 'Hydraulic Press 1', 'p1'),
  ('101-CMP-0001', 'Air Compressor A', 'p1'),
  ('101-WLD-0001', 'Robot Welder 3', 'p1'),
  ('101-CNV-0001', 'Conveyor Line 2', 'p1'),
  ('101-BLR-0001', 'Boiler 1', 'p1'),
  ('101-PMP-0001', 'Coolant Pump 4', 'p1'),
  ('201-CNC-0001', 'Vertical Mill 1', 'p2'),
  ('201-PRS-0001', 'Stamping Press 7', 'p2'),
  ('201-INJ-0001', 'Injection Moulder 2', 'p2'),
  ('201-CMP-0001', 'Air Compressor B', 'p2'),
  ('201-CHL-0001', 'Chiller 1', 'p2'),
  ('201-PKG-0001', 'Packaging Line 1', 'p2'),
];

final currentStatus = [
  for (var i = 0; i < _machines.length; i++)
    CurrentStatus(
      equipmentId: 'e$i',
      tagCode: _machines[i].$1,
      name: _machines[i].$2,
      plantId: _machines[i].$3,
      statusTypeId: switch (i) { 2 => 's3', 9 => 's2', 5 => 's4', 13 => null, _ => 's1' },
      reportedAt: _now.subtract(Duration(minutes: 37 * (i + 1))),
    ),
];

final recentEvents = [
  for (final (i, sid, who) in [(2, 's3', 'Ravi Kumar'), (9, 's2', 'Anita Desai'), (5, 's4', 'Ravi Kumar'), (0, 's1', 'Mohan R'), (11, 's1', 'Anita Desai'), (7, 's1', 'Mohan R')])
    StatusEvent(
      id: 'ev$i',
      equipmentId: 'e$i',
      statusTypeId: sid,
      plantId: _machines[i].$3,
      reportedAt: _now.subtract(Duration(minutes: 37 * (i + 1))),
      reporterName: who,
      equipmentName: _machines[i].$2,
      equipmentTag: _machines[i].$1,
    ),
];

DateTime get _today => DateTime(_now.year, _now.month, _now.day);

CheckTask _task(int n, int eq, String title, CheckFrequency f, {int dueOffset = 0, TaskStatus status = TaskStatus.pending, String? desc}) {
  final due = _today.add(Duration(days: dueOffset));
  return CheckTask(
    id: 't$n',
    itemId: 'i$n',
    equipmentId: 'e$eq',
    plantId: _machines[eq].$3,
    dueDate: due,
    windowEnd: switch (f) { CheckFrequency.daily => due, CheckFrequency.weekly => due.add(const Duration(days: 6)), CheckFrequency.monthly => DateTime(due.year, due.month + 1, due.day - 1) },
    status: status,
    title: title,
    frequency: f,
    equipmentName: _machines[eq].$2,
    equipmentCode: _machines[eq].$1,
    description: desc,
    completedAt: status == TaskStatus.done ? _today.add(const Duration(hours: 9, minutes: 12)) : null,
    completedByName: status == TaskStatus.done ? 'Ravi Kumar' : null,
  );
}

final checkTasks = [
  _task(1, 0, 'Check coolant level', CheckFrequency.daily, status: TaskStatus.done),
  _task(2, 0, 'Clean chip tray', CheckFrequency.daily, status: TaskStatus.done),
  _task(3, 0, 'Inspect spindle for noise / vibration', CheckFrequency.daily, desc: 'Listen at idle and at 1500 rpm'),
  _task(4, 2, 'Check hydraulic oil level', CheckFrequency.daily),
  _task(5, 2, 'Inspect hoses for leaks', CheckFrequency.weekly, desc: 'Look for wet spots around fittings'),
  _task(6, 2, 'Test emergency stop', CheckFrequency.daily, status: TaskStatus.done),
  _task(7, 3, 'Drain moisture from tank', CheckFrequency.daily),
  _task(8, 3, 'Check belt tension', CheckFrequency.monthly),
  _task(9, 4, 'Clean welding tip', CheckFrequency.daily, status: TaskStatus.done),
  _task(10, 4, 'Grease axis bearings', CheckFrequency.weekly, dueOffset: -2),
  _task(11, 7, 'Check pump pressure gauge', CheckFrequency.weekly, dueOffset: -3),
  _task(12, 0, 'Lubricate guideways', CheckFrequency.weekly, dueOffset: 1),
  _task(13, 6, 'Blow-down boiler', CheckFrequency.weekly, dueOffset: 2),
  _task(14, 3, 'Replace intake filter', CheckFrequency.monthly, dueOffset: 4),
];

final findings = [
  Finding(
    id: 'f1', equipmentId: 'e2', plantId: 'p1', description: 'Oil seeping from the main cylinder seal',
    status: FindingStatus.scheduled, reportedAt: _now.subtract(const Duration(hours: 26)), scheduledFor: _now.subtract(const Duration(hours: 2)),
    reporterName: 'Ravi Kumar', equipmentName: 'Hydraulic Press 1', equipmentCode: '101-PRS-0001',
  ),
  Finding(
    id: 'f2', equipmentId: 'e3', plantId: 'p1', description: 'Drive belt is frayed at one edge',
    status: FindingStatus.scheduled, reportedAt: _now.subtract(const Duration(hours: 3)), scheduledFor: _now.add(const Duration(hours: 20)),
    reporterName: 'Anita Desai', equipmentName: 'Air Compressor A', equipmentCode: '101-CMP-0001',
  ),
  Finding(
    id: 'f3', equipmentId: 'e0', plantId: 'p1', description: 'Coolant level below minimum',
    status: FindingStatus.open, reportedAt: _now.subtract(const Duration(minutes: 40)),
    reporterName: 'Ravi Kumar', equipmentName: 'CNC Lathe 1', equipmentCode: '101-CNC-0001',
  ),
  Finding(
    id: 'f4', equipmentId: 'e0', plantId: 'p1', description: 'Chip conveyor jammed',
    status: FindingStatus.resolved, reportedAt: _now.subtract(const Duration(days: 2)), resolvedAt: _now.subtract(const Duration(days: 2, hours: -1)),
    reporterName: 'Mohan R', resolverName: 'Mohan R', resolutionNote: 'Cleared swarf and restarted', equipmentName: 'CNC Lathe 1', equipmentCode: '101-CNC-0001',
  ),
];

final equipmentDetail = EquipmentDetail(
  equipment: const Equipment(id: 'e2', tagCode: '101-PRS-0001', name: 'Hydraulic Press 1', plantId: 'p1', isActive: true, type: 'Press', manufacturer: 'Schuler', model: 'MSD 250', serialNo: 'SC-88213'),
  plantName: 'Bengaluru',
  plantTimezone: 'Asia/Kolkata',
  areaName: 'Press shop',
);

final equipmentEvents = [
  StatusEvent(id: 'x1', equipmentId: 'e2', statusTypeId: 's3', plantId: 'p1', reportedAt: _now.subtract(const Duration(hours: 1)), reporterName: 'Ravi Kumar', note: 'Ram stops mid-stroke, pressure drops to 40 bar. Oil on the floor under the cylinder.'),
  StatusEvent(id: 'x2', equipmentId: 'e2', statusTypeId: 's2', plantId: 'p1', reportedAt: _now.subtract(const Duration(hours: 26)), reporterName: 'Anita Desai', note: 'Slow return stroke.'),
  StatusEvent(id: 'x3', equipmentId: 'e2', statusTypeId: 's1', plantId: 'p1', reportedAt: _now.subtract(const Duration(days: 6)), reporterName: 'Mohan R'),
  StatusEvent(id: 'x4', equipmentId: 'e2', statusTypeId: 's4', plantId: 'p1', reportedAt: _now.subtract(const Duration(days: 7)), reporterName: 'Mohan R', note: 'Quarterly service.'),
];

List<DailyCheckStat> checkStats(int days) {
  final rnd = math.Random(7);
  var cp = 410, cc = 371;
  return [
    for (var i = days - 1; i >= 0; i--)
      () {
        final d = _today.subtract(Duration(days: i));
        final weekend = d.weekday == DateTime.sunday;
        final planned = weekend ? 6 : 14 + rnd.nextInt(5) + (d.weekday == DateTime.monday ? 6 : 0);
        final done = i == 0 ? 4 : (planned - rnd.nextInt(weekend ? 2 : 4)).clamp(0, planned);
        cp += planned;
        cc += done;
        return DailyCheckStat(day: d, planned: planned, completed: done, cumPlanned: cp, cumCompleted: cc);
      }(),
  ];
}

List<DailyFindingStat> findingStats(int days) {
  final rnd = math.Random(3);
  var cf = 21, cr = 17;
  return [
    for (var i = days - 1; i >= 0; i--)
      () {
        final d = _today.subtract(Duration(days: i));
        final found = rnd.nextInt(10) < 6 ? rnd.nextInt(3) : 0;
        final resolved = math.min(cf + found - cr, rnd.nextInt(3));
        cf += found;
        cr += resolved;
        return DailyFindingStat(day: d, found: found, resolved: resolved, cumFound: cf, cumResolved: cr);
      }(),
  ];
}
