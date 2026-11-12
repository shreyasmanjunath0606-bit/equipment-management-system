-- Security hardening (see the security review of 2026-11-12).

-- ---------------------------------------------------------------- 1. failure photos: per plant
-- Paths are <equipment_id>/<file>.jpg (see flutter_app/lib/data/offline_queue.dart). Before, any active
-- user could list, read and upload photos of every plant.
-- NOTE: the policies below have a bug ("name" resolves to equipment.name); fixed in 20261112000002.
drop policy if exists failure_photos_insert on storage.objects;
drop policy if exists failure_photos_read   on storage.objects;
create policy failure_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'failure-photos'
              and exists (select 1 from public.equipment e
                           where e.id = public.try_uuid((storage.foldername(name))[1])
                             and public.has_plant_access(e.plant_id)));
create policy failure_photos_read on storage.objects for select to authenticated
  using (bucket_id = 'failure-photos'
         and exists (select 1 from public.equipment e
                      where e.id = public.try_uuid((storage.foldername(name))[1])
                        and public.has_plant_access(e.plant_id)));

-- ---------------------------------------------------------------- 2. check items: plant always from equipment
-- The trigger only fired on "update of equipment_id", so a manager could PATCH plant_id to another plant.
drop trigger check_items_biu on public.check_items;
create trigger check_items_biu before insert or update on public.check_items
  for each row execute function public.check_items_before_write();

-- ---------------------------------------------------------------- 3. findings
-- Insert: overdue alerts cannot be pre-silenced; a finding can only be attached to a check of the same equipment.
create or replace function public.findings_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
declare eq equipment%rowtype;
begin
  if tg_op = 'INSERT' then
    select * into eq from equipment where id = new.equipment_id;
    if not found then raise exception 'Equipment not found'; end if;
    new.plant_id := eq.plant_id;
    new.reported_at := now();
    new.overdue_notified_at := null;
    if new.check_task_id is not null and not exists
       (select 1 from check_tasks t where t.id = new.check_task_id and t.equipment_id = new.equipment_id) then
      raise exception 'This check is not on that equipment';
    end if;
  else
    new.equipment_id := old.equipment_id;
    new.plant_id := old.plant_id;
    new.reported_by := old.reported_by;
    new.reported_at := old.reported_at;
    new.check_task_id := old.check_task_id;
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
revoke execute on function public.findings_before_write() from public, anon, authenticated;

-- Update: plant managers / admins, or the person who reported the finding.
drop policy findings_update on public.findings;
create policy findings_update on public.findings for update
  using (public.is_plant_manager(plant_id)
         or (reported_by = auth.uid() and public.has_plant_access(plant_id)))
  with check (public.has_plant_access(plant_id));

-- ---------------------------------------------------------------- 4. status events: no rewriting the past
-- reported_at comes from the phone (offline reports keep their real time) but may not be more than
-- 7 days old; created_at is always the server's time.
create or replace function public.status_events_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare eq equipment%rowtype;
begin
  select * into eq from equipment where id = new.equipment_id;
  if not found or not eq.is_active then
    raise exception 'Equipment not found or retired';
  end if;
  new.created_at := now();
  if new.reported_at < now() - interval '7 days' then
    raise exception 'A status report cannot be more than 7 days old';
  end if;
  new.plant_id := eq.plant_id;
  return new;
end $$;
revoke execute on function public.status_events_before_insert() from public, anon, authenticated;

-- ---------------------------------------------------------------- 5. verified checks are final (note too)
create or replace function public.check_tasks_before_update()
returns trigger language plpgsql set search_path = public as $$
declare v_points int; v_results int;
begin
  if old.verified_at is not null and new.note is distinct from old.note then
    raise exception 'This check has been verified and can no longer be changed';
  end if;
  if new.note is distinct from old.note and auth.uid() is not null
     and old.assigned_to is distinct from auth.uid() and old.completed_by is distinct from auth.uid() then
    raise exception 'Only the worker doing this check can change its note';
  end if;
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
revoke execute on function public.check_tasks_before_update() from public, anon, authenticated;

-- ---------------------------------------------------------------- 6. stats: at most ~400 days per call
create or replace function public.check_stats_daily(p_plant uuid, p_from date, p_to date)
returns table (day date, planned int, completed int, cum_planned int, cum_completed int)
language sql stable security invoker set search_path = public as $$
  with days as (select d::date as day from generate_series(p_from, least(p_to, p_from + 400), interval '1 day') d),
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
  with days as (select d::date as day from generate_series(p_from, least(p_to, p_from + 400), interval '1 day') d),
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

-- ---------------------------------------------------------------- 7. deactivated users: no notifications / push tokens
drop policy notifications_read on public.notifications;
drop policy notifications_mark on public.notifications;
create policy notifications_read on public.notifications for select
  using (user_id = auth.uid() and public.is_active_user());
create policy notifications_mark on public.notifications for update
  using (user_id = auth.uid() and public.is_active_user()) with check (user_id = auth.uid());
drop policy device_tokens_own on public.device_tokens;
create policy device_tokens_own on public.device_tokens for all
  using (user_id = auth.uid() and public.is_active_user())
  with check (user_id = auth.uid() and public.is_active_user());

-- ---------------------------------------------------------------- 8. platform helper not for the API
do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'rls_auto_enable') then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $$;
