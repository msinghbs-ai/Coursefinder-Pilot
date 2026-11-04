-- CF-247 AER recovery selector fixtures (migration 20261104550000): mandate 16:32 §10 items 1-5 and 7-10 for AER. Run by run.sh.
\set ON_ERROR_STOP on
create or replace function fx.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is not true then raise exception 'FAILED: %', p_what; end if; raise notice 'ok: %', p_what; end $f$;
create or replace function fx.rule(p uuid) returns jsonb language sql as $f$ select security.aer_recovery_rule_v1(p) $f$;
create temp table before_state as select (select count(*) from pipeline.layer4_review_items where status = 'pending') pending,
  (select count(*) from pipeline.aer_read_supersessions) reads, (select count(*) from pipeline.admin_jobs) jobs;

-- 1 the first run after the change reclassifies every hold once, with a durable next action (§5, §10.5); no attempt is counted for deterministic ones
do $$
declare v jsonb; v2 jsonb; v_att0 bigint;
begin
  create temp table att0 as select entity, total_attempts from pipeline.work_items where lane = 'aer_technical';
end $$;
do $$
declare v jsonb; v2 jsonb;
begin
  v := security.aer_technical_recovery_v1();
  perform fx.ok((v->>'technical_checked')::int > 300, format('the first run reconsiders every hold once (%s): %s', v->>'technical_checked', v->'by_class'));
  perform fx.ok(not exists (select 1 from pipeline.work_items w where w.lane = 'aer_technical' and w.stage in ('parked', 'retry_wait', 'deferred', 'quarantined', 'awaiting_review')
                              and coalesce(w.unresolved_blocker->>'next_action', '') = ''), 'every hold has a next action (IQ-00232: none parked with no next step)');
  perform fx.ok(not exists (select 1 from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class = 'aer_row_limit'
                              and (w.unresolved_blocker->>'authority' is null or w.unresolved_blocker->>'retry_prohibited' is null)), 'row-limit holds name the authority blocker and why a retry is prohibited');
  perform fx.ok(not exists (select 1 from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class = 'aer_reread_eligible' and (w.unresolved_blocker->>'next_at') is null),
                'holds eligible for a corrected read have their next time (the next aer-scheduled-read run)');
  perform fx.ok(not exists (select 1 from pipeline.work_items w join att0 a on a.entity = w.entity where w.lane = 'aer_technical' and w.failure_class <> 'transient' and w.total_attempts <> a.total_attempts),
                'no attempt is counted for a classified hold; only a transient retry counts');
  v2 := security.aer_technical_recovery_v1();
  perform fx.ok((v2->>'technical_checked')::int = 0 and (v2->>'unchanged')::int > 300, format('the next run reports nothing again: every condition is unchanged (%s unchanged)', v2->>'unchanged'));
end $$;

