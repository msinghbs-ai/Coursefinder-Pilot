-- CF-247: fix a stall in the Layer 3 English and intake claims (public.layer3_fact_claim_service). Found on 1 Oct 2026:
-- when a worker loses a claim (its call ran past 120 seconds), the claim releases the work item after 30 minutes so the
-- page can be tried again, but left the item's interpretation in "calling". The next claim then picked the same course
-- and tried to open a second interpretation for it, which the one-open-call rule (unique index
-- layer3_interpretations_one_active_entity_task_profile_idx) refuses; the whole claim failed, and kept failing until
-- the hourly housekeeping closed the old interpretation (up to about 45 minutes with no English or intake work).
-- Measured: 26 failed claims between 06:00 and 08:30 UTC. The fix:
--   1. releasing a stale claim also closes its interpretation as provider_error (what housekeeping already does);
--   2. a course that still has an open interpretation for the same task and profile is skipped, not claimed.
-- Edited in place from the live definition, only if its body is the one checked on 1 Oct 2026 (md5 guard).

do $claim$
declare s text; d text; v text;
  o1 text := E'returning w.id)\n  update pipeline.layer3_fact_handoffs h set work_item_id=null, attempts=h.attempts+1 from stale where h.work_item_id=stale.id;';
  n1 text := E'returning w.id, w.interpretation_id),\n  stale_i as (\n    update pipeline.layer3_interpretations i set status=''provider_error'', call_completed_at=coalesce(i.call_completed_at,now()),\n           validator_result=coalesce(i.validator_result,''{}''::jsonb)||jsonb_build_object(''recovery_state'',''stale_claim_released'',''recovered_at'',now())\n      from stale where i.id=stale.interpretation_id and i.status in (''reserved'',''calling'') returning i.id)\n  update pipeline.layer3_fact_handoffs h set work_item_id=null, attempts=h.attempts+1 from stale where h.work_item_id=stale.id;';
  o2 text := E'       and not exists (select 1 from pipeline.layer4_review_items l where l.entity_type=''course'' and l.entity_id=pg.course_id and l.status=''pending''';
  n2 text := E'       and not exists (select 1 from pipeline.layer3_interpretations x where x.entity_type=''course'' and x.entity_id=pg.course_id and x.task_class=p_task_class\n                         and x.profile_id=p.id and x.status in (''reserved'',''calling''))\n' || o2;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'layer3_fact_claim_service';
  v := md5(s);
  if v is distinct from 'cf3240651482cd073b80a84168373b8e' then raise exception 'layer3_fact_claim_service changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'stale release not found once'; end if;
  if (length(d) - length(replace(d, o2, ''))) / length(o2) <> 1 then raise exception 'review-item condition not found once'; end if;
  execute replace(replace(d, o1, n1), o2, n2);
end $claim$;
