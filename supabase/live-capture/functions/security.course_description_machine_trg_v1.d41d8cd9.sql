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
  -- 11 Nov 2026 (CF-247 F-CDESC throughput): a reading recorded through the API (the AI worker's svc_enrich_ai_record, many answers in one call under the API statement time-out) is not admitted inside that call:
  -- a time-out there is not caught below and cancelled every answer of the call. The job course-description-machine admits it (settle, undecided items first). Readings the job itself records are admitted here as before.
  if nullif(current_setting('request.method', true), '') is not null then return null; end if;
  v_item := case when coalesce(new.value->>'review_item_id', '') ~ '^[0-9a-f-]{36}$' then (new.value->>'review_item_id')::uuid end;
  if v_item is null then return null; end if;
  begin perform security.course_description_machine_admit_v1(v_item, 'fresh_reading');
  exception when others then null; -- the reading stays waiting for a person (or the next run); recording it never fails
  end;
  return null;
end $function$
