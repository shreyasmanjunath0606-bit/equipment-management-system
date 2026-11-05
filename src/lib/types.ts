export type Role = "worker" | "manager" | "admin";

export interface Profile {
  id: string;
  name: string;
  email: string;
  role: Role;
  active: boolean;
}

export interface Plant {
  id: string;
  code: string;
  name: string;
  timezone: string;
}

export interface StatusType {
  id: string;
  key: string;
  label: string;
  color: string;
  is_failure: boolean;
  sort_order: number;
}

export interface CurrentStatusRow {
  equipment_id: string;
  tag_code: string;
  name: string;
  type: string | null;
  plant_id: string;
  area_id: string | null;
  status_event_id: string | null;
  status_type_id: string | null;
  note: string | null;
  reported_at: string | null;
}

export interface StatusEventRow {
  id: string;
  equipment_id: string;
  status_type_id: string;
  note: string | null;
  photo_path: string | null;
  reported_by: string;
  reported_at: string;
  profiles: { name: string } | null;
}

export interface NotificationRow {
  id: string;
  equipment_id: string;
  kind: "failure" | "recovery";
  message: string;
  read_at: string | null;
  created_at: string;
}