-- 2 §10.1: a deterministic refusal is never repeated against an unchanged copy and settings; the Diploma of Commerce shape is a row-limit hold
do $$
declare v_dc uuid := (select id from fx.dc where n = 1); r jsonb; v_rep uuid; h int;
begin
  r := fx.rule(v_dc);
  perform fx.ok(r->>'class' = 'row_limit' and (r->>'deterministic')::boolean and r->>'authority' like 'a row limit for this university%',
                'two row-limit refusals on the same copy: class row_limit, the authority blocker named');
  select s.old_item_id into v_rep from pipeline.aer_read_supersessions s join pipeline.field_enrich_items f on f.id = s.enrich_item_id
    join pipeline.coverage_course_pages pg on pg.course_id = s.course_id join pipeline.layer4_review_items i on i.id = s.old_item_id
   where s.state = 'refused' and s.outcome like 'the corrected read still drops%' and f.evidence_id = pg.evidence_id and i.status = 'pending' and pg.url = i.proposed_value->>'url'
     and not exists (select 1 from pipeline.manual_locks l where l.entity_id = i.entity_id) limit 1;
  r := fx.rule(v_rep);
  perform fx.ok(r->>'class' = 'unchanged_evidence' and r->>'retry_prohibited' like 'the reader refused the corrected read of this stored copy%', 'refused on the same copy: unchanged_evidence, the identical retry prohibited');
  select count(*) into h from security.aer_schedule_held_v1(50) z where z.eligible and (fx.rule(z.item_id)->>'eligible')::boolean is not true;
  perform fx.ok(h = 0, 'the scheduled held step selects nothing the rule does not make eligible');
  perform fx.ok(not exists (select 1 from security.aer_schedule_held_v1(50) z where z.item_id in (v_dc, v_rep) and z.eligible), 'neither is read again by the scheduled held step');
  update pipeline.platform_toolset_settings set value = '1' where key = 'aer.e13_recover_on';
  update pipeline.platform_toolset_settings set value = '["8e1adb6c-e069-43db-9584-bd054255e702"]' where key = 'aer.e13_recover_providers';
  perform fx.ok(not exists (select 1 from jsonb_array_elements(security.aer_e13_recover_v1(true)->'items') x where (x->>'item_id')::uuid in (v_dc, v_rep)), 'nor by the E13 pilot');
  update pipeline.platform_toolset_settings set value = '0' where key = 'aer.e13_recover_on';
end $$;

-- 3 §10.2: a changed copy or an authorised setting makes a parked item eligible again, by itself
do $$
declare v_dc uuid := (select id from fx.dc where n = 1); v_rep uuid; r jsonb; v jsonb;
begin
  select s.old_item_id into v_rep from pipeline.aer_read_supersessions s join pipeline.work_items w on w.entity = s.old_item_id::text and w.lane = 'aer_technical'
   where w.failure_class = 'aer_unchanged_evidence' and s.outcome like 'the corrected read still drops%' limit 1;
  update pipeline.coverage_course_pages set evidence_id = gen_random_uuid() where course_id = (select entity_id from pipeline.layer4_review_items where id = v_rep);
  r := fx.rule(v_rep);
  perform fx.ok(r->>'class' = 'changed_conditions' and (r->>'eligible')::boolean, 'a new stored copy: the refused item is eligible again (changed_conditions)');
  v := security.aer_technical_recovery_v1();
  perform fx.ok((select w.failure_class from pipeline.work_items w where w.lane = 'aer_technical' and w.entity = v_rep::text) = 'aer_reread_eligible'
                and (v->>'technical_checked')::int = 1, 'the lane reconsiders only that item and defers it to the scheduled read');
  update pipeline.platform_toolset_settings set value = '[{"provider_id": "8e1adb6c-e069-43db-9584-bd054255e702", "max_rows": 10}]', updated_at = now() where key = 'entry.max_rows_by_provider';
  r := fx.rule(v_dc);
  perform fx.ok(r->>'class' = 'changed_conditions', 'an authorised row limit (entry.max_rows_by_provider) makes the row-limit hold eligible again');
  update pipeline.platform_toolset_settings set value = '[]', updated_at = '2026-10-01 00:00:00+10' where key = 'entry.max_rows_by_provider';
  perform fx.ok(fx.rule(v_dc)->>'class' = 'row_limit', 'and without the change it stays a row-limit hold');
end $$;

-- 4 §10.3: transient conditions keep bounded retries; §10.4: duplicates make no work
do $$
declare v_tr uuid; w pipeline.work_items; n0 int;
begin
  select s.old_item_id into v_tr from pipeline.aer_read_supersessions s join pipeline.layer4_review_items i on i.id = s.old_item_id where s.state = 'requested' and i.status = 'pending' limit 1;
  perform fx.ok(fx.rule(v_tr)->>'class' = 'transient', 'a corrected read waiting for the reader: transient');
  update pipeline.layer4_item_readiness set readiness = 'technical_blocked' where item_id = v_tr;
  perform security.aer_technical_recovery_v1();
  select * into w from pipeline.work_items where lane = 'aer_technical' and entity = v_tr::text;
  perform fx.ok(w.failure_class = 'transient' and w.stage = 'retry_wait' and w.next_eligible_at > now(), 'transient: retry_wait with its next time (bounded by wc.transient_max_attempts)');
  select count(*) into n0 from pipeline.work_items where lane = 'aer_technical' and failure_class = 'duplicate';
  perform security.aer_technical_recovery_v1(); perform security.aer_technical_recovery_v1();
  perform fx.ok((select count(*) from pipeline.work_items where lane = 'aer_technical' and failure_class = 'duplicate') = n0
                and not exists (select 1 from pipeline.work_items w2 where w2.lane = 'aer_technical' and w2.failure_class = 'duplicate' and coalesce(w2.unresolved_blocker->>'next_action', '') = ''),
                'duplicates: parked once, never worked, each naming the item that is decided');
