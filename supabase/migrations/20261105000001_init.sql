-- Equipment Management System: initial schema (multi-plant, append-only history, RLS, notifications)

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- types
create type public.user_role as enum ('worker', 'manager', 'admin');

-- ---------------------------------------------------------------- tables
create table public.plants (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,
  name       text not null,
  timezone   text not null default 'UTC',
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.areas (
  id         uuid primary key default gen_random_uuid(),
  plant_id   uuid not null references public.plants(id),
  name       text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  unique (plant_id, name)
);

-- one row per login; created by trigger from an invite
create table public.profiles (
  id             uuid primary key references auth.users(id) on delete restrict,
  name           text not null,
  email          text not null,
  role           public.user_role not null default 'worker',
  active         boolean not null default true,
  deactivated_at timestamptz,
  created_at     timestamptz not null default now()
);

create table public.user_plants (
  user_id  uuid not null references public.profiles(id),
  plant_id uuid not null references public.plants(id),
  primary key (user_id, plant_id)
);

-- admin-created invitations; trigger on auth.users consumes them (never trust user_metadata)
create table public.invites (
  id         uuid primary key default gen_random_uuid(),
  email      text not null,
  name       text not null,
  role       public.user_role not null default 'worker',
  plant_ids  uuid[] not null default '{}',
  invited_by uuid references public.profiles(id),
  expires_at timestamptz not null default now() + interval '7 days',
  used_at    timestamptz,
  created_at timestamptz not null default now()
);
create unique index invites_open_email_idx on public.invites (lower(email)) where used_at is null;

create table public.equipment (
  id           uuid primary key default gen_random_uuid(),
  tag_code     text not null unique,
  name         text not null,
  type         text,
  plant_id     uuid not null references public.plants(id),
  area_id      uuid references public.areas(id),
  manufacturer text,
  model        text,
  serial_no    text,
  install_date date,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);
create index equipment_plant_idx on public.equipment (plant_id) where is_active;

-- factory has no existing statuses: admin-editable list, seeded with defaults
create table public.status_types (
  id         uuid primary key default gen_random_uuid(),
  key        text not null unique,
  label      text not null,
  color      text not null default '#6b7280',
  is_failure boolean not null default false,
  sort_order int not null default 0,
  active     boolean not null default true
);

-- APPEND-ONLY history
create table public.status_events (
  id               uuid primary key default gen_random_uuid(),
  client_event_id  uuid unique,                      -- idempotency key for offline retries
  equipment_id     uuid not null references public.equipment(id),
  plant_id         uuid not null references public.plants(id),  -- filled by trigger
  status_type_id   uuid not null references public.status_types(id),
  note             text check (char_length(note) <= 2000),
  photo_path       text,
  reported_by      uuid not null references public.profiles(id) default auth.uid(),
  reported_at      timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  check (reported_at <= now() + interval '5 minutes')
);
create index status_events_equipment_idx on public.status_events (equipment_id, reported_at desc);
create index status_events_plant_time_idx on public.status_events (plant_id, reported_at desc);
create index status_events_time_idx on public.status_events (reported_at desc);

create table public.notifications (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id),
  equipment_id    uuid not null references public.equipment(id),
  status_event_id uuid not null references public.status_events(id),
  kind            text not null check (kind in ('failure', 'recovery')),
  message         text not null,
  read_at         timestamptz,
  created_at      timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;

create table public.audit_log (
  id        bigint generated always as identity primary key,
  actor_id  uuid,
  action    text not null,
  entity    text not null,
  entity_id text,
  before    jsonb,
  after     jsonb,
  at        timestamptz not null default now()
);

-- ---------------------------------------------------------------- helpers
create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and active);
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and active and role = 'admin');
$$;

create or replace function public.has_plant_access(p_plant uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and active and role = 'admin')
      or exists (select 1 from profiles p join user_plants up on up.user_id = p.id
                 where p.id = auth.uid() and p.active and up.plant_id = p_plant);
$$;

create or replace function public.is_plant_manager(p_plant uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and active and role = 'admin')
      or exists (select 1 from profiles p join user_plants up on up.user_id = p.id
                 where p.id = auth.uid() and p.active and p.role = 'manager' and up.plant_id = p_plant);
$$;

