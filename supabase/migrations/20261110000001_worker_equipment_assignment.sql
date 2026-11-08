-- One worker <-> one equipment. The manager assigns each equipment to one worker and gives it up to
-- three workbooks: Daily (every day), Weekly (every Monday) and Monthly (on a chosen day of the
-- month). Every tab in such a workbook repeats at the workbook's frequency. "Extra" workbooks keep the
-- old behaviour (each tab's FREQUENCY cell decides, e.g. half-yearly). Workers only see and complete
-- the checks of the equipment assigned to them; managers see the plant and verify.

-- ---------------------------------------------------------------- assignment
alter table public.equipment add column assigned_worker uuid references public.profiles(id);
create unique index equipment_assigned_worker_key on public.equipment (assigned_worker) where assigned_worker is not null;

create or replace function public.equipment_check_assignment()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.assigned_worker is not null and (tg_op = 'INSERT' or new.assigned_worker is distinct from old.assigned_worker
                                          or new.plant_id is distinct from old.plant_id) then
    if not exists (select 1 from profiles p join user_plants up on up.user_id = p.id
                    where p.id = new.assigned_worker and p.active and p.role = 'worker'
                      and up.plant_id = new.plant_id) then
      raise exception 'Only an active worker of this plant can be assigned to this equipment';
    end if;
    if exists (select 1 from equipment where assigned_worker = new.assigned_worker and id <> new.id) then
      raise exception 'This worker already looks after another equipment — unassign it there first';
    end if;
  end if;
  if not new.is_active then new.assigned_worker := null; end if;
  return new;
end $$;
create trigger equipment_assignment_biu before insert or update of assigned_worker, is_active, plant_id on public.equipment
  for each row execute function public.equipment_check_assignment();

-- Reassigning moves the open (pending) checks to the new worker; finished ones stay as history.
create or replace function public.equipment_after_assignment()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update check_tasks set assigned_to = new.assigned_worker
   where equipment_id = new.id and status = 'pending' and assigned_to is distinct from new.assigned_worker;
  return new;
end $$;
create trigger equipment_assignment_au after update of assigned_worker on public.equipment
  for each row when (old.assigned_worker is distinct from new.assigned_worker)
  execute function public.equipment_after_assignment();

-- A worker who is deactivated, promoted or loses the plant no longer looks after the equipment.
create or replace function public.profiles_release_equipment()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not new.active or new.role <> 'worker' then
    update equipment set assigned_worker = null where assigned_worker = new.id;
  end if;
  return new;
end $$;
create trigger profiles_release_equipment_au after update of active, role on public.profiles
  for each row execute function public.profiles_release_equipment();

create or replace function public.user_plants_release_equipment()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update equipment set assigned_worker = null where assigned_worker = old.user_id and plant_id = old.plant_id;
  return old;
end $$;
create trigger user_plants_release_equipment_ad after delete on public.user_plants
  for each row execute function public.user_plants_release_equipment();

-- Managers pick from the plant's workers (profiles RLS hides other people from managers).
create or replace function public.plant_workers(p_plant uuid)
returns table (id uuid, name text, email text, equipment_id uuid)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, p.email, e.id
    from profiles p
    join user_plants up on up.user_id = p.id and up.plant_id = p_plant
    left join equipment e on e.assigned_worker = p.id
   where p.active and p.role = 'worker' and public.is_plant_manager(p_plant)
   order by p.name;
$$;

-- ---------------------------------------------------------------- sheets are slots on an equipment
alter table public.check_sheets
  add column equipment_id uuid references public.equipment(id),
  add column slot         text not null default 'extra' check (slot in ('daily', 'weekly', 'monthly', 'extra')),
  add column monthly_day  int  check (monthly_day between 1 and 31),
  add column active       boolean not null default true,
  add check (slot <> 'monthly' or monthly_day is not null);
create unique index check_sheets_slot_key on public.check_sheets (equipment_id, slot)
  where active and slot <> 'extra';

-- Existing workbooks become "extra" sheets of the equipment their checks are on.
update public.check_sheets s
   set equipment_id = (select ci.equipment_id from check_items ci where ci.sheet_id = s.id limit 1)
 where equipment_id is null;

-- Taking a sheet off (or replacing it) switches its checks off; that drops their open tasks.
create or replace function public.check_sheets_after_deactivate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.active and not new.active then
    update check_items set active = false where sheet_id = new.id and active;
  end if;
  return new;
end $$;
create trigger check_sheets_au after update of active on public.check_sheets
  for each row execute function public.check_sheets_after_deactivate();

-- First occurrence to schedule. Monthly sheets anchor start_date on 31-day January so every month
-- keeps the chosen day (clamped in short months); first_due stops occurrences before the upload.
alter table public.check_items add column first_due date;

-- ---------------------------------------------------------------- tasks carry their worker
alter table public.check_tasks add column assigned_to uuid references public.profiles(id);
create index check_tasks_assigned_idx on public.check_tasks (assigned_to, due_date) where assigned_to is not null;

update public.check_tasks t set assigned_to = e.assigned_worker
  from equipment e where e.id = t.equipment_id and t.status = 'pending' and e.assigned_worker is not null;

create or replace function public.generate_check_tasks(p_days_ahead int default 7)
returns int language sql volatile security definer set search_path = public as $$
  with items as (
    select ci.*, e.assigned_worker, (now() at time zone p.timezone)::date as today
      from check_items ci
      join plants p    on p.id = ci.plant_id and p.active
      join equipment e on e.id = ci.equipment_id and e.is_active
     where ci.active
  ), ins as (
    insert into check_tasks (check_item_id, equipment_id, plant_id, due_date, window_end, assigned_to)
    select i.id, i.equipment_id, i.plant_id, d::date,
           check_window_end(i.frequency, i.interval_count, i.start_date, d::date), i.assigned_worker
      from items i
      cross join lateral generate_series(
        greatest(i.start_date, coalesce(i.first_due, i.start_date), case i.frequency
          when 'daily'   then i.today - (i.interval_count - 1)
          when 'weekly'  then i.today - (7 * i.interval_count - 1)
          else (i.today - make_interval(months => i.interval_count))::date
        end),
        i.today + least(greatest(p_days_ahead, 0), 60),
        interval '1 day') d
     where check_due_on(i.frequency, i.interval_count, i.start_date, d::date)
       and check_window_end(i.frequency, i.interval_count, i.start_date, d::date) >= i.today
    on conflict (check_item_id, due_date) do nothing
    returning 1)
  select count(*)::int from ins;
$$;

-- ---------------------------------------------------------------- who sees / completes what
-- Managers (and admins) see the plant's checks; a worker sees their own and the ones they did.
drop policy check_tasks_read on public.check_tasks;
create policy check_tasks_read on public.check_tasks for select using (
  public.is_plant_manager(plant_id)
  or (public.has_plant_access(plant_id) and (assigned_to = auth.uid() or completed_by = auth.uid())));
drop policy check_tasks_update on public.check_tasks;
create policy check_tasks_update on public.check_tasks for update
  using (public.is_plant_manager(plant_id) or (public.has_plant_access(plant_id) and assigned_to = auth.uid()))
  with check (public.has_plant_access(plant_id));

create or replace function public.check_tasks_before_update()
returns trigger language plpgsql set search_path = public as $$
declare v_points int; v_results int;
begin
  if new.status is distinct from old.status then
    if new.status = 'missed' and auth.uid() is not null then
      raise exception 'Tasks are marked missed automatically';
    end if;
    if new.status in ('done', 'pending') and auth.uid() is not null and not public.is_worker() then
      raise exception 'Only workers complete checks; managers and admins verify them';
    end if;
    if new.status in ('done', 'pending') and auth.uid() is not null and old.assigned_to is distinct from auth.uid() then
      raise exception 'This check belongs to the worker assigned to this equipment';
    end if;
    if old.verified_at is not null then
      raise exception 'This check has been verified and can no longer be changed';
    end if;
    select count(*) into v_points from check_points where check_item_id = new.check_item_id;
    if new.status = 'done' then
      if v_points > 0 then
        select count(*) into v_results from check_point_results where check_task_id = new.id;
        if v_results < v_points then
          raise exception 'Record a result for every check point first';
        end if;
      end if;
      new.completed_by := coalesce(auth.uid(), new.completed_by);
      new.completed_at := now();
    elsif new.status = 'pending' then
      if old.status = 'missed' then raise exception 'A missed task cannot be reopened'; end if;
      if v_points > 0 then raise exception 'A submitted PM check cannot be reopened'; end if;
      new.completed_by := null;
      new.completed_at := null;
    end if;
  end if;
  return new;
end $$;

create or replace function public.submit_check_task(p_task uuid, p_results jsonb, p_note text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  t check_tasks%rowtype;
  r jsonb;
  pt check_points%rowtype;
  v_res public.check_point_result;
  v_existing check_point_results%rowtype;
  v_finding uuid;
  v_created int := 0;
  v_points int;
  v_given int;
begin
  if not public.is_worker() then
    raise exception 'Only workers complete checks; managers and admins verify them';
  end if;
  select * into t from check_tasks where id = p_task for update;
  if not found or not public.has_plant_access(t.plant_id) then
    raise exception 'Check not found';
  end if;
  if t.assigned_to is distinct from auth.uid() then
    raise exception 'This check belongs to the worker assigned to this equipment';
  end if;
  if t.verified_at is not null then
    raise exception 'This check has been verified and can no longer be changed';
  end if;
  if jsonb_typeof(p_results) <> 'array' then raise exception 'Results must be a list'; end if;

  select count(*) into v_points from check_points where check_item_id = t.check_item_id;
  select count(distinct x->>'point_id') into v_given
    from jsonb_array_elements(p_results) x
    join check_points cp on cp.id = public.try_uuid(x->>'point_id') and cp.check_item_id = t.check_item_id;
  if v_points = 0 or v_given < v_points then
    raise exception 'Record a result for every check point first';
  end if;

  for r in select * from jsonb_array_elements(p_results) loop
    select * into pt from check_points where id = public.try_uuid(r->>'point_id') and check_item_id = t.check_item_id;
    if not found then continue; end if;
    v_res := (r->>'result')::public.check_point_result;
    select * into v_existing from check_point_results where check_task_id = t.id and check_point_id = pt.id;
    v_finding := v_existing.finding_id;

    if v_res = 'abnormal_pending' and v_finding is null then
      insert into findings (check_task_id, equipment_id, description, photo_path, status, reported_by)
      values (t.id, t.equipment_id,
              left(format('%s — %s', pt.check_point, coalesce(nullif(btrim(r->>'note'), ''), 'abnormal, correction pending')), 2000),
              nullif(r->>'photo_path', ''), 'open', auth.uid())
      returning id into v_finding;
      v_created := v_created + 1;
    end if;

    insert into check_point_results (check_task_id, check_point_id, result, note, finding_id, recorded_by)
    values (t.id, pt.id, v_res, nullif(btrim(coalesce(r->>'note', '')), ''), v_finding, auth.uid())
    on conflict (check_task_id, check_point_id) do update
      set result = excluded.result, note = excluded.note, finding_id = excluded.finding_id,
          recorded_by = excluded.recorded_by, recorded_at = now();
  end loop;

  update check_tasks
     set status = 'done', note = coalesce(nullif(btrim(coalesce(p_note, '')), ''), note)
   where id = t.id and status <> 'done';
  return jsonb_build_object('findings_created', v_created);
end $$;

-- ---------------------------------------------------------------- import into a slot
drop function public.import_pm_workbook(uuid, uuid, text, text, text, jsonb);

-- p_slot: daily | weekly | monthly -> every tab repeats at that frequency (weekly on Mondays, monthly
-- on p_monthly_day) and replaces the equipment's previous sheet in that slot.
-- extra -> each tab keeps its own frequency / start date (the old behaviour).
create or replace function public.import_pm_workbook(
  p_plant uuid, p_equipment uuid, p_title text, p_file_name text, p_file_path text, p_checks jsonb,
  p_slot text default 'extra', p_monthly_day int default null)
returns jsonb language plpgsql volatile security invoker set search_path = public as $$
declare
  v_sheet uuid; v_item uuid; c jsonb; v_items int := 0; v_points int := 0; v_n int; v_tasks int;
  v_today date; v_start date; v_first date; v_replaced int := 0;
begin
  if not public.is_plant_manager(p_plant) then
    raise exception 'Only managers of this plant can upload check sheets';
  end if;
  if not exists (select 1 from equipment where id = p_equipment and plant_id = p_plant and is_active) then
    raise exception 'Choose active equipment in this plant';
  end if;
  if p_slot not in ('daily', 'weekly', 'monthly', 'extra') then raise exception 'Unknown sheet type'; end if;
  if p_slot = 'monthly' and (p_monthly_day is null or p_monthly_day not between 1 and 31) then
    raise exception 'Choose the day of the month for the monthly sheet';
  end if;

  select (now() at time zone timezone)::date into v_today from plants where id = p_plant;
  if p_slot = 'daily' then
    v_start := v_today; v_first := v_today;
  elsif p_slot = 'weekly' then
    v_start := v_today - (extract(isodow from v_today)::int - 1); v_first := v_start;   -- this week's Monday
  elsif p_slot = 'monthly' then
    v_start := make_date(extract(year from v_today)::int - 1, 1, p_monthly_day);       -- anchor, see first_due
    v_first := (v_start + make_interval(months => public.months_between(v_start, v_today)))::date;
  end if;

  if p_slot <> 'extra' then
    update check_sheets set active = false
     where equipment_id = p_equipment and slot = p_slot and active;
    get diagnostics v_replaced = row_count;
  end if;

  insert into check_sheets (plant_id, title, file_name, file_path, equipment_id, slot, monthly_day)
  values (p_plant, p_title, p_file_name, p_file_path, p_equipment, p_slot,
          case when p_slot = 'monthly' then p_monthly_day end)
  returning id into v_sheet;

  for c in select * from jsonb_array_elements(p_checks) loop
    insert into check_items (sheet_id, equipment_id, title, description, frequency, interval_count, frequency_text,
                             start_date, first_due, source_tab, pm_type, pm_rank, man_power, time_minutes, kanban_no,
                             safety_note, tools, image_paths)
    values (v_sheet, p_equipment, left(btrim(c->>'title'), 300), null,
            case when p_slot = 'extra' then lower(c->>'frequency')::public.check_frequency
                 else p_slot::public.check_frequency end,
            case when p_slot = 'extra' then coalesce((c->>'interval_count')::int, 1) else 1 end,
            c->>'frequency_text',
            coalesce(v_start, (c->>'start_date')::date), v_first,
            c->>'source_tab', c->>'pm_type', c->>'pm_rank',
            c->>'man_power', c->>'time_minutes', c->>'kanban_no', c->>'safety_note', c->>'tools',
            coalesce(array(select jsonb_array_elements_text(c->'image_paths')), '{}'))
    returning id into v_item;
    v_items := v_items + 1;

    insert into check_points (check_item_id, position, sl_no, check_point, safety_point, key_points, if_not_done,
                              checking_method, std_value, action_if_ng, pm_rank, image_paths)
    select v_item, o, p->>'sl_no', left(btrim(p->>'check_point'), 1000), p->>'safety_point', p->>'key_points',
           p->>'if_not_done', p->>'checking_method', p->>'std_value', p->>'action_if_ng', p->>'pm_rank',
           coalesce(array(select jsonb_array_elements_text(p->'image_paths')), '{}')
      from jsonb_array_elements(c->'points') with ordinality as x(p, o)
     where coalesce(btrim(p->>'check_point'), '') <> '';
    get diagnostics v_n = row_count;
    v_points := v_points + v_n;
  end loop;

  update check_sheets set row_count = v_items where id = v_sheet;
  v_tasks := public.generate_check_tasks(7);
  return jsonb_build_object('sheet_id', v_sheet, 'items', v_items, 'points', v_points,
                            'tasks_created', v_tasks, 'replaced', v_replaced > 0);
end $$;

-- ---------------------------------------------------------------- reminders
-- Workers: their own checks due today / weekly + monthly due tomorrow.
-- Managers: one plant summary of today's checks, flagging equipment with checks but no worker.
create or replace function public.notify_check_reminders()
returns int language plpgsql volatile security definer set search_path = public as $$
declare n1 int; n2 int; n3 int;
begin
  with today as (
    select p.id plant_id, p.name plant_name, (now() at time zone p.timezone)::date d
      from plants p
     where p.active and extract(hour from (now() at time zone p.timezone)) >= 7
  ), counts as (
    select t.assigned_to, t.plant_id, td.d, count(*) n,
           string_agg(distinct e.name, ', ') equipment
      from check_tasks t
      join today td on td.plant_id = t.plant_id and t.due_date = td.d
      join equipment e on e.id = t.equipment_id
     where t.status = 'pending' and t.assigned_to is not null
     group by t.assigned_to, t.plant_id, td.d
  ), ins as (
    insert into notifications (user_id, plant_id, kind, message, dedupe_key)
    select c.assigned_to, c.plant_id, 'check_due',
           format('%s check%s due today on %s', c.n, case when c.n = 1 then '' else 's' end, c.equipment),
           format('due:%s:%s:%s', c.assigned_to, c.plant_id, c.d)
      from counts c join profiles pr on pr.id = c.assigned_to and pr.active
    on conflict (dedupe_key) do nothing
    returning 1)
  select count(*) into n1 from ins;

  with tmr as (
    select p.id plant_id, (now() at time zone p.timezone)::date + 1 d
      from plants p
     where p.active and extract(hour from (now() at time zone p.timezone)) >= 7
  ), counts as (
    select t.assigned_to, t.plant_id, tm.d, string_agg(distinct e.name, ', ') equipment,
           count(*) filter (where ci.frequency = 'weekly') w,
           count(*) filter (where ci.frequency = 'monthly' and ci.interval_count = 1) m,
           count(*) filter (where ci.frequency = 'monthly' and ci.interval_count > 1) l
      from check_tasks t
      join check_items ci on ci.id = t.check_item_id
      join equipment e on e.id = t.equipment_id
      join tmr tm on tm.plant_id = t.plant_id and t.due_date = tm.d
     where ci.frequency in ('weekly', 'monthly') and t.status = 'pending' and t.assigned_to is not null
     group by t.assigned_to, t.plant_id, tm.d
  ), ins as (
    insert into notifications (user_id, plant_id, kind, message, dedupe_key)
    select c.assigned_to, c.plant_id, 'check_reminder',
           format('Tomorrow on %s: %s', c.equipment, concat_ws(', ',
             case when c.w > 0 then format('%s weekly check%s', c.w, case when c.w = 1 then '' else 's' end) end,
             case when c.m > 0 then format('%s monthly check%s', c.m, case when c.m = 1 then '' else 's' end) end,
             case when c.l > 0 then format('%s long-interval PM check%s', c.l, case when c.l = 1 then '' else 's' end) end)),
           format('tomorrow:%s:%s:%s', c.assigned_to, c.plant_id, c.d)
      from counts c join profiles pr on pr.id = c.assigned_to and pr.active
    on conflict (dedupe_key) do nothing
    returning 1)
  select count(*) into n2 from ins;

  with today as (
    select p.id plant_id, p.name plant_name, (now() at time zone p.timezone)::date d
      from plants p
     where p.active and extract(hour from (now() at time zone p.timezone)) >= 7
  ), counts as (
    select t.plant_id, td.plant_name, td.d, count(*) n,
           count(distinct t.equipment_id) filter (where t.assigned_to is null) unassigned
      from check_tasks t join today td on td.plant_id = t.plant_id and t.due_date = td.d
     where t.status = 'pending'
     group by t.plant_id, td.plant_name, td.d
  ), ins as (
    insert into notifications (user_id, plant_id, kind, message, dedupe_key)
    select pr.id, c.plant_id, 'check_due',
           format('%s check%s due today at %s%s', c.n, case when c.n = 1 then '' else 's' end, c.plant_name,
                  case when c.unassigned > 0 then format(' · %s equipment have no worker assigned', c.unassigned) else '' end),
           format('due:%s:%s:%s', pr.id, c.plant_id, c.d)
      from counts c
      join user_plants up on up.plant_id = c.plant_id
      join profiles pr on pr.id = up.user_id and pr.active and pr.role = 'manager'
    on conflict (dedupe_key) do nothing
    returning 1)
  select count(*) into n3 from ins;
  return n1 + n2 + n3;
end $$;

-- ---------------------------------------------------------------- privileges
revoke execute on function public.equipment_check_assignment()     from public, anon, authenticated;
revoke execute on function public.equipment_after_assignment()     from public, anon, authenticated;
revoke execute on function public.profiles_release_equipment()     from public, anon, authenticated;
revoke execute on function public.user_plants_release_equipment()  from public, anon, authenticated;
revoke execute on function public.check_sheets_after_deactivate()  from public, anon, authenticated;
revoke execute on function public.plant_workers(uuid)              from public, anon;
revoke execute on function public.import_pm_workbook(uuid, uuid, text, text, text, jsonb, text, int) from public, anon;
grant execute on function public.plant_workers(uuid)         to authenticated;
grant execute on function public.import_pm_workbook(uuid, uuid, text, text, text, jsonb, text, int) to authenticated;
