-- CF-247 SS-021 part 3 (20261104190000) acceptance on fixtures (overnight mandate 3 Nov 2026 21:59 §3): AER at its limit does not stop fees or
-- intakes; one university cannot starve others; the paid cap parks and later resumes; Layer 4 admission is unchanged; failures stay with their
-- item; the issue writer maps refused values. Each check raises on failure and says "ok" when it holds.
set client_min_messages = notice;
create or replace function fx.ok(p boolean, p_msg text) returns void language plpgsql as $$
begin if not coalesce(p, false) then raise exception 'FAILED: %', p_msg; end if; raise notice 'ok: %', p_msg; end $$;
create or replace function fx.setn(p_key text, p_val jsonb) returns void language sql as $$
  insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values ('pipeline', p_key, p_key, 'number', p_val)
  on conflict (toolset_key, key) do update set value = excluded.value $$;
create or replace function fx.l4() returns text language sql as $$ select md5(coalesce(string_agg(i::text, '|' order by i.id), '')) from pipeline.layer4_review_items i $$;
select fx.ok((select count(*) from pipeline.platform_toolset_settings where key in ('wc.aer_fair_on', 'wc.page_find_release_on', 'wc.fee_item_claims_on')
                and value = to_jsonb(0)) = 3, 'shipped OFF: AER readiness counting, plan release and fee page claims (they change admission or spend)');

-- universities: P1 has much waiting; P2 a matrix with duplicates; P3, P4 and P5 have nothing waiting; P6 a matrix source with nothing waiting
create temp table u(k text primary key, id uuid);
insert into u values ('P1', '10000000-0000-0000-0000-000000000001'), ('P2', '10000000-0000-0000-0000-000000000002'), ('P3', '10000000-0000-0000-0000-000000000003'),
                     ('P4', '10000000-0000-0000-0000-000000000004'), ('P5', '10000000-0000-0000-0000-000000000005'), ('P6', '10000000-0000-0000-0000-000000000006'),
                     ('P7', '10000000-0000-0000-0000-000000000007'), ('P8', '10000000-0000-0000-0000-000000000008');
insert into catalogue.providers(id, stable_key, canonical_name, country_id) select id, 'fx-' || k, 'University ' || k, gen_random_uuid() from u on conflict do nothing;
-- the owner the scheduled reading runs as, with the Platform Admin rank
insert into security.roles values ('platform_admin', 6, 'active') on conflict do nothing;
insert into pipeline.field_gap_queue_control values (1, '20000000-0000-0000-0000-000000000001') on conflict do nothing;
insert into security.user_roles values ('20000000-0000-0000-0000-000000000001', 'platform_admin', null);
select fx.setn('aer.schedule_layer4_max', '10'), fx.setn('batch.aer_schedule_courses', '20'), fx.setn('aer.schedule_daily_max', '200'),
       fx.setn('wc.aer_provider_share_pct', '40'), fx.setn('wc.aer_new_provider_reserve_pct', '10');

-- Layer 4 waiting AER items: P1 courses c1..c6 (c1 and c2 twice more: duplicates; c3 and c4 technically held); P2 matrix x4 (3 duplicates)
create temp table c(k text primary key, id uuid, pk text);
insert into c select 'c' || g, ('30000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'P1' from generate_series(1, 6) g;
insert into catalogue.courses(id, stable_key, provider_id, canonical_title, lifecycle_status) select c.id, 'fx-' || c.k, u.id, 'Course ' || c.k, 'active' from c join u on u.k = c.pk;
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status, created_at)
select gen_random_uuid(), 'course', c.id, 'course_entry_first_read', 'pending', now() - interval '2 days' + make_interval(mins => n) from c, generate_series(1, case when c.k in ('c1', 'c2') then 2 else 1 end) n;
insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, status, created_at)
select gen_random_uuid(), 'provider', (select id from u where k = 'P2'), 'entry_matrix_first_run', 'pending', now() - make_interval(hours => n) from generate_series(1, 4) n;
insert into pipeline.layer4_item_readiness(item_id, entity_type, entity_id, field_code, readiness, reasons, route)
select i.id, i.entity_type, i.entity_id, i.field_code, case when c.k in ('c3', 'c4') then 'technical_blocked' else 'judgement_ready' end,
       case when c.k in ('c3', 'c4') then array['completeness_gate'] else '{}' end, case when c.k in ('c3', 'c4') then 'repair:completeness_gate' else 'review' end
  from pipeline.layer4_review_items i left join c on c.id = i.entity_id;
