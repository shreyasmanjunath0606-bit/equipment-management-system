-- Only workers complete checks. Managers and admins are the in-charge: they see checks and verify
-- them (verify_check_task), but cannot tick a check or record point results themselves.

create or replace function public.is_worker()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and active and role = 'worker');
$$;
revoke execute on function public.is_worker() from public, anon;
grant execute on function public.is_worker() to authenticated;

-- Same rules as before, plus: a signed-in non-worker cannot change a task's completion.
-- (Cron jobs run without a user, so marking tasks "missed" still works.)
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

-- submit_check_task: workers only (also blocks a manager re-submitting a worker's results).
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
