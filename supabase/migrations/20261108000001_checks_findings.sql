-- Scheduled checks (Excel check sheets), equipment codes, findings, reminders, KPI stats.
-- See docs/plans/new-features-plan.md

-- ---------------------------------------------------------------- extensions
create extension if not exists pg_cron with schema pg_catalog;

-- ---------------------------------------------------------------- feature 2: equipment codes
-- tag_code is the one unique code; uniqueness is now case-insensitive.
create unique index if not exists equipment_tag_code_upper_idx on public.equipment (upper(tag_code));

-- <PLANT>-<TYPE3>-<0001>, e.g. 101-CNC-0001. Used when a code is left blank.
create or replace function public.generate_equipment_code(p_plant uuid, p_type text)
returns text language plpgsql volatile security definer set search_path = public as $$
declare
  v_plant text; v_type text; v_prefix text; v_next int;
begin
  select upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g')) into v_plant from plants where id = p_plant;
  if v_plant is null or v_plant = '' then v_plant := 'EQ'; end if;
  v_type := upper(left(regexp_replace(coalesce(p_type, ''), '[^A-Za-z0-9]', '', 'g'), 3));
  if v_type = '' then v_type := 'EQP'; end if;
  v_prefix := left(v_plant, 6) || '-' || v_type || '-';
  perform pg_advisory_xact_lock(hashtext(v_prefix));
  select coalesce(max((substring(upper(tag_code) from length(v_prefix) + 1))::int), 0) + 1 into v_next
    from equipment
   where upper(tag_code) like v_prefix || '%'
     and substring(upper(tag_code) from length(v_prefix) + 1) ~ '^[0-9]+$';
  return v_prefix || lpad(v_next::text, 4, '0');
end $$;

create or replace function public.equipment_code_before_write()
returns trigger language plpgsql set search_path = public as $$
begin
  new.tag_code := btrim(coalesce(new.tag_code, ''));
  if new.tag_code = '' then
    new.tag_code := public.generate_equipment_code(new.plant_id, new.type);
  end if;
  return new;
end $$;
create trigger equipment_code_biu before insert or update of tag_code on public.equipment
  for each row execute function public.equipment_code_before_write();

-- ---------------------------------------------------------------- types
create type public.check_frequency  as enum ('daily', 'weekly', 'monthly');
create type public.check_task_status as enum ('pending', 'done', 'missed');
create type public.finding_status   as enum ('open', 'scheduled', 'resolved');

-- ---------------------------------------------------------------- tables
-- One row per uploaded Excel check sheet (the file itself lives in storage bucket `check-sheets`).
create table public.check_sheets (
  id          uuid primary key default gen_random_uuid(),
  plant_id    uuid not null references public.plants(id),
  title       text not null check (char_length(title) between 1 and 200),
  file_name   text not null,
  file_path   text,
  row_count   int  not null default 0,
  uploaded_by uuid not null references public.profiles(id) default auth.uid(),
  created_at  timestamptz not null default now()
);
create index check_sheets_plant_idx on public.check_sheets (plant_id, created_at desc);

-- Recurring check definition (one Excel row).
create table public.check_items (
  id           uuid primary key default gen_random_uuid(),
  sheet_id     uuid references public.check_sheets(id),
  equipment_id uuid not null references public.equipment(id),
  plant_id     uuid not null references public.plants(id),     -- filled by trigger
  title        text not null check (char_length(title) between 1 and 300),
  description  text check (char_length(description) <= 2000),
  frequency    public.check_frequency not null,
  start_date   date not null,
  active       boolean not null default true,
  created_by   uuid references public.profiles(id) default auth.uid(),
  created_at   timestamptz not null default now()
);
create index check_items_plant_idx on public.check_items (plant_id) where active;
create index check_items_equipment_idx on public.check_items (equipment_id);
create index check_items_sheet_idx on public.check_items (sheet_id);

