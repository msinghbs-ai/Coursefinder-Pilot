-- HELD (not a migration): forward recovery for 20261111000000 (course description admission outside the AI worker's recording call, CF-247 F-CDESC). It restores security.course_description_machine_trg_v1 byte for byte to the body read live on
-- 10 Nov 2026 23:40 AEDT (a fresh reading admitted inside whatever statement records it, including the worker's API call). Run only if the Platform Admin decides to take the change back; while it is in force a worker batch with more than about
-- 8 description readings can again time out and lose every answer in the batch. Guarded by the md5 of what is live now (the edited text or the original); a body that is neither stops it. Nothing is dropped or deleted.

do $g$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_trg_v1()'::regprocedure);
begin
  if md5(v_src) = 'ec9b96498c54e37f8492a1003ea97520' then raise notice 'already the original'; return; end if;
  if md5(v_src) <> 'c75d63a6390f4cb0e3ed7276e70c25f8' then raise exception 'live security.course_description_machine_trg_v1() differs from both texts this recovery knows (body md5 %)', md5(v_src); end if;
  execute $ddl$
CREATE OR REPLACE FUNCTION security.course_description_machine_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_item uuid;
begin
  if pg_trigger_depth() > 5 then return null; end if; -- fixed: a bound on nested trigger chains (promote-held inside an admission); the job takes the rest
  if security.pipeline_num_v1('enrich.course_description_machine_on', 0) < 1 then return null; end if;
  v_item := case when coalesce(new.value->>'review_item_id', '') ~ '^[0-9a-f-]{36}$' then (new.value->>'review_item_id')::uuid end;
  if v_item is null then return null; end if;
  begin perform security.course_description_machine_admit_v1(v_item, 'fresh_reading');
  exception when others then null; -- the reading stays waiting for a person (or the next run); recording it never fails
  end;
  return null;
end $function$
$ddl$;
end $g$;
comment on function security.course_description_machine_trg_v1() is 'CF-247 F-CDESC: after a course description reading reaches Layer 4 (state review), admits it at once under the machine rule while enrich.course_description_machine_on is 1. Off: does nothing. Errors are swallowed; the reading stays waiting.';