end $$;

-- 5 human-assisted: an open intervention waits for review with its reference; no rows request is raised for a deterministic repeat
do $$
declare v_iv record; v jsonb;
begin
  select * into v_iv from pipeline.layer4_interventions where missing_fact = 'aer_course_identity' limit 1;
  perform fx.ok((select w.stage || ':' || coalesce(w.review_ref, '') from pipeline.work_items w where w.lane = 'aer_technical' and w.entity = v_iv.entity) = 'awaiting_review:intervention:' || v_iv.id,
                'a shared page with its Human input needed item waits for review, with the reference');
  v := security.har_aer_item_generate_v1(40);
  perform fx.ok(not exists (select 1 from pipeline.layer4_interventions where missing_fact = 'aer_read_rows_missing'), 'no rows request: typed rows would resume the same refused read');
  perform fx.ok(exists (select 1 from pipeline.layer4_interventions where missing_fact = 'aer_course_identity' and entity <> v_iv.entity), 'identity items are still raised for other shared pages');
end $$;

-- 6 the panel agrees with the rule: a row-limit repeat recommends the row-limit decision, never Open human input or the same read
do $$
declare d jsonb; v_dc uuid := (select id from fx.dc where n = 1);
begin
  update fx.caller set uid = '22222222-2222-2222-2222-222222222222', rank = 6;
  d := security.layer4_aer_recovery_detail_v1(v_dc::text);
  perform fx.ok(d->'sections'->0->'body'->>'Recommended recovery' = 'row_limit_decision' and d->'sections'->0->'body'->>'Owner' = 'Platform Admin'
                and d->'sections'->0->'body'->>'Human input needed' like 'no: the Platform Admin decides a row limit%', 'the panel recommends the row-limit decision (Platform Admin)');
  perform fx.ok((select bool_and(not (a->>'allowed')::boolean) from jsonb_array_elements(d->'actions') a where a->>'key' in ('reread_stored', 'open_intervention')),
                'Re-read from stored evidence and Open human input are not offered for it');
  perform fx.ok(d->'sections'->1->'body'->>'Instead' like 'Ask the Platform Admin for a row limit for this university%', 'the repeat explanation names the row limit, not typed rows');
end $$;

