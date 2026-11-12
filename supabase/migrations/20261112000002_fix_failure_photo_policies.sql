-- Fix for 20261112000001: inside the EXISTS subquery an unqualified "name" resolved to equipment.name,
-- not the storage object's path, so no photo matched (nobody could read or upload failure photos).
drop policy if exists failure_photos_insert on storage.objects;
drop policy if exists failure_photos_read   on storage.objects;
create policy failure_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'failure-photos'
              and exists (select 1 from public.equipment e
                           where e.id = public.try_uuid((storage.foldername(objects.name))[1])
                             and public.has_plant_access(e.plant_id)));
create policy failure_photos_read on storage.objects for select to authenticated
  using (bucket_id = 'failure-photos'
         and exists (select 1 from public.equipment e
                      where e.id = public.try_uuid((storage.foldername(objects.name))[1])
                        and public.has_plant_access(e.plant_id)));