-- One row per due occurrence. A task can be completed until window_end (daily: same day,
-- weekly: 6 days later, monthly: the day before the next occurrence), after that it is "missed".
create table public.check_tasks (
  id            uuid primary key default gen_random_uuid(),
  check_item_id uuid not null references public.check_items(id),
  equipment_id  uuid not null references public.equipment(id),
  plant_id      uuid not null references public.plants(id),
  due_date      date not null,
  window_end    date not null,
  status        public.check_task_status not null default 'pending',
  completed_by  uuid references public.profiles(id),
  completed_at  timestamptz,
  note          text check (char_length(note) <= 1000),
  created_at    timestamptz not null default now(),
  unique (check_item_id, due_date)
);
create index check_tasks_plant_due_idx on public.check_tasks (plant_id, due_date);
create index check_tasks_equipment_due_idx on public.check_tasks (equipment_id, due_date desc);
create index check_tasks_pending_idx on public.check_tasks (plant_id, window_end) where status = 'pending';

-- Problems found while checking.
create table public.findings (
  id                  uuid primary key default gen_random_uuid(),
  client_id           uuid unique,                                  -- idempotency key for offline retries
  check_task_id       uuid references public.check_tasks(id),
  equipment_id        uuid not null references public.equipment(id),
  plant_id            uuid not null references public.plants(id),  -- filled by trigger
  description         text not null check (char_length(description) between 1 and 2000),
  photo_path          text,
  status              public.finding_status not null default 'open',
  scheduled_for       timestamptz,
  overdue_notified_at timestamptz,
  reported_by         uuid not null references public.profiles(id) default auth.uid(),
  reported_at         timestamptz not null default now(),
  resolved_by         uuid references public.profiles(id),
  resolved_at         timestamptz,
  resolution_note     text check (char_length(resolution_note) <= 2000),
  check (status <> 'scheduled' or scheduled_for is not null)
);
create index findings_plant_idx on public.findings (plant_id, reported_at desc);
create index findings_equipment_idx on public.findings (equipment_id, reported_at desc);
create index findings_overdue_idx on public.findings (scheduled_for)
  where status = 'scheduled' and overdue_notified_at is null;

-- Phone push tokens (FCM).
create table public.device_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles(id) default auth.uid(),
  platform   text not null check (platform in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);

-- notifications: allow check / finding notifications too
alter table public.notifications alter column equipment_id drop not null;
alter table public.notifications alter column status_event_id drop not null;
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('failure', 'recovery', 'check_due', 'check_reminder', 'finding_overdue'));
alter table public.notifications add column check_task_id uuid references public.check_tasks(id);
alter table public.notifications add column finding_id uuid references public.findings(id);
alter table public.notifications add column plant_id uuid references public.plants(id);
alter table public.notifications add column dedupe_key text unique;   -- stops cron re-runs double-notifying

-- ---------------------------------------------------------------- recurrence
-- Is a check with this frequency/start date due on p_day? Monthly keeps the day-of-month and
-- clamps to the month's last day (31 Jan -> 28/29 Feb).
create or replace function public.check_due_on(p_freq public.check_frequency, p_start date, p_day date)
returns boolean language sql immutable set search_path = public as $$
  select p_day >= p_start and case p_freq
    when 'daily'  then true
    when 'weekly' then (p_day - p_start) % 7 = 0
    when 'monthly' then p_day = (p_start + make_interval(months =>
        (extract(year from p_day)::int - extract(year from p_start)::int) * 12
      + (extract(month from p_day)::int - extract(month from p_start)::int)))::date
  end;
$$;

-- Last day a task may still be completed.
create or replace function public.check_window_end(p_freq public.check_frequency, p_start date, p_due date)
returns date language sql immutable set search_path = public as $$
  select case p_freq
    when 'daily'  then p_due
    when 'weekly' then p_due + 6
    when 'monthly' then (p_start + make_interval(months =>
        (extract(year from p_due)::int - extract(year from p_start)::int) * 12
      + (extract(month from p_due)::int - extract(month from p_start)::int) + 1))::date - 1
  end;
$$;

-- Create tasks from today (plant-local) up to p_days_ahead days ahead. Idempotent.
create or replace function public.generate_check_tasks(p_days_ahead int default 7)
returns int language sql volatile security definer set search_path = public as $$
  with ins as (
    insert into check_tasks (check_item_id, equipment_id, plant_id, due_date, window_end)
    select ci.id, ci.equipment_id, ci.plant_id, d::date, check_window_end(ci.frequency, ci.start_date, d::date)
      from check_items ci
      join plants p    on p.id = ci.plant_id and p.active
      join equipment e on e.id = ci.equipment_id and e.is_active
      cross join lateral generate_series(
        greatest(ci.start_date, (now() at time zone p.timezone)::date),
        (now() at time zone p.timezone)::date + least(greatest(p_days_ahead, 0), 60),
        interval '1 day') d
     where ci.active and check_due_on(ci.frequency, ci.start_date, d::date)
    on conflict (check_item_id, due_date) do nothing
    returning 1)
  select count(*)::int from ins;