-- eligible courses for new reads: 10 of P1, 10 of P3, 1 of P4
insert into fx.aer_candidates(course_id, provider_id)
select gen_random_uuid(), u.id from u, generate_series(1, case u.k when 'P4' then 1 else 10 end) where u.k in ('P1', 'P3', 'P4') order by u.k;
-- due matrix refreshes: P2 (a matrix item waits) and P6 (nothing waits)
insert into pipeline.entry_matrix_sources(provider_id, status, read_via, read_at) select id, 'read', 'html', now() - interval '60 days' from u where k in ('P2', 'P6');
-- independent lanes: a fee page due; intake fields waiting
insert into pipeline.fee_reader_queue(provider_id, state, fact_source_id, content_hash) values ((select id from u where k = 'P5'), 'queued', gen_random_uuid(), 'h1');
select fx.setn('fees.run_every_minutes', '1');
do $$
declare v_l4 text := fx.l4(); v jsonb; v_room jsonb;
begin
  perform fx.ok((security.work_review_room_v1('aer')->>'room')::int = 0 and (security.work_review_room_v1('aer')->>'waiting')::int = 12,
                'F4 switch off: the raw count (12 waiting) fills the limit of 10, as before');
  v := security.aer_schedule_tick_v1(false);
  perform fx.ok((v->>'back_pressure')::boolean and (v->>'course_reads')::int = 0 and (v->>'matrix_pages')::int = 0, 'F4 switch off: back-pressure stops new reads and refreshes, as before');
  -- AER at its limit does not stop fees or intakes
  v := security.fee_reader_tick_v1();
  perform fx.ok((v->>'worker')::int = 1, 'AER at its limit: the fee worker is still called for its due page');
  perform fx.ok((select count(*) from security.work_fair_pick_v1('intakes', 'field_read', jsonb_build_array(
                   jsonb_build_object('entity', 'i1', 'provider_id', (select id from u where k = 'P1'), 'field', 'intakes'),
                   jsonb_build_object('entity', 'i2', 'provider_id', (select id from u where k = 'P3'), 'field', 'intakes')), 10)) = 2,
                'AER at its limit: intake work with no review category is still selected');
  perform fx.ok((select count(*) from security.work_fair_pick_v1('fees', 'fee_read', jsonb_build_array(
                   jsonb_build_object('entity', 'f1', 'provider_id', (select id from u where k = 'P1'), 'field', 'tuition', 'category', 'no_page')), 10)) = 1,
                'AER at its limit: work in another review category is still selected');
  perform fx.ok(fx.l4() = v_l4, 'F4 switch off: no Layer 4 item changed');
end $$;

