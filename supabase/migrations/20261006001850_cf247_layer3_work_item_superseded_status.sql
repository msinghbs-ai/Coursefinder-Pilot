do $g$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'pipeline.layer3_work_items'::regclass and conname = 'layer3_work_items_status_check' and pg_get_constraintdef(oid) not like '%superseded%') then
    raise exception 'layer3_work_items_status_check is not the expected definition; refusing to replace it';
  end if;
end $g$;
alter table pipeline.layer3_work_items drop constraint layer3_work_items_status_check;
alter table pipeline.layer3_work_items add constraint layer3_work_items_status_check check (status = any (array['pending','reserved','interpreting','validated','no_candidate','rejected','admission_pending','layer4_required','admitted','parked','failed','superseded']));
