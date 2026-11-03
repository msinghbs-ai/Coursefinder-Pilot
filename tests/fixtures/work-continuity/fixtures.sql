-- CF-247 SS-021 work continuity: the mandate §8 cases 1-9 (3 Nov 2026 21:19) on the fixture database run.sh builds. Every case raises on failure.
-- Time is moved by setting next_eligible_at or lease_until into the past (fixture only).
\set ON_ERROR_STOP 1
create or replace function fx.ok(p boolean, p_label text) returns void language plpgsql as $f$
begin
  if p is distinct from true then raise exception 'FAILED: %', p_label; end if;
  raise notice 'ok: %', p_label;
end $f$;
create or replace function fx.wi(p_lane text, p_entity text, p_kind text) returns pipeline.work_items language sql as
  $f$ select * from pipeline.work_items where lane = p_lane and entity = p_entity and work_kind = p_kind $f$;
create or replace function fx.due(p_lane text) returns void language sql as
  $f$ update pipeline.work_items set next_eligible_at = now() - interval '1 minute' where lane = p_lane and stage in ('retry_wait', 'deferred') and next_eligible_at is not null $f$;
create table fx.protected_before as
  select (select count(*) from pipeline.layer4_review_items) l4, (select md5(coalesce(string_agg(i::text, '|' order by i.id), '')) from pipeline.layer4_review_items i) l4_md5,
         (select count(*) from pipeline.layer4_decisions) dec, (select count(*) from pipeline.layer4_auto_admissions) adm, (select count(*) from pipeline.manual_locks) locks;

-- seed: three universities with refused pages, Layer 4 waiting items, a manual lock
insert into catalogue.providers(id, stable_key, canonical_name, country_id)
select ('00000000-0000-0000-0000-00000000000' || n)::uuid, 'p' || n, 'University ' || n, '00000000-0000-0000-0000-0000000000aa'::uuid from generate_series(1, 6) n;
insert into pipeline.coverage_course_pages(course_id, provider_id, read_status)
select gen_random_uuid(), ('00000000-0000-0000-0000-00000000000' || p)::uuid, 'identity_mismatch' from generate_series(1, 3) p, generate_series(1, 4 - p + 2) c;
insert into fx.relink_mode values ('00000000-0000-0000-0000-000000000001', 'error', 0);  -- the largest university fails
insert into pipeline.manual_locks(entity, entity_id, field) values ('course', gen_random_uuid(), 'official_url');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status)
select 'course', gen_random_uuid(), 'course_entry_first_read', 'pending' from generate_series(1, 3);
update fx.protected_before set l4 = (select count(*) from pipeline.layer4_review_items), l4_md5 = (select md5(string_agg(i::text, '|' order by i.id)) from pipeline.layer4_review_items i),
       locks = (select count(*) from pipeline.manual_locks);

-- the job is catalogued and scheduled without a number; the policies have their settings
select fx.ok((select count(*) = 1 from cron.job j join pipeline.automation_catalogue c on c.jobname = j.jobname where j.jobname = 'work-continuity' and j.command !~ '[(,]\s*[0-9]'), 'job work-continuity catalogued, command has no number');
select fx.ok(not exists (select 1 from pipeline.work_recovery_policies p where (p.max_attempts_key is not null and not exists (select 1 from pipeline.platform_toolset_settings s where s.key = p.max_attempts_key))
                                                                       or (p.recheck_key is not null and not exists (select 1 from pipeline.platform_toolset_settings s where s.key = p.recheck_key))), 'every policy threshold is a setting');
