-- CF-247 (23 Oct 2026). Read with AI on the 12 University of Auckland diplomas (08:05) found two gaps.
-- 1 The AI fill asked for nothing: every missing field of these courses carried an "AI found no value" hold from 14 Oct, and the
--   fill queue's gate (security.field_enrich_items_gate_v1) silently skips a held field. A person asking with a reason now releases
--   those holds for the fields asked (logged on the flag: released by that person, reason "Read with AI: ..."), so the AI fill runs.
-- 2 A page fee that went to the AI fee check once is never checked again, even after the page is read again with a different fee:
--   the page keeps the old work item (l3_work_item_id) for good. 68 NZ courses without an international fee are held this way, 51 of
--   them with a different fee on the page now (Auckland: the 2027 page). The fee is now handed to the AI fee check again when the
--   earlier check is closed (admitted, failed, no candidate, parked, or sent to review with no review pending) and the fee the page
--   shows now differs from the one checked. Read with AI also hands the course's fee over again after the page is read.
-- Replaces: nothing (public.svc_coverage_tuition_handoff_next and public.admin_course_read_now edited in place, md5-guarded)
-- Retires: nothing
do $do$
declare v_def text := pg_get_functiondef('public.svc_coverage_tuition_handoff_next(integer)'::regprocedure);
  v_old text := $o$and p.l3_work_item_id is null$o$;
  v_new text := $n$and (p.l3_work_item_id is null or exists (select 1 from pipeline.layer3_work_items w where w.id = p.l3_work_item_id
             and w.status in ('admitted', 'failed', 'no_candidate', 'parked', 'layer4_required')
             and not exists (select 1 from pipeline.layer4_review_items r where r.entity_id = p.course_id and r.field_code = 'provider_current_tuition_validation' and r.status = 'pending')
             and (w.candidate_context->'provider_current_tuition'->>'amount') is distinct from (security.coverage_tuition_target_v1(p.candidates->'fee')->>'amount')))$n$;
begin
  if md5(v_def) <> '1c75375d077b75eb9a9afb42f4f02ca5' then raise exception 'public.svc_coverage_tuition_handoff_next is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'handoff next: expected one work-item test'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

do $do$
declare v_def text := pg_get_functiondef('public.admin_course_read_now(uuid,text)'::regprocedure);
  v_old text := $o$  -- 2 an AI fill task for this course's missing fields$o$;
  v_new text := $n$  -- the page's fee goes to the AI fee check again once the page is read (a closed earlier check no longer holds it)
  update pipeline.coverage_course_pages set l3_handoff_at = null, l3_work_item_id = null
   where course_id = p_course_id and l3_work_item_id is not null
     and not exists (select 1 from pipeline.layer4_review_items r where r.entity_id = p_course_id and r.field_code = 'provider_current_tuition_validation' and r.status = 'pending');
  -- 2 an AI fill task for this course's missing fields$n$;
  v_old2 text := $o$  if cardinality(v_fields) > 0 then
    insert into pipeline.admin_jobs$o$;
  v_new2 text := $n$  if cardinality(v_fields) > 0 then
    -- a person asked, with a reason: earlier "AI found no value" holds on these fields are released so the fill is not skipped
    update pipeline.enrichment_flags f set state = 'released', released_at = now(), released_by = auth.uid(), release_kind = 'person', release_reason = 'Read with AI: ' || v_reason, updated_at = now()
     where f.entity = 'course' and f.entity_key = p_course_id::text and f.reason_code = 'enrich_no_value' and f.state in ('raised', 'counting') and f.field = any (v_fields);
    insert into pipeline.admin_jobs$n$;
begin
  if md5(v_def) <> 'bd6fb1d3e457a24c15c520943f4b3e69' then raise exception 'public.admin_course_read_now is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'read now: expected one fill step'; end if;
  if (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2) <> 1 then raise exception 'read now: expected one job insert'; end if;
  execute replace(replace(v_def, v_old, v_new), v_old2, v_new2);
end $do$;

select 'read with AI releases holds; changed page fees are checked again' ok;
do $t$ declare r jsonb; n int; begin
  perform set_config('request.jwt.claims', '{"sub":"63ba56cb-48d4-4169-98c2-7c4d1f72925b","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '63ba56cb-48d4-4169-98c2-7c4d1f72925b', true);
  r := public.admin_course_read_now('500fc010-f941-4e24-b1a6-0e11a5f6fed0', 'dry run test');
  select count(*) into n from pipeline.coverage_course_pages p join catalogue.courses co on co.id=p.course_id and co.lifecycle_status='active'
   where p.read_status='read' and p.candidates->'fee'->'candidates' @> '[{"international": true}]'::jsonb and p.l3_work_item_id is not null
     and exists (select 1 from pipeline.layer3_work_items w where w.id = p.l3_work_item_id and w.status in ('admitted', 'failed', 'no_candidate', 'parked', 'layer4_required')
             and not exists (select 1 from pipeline.layer4_review_items r where r.entity_id = p.course_id and r.field_code = 'provider_current_tuition_validation' and r.status = 'pending')
             and (w.candidate_context->'provider_current_tuition'->>'amount') is distinct from (security.coverage_tuition_target_v1(p.candidates->'fee')->>'amount'));
  raise exception 'DRYRUN OK %', jsonb_build_object('read_now', r, 'items', (select jsonb_agg(jsonb_build_object('f', i.field, 's', i.state)) from pipeline.field_enrich_items i where i.job_id = (r->>'job_id')::uuid),
    'page_l3', (select l3_work_item_id from pipeline.coverage_course_pages where course_id='500fc010-f941-4e24-b1a6-0e11a5f6fed0'), 'released_by_change', n,
    'next_sample', (select jsonb_array_length(public.svc_coverage_tuition_handoff_next(5)))); end $t$;