-- ---------------------------------------------------------------- triggers
-- Create profile when an invited person signs up. No invite => signup rejected.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare inv invites%rowtype; pid uuid;
begin
  select * into inv from invites
   where lower(email) = lower(new.email) and used_at is null and expires_at > now()
   order by created_at desc limit 1;
  if not found then
    raise exception 'No valid invitation for this email';
  end if;
  insert into profiles (id, name, email, role) values (new.id, inv.name, new.email, inv.role);
  foreach pid in array inv.plant_ids loop
    insert into user_plants (user_id, plant_id) values (new.id, pid);
  end loop;
  update invites set used_at = now() where id = inv.id;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- status_events: derive plant, enforce access, block edits/deletes
create or replace function public.status_events_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare eq equipment%rowtype;
begin
  select * into eq from equipment where id = new.equipment_id;
  if not found or not eq.is_active then
    raise exception 'Equipment not found or retired';
  end if;
  new.plant_id := eq.plant_id;
  return new;
end $$;
create trigger status_events_bi before insert on public.status_events
  for each row execute function public.status_events_before_insert();

create or replace function public.block_mutation()
returns trigger language plpgsql as $$
begin
  raise exception '% on % is not allowed: history is append-only', tg_op, tg_table_name;
end $$;
create trigger status_events_no_update before update or delete on public.status_events
  for each row execute function public.block_mutation();
create trigger status_events_no_truncate before truncate on public.status_events
  for each statement execute function public.block_mutation();

-- notifications: failure / recovery -> active managers of that plant + admins (not the reporter)
create or replace function public.notify_on_status_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  new_st status_types%rowtype;
  prev_failure boolean;
  eq_name text; plant_name text; who text; k text; msg text;
begin
  select * into new_st from status_types where id = new.status_type_id;
  select coalesce(st.is_failure, false) into prev_failure
    from status_events e join status_types st on st.id = e.status_type_id
   where e.equipment_id = new.equipment_id and e.id <> new.id
   order by e.reported_at desc, e.created_at desc limit 1;
  prev_failure := coalesce(prev_failure, false);

  if new_st.is_failure then k := 'failure';
  elsif prev_failure then k := 'recovery';
  else return new;
  end if;

  select e.name, p.name into eq_name, plant_name
    from equipment e join plants p on p.id = e.plant_id where e.id = new.equipment_id;
  select name into who from profiles where id = new.reported_by;
  msg := case k
    when 'failure'  then format('%s (%s) is now %s — reported by %s', eq_name, plant_name, new_st.label, who)
    else                 format('%s (%s) is back: %s — reported by %s', eq_name, plant_name, new_st.label, who)
  end;

  insert into notifications (user_id, equipment_id, status_event_id, kind, message)
  select p.id, new.equipment_id, new.id, k, msg
    from profiles p
   where p.active and p.id <> new.reported_by
     and (p.role = 'admin'
          or (p.role = 'manager' and exists
              (select 1 from user_plants up where up.user_id = p.id and up.plant_id = new.plant_id)));
  return new;
end $$;
create trigger status_events_notify after insert on public.status_events
  for each row execute function public.notify_on_status_event();