-- F4 on: distinct review-ready decisions under the same limit, universities in turn
select fx.setn('wc.aer_fair_on', '1');
do $$
declare v_l4 text := fx.l4(); v jsonb; r jsonb; v_p1 int; v_p3 int; v_p4 int;
begin
  r := security.work_review_room_v1('aer');
  perform fx.ok((r->>'limit')::int = 10 and (r->>'raw_waiting')::int = 12 and (r->>'waiting')::int = 5 and (r->>'technical')::int = 2 and (r->>'duplicates')::int = 5
                and (r->>'room')::int = 5, 'F4: same limit (10); 12 raw items are 5 distinct review-ready decisions (2 technically held, 5 duplicates not counted): room 5');
  v := security.aer_schedule_tick_v1(false);
  select count(*) filter (where f.provider_id = (select id from u where k = 'P1')), count(*) filter (where f.provider_id = (select id from u where k = 'P3')),
         count(*) filter (where f.provider_id = (select id from u where k = 'P4'))
    into v_p1, v_p3, v_p4 from pipeline.field_enrich_items f where f.field = 'entry_requirements';
  perform fx.ok((v->>'course_reads')::int = 5 and not (v->>'back_pressure')::boolean, 'F4: five new reads, exactly the room');
  perform fx.ok(v_p1 = 0, 'F4: P1, at its share (4 of a 4-item share waiting), takes no new read');
  perform fx.ok(v_p4 = 1 and v_p3 = 4, 'F4: one university cannot starve others: P4''s single course is read in its turn; P3 stops at its share (4)');
  r := security.work_review_room_v1('aer');
  perform fx.ok((r->>'waiting')::int + (r->>'in_progress')::int = 10 and (r->>'room')::int = 0, 'F4: decisions waiting plus reads in progress now equal the limit, never more');
  perform fx.ok((v->>'matrix_pages')::int = 2, 'F4: with room, due matrix refreshes run as before');
  update pipeline.entry_matrix_sources set status = 'read', read_at = now() - interval '60 days';
  v := security.aer_schedule_tick_v1(false);
  perform fx.ok((v->>'back_pressure')::boolean and (v->>'course_reads')::int = 0, 'F4: at the limit the next run starts no read (the limit is never bypassed)');
  perform fx.ok((v->>'matrix_pages')::int = 1 and (v->'matrix'->0->>'provider_id')::uuid = (select id from u where k = 'P6'),
                'F4: at the limit the due matrix refresh of P6 (nothing waiting) still runs; P2''s (a matrix item waits) does not');
  perform fx.ok((select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class = 'technical_hold' and w.stage = 'retry_wait') = 2
                and (select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class = 'duplicate' and w.stage = 'parked') = 5,
                'F4: technically held items wait for their bounded re-check; duplicates are parked, not counted');
  perform fx.ok((select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class = 'duplicate' and w.repeat_count > 0) = 0,
                'F4: an unchanged duplicate is not reported again by the next run');
  perform fx.ok(fx.l4() = v_l4, 'F4: Layer 4 admission unchanged: no item created, decided, approved or changed (never an automatic entry approval)');
end $$;

-- F4 bounded technical recovery: re-check at the backoff, parked after wc.aer_tech_max_attempts, recovered when ready
do $$
declare v jsonb;
begin
  update pipeline.work_items set next_eligible_at = now() - interval '1 minute' where lane = 'aer_technical' and failure_class = 'technical_hold';
  v := security.aer_technical_recovery_v1();
  update pipeline.work_items set next_eligible_at = now() - interval '1 minute' where lane = 'aer_technical' and failure_class = 'technical_hold';
  v := security.aer_technical_recovery_v1();
  perform fx.ok((select count(*) from pipeline.work_items w where w.lane = 'aer_technical' and w.failure_class = 'technical_hold' and w.stage = 'parked' and w.attempts = 3) = 2,
                'F4: a technically held item is parked after wc.aer_tech_max_attempts (3) re-checks, no endless retry');
  update pipeline.layer4_item_readiness x set readiness = 'judgement_ready', reasons = '{}' from catalogue.courses c where c.id = x.entity_id and c.stable_key = 'fx-c3';
  v := security.aer_technical_recovery_v1();
  perform fx.ok((v->>'recovered')::int = 1 and exists (select 1 from pipeline.work_items w join pipeline.layer4_review_items i on i.id::text = w.entity
                  join catalogue.courses c on c.id = i.entity_id where w.lane = 'aer_technical' and c.stable_key = 'fx-c3' and w.stage = 'done' and w.recovered_at is not null),
                'F4: a held item that becomes review-ready is recovered');
