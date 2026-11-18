-- CF-247 F-CDESC (throughput; Platform Admin 10 Nov 2026 23:17 AEDT "go ahead"): a course description reading recorded by the AI worker is no longer admitted inside the worker's recording call; the job course-description-machine admits it.
--
-- Evidence (project fxcwkweaxjtknorudmwp, SELECT and logs only, 10 Nov 2026 23:00 to 23:40 AEDT). After enrich.course_text_items_per_day went 500 -> 2000 (16:51 AEDT) the description reader made about 118 readings in the day instead of about 2000:
--   - The AI worker (edge function coverage-sweep) records up to 40 answers in ONE call of public.svc_enrich_ai_record, through the API, under its statement time-out (role authenticator: statement_timeout 8s).
--   - For each description reading that call moves to state 'review', the AFTER trigger field_enrich_items_cdesc_machine runs security.course_description_machine_admit_v1(item, 'fresh_reading') inside the same statement: the machine check
--     (catalogue-wide duplicate scans) and the consumer read-back (public.website_v2_course). Measured on 12 real waiting items: check 414 ms average (3.3 s max), read-back 501 ms average (1.5 s max), so about 1 s a reading.
--   - A batch with more than about 8 description readings passes 8 s. The time-out is query_canceled, which "exception when others" in the trigger does NOT catch, so it cancels the WHOLE call and every answer in the batch is lost:
--     24 statement time-outs 07:29 to 07:41 UTC, every one in svc_enrich_ai_record -> enrich_course_text_record_v1 line 66 -> course_description_machine_trg_v1 -> course_description_machine_admit_v1 line 13 (the check) or line 22 (the read-back).
--   - The items were leased again (4 minute lease) and asked again; after 3 tries the slice settled them failed ("no answer could be recorded after 3 tries"): job 4a20ee5e, 385 description items failed although each has a paid AI
--     answer stored (pipeline.enrich_ai_answers, 385 kept as 'recorded' after the fact, 596 'superseded: leased again'; about US$1.06 of AI spend for nothing).
--   - Before the cap rise a batch rarely held more than a few description readings, so the call fitted inside 8 s; the defect was latent.
--
-- What this changes: security.course_description_machine_trg_v1 only (md5-guarded body replacement). When the reading is recorded through the API (PostgREST sets the transaction setting request.method for every API request; pg_cron and
-- the job have none), the trigger does not run the admission. The reading is recorded at once and stays a waiting first description (pipeline.layer4_review_items, status pending, no machine decision yet); the job course-description-machine
-- (every 10 minutes, security.course_description_machine_settle_v1: undecided items first, oldest first, 40 s time box) runs exactly the same admission on it, with via 'settle'. A reading moved to 'review' by the job itself
-- (security.cdesc_subset_recover_v1 and security.cdesc_recheck_held_v1, which rely on the admission running at once inside their sub-transaction) is admitted here exactly as before. Nothing else changes: the machine rule, the checks,
-- the read-back, the switch enrich.course_description_machine_on, the job, its schedule and every setting are unchanged. If the API ever stopped setting request.method the trigger would simply behave as it does today (no loss).
-- Effect: the worker's recording call no longer depends on the catalogue size or the consumer function; a fresh reading is admitted within one job run (10 minutes) instead of at once. At 10 Nov 23:30 AEDT the job had 0 undecided items
-- waiting (1,663 pending, every one already decided by the rule), so a fresh reading is first in the job's order.
--
-- Live definition this change edits (pg_proc.prosrc md5, read 10 Nov 2026 23:40 AEDT), before -> after (the migration stops, and applies nothing, if the live body is neither):
--   security.course_description_machine_trg_v1()   ec9b96498c54e37f8492a1003ea97520 -> c75d63a6390f4cb0e3ed7276e70c25f8
-- Replaces: the body of security.course_description_machine_trg_v1 is replaced in place (md5-guarded); admission of a fresh reading inside the AI worker's recording call is replaced by admission in the job course-description-machine (existing settle)
-- Retires: nothing
-- Nothing is dropped or deleted by this migration. No setting, job, table, Layer 4 item, reading or description is changed by applying it. Forward recovery (restores the previous body byte for byte): supabase/held/cdesc_admit_outside_ai_record_forward_recovery.sql

do $g$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_trg_v1()'::regprocedure);
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = 'c75d63a6390f4cb0e3ed7276e70c25f8' then raise notice 'security.course_description_machine_trg_v1(): already applied'; return; end if;
  if md5(v_src) <> 'ec9b96498c54e37f8492a1003ea97520' then raise exception 'live security.course_description_machine_trg_v1() differs from the definition this change replaces (body md5 %)', md5(v_src); end if;
  execute $ddl$
create or replace function security.course_description_machine_trg_v1()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
$ddl$;
end $g$;

comment on function security.course_description_machine_trg_v1() is 'CF-247 F-CDESC: after a course description reading reaches Layer 4 (state review), admits it at once under the machine rule while enrich.course_description_machine_on is 1, when the job records it (subset recovery, held recheck). A reading recorded through the API (the AI worker) is left waiting and admitted by the job course-description-machine (settle) on its next run, so the worker''s recording call never waits on the admission. Off: does nothing. Errors are swallowed; the reading stays waiting.';
revoke all on function security.course_description_machine_trg_v1() from public, anon, authenticated;

-- post-check: the body is the one this change states, and the trigger that calls it is unchanged (after update of state, review, description)
do $p$
begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.course_description_machine_trg_v1()'::regprocedure)) <> 'c75d63a6390f4cb0e3ed7276e70c25f8' then raise exception 'post-check: security.course_description_machine_trg_v1() is not the body this change states'; end if;
  if not exists (select 1 from pg_trigger t where t.tgname = 'field_enrich_items_cdesc_machine' and t.tgrelid = 'pipeline.field_enrich_items'::regclass and t.tgfoid = 'security.course_description_machine_trg_v1()'::regprocedure and not t.tgisinternal and t.tgenabled = 'O') then
    raise exception 'post-check: trigger field_enrich_items_cdesc_machine is missing, disabled or calls another function'; end if;
end $p$;