$$;

-- Pending tasks whose completion window has passed become "missed".
create or replace function public.mark_missed_check_tasks()
returns int language sql volatile security definer set search_path = public as $$
  with upd as (
    update check_tasks t set status = 'missed'
      from plants p
     where p.id = t.plant_id and t.status = 'pending'
       and t.window_end < (now() at time zone p.timezone)::date
    returning 1)
  select count(*)::int from upd;
$$;

-- ---------------------------------------------------------------- triggers
create or replace function public.check_items_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare eq equipment%rowtype;
begin
  select * into eq from equipment where id = new.equipment_id;
  if not found or (tg_op = 'INSERT' and not eq.is_active) then
    raise exception 'Equipment not found or retired';
  end if;
  new.plant_id := eq.plant_id;
  return new;
end $$;
create trigger check_items_biu before insert or update of equipment_id on public.check_items
  for each row execute function public.check_items_before_write();

-- Deactivating a check item drops its future pending tasks.
create or replace function public.check_items_after_deactivate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.active and not new.active then
    delete from check_tasks where check_item_id = new.id and status = 'pending' and due_date > current_date;
  end if;
  return new;
end $$;
create trigger check_items_au after update of active on public.check_items
  for each row execute function public.check_items_after_deactivate();

-- Ticking a task stamps who/when; users may only toggle pending <-> done (late completion of a
-- missed task is allowed), never set "missed" themselves.
create or replace function public.check_tasks_before_update()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'missed' and auth.uid() is not null then
      raise exception 'Tasks are marked missed automatically';
    end if;
    if new.status = 'done' then
      new.completed_by := coalesce(auth.uid(), new.completed_by);
      new.completed_at := now();
    elsif new.status = 'pending' then
      if old.status = 'missed' then raise exception 'A missed task cannot be reopened'; end if;
      new.completed_by := null;
      new.completed_at := null;
    end if;
  end if;
  return new;
end $$;
create trigger check_tasks_bu before update on public.check_tasks
  for each row execute function public.check_tasks_before_update();

create or replace function public.findings_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare eq equipment%rowtype;
begin
  if tg_op = 'INSERT' then
    select * into eq from equipment where id = new.equipment_id;
    if not found then raise exception 'Equipment not found'; end if;
    new.plant_id := eq.plant_id;
    new.reported_at := now();
  else
    new.equipment_id := old.equipment_id;
    new.plant_id := old.plant_id;
    new.reported_by := old.reported_by;
    new.reported_at := old.reported_at;
  end if;
  if new.status = 'resolved' and (tg_op = 'INSERT' or old.status <> 'resolved') then
    new.resolved_by := auth.uid();
    new.resolved_at := now();
  elsif new.status <> 'resolved' then
    new.resolved_by := null;
    new.resolved_at := null;
  end if;
  if tg_op = 'UPDATE' and new.scheduled_for is distinct from old.scheduled_for then
    new.overdue_notified_at := null;
  end if;
  return new;
end $$;
create trigger findings_biu before insert or update on public.findings
  for each row execute function public.findings_before_write();

create trigger audit_check_sheets after insert or update or delete on public.check_sheets
  for each row execute function public.audit_row();
create trigger audit_check_items after insert or update or delete on public.check_items
  for each row execute function public.audit_row();
create trigger audit_findings after insert or update on public.findings
  for each row execute function public.audit_row();

-- ---------------------------------------------------------------- import RPC
-- Rows: [{code, title, description, frequency, start_date}]. Runs as the caller (RLS applies).
-- Codes must belong to active equipment in p_plant; others are skipped (the app validates first).
create or replace function public.import_check_sheet(
  p_plant uuid, p_title text, p_file_name text, p_file_path text, p_rows jsonb)