select fx.ok(not exists (select 1 from pipeline.platform_toolset_settings s where s.key like 'wc.%' and (s.label is null or s.unit is null or s.used_by is null or s.min_value is null or s.max_value is null)), 'every wc setting has label, range, unit and used_by');
select fx.ok((select count(*) from pipeline.platform_toolset_settings s where s.key like 'wc.%' and s.key like '%\_on' and (s.value #>> '{}')::numeric = 0) = 1
             and security.pipeline_num_v1('wc.ai_recovery_on', 9) = 0, 'only the AI-spending switch ships off');

-- §8.1 one failed course (university) does not stop the others; §4 per-item isolation
select fx.ok((security.course_relink_tick_v1(100)->>'providers')::int = 2, '8.1 relink: two universities relinked although the first in line failed');
select fx.ok((select count(*) from pipeline.course_relink) = 7, '8.1 relink: the other universities'' courses were taken (4 + 3)');
select fx.ok((fx.wi('course_relink', '00000000-0000-0000-0000-000000000001', 'relink')).stage = 'retry_wait'
             and (fx.wi('course_relink', '00000000-0000-0000-0000-000000000001', 'relink')).failure_class = 'unknown'
             and (fx.wi('course_relink', '00000000-0000-0000-0000-000000000001', 'relink')).next_eligible_at > now(), '8.1 the failed university waits for its backoff with its evidence');
select fx.ok((fx.wi('course_relink', '00000000-0000-0000-0000-000000000002', 'relink')).stage = 'done', '8.1 a relinked university is done');
-- the next run does not start with the waiting university
truncate fx.relink_calls;
select security.course_relink_tick_v1(100);
select fx.ok(not exists (select 1 from fx.relink_calls where provider_id = '00000000-0000-0000-0000-000000000001'), '8.1 the waiting university is skipped until it is due');
-- off: as before (largest first, one failure stops the run)
update pipeline.platform_toolset_settings set value = to_jsonb(0) where key = 'wc.relink_fair_on';
delete from pipeline.course_relink where provider_id <> '00000000-0000-0000-0000-000000000001';
do $$ begin perform security.course_relink_tick_v1(100); raise exception 'FAILED: off should fail as before'; exception when others then
  if sqlerrm like 'FAILED%' then raise; end if; raise notice 'ok: wc.relink_fair_on 0 behaves as before (the failure stops the run)'; end $$;
update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'wc.relink_fair_on';

-- §4 time-out attribution: a run stopped by the statement time-out is recorded against the university heading the order
delete from pipeline.course_relink; delete from pipeline.work_items where lane = 'course_relink';
update fx.relink_mode set mode = 'ok', sleep_s = 2 where provider_id = '00000000-0000-0000-0000-000000000001';
set statement_timeout = '1s';
do $$ begin
  perform security.course_relink_tick_v1(100);
  raise exception 'FAILED: the slow university should time out';
exception when query_canceled then raise notice 'ok: the slow university stops the whole run (statement time-out)';
end $$;
reset statement_timeout;
insert into cron.job_run_details(jobid, status, return_message, start_time, end_time)
select jobid, 'failed', 'ERROR:  canceling statement due to statement timeout', now(), now() from cron.job where jobname = 'course-relink';
select fx.ok((security.work_relink_attribute_v1()->>'attributed') = '00000000-0000-0000-0000-000000000001', '8.5 the time-out is attributed to the university heading the order');
select fx.ok((security.work_relink_attribute_v1()->>'timeouts')::int = 0, '8.5 the same failed run is attributed once (cursor)');
update fx.relink_mode set sleep_s = 0;
truncate fx.relink_calls;
select fx.ok((security.course_relink_tick_v1(100)->>'providers')::int = 2
             and not exists (select 1 from fx.relink_calls where provider_id = '00000000-0000-0000-0000-000000000001'), '8.5 the next run relinks the others, not the timed-out head');

-- §8.2 one unavailable provider does not stop other providers
select security.work_item_report_v1('fees', 'course-x1', 'fee_read', 'failed', '{"provider_id": "00000000-0000-0000-0000-000000000004", "message": "ENOTFOUND www.p4.example"}');
select fx.ok((fx.wi('fees', 'course-x1', 'fee_read')).stage = 'deferred' and (fx.wi('fees', 'course-x1', 'fee_read')).failure_class = 'site_unavailable', '8.2 unavailable website: deferred for its re-check');
select fx.ok((select array_agg(entity order by pos) from security.work_fair_pick_v1('fees', 'fee_read', '[
   {"entity": "course-x1", "provider_id": "00000000-0000-0000-0000-000000000004"}, {"entity": "course-x2", "provider_id": "00000000-0000-0000-0000-000000000005"},
   {"entity": "course-x3", "provider_id": "00000000-0000-0000-0000-000000000006"}]', 10)) = array['course-x2', 'course-x3'], '8.2 the other providers are selected');
-- §4 round-robin: one provider's backlog does not crowd out another's first item
select fx.ok((select array_agg(entity order by pos) from security.work_fair_pick_v1('fees', 'fee_read', '[
   {"entity": "a1", "provider_id": "00000000-0000-0000-0000-000000000005", "priority": 9}, {"entity": "a2", "provider_id": "00000000-0000-0000-0000-000000000005", "priority": 8},
   {"entity": "a3", "provider_id": "00000000-0000-0000-0000-000000000005", "priority": 7}, {"entity": "b1", "provider_id": "00000000-0000-0000-0000-000000000006", "priority": 1}]', 2)) = array['a1', 'b1'], '4 fair: each provider''s first item before any second');

-- §8.3 an AER queue at its limit does not stop fees, intakes or other work; §5 parking is not admission and raises no review item
update pipeline.platform_toolset_settings set value = to_jsonb(3) where key = 'aer.schedule_layer4_max';
select fx.ok((security.work_review_room_v1('aer')->>'room')::int = 0, '8.3 AER category full (3 waiting of 3)');
create temp table pick as select * from security.work_fair_pick_v1('enrich', 'field_read', '[
   {"entity": "c1:entry", "provider_id": "00000000-0000-0000-0000-000000000005", "field": "entry_requirements", "category": "aer"},
   {"entity": "c1:fees", "provider_id": "00000000-0000-0000-0000-000000000005", "field": "fees"},
   {"entity": "c1:intakes", "provider_id": "00000000-0000-0000-0000-000000000005", "field": "intakes"},
   {"entity": "c2:entry", "provider_id": "00000000-0000-0000-0000-000000000006", "field": "entry_requirements", "category": "aer"}]', 10);
select fx.ok((select array_agg(entity order by entity) from pick) = array['c1:fees', 'c1:intakes'], '8.3 fees and intakes still selected while AER is full');
select fx.ok((fx.wi('enrich', 'c1:entry', 'field_read')).stage = 'deferred' and (fx.wi('enrich', 'c1:entry', 'field_read')).failure_class = 'review_full'
             and (fx.wi('enrich', 'c1:entry', 'field_read')).attempts = 0, '8.3 AER work deferred without an attempt');
select fx.ok((select count(*) from pipeline.layer4_review_items) = (select l4 from fx.protected_before), '8.3 no review item raised by deferring');
-- capacity frees: one item decided by a person; the tick returns one AER item (never more than the room)
update pipeline.layer4_review_items set status = 'approved' where id = (select id from pipeline.layer4_review_items where status = 'pending' order by id limit 1);
select fx.due('enrich');
select security.work_continuity_tick_v1();
select fx.ok((select count(*) from pipeline.work_items where lane = 'enrich' and failure_class = 'review_full' and stage = 'eligible') = 2, '5 room returned: deferred AER work is eligible again');
select fx.ok((select count(*) from security.work_fair_pick_v1('enrich', 'field_read', '[
   {"entity": "c1:entry", "provider_id": "00000000-0000-0000-0000-000000000005", "field": "entry_requirements", "category": "aer"},
   {"entity": "c2:entry", "provider_id": "00000000-0000-0000-0000-000000000006", "field": "entry_requirements", "category": "aer"}]', 10)) = 1, '5 a category takes at most its room in one selection');
update pipeline.layer4_review_items set status = 'pending' where status = 'approved';  -- fixture only: restore the protected snapshot
update pipeline.platform_toolset_settings set value = to_jsonb(600) where key = 'aer.schedule_layer4_max';

-- §8.4 failed AI extraction is parked and recoverable
insert into pipeline.field_enrich_items(provider_id, course_id, field, state, reason, attempts)
select '00000000-0000-0000-0000-000000000005', ('00000000-0000-0000-0000-0000000001' || lpad(n::text, 2, '0'))::uuid, 'intakes', 'failed', 'no answer could be recorded after 3 tries', 3 from generate_series(1, 4) n;
select fx.ok(((security.work_continuity_tick_v1())->'ai_extraction'->>'recorded')::int = 4, '8.4 the four reads without an answer are recorded');
select fx.ok((select count(*) from pipeline.work_items where lane = 'ai_extraction' and work_kind = 'field_read' and stage = 'retry_wait' and failure_class = 'ai_incomplete') = 4, '8.4 retry-due with backoff, no claim held');
select fx.ok(((security.work_continuity_tick_v1())->'ai_extraction'->>'recorded')::int = 0, '8.4 recorded once (cursor)');
select fx.due('ai_extraction');
select fx.ok((select count(*) from security.work_items_due_v1('ai_extraction', 'field_read', 10)) = 0, '8.4 not handed to the reader while wc.ai_recovery_on is 0 (AI spend ships off)');
update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'wc.ai_recovery_on';
select fx.ok((select count(*) from security.work_items_due_v1('ai_extraction', 'field_read', 10)) = 4, '8.4 handed back when switched on');
update pipeline.platform_toolset_settings set value = to_jsonb(0) where key = 'wc.ai_recovery_on';
-- a later read fills one: recovered; another exhausts its attempts: parked with evidence
insert into pipeline.field_enrich_items(provider_id, course_id, field, state) values ('00000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000101', 'intakes', 'filled');
select security.work_continuity_tick_v1();
select fx.ok((fx.wi('ai_extraction', '00000000-0000-0000-0000-000000000101:intakes', 'field_read')).stage = 'done'
             and (fx.wi('ai_extraction', '00000000-0000-0000-0000-000000000101:intakes', 'field_read')).recovered_at is not null, '8.4/8.7 a later fill marks the item recovered');
select security.work_item_report_v1('ai_extraction', '00000000-0000-0000-0000-000000000102:intakes', 'field_read', 'failed', '{"class": "ai_incomplete", "message": "no answer could be recorded after 3 tries"}') from generate_series(1, 2);
select fx.ok((fx.wi('ai_extraction', '00000000-0000-0000-0000-000000000102:intakes', 'field_read')).stage = 'parked'
             and (fx.wi('ai_extraction', '00000000-0000-0000-0000-000000000102:intakes', 'field_read')).unresolved_blocker->>'reason' like 'attempts used up%'
             and (fx.wi('ai_extraction', '00000000-0000-0000-0000-000000000102:intakes', 'field_read')).lease_until is null, '8.4 attempts used up: parked with evidence, no claim, no infinite retry');

-- §8.5 an expired lease does not starve the queue
select fx.ok((security.work_claim_v1('scholarship', 'page_read', '[{"entity": "s1", "provider_id": "00000000-0000-0000-0000-000000000005"}, {"entity": "s2", "provider_id": "00000000-0000-0000-0000-000000000006"}]', 10, 300))::text like '%s1%', '8.5 claimed');
select fx.ok((select count(*) from security.work_fair_pick_v1('scholarship', 'page_read', '[{"entity": "s1"}, {"entity": "s2"}]', 10)) = 0, '8.5 a valid claim is not handed out twice');
update pipeline.work_items set lease_until = now() - interval '1 minute' where lane = 'scholarship';
select fx.ok((select count(*) from security.work_fair_pick_v1('scholarship', 'page_read', '[{"entity": "s1"}, {"entity": "s2"}]', 10)) = 2, '8.5 an expired claim does not hold the item');
select fx.ok((security.work_continuity_tick_v1()->>'claims_released')::int = 2 and (fx.wi('scholarship', 's1', 'page_read')).stage = 'retry_wait'
             and (fx.wi('scholarship', 's1', 'page_read')).lease_until is null and (fx.wi('scholarship', 's1', 'page_read')).failure_class = 'lease_expired', '8.5 the tick releases expired claims safely (transient attempt)');

-- §8.6 duplicate errors produce one actionable case; §7 an unchanged blocker never re-notifies
select security.work_item_report_v1('fees', 'dup-' || n, 'fee_read', 'failed', jsonb_build_object('class', 'transient', 'message', 'HTTP 503 from worker ' || n))
  from generate_series(1, 3) n, generate_series(1, 5) k;
select fx.ok((select bool_and(jsonb_array_length(evidence) = 1 and stage = 'parked') from pipeline.work_items where entity like 'dup-%'), '8.6 an identical repeat adds no evidence; attempts end in parked');
select security.work_continuity_tick_v1();
select fx.ok((select count(*) from pipeline.integration_issues where fingerprint = 'work_blocked:fees:transient') = 1, '8.6 one issue for the blocker');
create temp table ev as select (select count(*) from pipeline.integration_issue_events) n, (select retry_count from pipeline.integration_issues where fingerprint = 'work_blocked:fees:transient') rc;
select security.work_item_report_v1('fees', 'dup-4', 'fee_read', 'failed', '{"class": "transient", "message": "HTTP 503 from worker 4"}') from generate_series(1, 5);
select security.work_continuity_tick_v1();
select fx.ok((select count(*) from pipeline.integration_issue_events) = (select n from ev)
             and (select retry_count from pipeline.integration_issues where fingerprint = 'work_blocked:fees:transient') = (select rc from ev), '8.6 the unchanged blocker is not raised again when items join it');
select fx.ok((select count(distinct (escalation->>'issue_id')) from pipeline.work_items where entity like 'dup-%') = 1, '8.6 every item of the blocker carries the one case');

-- §7 controller integration: diagnosis by the registered rule, auto only for retry, park and release-claim
select fx.ok(security.ops_detect_match_v1((select detect from pipeline.ops_root_causes where code = 'work_retries_exhausted'), '{"fingerprint": "work_blocked:fees:transient"}'), '7 the controller''s rule diagnoses the issue');
select fx.ok((select array_agg(code order by code) from pipeline.ops_remedies where authority = 'auto' and code like 'work\_%') = array['work_park_exhausted', 'work_release_claims', 'work_retry_parked'], '7 auto only: retry, park, release-claim');
select fx.ok((select bool_and(authority = 'admin') from pipeline.ops_remedies r where r.treats && array['work_identity_conflict', 'work_budget_exhausted', 'work_authority_required']), '7 authority, budget and identity blockers go to the Platform Admin');
select fx.ok((select authority = 'release' and treats = array['wc_head_of_line_fixed_order'] from pipeline.ops_remedies where code = 'work_continuity_adoption'), '7 the audit''s live root causes route to the adopting release');
-- §8.7 recovery returns the item to the right stage: the controller's retry remedy (under the authority guard) re-arms, the lane completes it
set cf247.ops_remedy = 'on';
select fx.ok((security.work_remedy_retry_parked_v1((select id from pipeline.integration_issues where fingerprint = 'work_blocked:fees:transient'))->>'changed')::int = 4, '8.7 retry remedy re-arms the parked items (guard on)');
reset cf247.ops_remedy;
select fx.ok((fx.wi('fees', 'dup-1', 'fee_read')).stage = 'retry_wait' and (fx.wi('fees', 'dup-1', 'fee_read')).attempts = 0, '8.7 back to retry_wait with attempts starting again');
select fx.due('fees'); select security.work_continuity_tick_v1();
select fx.ok((fx.wi('fees', 'dup-1', 'fee_read')).stage = 'eligible', '8.7 due: eligible in its lane');
select security.work_item_report_v1('fees', 'dup-' || n, 'fee_read', 'claimed', '{"lease_seconds": 60}') from generate_series(1, 4) n;
select security.work_item_report_v1('fees', 'dup-' || n, 'fee_read', 'succeeded', '{}') from generate_series(1, 4) n;
select fx.ok((select bool_and(stage = 'done' and recovered_at is not null and attempts = 0) from pipeline.work_items where entity like 'dup-%'), '8.7 completed: done and counted as recovered');
select fx.ok((security.work_verify_recovered_v1((select id from pipeline.integration_issues where fingerprint = 'work_blocked:fees:transient'))->>'passed')::boolean, '8.7 the controller''s verification passes');

-- budget: only the paid lane pauses, free lanes continue, the lane resumes when the budget allows
insert into fx.budget values ('course_page', 0);
select security.work_item_report_v1('paid_acquisition', 'pg-1', 'page_fetch', 'budget', '{"purpose": "course_page"}');
select fx.ok(security.work_lane_paused_v1('paid_acquisition') and not security.work_lane_paused_v1('stored_evidence'), '3 budget: only the paid lane is paused');
select fx.ok((select count(*) from security.work_fair_pick_v1('paid_acquisition', 'page_fetch', '[{"entity": "pg-2"}]', 5)) = 0
             and (select count(*) from security.work_fair_pick_v1('stored_evidence', 'page_read', '[{"entity": "st-1"}]', 5)) = 1, '3 budget: the paid lane selects nothing; stored-evidence work continues');
update pipeline.work_items set next_eligible_at = now() - interval '1 minute' where lane = 'paid_acquisition' and entity = '*lane';
select security.work_continuity_tick_v1();
select fx.ok(security.work_lane_paused_v1('paid_acquisition'), '3 budget: still paused while the budget check holds it');
update fx.budget set left_credits = 50;
update pipeline.work_items set next_eligible_at = now() - interval '1 minute' where lane = 'paid_acquisition' and entity = '*lane';
select security.work_continuity_tick_v1();
select fx.ok(not security.work_lane_paused_v1('paid_acquisition') and (fx.wi('paid_acquisition', 'pg-1', 'page_fetch')).stage = 'eligible', '3 budget: resumes automatically when the budget allows');
select fx.ok((select count(*) from pipeline.integration_issues where fingerprint = 'work_blocked:paid_acquisition:budget_exhausted') = 1, '7 the budget blocker was raised once for a decision');

-- §8.8 every admission still passes Layer 4; §8.9 locks, holds and decisions are protected
select security.work_item_report_v1('enrich', 'c9:english', 'field_read', 'review', jsonb_build_object('review_ref', (select id from pipeline.layer4_review_items limit 1)));
select fx.ok((fx.wi('enrich', 'c9:english', 'field_read')).stage = 'awaiting_review' and not security.work_item_eligible_v1('enrich', 'c9:english', 'field_read'), '8.8 a pending human decision is waiting, not admitted, not eligible');
select security.work_item_report_v1('enrich', 'c8:official_url', 'field_read', 'locked', jsonb_build_object('lock', jsonb_build_object('entity', 'course', 'field', 'official_url')));
select fx.ok((fx.wi('enrich', 'c8:official_url', 'field_read')).stage = 'parked' and (fx.wi('enrich', 'c8:official_url', 'field_read')).lock_refs <> '[]', '8.9 a manual lock is held, never retried');
select security.work_item_report_v1('enrich', 'c7:fees', 'field_read', 'failed', '{"sqlstate": "23505", "message": "duplicate key value violates unique constraint"}');
select fx.ok((fx.wi('enrich', 'c7:fees', 'field_read')).stage = 'quarantined', '3 identity conflict: quarantined');
set cf247.ops_remedy = 'on';
select security.work_remedy_retry_parked_v1(id), security.work_remedy_park_v1(id), security.work_remedy_release_claims_v1(id) from pipeline.integration_issues where fingerprint like 'work\_blocked:%';
reset cf247.ops_remedy;
select fx.ok((fx.wi('enrich', 'c8:official_url', 'field_read')).stage = 'parked' and (fx.wi('enrich', 'c7:fees', 'field_read')).stage = 'quarantined', '8.9 remedies never re-arm a locked or quarantined item');
select fx.ok((select count(*) from pipeline.layer4_review_items) = b.l4 and (select md5(string_agg(i::text, '|' order by i.id)) from pipeline.layer4_review_items i) = b.l4_md5
             and (select count(*) from pipeline.layer4_decisions) = b.dec and (select count(*) from pipeline.layer4_auto_admissions) = b.adm
             and (select count(*) from pipeline.manual_locks) = b.locks, '8.8/8.9 Layer 4 items, decisions, admissions and manual locks unchanged by the whole run') from fx.protected_before b;
do $$ begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and (p.proname like 'work\_%' escape '\' or p.proname like 'course_relink_fair%')
              and pg_get_functiondef(p.oid) ~* '(insert into|update|delete from)\s+(pipeline\.(layer4_|manual_locks|platform_toolset_settings)|catalogue\.|search\.)') then
    raise exception 'FAILED: a work-continuity function writes Layer 4, locks, settings, the catalogue or the search projection';
  end if;
  raise notice 'ok: 8.8/8.9 no work-continuity function writes Layer 4, locks, settings, the catalogue or the projection';
end $$;

-- §9 the report, in the operations report
select fx.ok((security.work_continuity_report_v1()->'lanes') @> '[{"lane": "course_relink"}]' and (security.work_continuity_report_v1() ? 'repeated_root_causes')
             and jsonb_typeof(security.work_continuity_report_v1()->'review_room') = 'array', '9 per-lane report');
select fx.ok((select (l->>'blocked')::int >= 1 and l ? 'parked' and l ? 'retry_due' and l ? 'recovery_success_pct' and l ? 'oldest_blocked_at' and l ? 'awaiting_authority'
                and (l->>'recovered')::int >= 1
                from jsonb_array_elements(security.work_continuity_report_v1()->'lanes') l where l->>'lane' = 'ai_extraction'), '9 lane figures: blocked (the parked read re-armed by the remedy), parked, retry-due, recovery, oldest, authority');
select fx.ok(security.ops_report_v1(24) ? 'work_continuity' and not (security.ops_report_v1(24)->'work_continuity' ? 'error'), '9 ops_report_v1 carries the work_continuity section');

-- off: nothing is recorded
update pipeline.platform_toolset_settings set value = to_jsonb(0) where key = 'wc.on';
select fx.ok((security.work_item_report_v1('fees', 'off-1', 'fee_read', 'failed', '{}')->>'recorded')::boolean = false and fx.wi('fees', 'off-1', 'fee_read') is null, 'wc.on 0: nothing recorded');
update pipeline.platform_toolset_settings set value = to_jsonb(1) where key = 'wc.on';