end $$;

-- F4 reserve: when the room is down to the reserve, only universities with nothing waiting get new reads
do $$
declare n_p3 int; n_p5 int;
begin
  delete from pipeline.field_enrich_items where field = 'entry_requirements' and provider_id = (select id from u where k = 'P3');
  insert into fx.aer_candidates(course_id, provider_id) select gen_random_uuid(), (select id from u where k = 'P5');
  perform fx.setn('wc.aer_new_provider_reserve_pct', '50');
  perform fx.setn('wc.aer_provider_share_pct', '100');
  insert into pipeline.field_enrich_items(provider_id, course_id, state, field, attempts, created_at, updated_at)
  select (select id from u where k = 'P3'), gen_random_uuid(), 'queued', 'entry_requirements', 0, now(), now();
  select count(*) filter (where provider_id = (select id from u where k = 'P3')), count(*) filter (where provider_id = (select id from u where k = 'P5'))
    into n_p3, n_p5 from security.aer_fair_courses_v1(5);
  perform fx.ok(n_p3 = 0 and n_p5 = 1, 'F4: the reserve keeps the last room for a university with nothing waiting (P5), not one already reading (P3)');
  perform fx.setn('wc.aer_new_provider_reserve_pct', '10');
end $$;

-- F3: the paid cap parks and later resumes; a task that can never run ends at once
insert into pipeline.course_link_search_settings values (1, true, 100000, 'worker') on conflict (id) do nothing;
select fx.setn('search.daily_picked_cap', '2');
insert into pipeline.course_link_search(course_id, provider_id, stage, state, attempts, sent_at, queued_at)
select gen_random_uuid(), (select id from u where k = 'P8'), 'title', 'none', 1, now() - make_interval(mins => g), now() from generate_series(1, 2) g;
insert into pipeline.course_link_search(course_id, provider_id, stage, state, attempts, queued_at)
select gen_random_uuid(), (select id from u where k = 'P7'), 'title', 'queued', 0, now() from generate_series(1, 5);
insert into pipeline.admin_jobs(id, kind, state, args, result, started_at) values
 ('40000000-0000-0000-0000-000000000001', 'course_page_find', 'running', jsonb_build_object('provider_id', (select id from u where k = 'P7')),
  jsonb_build_object('unprocessed', 5, 'held', jsonb_build_object('code', 'waiting_turn', 'reason', '5 search(es) waiting their turn')), now() - interval '18 hours'),
 ('40000000-0000-0000-0000-000000000002', 'course_page_find', 'running', jsonb_build_object('provider_id', (select id from u where k = 'P6')),
  jsonb_build_object('unprocessed', 231, 'held', jsonb_build_object('code', 'skipped_provider', 'reason', 'skip list'),
                     'blocked', jsonb_build_object('code', 'skipped_provider', 'words', 'This university is on the search skip list', 'fix', 'Settings › Pipeline settings › search.skip_providers')), now() - interval '19 hours'),
 ('40000000-0000-0000-0000-000000000003', 'course_page_find', 'running', jsonb_build_object('provider_id', (select id from u where k = 'P8')),
  jsonb_build_object('unprocessed', 3), now() - interval '1 hour');
