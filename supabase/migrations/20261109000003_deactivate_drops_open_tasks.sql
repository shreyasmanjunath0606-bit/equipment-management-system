-- Switching a check off must also remove the occurrence workers can still complete right now.
-- Before, only tasks with due_date > current_date were dropped, so a monthly check due on the 1st
-- (window open all month) stayed on the workers' list after being switched off.
--
-- Now: drop every *pending* task of the item whose completion window has not closed yet
-- (plant-local date). Done / missed / verified tasks are history and are kept, as are pending
-- tasks that already have a finding attached. Notifications pointing at dropped tasks go too.
create or replace function public.check_items_after_deactivate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.active and not new.active then
    with dropped as (
      select t.id
        from check_tasks t
        join plants p on p.id = t.plant_id
       where t.check_item_id = new.id
         and t.status = 'pending'
         and t.window_end >= (now() at time zone p.timezone)::date
         and not exists (select 1 from findings f where f.check_task_id = t.id)
    ), gone_notifications as (
      delete from notifications n using dropped d where n.check_task_id = d.id
    )
    delete from check_tasks t using dropped d where t.id = d.id;
  end if;
  return new;
end $$;

revoke execute on function public.check_items_after_deactivate() from public, anon, authenticated;