returns jsonb language plpgsql volatile security invoker set search_path = public as $$
declare v_sheet uuid; v_items int; v_tasks int;
begin
  if not public.is_plant_manager(p_plant) then
    raise exception 'Only managers of this plant can upload check sheets';
  end if;
  insert into check_sheets (plant_id, title, file_name, file_path)
  values (p_plant, p_title, p_file_name, p_file_path) returning id into v_sheet;

  insert into check_items (sheet_id, equipment_id, title, description, frequency, start_date)
  select v_sheet, e.id, btrim(r->>'title'), nullif(btrim(coalesce(r->>'description', '')), ''),
         lower(r->>'frequency')::public.check_frequency, (r->>'start_date')::date
    from jsonb_array_elements(p_rows) r
    join equipment e on upper(e.tag_code) = upper(btrim(r->>'code')) and e.plant_id = p_plant and e.is_active
   where coalesce(btrim(r->>'title'), '') <> '';
  get diagnostics v_items = row_count;

  update check_sheets set row_count = v_items where id = v_sheet;
  v_tasks := public.generate_check_tasks(7);
  return jsonb_build_object('sheet_id', v_sheet, 'items', v_items, 'tasks_created', v_tasks);
end $$;

-- ---------------------------------------------------------------- notifications (cron)
-- Hourly: once a plant's local time is past 07:00, each assigned user gets one summary of today's
-- checks, plus a heads-up for weekly/monthly checks due tomorrow. dedupe_key makes re-runs safe.
create or replace function public.notify_check_reminders()
returns int language plpgsql volatile security definer set search_path = public as $$
declare n1 int; n2 int;
begin
  with today as (
    select p.id plant_id, p.name plant_name, (now() at time zone p.timezone)::date d
      from plants p
     where p.active and extract(hour from (now() at time zone p.timezone)) >= 7
  ), counts as (
    select t.plant_id, td.plant_name, td.d, count(*) n
      from check_tasks t join today td on td.plant_id = t.plant_id and t.due_date = td.d
     where t.status = 'pending'
     group by t.plant_id, td.plant_name, td.d
  ), ins as (
    insert into notifications (user_id, plant_id, kind, message, dedupe_key)
    select pr.id, c.plant_id, 'check_due',
           format('%s check%s due today at %s', c.n, case when c.n = 1 then '' else 's' end, c.plant_name),
           format('due:%s:%s:%s', pr.id, c.plant_id, c.d)
      from counts c
      join user_plants up on up.plant_id = c.plant_id
      join profiles pr on pr.id = up.user_id and pr.active
    on conflict (dedupe_key) do nothing
    returning 1)
  select count(*) into n1 from ins;

  with tmr as (
    select p.id plant_id, p.name plant_name, (now() at time zone p.timezone)::date + 1 d
      from plants p
     where p.active and extract(hour from (now() at time zone p.timezone)) >= 7
  ), counts as (
    select t.plant_id, tm.plant_name, tm.d,
           count(*) filter (where ci.frequency = 'weekly') w,
           count(*) filter (where ci.frequency = 'monthly') m
      from check_tasks t
      join check_items ci on ci.id = t.check_item_id
      join tmr tm on tm.plant_id = t.plant_id and t.due_date = tm.d
     where ci.frequency in ('weekly', 'monthly') and t.status = 'pending'
     group by t.plant_id, tm.plant_name, tm.d
  ), ins as (
    insert into notifications (user_id, plant_id, kind, message, dedupe_key)
    select pr.id, c.plant_id, 'check_reminder',
           format('Tomorrow at %s: %s', c.plant_name, concat_ws(' and ',
             case when c.w > 0 then format('%s weekly check%s', c.w, case when c.w = 1 then '' else 's' end) end,
             case when c.m > 0 then format('%s monthly check%s', c.m, case when c.m = 1 then '' else 's' end) end)),
           format('tomorrow:%s:%s:%s', pr.id, c.plant_id, c.d)
      from counts c
      join user_plants up on up.plant_id = c.plant_id
      join profiles pr on pr.id = up.user_id and pr.active
    on conflict (dedupe_key) do nothing
    returning 1)
  select count(*) into n2 from ins;
  return n1 + n2;
end $$;

