-- PM check-sheet workbooks (e.g. "ALP C GUN.xlsx"): one workbook per equipment, one tab per PM check,
-- one row per check point. Frequency comes from each tab's FREQUENCY cell (daily, weekly, monthly,
-- 4 monthly, half yearly, ...). Workers record a result per point; an in-charge verifies.
-- See docs/plans/pm-check-sheets-plan.md

-- ---------------------------------------------------------------- check items = one PM check (tab)
alter table public.check_items
  add column interval_count int not null default 1 check (interval_count between 1 and 60),
  add column frequency_text text check (char_length(frequency_text) <= 100),
  add column source_tab     text check (char_length(source_tab) <= 100),
  add column pm_type        text check (char_length(pm_type) <= 50),
  add column pm_rank        text check (char_length(pm_rank) <= 20),
  add column man_power      text check (char_length(man_power) <= 100),
  add column time_minutes   text check (char_length(time_minutes) <= 100),
  add column kanban_no      text check (char_length(kanban_no) <= 100),
  add column safety_note    text check (char_length(safety_note) <= 2000),
  add column tools          text check (char_length(tools) <= 2000),
  add column image_paths    text[] not null default '{}';

-- ---------------------------------------------------------------- check points (rows of a tab)
create table public.check_points (
  id              uuid primary key default gen_random_uuid(),
  check_item_id   uuid not null references public.check_items(id) on delete cascade,
  position        int  not null,
  sl_no           text check (char_length(sl_no) <= 20),
  check_point     text not null check (char_length(check_point) between 1 and 1000),
  safety_point    text check (char_length(safety_point) <= 2000),
  key_points      text check (char_length(key_points) <= 2000),
  if_not_done     text check (char_length(if_not_done) <= 2000),
  checking_method text check (char_length(checking_method) <= 2000),
  std_value       text check (char_length(std_value) <= 2000),
  action_if_ng    text check (char_length(action_if_ng) <= 2000),
  pm_rank         text check (char_length(pm_rank) <= 20),
  image_paths     text[] not null default '{}',
  unique (check_item_id, position)
);

-- ○ ok · ⊗ corrected (immediate correction) · △ abnormal_pending.
-- ▲ "pending completed" is not stored: it is an abnormal_pending point whose finding is resolved.
create type public.check_point_result as enum ('ok', 'corrected', 'abnormal_pending');

create table public.check_point_results (
  id             uuid primary key default gen_random_uuid(),
  check_task_id  uuid not null references public.check_tasks(id) on delete cascade,
  check_point_id uuid not null references public.check_points(id) on delete cascade,
  result         public.check_point_result not null,
  note           text check (char_length(note) <= 1000),
  finding_id     uuid references public.findings(id),
  recorded_by    uuid not null references public.profiles(id),
  recorded_at    timestamptz not null default now(),
  unique (check_task_id, check_point_id)
);
create index check_point_results_point_idx on public.check_point_results (check_point_id);

-- ---------------------------------------------------------------- in-charge verification
alter table public.check_tasks
  add column verified_by uuid references public.profiles(id),
  add column verified_at timestamptz,
  add column verify_note text check (char_length(verify_note) <= 1000);
create index check_tasks_unverified_idx on public.check_tasks (plant_id, completed_at desc)
  where status = 'done' and verified_at is null;

-- ---------------------------------------------------------------- recurrence with an interval
-- Months between the start month and p_day's month.
create or replace function public.months_between(p_start date, p_day date)
returns int language sql immutable set search_path = public as $$
  select (extract(year from p_day)::int - extract(year from p_start)::int) * 12
       + (extract(month from p_day)::int - extract(month from p_start)::int);
$$;

-- Due every p_interval days / weeks / months from p_start. Monthly keeps the day of month and
-- clamps to the month's last day (31 Jan -> 28/29 Feb).
create or replace function public.check_due_on(p_freq public.check_frequency, p_interval int, p_start date, p_day date)
returns boolean language sql immutable set search_path = public as $$
  select p_day >= p_start and case p_freq
    when 'daily'  then (p_day - p_start) % greatest(p_interval, 1) = 0
    when 'weekly' then (p_day - p_start) % (7 * greatest(p_interval, 1)) = 0
    when 'monthly' then public.months_between(p_start, p_day) % greatest(p_interval, 1) = 0
                    and p_day = (p_start + make_interval(months => public.months_between(p_start, p_day)))::date
  end;
$$;