do $$
declare v jsonb; v_reset timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC' + interval '1 day'; w pipeline.work_items; v_q int;
begin
  perform fx.ok((security.course_search_paid_cap_v1()->>'code') = 'daily_cap' and (security.course_search_paid_cap_v1()->>'resumes_at')::timestamptz = v_reset,
                'F3: the day''s picked-courses cap is seen, with its reset at 00:00 UTC');
  select count(*) into v_q from pipeline.course_link_search where state = 'queued';
  v := security.page_find_continuity_v1();
  perform fx.ok((v->>'ended_cannot_run')::int = 1 and (select state from pipeline.admin_jobs where id = '40000000-0000-0000-0000-000000000002') = 'failed'
                and (select outcome from pipeline.admin_jobs where id = '40000000-0000-0000-0000-000000000002') = 'blocked_policy'
                and (select error from pipeline.admin_jobs where id = '40000000-0000-0000-0000-000000000002') like 'Cannot run: This university is on the search skip list%',
                'F3: a skip-listed task ends at once, failed, with its blocker (not held for 24 hours)');
  perform fx.ok(exists (select 1 from pipeline.work_items where lane = 'page_find' and entity = (select id::text from u where k = 'P6') and failure_class = 'authority' and stage = 'parked'),
                'F3: the cannot-run blocker is recorded for a Platform Admin decision');
  select * into w from pipeline.work_items where lane = 'page_find' and entity = (select id::text from u where k = 'P7') and work_kind = 'find';
  perform fx.ok(w.stage = 'deferred' and w.failure_class = 'budget_exhausted' and w.next_eligible_at = v_reset and w.attempts = 0,
                'F3: the capped task is parked as budget exhausted, next eligible at the cap reset, no attempt used');
  perform fx.ok((select stage from pipeline.work_items where lane = 'page_find' and entity = '*lane') = 'lane_paused'
                and (select next_eligible_at from pipeline.work_items where lane = 'page_find' and entity = '*lane') = v_reset,
                'F3: only the paid page_find lane pauses, until the reset');
  perform fx.ok((select state from pipeline.admin_jobs where id = '40000000-0000-0000-0000-000000000001') = 'running',
                'F3: wc.page_find_release_on 0: the parked task stays running (release ships off)');
  v := security.page_find_continuity_v1();
  perform fx.ok((v->>'parked')::int = 0 and (select repeat_count from pipeline.work_items where id = w.id) = 0, 'F3: an unchanged park is not reported again');
  perform fx.setn('wc.page_find_release_on', '1');
  v := security.page_find_continuity_v1();
  perform fx.ok((v->>'released')::int = 1 and (select state from pipeline.admin_jobs where id = '40000000-0000-0000-0000-000000000001') = 'failed'
                and (select outcome from pipeline.admin_jobs where id = '40000000-0000-0000-0000-000000000001') = 'deferred_dependency'
                and (select error from pipeline.admin_jobs where id = '40000000-0000-0000-0000-000000000001') like 'Parked: %stay queued%',
                'F3: released, the parked task ends (deferred_dependency) and gives back its plan slot');
  perform fx.ok((select count(*) from pipeline.course_link_search where state = 'queued') = v_q, 'F3: no queued search is removed or sent by the park');
  perform fx.ok((select state from pipeline.admin_jobs where id = '40000000-0000-0000-0000-000000000003') = 'running', 'F3: a task that is moving is left alone');
  -- the cap resets: the lane and the item come back by themselves (job work-continuity), and the next task moving is a recovery
  update pipeline.course_link_search set sent_at = now() - interval '2 days' where sent_at is not null;
  update pipeline.work_items set next_eligible_at = now() - interval '1 minute' where lane = 'page_find' and stage in ('deferred', 'lane_paused');
  perform security.work_continuity_tick_v1();
  perform fx.ok((select stage from pipeline.work_items where lane = 'page_find' and entity = '*lane') = 'done'
                and (select stage from pipeline.work_items where id = w.id) = 'eligible', 'F3: after the reset the lane resumes and the parked work is eligible again');
  insert into pipeline.admin_jobs(id, kind, state, args, result, started_at) values ('40000000-0000-0000-0000-000000000004', 'course_page_find', 'running',
    jsonb_build_object('provider_id', (select id from u where k = 'P7')), jsonb_build_object('unprocessed', 5), now());
  v := security.page_find_continuity_v1();
  perform fx.ok((v->>'recovered')::int = 1 and (select stage from pipeline.work_items where id = w.id) = 'done'
                and (select recovered_at from pipeline.work_items where id = w.id) is not null, 'F3: the re-planned task moving again records the recovery');
  perform fx.setn('wc.page_find_release_on', '0');
