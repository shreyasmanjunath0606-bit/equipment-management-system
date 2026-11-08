import 'package:flutter/painting.dart';

enum Role {
  worker,
  manager,
  admin;

  static Role parse(String? v) => Role.values.firstWhere((r) => r.name == v, orElse: () => Role.worker);
  bool get isManagerOrAdmin => this == Role.manager || this == Role.admin;
  String get label => '${name[0].toUpperCase()}${name.substring(1)}';
}

typedef Json = Map<String, dynamic>;

DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

class Profile {
  const Profile({required this.id, required this.name, required this.email, required this.role, required this.active});
  final String id, name, email;
  final Role role;
  final bool active;

  factory Profile.fromJson(Json j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        role: Role.parse(j['role'] as String?),
        active: j['active'] as bool? ?? true,
      );

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}

class Plant {
  const Plant({required this.id, required this.code, required this.name, required this.timezone, this.active = true});
  final String id, code, name, timezone;
  final bool active;

  factory Plant.fromJson(Json j) => Plant(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        timezone: j['timezone'] as String? ?? 'UTC',
        active: j['active'] as bool? ?? true,
      );
}

class StatusType {
  const StatusType({
    required this.id,
    required this.key,
    required this.label,
    required this.colorHex,
    required this.isFailure,
    required this.sortOrder,
  });
  final String id, key, label, colorHex;
  final bool isFailure;
  final int sortOrder;

  Color get color {
    final h = colorHex.replaceFirst('#', '');
    final full = h.length == 3 ? h.split('').map((c) => '$c$c').join() : h;
    return Color(int.tryParse('FF$full', radix: 16) ?? 0xFF6B7280);
  }

  factory StatusType.fromJson(Json j) => StatusType(
        id: j['id'] as String,
        key: j['key'] as String,
        label: j['label'] as String,
        colorHex: j['color'] as String? ?? '#6b7280',
        isFailure: j['is_failure'] as bool? ?? false,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );
}

/// Row of the `equipment_current_status` view.
class CurrentStatus {
  const CurrentStatus({
    required this.equipmentId,
    required this.tagCode,
    required this.name,
    required this.plantId,
    this.type,
    this.areaId,
    this.statusEventId,
    this.statusTypeId,
    this.note,
    this.reportedAt,
  });
  final String equipmentId, tagCode, name, plantId;
  final String? type, areaId, statusEventId, statusTypeId, note;
  final DateTime? reportedAt;

  factory CurrentStatus.fromJson(Json j) => CurrentStatus(
        equipmentId: j['equipment_id'] as String,
        tagCode: j['tag_code'] as String,
        name: j['name'] as String,
        type: j['type'] as String?,
        plantId: j['plant_id'] as String,
        areaId: j['area_id'] as String?,
        statusEventId: j['status_event_id'] as String?,
        statusTypeId: j['status_type_id'] as String?,
        note: j['note'] as String?,
        reportedAt: _dt(j['reported_at']),
      );
}

class Equipment {
  const Equipment({
    required this.id,
    required this.tagCode,
    required this.name,
    required this.plantId,
    required this.isActive,
    this.type,
    this.areaId,
    this.manufacturer,
    this.model,
    this.serialNo,
    this.installDate,
    this.assignedWorker,
  });
  final String id, tagCode, name, plantId;
  final String? type, areaId, manufacturer, model, serialNo;

  /// The one worker who looks after this equipment and does all its checks.
  final String? assignedWorker;
  final DateTime? installDate;
  final bool isActive;

  static const columns = 'id,tag_code,name,type,plant_id,area_id,manufacturer,model,serial_no,install_date,is_active,assigned_worker';

  factory Equipment.fromJson(Json j) => Equipment(
        id: j['id'] as String,
        tagCode: j['tag_code'] as String,
        name: j['name'] as String,
        type: j['type'] as String?,
        plantId: j['plant_id'] as String,
        areaId: j['area_id'] as String?,
        manufacturer: j['manufacturer'] as String?,
        model: j['model'] as String?,
        serialNo: j['serial_no'] as String?,
        installDate: j['install_date'] == null ? null : DateTime.parse(j['install_date'] as String),
        isActive: j['is_active'] as bool? ?? true,
        assignedWorker: j['assigned_worker'] as String?,
      );
}

class StatusEvent {
  const StatusEvent({
    required this.id,
    required this.equipmentId,
    required this.statusTypeId,
    required this.reportedAt,
    required this.plantId,
    this.note,
    this.photoPath,
    this.reporterName,
    this.equipmentName,
    this.equipmentTag,
  });
  final String id, equipmentId, statusTypeId, plantId;
  final String? note, photoPath, reporterName, equipmentName, equipmentTag;
  final DateTime reportedAt;

  factory StatusEvent.fromJson(Json j) => StatusEvent(
        id: j['id'] as String,
        equipmentId: j['equipment_id'] as String,
        statusTypeId: j['status_type_id'] as String,
        plantId: j['plant_id'] as String? ?? '',
        note: j['note'] as String?,
        photoPath: j['photo_path'] as String?,
        reportedAt: _dt(j['reported_at'])!,
        reporterName: (j['profiles'] as Json?)?['name'] as String?,
        equipmentName: (j['equipment'] as Json?)?['name'] as String?,
        equipmentTag: (j['equipment'] as Json?)?['tag_code'] as String?,
      );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.message,
    required this.createdAt,
    this.equipmentId,
    this.readAt,
  });
  final String id, kind, message;
  final String? equipmentId;
  final DateTime createdAt;
  final DateTime? readAt;
  bool get unread => readAt == null;

  factory AppNotification.fromJson(Json j) => AppNotification(
        id: j['id'] as String,
        kind: j['kind'] as String,
        message: j['message'] as String,
        equipmentId: j['equipment_id'] as String?,
        createdAt: _dt(j['created_at'])!,
        readAt: _dt(j['read_at']),
      );
}