-- Every 15 min: scheduled findings past their time and still unresolved -> plant managers + admins, once.
create or replace function public.notify_overdue_findings()
returns int language plpgsql volatile security definer set search_path = public as $$
declare n int;
begin
  with due as (
    update findings f set overdue_notified_at = now()
     where f.status = 'scheduled' and f.overdue_notified_at is null and f.scheduled_for < now()
    returning f.*
  ), ins as (
    insert into notifications (user_id, equipment_id, plant_id, finding_id, kind, message, dedupe_key)
    select pr.id, d.equipment_id, d.plant_id, d.id, 'finding_overdue',
           format('Overdue fix: %s (%s) — "%s" was scheduled for %s by %s',
                  e.name, e.tag_code, left(d.description, 80),
                  to_char(d.scheduled_for at time zone p.timezone, 'DD Mon HH24:MI'), rp.name),
           format('overdue:%s:%s:%s', pr.id, d.id, d.scheduled_for)
      from due d
      join equipment e on e.id = d.equipment_id
      join plants p on p.id = d.plant_id
      join profiles rp on rp.id = d.reported_by
      join profiles pr on pr.active and (pr.role = 'admin' or (pr.role = 'manager' and exists
           (select 1 from user_plants up where up.user_id = pr.id and up.plant_id = d.plant_id)))
    on conflict (dedupe_key) do nothing
    returning 1)
  select count(*) into n from ins;
  return n;
end $$;

-- ---------------------------------------------------------------- KPI stats (run as caller -> RLS)
create or replace function public.check_stats_daily(p_plant uuid, p_from date, p_to date)
returns table (day date, planned int, completed int, cum_planned int, cum_completed int)
language sql stable security invoker set search_path = public as $$
  with days as (select d::date as day from generate_series(p_from, p_to, interval '1 day') d),
  t as (
    select due_date, count(*) planned, count(*) filter (where status = 'done') completed
      from check_tasks
     where due_date between p_from and p_to and (p_plant is null or plant_id = p_plant)
     group by due_date),
  base as (
    select count(*) planned, count(*) filter (where status = 'done') completed
      from check_tasks
     where due_date < p_from and (p_plant is null or plant_id = p_plant))
  select days.day,
         coalesce(t.planned, 0)::int,
         coalesce(t.completed, 0)::int,
         (base.planned   + sum(coalesce(t.planned, 0))   over (order by days.day))::int,
         (base.completed + sum(coalesce(t.completed, 0)) over (order by days.day))::int
    from days left join t on t.due_date = days.day cross join base
   order by days.day;
$$;

create or replace function public.finding_stats_daily(p_plant uuid, p_from date, p_to date)
returns table (day date, found int, resolved int, cum_found int, cum_resolved int)
language sql stable security invoker set search_path = public as $$
  with days as (select d::date as day from generate_series(p_from, p_to, interval '1 day') d),
  f as (
    select f.*, (f.reported_at at time zone p.timezone)::date rday, (f.resolved_at at time zone p.timezone)::date sday
      from findings f join plants p on p.id = f.plant_id
     where p_plant is null or f.plant_id = p_plant),
  fd as (select rday, count(*) n from f where rday between p_from and p_to group by rday),
  sd as (select sday, count(*) n from f where sday between p_from and p_to group by sday),
  base as (select count(*) filter (where rday < p_from) found, count(*) filter (where sday < p_from) resolved from f)
  select days.day,
         coalesce(fd.n, 0)::int,
         coalesce(sd.n, 0)::int,
         (base.found    + sum(coalesce(fd.n, 0)) over (order by days.day))::int,
         (base.resolved + sum(coalesce(sd.n, 0)) over (order by days.day))::int
    from days
    left join fd on fd.rday = days.day
    left join sd on sd.sday = days.day
    cross join base
   order by days.day;
$$;

-- ---------------------------------------------------------------- RLS
alter table public.check_sheets  enable row level security;
alter table public.check_items   enable row level security;
alter table public.check_tasks   enable row level security;
alter table public.findings      enable row level security;
alter table public.device_tokens enable row level security;

create policy check_sheets_read  on public.check_sheets for select using (public.has_plant_access(plant_id));
create policy check_sheets_write on public.check_sheets for all
  using (public.is_plant_manager(plant_id)) with check (public.is_plant_manager(plant_id));

create policy check_items_read  on public.check_items for select using (public.has_plant_access(plant_id));
create policy check_items_write on public.check_items for all
  using (public.is_plant_manager(plant_id))
  with check (exists (select 1 from public.equipment e where e.id = equipment_id and public.is_plant_manager(e.plant_id)));

create policy check_tasks_read   on public.check_tasks for select using (public.has_plant_access(plant_id));
create policy check_tasks_update on public.check_tasks for update
  using (public.has_plant_access(plant_id)) with check (public.has_plant_access(plant_id));