end $$;

-- F9: the fee reader works page by page
do $$
declare v jsonb;
begin
  update pipeline.fee_reader_queue set state = 'leased', leased_until = now() + interval '3 minutes';
  insert into pipeline.fee_reader_queue(provider_id, state, fact_source_id, content_hash) values ((select id from u where k = 'P5'), 'queued', gen_random_uuid(), 'h2');
  v := security.fee_reader_tick_v1();
  perform fx.ok((v->>'worker')::int = 0, 'F9 switch off: a live lease anywhere holds the fee worker (as before)');
  perform fx.setn('wc.fee_item_claims_on', '1');
  v := security.fee_reader_tick_v1();
  perform fx.ok((v->>'worker')::int = 1, 'F9: with page claims, a due page is read while another page is leased');
  perform fx.setn('wc.fee_live_leases_max', '1');
  v := security.fee_reader_tick_v1();
  perform fx.ok((v->>'worker')::int = 0, 'F9: no more than wc.fee_live_leases_max pages leased at once');
  perform fx.setn('wc.fee_item_claims_on', '0');
end $$;

-- F9: course page searches isolated and capped
insert into pipeline.course_link_recipes values ((select id from u where k = 'P4'), true, 'p4.example');
insert into net._http_response(id, status_code, content) values
 (9001, 200, '{"data": [{"url": "https://p4.example/good"}]}'), (9002, 200, '{not json'), (9003, 200, '{"data": [{"url": "https://p4.example/refuse"}]}');
insert into pipeline.course_link_search(course_id, provider_id, stage, state, attempts, req_id, sent_at, queued_at) values
 ('50000000-0000-0000-0000-000000000001', (select id from u where k = 'P4'), 'title', 'sent', 0, 9001, now(), now()),
 ('50000000-0000-0000-0000-000000000002', (select id from u where k = 'P4'), 'title', 'sent', 0, 9002, now(), now()),
 ('50000000-0000-0000-0000-000000000003', (select id from u where k = 'P4'), 'title', 'sent', 0, 9003, now(), now()),
 ('50000000-0000-0000-0000-000000000004', (select id from u where k = 'P4'), 'title', 'sent', 0, 9999, now() - interval '30 minutes', now()),
 ('50000000-0000-0000-0000-000000000005', (select id from u where k = 'P4'), 'title', 'sent', 2, 9998, now() - interval '30 minutes', now());
