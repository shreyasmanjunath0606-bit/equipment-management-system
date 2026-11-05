alter function public.block_mutation() set search_path = public;
alter function public.profiles_deactivation() set search_path = public;

-- trigger-only functions: nobody should call them through the API
revoke execute on function public.audit_row()                   from public, anon, authenticated;
revoke execute on function public.handle_new_user()             from public, anon, authenticated;
revoke execute on function public.notify_on_status_event()      from public, anon, authenticated;
revoke execute on function public.status_events_before_insert() from public, anon, authenticated;

-- RLS helper functions: signed-in users only (policies run as the caller)
revoke execute on function public.is_active_user()            from public, anon;
revoke execute on function public.is_admin()                  from public, anon;
revoke execute on function public.has_plant_access(uuid)      from public, anon;
revoke execute on function public.is_plant_manager(uuid)      from public, anon;
grant  execute on function public.is_active_user()            to authenticated;
grant  execute on function public.is_admin()                  to authenticated;
grant  execute on function public.has_plant_access(uuid)      to authenticated;
grant  execute on function public.is_plant_manager(uuid)      to authenticated;