-- generic audit for admin-managed tables
create or replace function public.audit_row()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into audit_log (actor_id, action, entity, entity_id, before, after)
  values (auth.uid(), tg_op, tg_table_name,
          coalesce((to_jsonb(new)->>'id'), (to_jsonb(old)->>'id')),
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return coalesce(new, old);
end $$;
create trigger audit_equipment after insert or update or delete on public.equipment
  for each row execute function public.audit_row();
create trigger audit_profiles after update on public.profiles
  for each row execute function public.audit_row();
create trigger audit_user_plants after insert or delete on public.user_plants
  for each row execute function public.audit_row();
create trigger audit_status_types after insert or update or delete on public.status_types
  for each row execute function public.audit_row();
create trigger audit_plants after insert or update or delete on public.plants
  for each row execute function public.audit_row();

-- stamp deactivation time
create or replace function public.profiles_deactivation()
returns trigger language plpgsql as $$
begin
  if old.active and not new.active then new.deactivated_at := now(); end if;
  if not old.active and new.active then new.deactivated_at := null; end if;
  return new;
end $$;
create trigger profiles_deactivation before update on public.profiles
  for each row execute function public.profiles_deactivation();

-- ---------------------------------------------------------------- views
create view public.equipment_current_status
with (security_invoker = true) as
select distinct on (e.id)
       e.id as equipment_id, e.tag_code, e.name, e.type, e.plant_id, e.area_id,
       se.id as status_event_id, se.status_type_id, se.note, se.reported_by, se.reported_at
  from public.equipment e
  left join public.status_events se on se.equipment_id = e.id
 where e.is_active
 order by e.id, se.reported_at desc nulls last, se.created_at desc nulls last;

-- ---------------------------------------------------------------- RLS
alter table public.plants         enable row level security;
alter table public.areas          enable row level security;
alter table public.profiles       enable row level security;
alter table public.user_plants    enable row level security;
alter table public.invites        enable row level security;
alter table public.equipment      enable row level security;
alter table public.status_types   enable row level security;
alter table public.status_events  enable row level security;
alter table public.notifications  enable row level security;
alter table public.audit_log      enable row level security;

-- plants / areas
create policy plants_read  on public.plants for select using (public.has_plant_access(id));
create policy plants_admin on public.plants for all    using (public.is_admin()) with check (public.is_admin());
create policy areas_read   on public.areas  for select using (public.has_plant_access(plant_id));
create policy areas_write  on public.areas  for all
  using (public.is_plant_manager(plant_id)) with check (public.is_plant_manager(plant_id));

-- profiles: see yourself, admins see all, managers see people in their plants
create policy profiles_read on public.profiles for select using (
  id = auth.uid()
  or public.is_admin()
  or exists (select 1 from public.user_plants up
              where up.user_id = profiles.id and public.is_plant_manager(up.plant_id))
  -- reporters shown on history: anyone with plant access to an event they reported
  or exists (select 1 from public.status_events se
              where se.reported_by = profiles.id and public.has_plant_access(se.plant_id))
);
create policy profiles_admin_update on public.profiles for update
  using (public.is_admin()) with check (public.is_admin());

create policy user_plants_read on public.user_plants for select
  using (user_id = auth.uid() or public.is_plant_manager(plant_id));
create policy user_plants_admin on public.user_plants for all
  using (public.is_admin()) with check (public.is_admin());

create policy invites_admin on public.invites for all
  using (public.is_admin()) with check (public.is_admin());

-- equipment
create policy equipment_read  on public.equipment for select using (public.has_plant_access(plant_id));
create policy equipment_write on public.equipment for all
  using (public.is_plant_manager(plant_id)) with check (public.is_plant_manager(plant_id));

-- status types
create policy status_types_read  on public.status_types for select using (public.is_active_user());
create policy status_types_admin on public.status_types for all
  using (public.is_admin()) with check (public.is_admin());

-- status events: read within plant; insert only as yourself within plant; no update/delete policies
create policy status_events_read on public.status_events for select
  using (public.has_plant_access(plant_id));
create policy status_events_insert on public.status_events for insert
  with check (
    reported_by = auth.uid()
    and exists (select 1 from public.equipment e
                 where e.id = equipment_id and public.has_plant_access(e.plant_id))
  );

-- notifications: own only; may only set read_at
create policy notifications_read on public.notifications for select using (user_id = auth.uid());
create policy notifications_mark on public.notifications for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke update on public.notifications from authenticated;
grant  update (read_at) on public.notifications to authenticated;

create policy audit_admin_read on public.audit_log for select using (public.is_admin());

-- table privileges (RLS does the row filtering)
grant usage on schema public to authenticated;
grant select on public.plants, public.areas, public.profiles, public.user_plants,
               public.equipment, public.status_types, public.status_events,
               public.notifications, public.equipment_current_status to authenticated;
grant insert, update, delete on public.areas, public.equipment, public.plants,
               public.status_types, public.user_plants, public.invites to authenticated;
grant select on public.invites, public.audit_log to authenticated;
grant update on public.profiles to authenticated;
grant insert on public.status_events to authenticated;

-- realtime for the notification bell and live dashboard
alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.status_events;

-- ---------------------------------------------------------------- seed defaults
insert into public.status_types (key, label, color, is_failure, sort_order) values
  ('running',     'Running',           '#16a34a', false, 1),
  ('degraded',    'Degraded',          '#d97706', true,  2),
  ('down',        'Down',              '#dc2626', true,  3),
  ('maintenance', 'Under Maintenance', '#2563eb', false, 4);

-- Storage bucket for failure photos (private; access via signed URLs)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('failure-photos', 'failure-photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy failure_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'failure-photos' and public.is_active_user());
create policy failure_photos_read on storage.objects for select to authenticated
  using (bucket_id = 'failure-photos' and public.is_active_user());