-- Last day a task may still be completed: the day before the next occurrence.
create or replace function public.check_window_end(p_freq public.check_frequency, p_interval int, p_start date, p_due date)
returns date language sql immutable set search_path = public as $$
  select case p_freq
    when 'daily'  then p_due + greatest(p_interval, 1) - 1
    when 'weekly' then p_due + 7 * greatest(p_interval, 1) - 1
    when 'monthly' then (p_start + make_interval(months =>
        public.months_between(p_start, p_due) + greatest(p_interval, 1)))::date - 1
  end;
$$;

-- Create tasks up to p_days_ahead days ahead, including the current occurrence when its window is
-- still open (so a monthly sheet uploaded on the 8th still gets this month's check). Idempotent.
create or replace function public.generate_check_tasks(p_days_ahead int default 7)
returns int language sql volatile security definer set search_path = public as $$
  with items as (
    select ci.*, (now() at time zone p.timezone)::date as today
      from check_items ci
      join plants p    on p.id = ci.plant_id and p.active
      join equipment e on e.id = ci.equipment_id and e.is_active
     where ci.active
  ), ins as (
    insert into check_tasks (check_item_id, equipment_id, plant_id, due_date, window_end)
    select i.id, i.equipment_id, i.plant_id, d::date,
           check_window_end(i.frequency, i.interval_count, i.start_date, d::date)
      from items i
      cross join lateral generate_series(
        greatest(i.start_date, case i.frequency
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

drop function public.check_due_on(public.check_frequency, date, date);
drop function public.check_window_end(public.check_frequency, date, date);

-- ---------------------------------------------------------------- task updates
-- PM tasks (with check points) are completed through submit_check_task only; verified tasks are final.
create or replace function public.check_tasks_before_update()
returns trigger language plpgsql set search_path = public as $$
declare v_points int; v_results int;
begin
  if new.status is distinct from old.status then
    if new.status = 'missed' and auth.uid() is not null then
      raise exception 'Tasks are marked missed automatically';
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

-- ---------------------------------------------------------------- worker submit
-- p_results: [{point_id, result: ok|corrected|abnormal_pending, note?, photo_path?}] covering every point.
-- Each △ gets a finding (reused on resubmission). Resubmitting before verification replaces results.
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
  select * into t from check_tasks where id = p_task for update;
  if not found or not public.has_plant_access(t.plant_id) then
    raise exception 'Check not found';
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

-- ---------------------------------------------------------------- in-charge verify
create or replace function public.verify_check_task(p_task uuid, p_note text default null)
returns void language plpgsql volatile security definer set search_path = public as $$
declare t check_tasks%rowtype;
begin
  select * into t from check_tasks where id = p_task for update;
  if not found or not public.is_plant_manager(t.plant_id) then
    raise exception 'Only the in-charge (manager) of this plant can verify checks';
  end if;
  if t.status <> 'done' then raise exception 'Only completed checks can be verified'; end if;
  if t.verified_at is not null then return; end if;
  update check_tasks
     set verified_by = auth.uid(), verified_at = now(), verify_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_task;
end $$;

-- ---------------------------------------------------------------- import RPC
-- p_checks: [{title, source_tab, frequency, interval_count, frequency_text, start_date, pm_type, pm_rank,
--             man_power, time_minutes, kanban_no, safety_note, tools, image_paths[],
--             points: [{sl_no, check_point, safety_point, key_points, if_not_done, checking_method,
--                       std_value, action_if_ng, pm_rank, image_paths[]}]}]
create or replace function public.import_pm_workbook(
  p_plant uuid, p_equipment uuid, p_title text, p_file_name text, p_file_path text, p_checks jsonb)
returns jsonb language plpgsql volatile security invoker set search_path = public as $$
declare v_sheet uuid; v_item uuid; c jsonb; v_items int := 0; v_points int := 0; v_n int; v_tasks int;
begin
  if not public.is_plant_manager(p_plant) then
    raise exception 'Only managers of this plant can upload check sheets';
  end if;
  if not exists (select 1 from equipment where id = p_equipment and plant_id = p_plant and is_active) then
    raise exception 'Choose active equipment in this plant';
  end if;
  insert into check_sheets (plant_id, title, file_name, file_path)
  values (p_plant, p_title, p_file_name, p_file_path) returning id into v_sheet;

  for c in select * from jsonb_array_elements(p_checks) loop
    insert into check_items (sheet_id, equipment_id, title, description, frequency, interval_count, frequency_text,
                             start_date, source_tab, pm_type, pm_rank, man_power, time_minutes, kanban_no,
                             safety_note, tools, image_paths)
    values (v_sheet, p_equipment, left(btrim(c->>'title'), 300), null,
            lower(c->>'frequency')::public.check_frequency, coalesce((c->>'interval_count')::int, 1),
            c->>'frequency_text', (c->>'start_date')::date, c->>'source_tab', c->>'pm_type', c->>'pm_rank',
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
  return jsonb_build_object('sheet_id', v_sheet, 'items', v_items, 'points', v_points, 'tasks_created', v_tasks);
end $$;

-- ---------------------------------------------------------------- reminders: name PM frequencies
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
           count(*) filter (where ci.frequency = 'monthly' and ci.interval_count = 1) m,
           count(*) filter (where ci.frequency = 'monthly' and ci.interval_count > 1) l
      from check_tasks t
      join check_items ci on ci.id = t.check_item_id
      join tmr tm on tm.plant_id = t.plant_id and t.due_date = tm.d
     where ci.frequency in ('weekly', 'monthly') and t.status = 'pending'
     group by t.plant_id, tm.plant_name, tm.d
  ), ins as (
    insert into notifications (user_id, plant_id, kind, message, dedupe_key)
    select pr.id, c.plant_id, 'check_reminder',
           format('Tomorrow at %s: %s', c.plant_name, concat_ws(', ',
             case when c.w > 0 then format('%s weekly check%s', c.w, case when c.w = 1 then '' else 's' end) end,
             case when c.m > 0 then format('%s monthly check%s', c.m, case when c.m = 1 then '' else 's' end) end,
             case when c.l > 0 then format('%s long-interval PM check%s (4-monthly, half-yearly, ...)', c.l, case when c.l = 1 then '' else 's' end) end)),
           format('tomorrow:%s:%s:%s', pr.id, c.plant_id, c.d)
      from counts c
      join user_plants up on up.plant_id = c.plant_id
      join profiles pr on pr.id = up.user_id and pr.active
    on conflict (dedupe_key) do nothing
    returning 1)
  select count(*) into n2 from ins;
  return n1 + n2;
end $$;

-- ---------------------------------------------------------------- RLS
alter table public.check_points        enable row level security;
alter table public.check_point_results enable row level security;

create policy check_points_read on public.check_points for select using (
  exists (select 1 from public.check_items ci where ci.id = check_item_id and public.has_plant_access(ci.plant_id)));
create policy check_points_write on public.check_points for all
  using (exists (select 1 from public.check_items ci where ci.id = check_item_id and public.is_plant_manager(ci.plant_id)))
  with check (exists (select 1 from public.check_items ci where ci.id = check_item_id and public.is_plant_manager(ci.plant_id)));

create policy check_point_results_read on public.check_point_results for select using (
  exists (select 1 from public.check_tasks t where t.id = check_task_id and public.has_plant_access(t.plant_id)));

create trigger audit_check_point_results after insert or update on public.check_point_results
  for each row execute function public.audit_row();

-- ---------------------------------------------------------------- privileges
grant select, insert, update, delete on public.check_points to authenticated;
grant select on public.check_point_results to authenticated;   -- written only via submit_check_task

revoke execute on function public.months_between(date, date) from public, anon;
revoke execute on function public.check_due_on(public.check_frequency, int, date, date) from public, anon;
revoke execute on function public.check_window_end(public.check_frequency, int, date, date) from public, anon;
revoke execute on function public.submit_check_task(uuid, jsonb, text) from public, anon;
revoke execute on function public.verify_check_task(uuid, text) from public, anon;
revoke execute on function public.import_pm_workbook(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function public.months_between(date, date) to authenticated;
grant execute on function public.check_due_on(public.check_frequency, int, date, date) to authenticated;
grant execute on function public.check_window_end(public.check_frequency, int, date, date) to authenticated;
grant execute on function public.submit_check_task(uuid, jsonb, text) to authenticated;
grant execute on function public.verify_check_task(uuid, text) to authenticated;
grant execute on function public.import_pm_workbook(uuid, uuid, text, text, text, jsonb) to authenticated;

alter publication supabase_realtime add table public.check_point_results;

-- ---------------------------------------------------------------- storage: sheet pictures
-- Pictures from the workbook live next to it: <plant_id>/<sheet uuid>/img/<n>.<ext>
update storage.buckets
   set allowed_mime_types = array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                  'application/octet-stream', 'image/jpeg', 'image/png', 'image/gif', 'image/webp']
 where id = 'check-sheets';