create policy findings_read   on public.findings for select using (public.has_plant_access(plant_id));
create policy findings_insert on public.findings for insert with check (
  reported_by = auth.uid()
  and exists (select 1 from public.equipment e where e.id = equipment_id and public.has_plant_access(e.plant_id)));
create policy findings_update on public.findings for update
  using (public.has_plant_access(plant_id)) with check (public.has_plant_access(plant_id));

create policy device_tokens_own on public.device_tokens for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------- privileges
grant select, insert, update, delete on public.check_sheets, public.check_items to authenticated;
grant select on public.check_tasks to authenticated;
grant update (status, note) on public.check_tasks to authenticated;
grant select, insert on public.findings to authenticated;
grant update (status, scheduled_for, resolution_note, photo_path) on public.findings to authenticated;
grant select, insert, update, delete on public.device_tokens to authenticated;

-- trigger / cron-only functions: not callable through the API
revoke execute on function public.equipment_code_before_write()    from public, anon, authenticated;
revoke execute on function public.check_items_before_write()        from public, anon, authenticated;
revoke execute on function public.check_items_after_deactivate()    from public, anon, authenticated;
revoke execute on function public.check_tasks_before_update()       from public, anon, authenticated;
revoke execute on function public.findings_before_write()           from public, anon, authenticated;
revoke execute on function public.mark_missed_check_tasks()         from public, anon, authenticated;
revoke execute on function public.notify_check_reminders()          from public, anon, authenticated;
revoke execute on function public.notify_overdue_findings()         from public, anon, authenticated;
revoke execute on function public.generate_equipment_code(uuid, text) from public, anon;
revoke execute on function public.generate_check_tasks(int)         from public, anon;
revoke execute on function public.import_check_sheet(uuid, text, text, text, jsonb) from public, anon;
revoke execute on function public.check_stats_daily(uuid, date, date)   from public, anon;
revoke execute on function public.finding_stats_daily(uuid, date, date) from public, anon;
grant execute on function public.generate_equipment_code(uuid, text) to authenticated;
grant execute on function public.generate_check_tasks(int)         to authenticated;  -- idempotent, safe
grant execute on function public.import_check_sheet(uuid, text, text, text, jsonb) to authenticated;
grant execute on function public.check_stats_daily(uuid, date, date)   to authenticated;
grant execute on function public.finding_stats_daily(uuid, date, date) to authenticated;

-- realtime for live checklists and findings
alter publication supabase_realtime add table public.check_tasks;
alter publication supabase_realtime add table public.findings;

-- ---------------------------------------------------------------- storage: uploaded check sheets
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('check-sheets', 'check-sheets', false, 10485760,
        array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/octet-stream'])
on conflict (id) do nothing;

-- uuid cast that returns null instead of raising (storage paths are free text)
create or replace function public.try_uuid(p text)
returns uuid language plpgsql immutable set search_path = public as $$
begin
  return p::uuid;
exception when others then
  return null;
end $$;

-- path: <plant_id>/<uuid>.xlsx
create policy check_sheets_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'check-sheets'
              and public.is_plant_manager(public.try_uuid((storage.foldername(name))[1])));
create policy check_sheets_download on storage.objects for select to authenticated
  using (bucket_id = 'check-sheets'
         and public.has_plant_access(public.try_uuid((storage.foldername(name))[1])));

-- coworkers' names on findings / completed checks: anyone sharing a plant with you
-- (security definer: user_plants RLS would otherwise hide other people's rows from workers)
create or replace function public.shares_plant_with(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from user_plants mine
                   join user_plants theirs on theirs.plant_id = mine.plant_id
                  where mine.user_id = auth.uid() and theirs.user_id = p_user);
$$;
revoke execute on function public.shares_plant_with(uuid) from public, anon;
grant  execute on function public.shares_plant_with(uuid) to authenticated;
create policy profiles_read_coworkers on public.profiles for select using (public.shares_plant_with(id));

-- ---------------------------------------------------------------- schedules
select cron.schedule('generate-check-tasks', '5 * * * *',
  $$select public.mark_missed_check_tasks(); select public.generate_check_tasks(7);$$);
select cron.schedule('check-reminders', '10 * * * *', $$select public.notify_check_reminders();$$);
select cron.schedule('overdue-findings', '*/15 * * * *', $$select public.notify_overdue_findings();$$);