-- 7 §6, §10.7-10.9: one genuinely recoverable item end to end: eligible -> corrected read asked by the scheduled held step -> read completes ->
--    E13 passes -> review-ready -> an authorised decision -> active rows -> consumer projection; the lane records the recovery
do $$
declare z record; v_new uuid := gen_random_uuid(); v_course uuid; v jsonb; v_res jsonb; v_t0 timestamptz := now() - interval '1 second';
begin
  select h.* into z from security.aer_schedule_held_v1(10) h where h.eligible limit 1;
  perform fx.ok(z.item_id is not null and fx.rule(z.item_id)->>'class' in ('reread_eligible', 'changed_conditions'), format('the held step picks an eligible item (%s)', fx.rule(z.item_id)->>'class'));
  update pipeline.layer4_item_readiness set readiness = 'technical_blocked' where item_id = z.item_id;
  perform security.aer_technical_recovery_v1();
  v_res := security.course_entry_correction_v1(z.item_id, '11111111-1111-1111-1111-111111111111', 'Scheduled entry reading (job aer-scheduled-read): read again from the same stored page');
  perform fx.ok((v_res->>'job_id') is not null, 'one corrected read is asked through the existing route (D-R2), from the stored copy');
  select entity_id into v_course from pipeline.layer4_review_items where id = z.item_id;
  -- the reader completes the corrected read (complete: every printed requirement kept), as security.enrich_entry_record_v1 records it
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value, status) select v_new, 'course', v_course, 'course_entry_first_read', proposed_value, 'pending' from pipeline.layer4_review_items where id = z.item_id;
  update pipeline.layer4_review_items set status = 'superseded' where id = z.item_id;
  update pipeline.aer_read_supersessions set state = 'superseded', new_item_id = v_new, closed_at = now() where (v_res->>'request_id')::uuid = id;
  update pipeline.field_enrich_items set state = 'review' where id = (v_res->>'enrich_item_id')::bigint;
  insert into catalogue.course_entry_requirements(course_id, kind, audience, quote, status, provenance) values (v_course, 'minimum_grade', 'international', 'A GPA of 5.0', 'proposed', jsonb_build_object('review_item_id', v_new::text));
  insert into fx.gate values (v_new, '{"rule": "E13", "complete": true, "rows_cut": 0, "shared_page": [], "drops_uncovered": [], "reasons": []}');
  perform security.layer4_readiness_tick_v1();
  perform fx.ok((select readiness from pipeline.layer4_item_readiness where item_id = v_new) = 'judgement_ready' and fx.rule(v_new)->>'class' = 'ready', 'E13 passes: the replacement is review-ready');
  v := security.aer_technical_recovery_v1();
  perform fx.ok((select w.stage || ':' || coalesce(w.recovered_at::text, '') <> 'done:' from pipeline.work_items w where w.lane = 'aer_technical' and w.entity = z.item_id::text)
                and (v->>'recovered')::int >= 1, 'the lane records the recovery (recovered_at set)');
  -- an authorised decision (as course_entry_review_apply_v1 applies Approve all rows), then the consumer projection
  insert into pipeline.layer4_decisions(review_item_id, action) values (v_new, 'approve');
  update pipeline.layer4_review_items set status = 'approved' where id = v_new;
  update catalogue.course_entry_requirements set status = 'active', updated_at = now() where provenance->>'review_item_id' = v_new::text;
  insert into search.course_documents(course_id, provider_id, country_id, provider_name, course_title, search_text, search_tsv, publication_status)
  select v_course, c.provider_id, p.country_id, p.canonical_name, c.canonical_title, c.canonical_title, to_tsvector(c.canonical_title), 'published' from catalogue.courses c join catalogue.providers p on p.id = c.provider_id where c.id = v_course
  on conflict (course_id) do nothing;
  v := security.aer_recovery_report_v1(v_t0);
  perform fx.ok((v->>'corrected_reads_asked')::int = 1 and (v->>'replaced')::int = 1 and (v->>'recovered')::int >= 1 and (v->>'active_rows_gained')::int = 1 and (v->>'published_courses_gained')::int = 1,
                format('measured as transitions: asked 1, replaced 1, recovered, 1 active row, 1 course published (%s)', v - 'holds_by_class'));
end $$;

-- 8 §10.10: other providers keep progressing: holds of RMIT do not stop the held step taking other universities' eligible reads
select fx.ok((select count(distinct z.provider_id) from security.aer_schedule_held_v1(10) z where z.eligible) >= 1
             and not exists (select 1 from security.aer_schedule_held_v1(10) z where z.eligible and z.provider_id = '8e1adb6c-e069-43db-9584-bd054255e702'
                               and (fx.rule(z.item_id)->>'eligible')::boolean is not true), 'other universities'' eligible reads proceed; RMIT''s deterministic holds take no place');
-- nothing decided, read or spent by the change itself beyond the end-to-end step
select fx.ok((select count(*) from pipeline.admin_jobs) = (select jobs from before_state) + 1, 'the only read asked is the end-to-end step''s one');