do $$
declare v jsonb; v_failed boolean := false;
begin
  perform fx.setn('wc.link_search_continuity_on', '0');
  begin
    v := security.course_link_search_tick_v1(40);
  exception when others then v_failed := true;
  end;
  perform fx.ok(v_failed, 'F9 switch off: one bad answer body stops the whole run (as before)');
  perform fx.setn('wc.link_search_continuity_on', '1');
  v := security.course_link_search_tick_v1(40);
  perform fx.ok((v->>'found')::int = 1 and (select state from pipeline.course_link_search where course_id = '50000000-0000-0000-0000-000000000001') = 'found',
                'F9: the good search is harvested and bound although two others fail in the same run');
  perform fx.ok((select count(*) from pipeline.course_link_search where course_id in ('50000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000003')
                   and state = 'queued' and attempts = 1) = 2 and (v->>'failed')::int = 2,
                'F9: the bad body and the bind refusal set back only their own search (one attempt each)');
  perform fx.ok((select count(*) from pipeline.work_items where lane = 'course_link_search' and stage = 'retry_wait'
                   and entity in ('50000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000003')) = 2, 'F9: both failures recorded with a next attempt');
  perform fx.ok((select state || attempts from pipeline.course_link_search where course_id = '50000000-0000-0000-0000-000000000004') = 'sent1'
                and (select stage from pipeline.work_items where lane = 'course_link_search' and entity = '50000000-0000-0000-0000-000000000004') = 'retry_wait',
                'F9: an unanswered search is recorded once and not re-sent before its next attempt');
  perform fx.ok((select state || attempts from pipeline.course_link_search where course_id = '50000000-0000-0000-0000-000000000005') = 'error3'
                and (select stage from pipeline.work_items where lane = 'course_link_search' and entity = '50000000-0000-0000-0000-000000000005') = 'parked',
                'F9: a search unanswered for the third send ends in error and is parked (the send cap)');
  v := security.course_link_search_tick_v1(40);
  perform fx.ok((select state || attempts from pipeline.course_link_search where course_id = '50000000-0000-0000-0000-000000000004') = 'sent1',
                'F9: the next run before the backoff neither counts nor re-sends it');
  update pipeline.work_items set next_eligible_at = now() - interval '1 minute' where lane = 'course_link_search' and entity = '50000000-0000-0000-0000-000000000004';
  v := security.course_link_search_tick_v1(40);
  perform fx.ok((select state || attempts from pipeline.course_link_search where course_id = '50000000-0000-0000-0000-000000000004') = 'queued1' and (v->>'resent')::int = 1,
                'F9: once due it is queued again for the search lane');
end $$;

-- F2: the governed issue writer maps values its checks refuse
do $$
declare v jsonb; i pipeline.integration_issues;
begin
  v := security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'fx:identity', 'title', 'fixture', 'root_cause_class', 'data', 'workstream', 'G',
         'validation_layer', 'V9', 'evidence', jsonb_build_object('a', 1)), 'provider-identity-check');
  select * into i from pipeline.integration_issues where id = (v->>'id')::bigint;
  perform fx.ok(v->>'action' = 'created' and i.root_cause_class = 'unclassified' and i.workstream = 'A10' and i.validation_layer = 'manual',
                'F2: root_cause_class data, workstream G and validation layer V9 are mapped (unclassified, A10, manual) instead of raising');
  perform fx.ok(i.evidence->'unmapped' = '{"root_cause_class": "data", "workstream": "G", "validation_layer": "V9"}'::jsonb and (i.evidence->>'a')::int = 1,
                'F2: the values sent are kept in evidence.unmapped beside the evidence');
  v := security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'fx:valid', 'root_cause_class', 'data_drift', 'workstream', 'A3', 'validation_layer', 'V3'), 'fx');
  select * into i from pipeline.integration_issues where id = (v->>'id')::bigint;
  perform fx.ok(i.root_cause_class = 'data_drift' and i.workstream = 'A3' and i.validation_layer = 'V3' and not (i.evidence ? 'unmapped'), 'F2: allowed values are kept as sent');
  begin
    perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'fx:sev', 'severity', 'P9'), 'fx');
    perform fx.ok(false, 'F2: an unknown severity still raises');
  exception when sqlstate '22023' then perform fx.ok(true, 'F2: an unknown severity still raises (a programming error, not a value to map)');
  end;
end $$;

-- the switches as shipped, and nothing spent or admitted by this change
do $$
begin
  perform fx.ok((select count(*) from pipeline.platform_toolset_settings where key in ('wc.page_find_park_on', 'wc.page_find_never_end_on', 'wc.link_search_continuity_on')
                   and value = to_jsonb(1)) = 3, 'shipped ON: the park record, ending tasks that can never run, search isolation and cap');
  perform fx.ok((select count(*) from cron.job where jobname = 'work-continuity-lanes' and command !~ '(^|[^a-z_0-9])[0-9]+') = 1
                and exists (select 1 from pipeline.automation_catalogue where jobname = 'work-continuity-lanes'), 'G1/G2: the job is catalogued and its command has no number');
end $$;
