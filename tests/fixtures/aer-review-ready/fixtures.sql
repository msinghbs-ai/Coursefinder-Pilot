-- CF-247 AER: one definition of "ready to decide" (migration 20261108040000): assertions on the production-shaped seed of ../aer-review-queue, after the
-- migration. Everything this file builds is rolled back at the end. Fixture data only.
\set ON_ERROR_STOP on
create or replace function fx.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is not true then raise exception 'FAILED: %', p_what; end if; raise notice 'ok: %', p_what; end $f$;

begin;
create temp table before_state as select (select count(*) from pipeline.layer4_review_items where status = 'pending') pending,
  (select count(*) from catalogue.course_entry_requirements where status = 'active') active, (select count(*) from pipeline.layer4_decisions) decisions,
  (select count(*) from pipeline.layer4_review_items where status <> 'pending') decided_items,
  security.pipeline_num_v1('aer.schedule_layer4_max', 600) lim, (select md5(string_agg(key || value::text, '|' order by key)) from pipeline.platform_toolset_settings) settings;

-- 1 one definition: the scheduling counts equal the Inbox (live: 245 ready to decide against the counter's 203) ------------------------------------
do $$
declare v jsonb := security.work_review_ready_v1('aer'); q jsonb := public.admin_layer4_aer_queue('{}'); n_ready int; n_dup int; n_stale int; n_exc int; n_held int;
begin
  select count(*) filter (where ready), count(*) filter (where duplicate_of is not null), count(*) filter (where settlement = 'stale'),
         count(*) filter (where ready and duplicate_of is null and review_class = 'approve_except'), count(*) filter (where settlement in ('recoverable', 'needs_input') and duplicate_of is null)
    into n_ready, n_dup, n_stale, n_exc, n_held from security.aer_review_ready_v1(null);
  perform fx.ok((q->>'ready')::int = n_ready and n_ready = (select count(*) from security.aer_settlement_v1(null) where settlement = 'ready'),
                format('aer_review_ready_v1 ready (%s) is the Inbox''s ready (%s) and the settlement''s', n_ready, q->>'ready'));
  perform fx.ok((v->>'ready_waiting')::int = n_ready - (select count(*) from security.aer_review_ready_v1(null) r where r.ready and r.duplicate_of is not null),
                format('the counter''s ready_waiting (%s) is the Inbox''s ready less true duplicates only', v->>'ready_waiting'));
  perform fx.ok((v->>'ready_waiting')::int + (v->>'technical')::int + (v->>'stale')::int + (v->>'resolvable')::int + (v->>'duplicates')::int = (v->>'raw_waiting')::int
                and (v->>'raw_waiting')::int = 605, format('every waiting item is in exactly one state (%s)', v - 'category' - 'in_progress'));
  perform fx.ok((v->>'approve_except')::int = n_exc and n_exc > 0, format('Approve except items are ready, counted apart (%s)', n_exc));
  perform fx.ok((v->>'stale')::int = (select count(*) from security.aer_review_ready_v1(null) where settlement = 'stale' and duplicate_of is null), 'stale reads are not ready');
  -- the university summary (what the Inbox shows) equals the single definition for every university
  perform fx.ok(not exists (select 1 from (select provider_id, count(*) filter (where ready) n from security.aer_review_ready_v1(null) group by 1) a
                             where (security.layer4_aer_university_summary_v1(a.provider_id)->>'review_ready')::int <> a.n), 'every university''s "ready to decide" equals the single definition');
  -- the provider share check reads it too
  perform fx.ok((select coalesce(sum(waiting), 0) from security.aer_provider_load_v1()) >= (v->>'ready_waiting')::int, 'the provider load counts the same ready items (plus reads in progress)');
end $$;

-- 2 live shapes built here: matrix runs from different pages are not duplicates; the same page twice is; stale, lock, new item ------------------------
create or replace function fx.mk_matrix(p_provider uuid, p_url text, p_gate jsonb) returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, proposed_value, created_at) values ('provider', p_provider, 'entry_matrix_first_run', jsonb_build_object('url', p_url, 'run_id', gen_random_uuid()::text), clock_timestamp())
    returning id into v;
  insert into fx.gate(item_id, g) values (v, p_gate);
  return v;
end $f$;
create or replace function fx.mk_course(p_provider uuid, p_key text, p_bound text, p_read text, p_gate jsonb, p_lifecycle text default 'active') returns uuid language plpgsql as $f$
declare c uuid := gen_random_uuid(); v uuid;
begin
  insert into catalogue.courses(id, stable_key, provider_id, canonical_title, lifecycle_status) values (c, p_key, p_provider, 'Fixture ' || p_key, p_lifecycle);
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, status) values (c, p_provider, p_bound, 'bound');
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, proposed_value, created_at) values ('course', c, 'course_entry_first_read', jsonb_build_object('url', p_read), clock_timestamp()) returning id into v;
  insert into fx.gate(item_id, g) values (v, p_gate);
  return v;
end $f$;
do $$
declare p uuid := (select id from catalogue.providers order by canonical_name limit 1); p2 uuid := (select id from catalogue.providers order by canonical_name offset 1 limit 1);
        okg jsonb := '{"rule": "D-R3", "rows": 3, "flagged": [], "reasons": [], "complete": true, "no_table": false, "same_identity": []}';
        exg jsonb := '{"rule": "D-R3", "rows": 3, "reasons": ["2 waiting row(s) cannot be admitted as read: leave them out with Approve except"], "complete": false, "flagged": [{"id": "r1"}, {"id": "r2"}], "same_identity": []}';
        cok jsonb := '{"rule": "E13", "reasons": [], "complete": true, "rows_cut": 0, "joined": [], "audience": [], "shared_page": [], "not_requirement": [], "other_programme": [], "drops_uncovered": []}';
        cex jsonb := '{"rule": "E13", "complete": false, "rows_cut": 0, "joined": [], "audience": [], "shared_page": [], "other_programme": [], "drops_uncovered": [], "reasons": ["1 waiting row(s) are not entry requirements: leave them out with Approve except"], "not_requirement": [{"id": "n1", "quote": "Credit for prior study"}]}';
        m1 uuid; m2 uuid; m3 uuid; m4 uuid; c_ok uuid; c_ex uuid; c_stale uuid; c_inactive uuid; c_lock uuid; c_new uuid; r record; b_ready int; b_pend int; v0 jsonb := security.work_review_ready_v1('aer');
begin
  select count(*) filter (where ready), count(*) into b_ready, b_pend from security.aer_review_ready_v1(null);
  -- matrix runs of one university from three different source pages (as ANU live: 24 runs, 24 urls) and one page read twice
  m1 := fx.mk_matrix(p, 'https://fx.example/m/a', okg); m2 := fx.mk_matrix(p, 'https://fx.example/m/b', okg); m3 := fx.mk_matrix(p, 'https://fx.example/m/c', exg);
  m4 := fx.mk_matrix(p, 'https://fx.example/m/a', okg);
  c_ok := fx.mk_course(p2, 'fx-ok', 'https://fx.example/c/ok', 'https://fx.example/c/ok', cok);
  c_ex := fx.mk_course(p2, 'fx-ex', 'https://fx.example/c/ex', 'https://fx.example/c/ex', cex);
  c_stale := fx.mk_course(p2, 'fx-stale', 'https://library.fx.example/archive/1', 'https://fx.example/c/stale', cok);
  c_inactive := fx.mk_course(p2, 'fx-inactive', 'https://fx.example/c/in', 'https://fx.example/c/in', cok, 'inactive');
  c_lock := fx.mk_course(p2, 'fx-lock', 'https://fx.example/c/lock', 'https://fx.example/c/lock', cok);
  insert into pipeline.manual_locks(entity, entity_id, field, mode) select 'course', entity_id, 'course_url', 'keep' from pipeline.layer4_review_items where id = c_lock;
  -- classify these as the readiness run does (the gate answers from fx.gate)
  perform security.layer4_readiness_items_v1(array[m1, m2, m3, m4, c_ok, c_ex, c_stale, c_inactive, c_lock]);
  select * into r from security.aer_review_ready_v1(null) where item_id = m1;
  perform fx.ok(r.ready and r.duplicate_of is null and r.review_class = 'complete', 'a matrix run with a complete gate is ready');
  perform fx.ok((select ready and duplicate_of is null from security.aer_review_ready_v1(null) where item_id = m2), 'a second matrix run of the university from another page is NOT a duplicate (live: ANU 22 runs, 22 pages)');
  perform fx.ok((select ready and duplicate_of is null and review_class = 'approve_except' and exception_rows = 2 from security.aer_review_ready_v1(null) where item_id = m3),
                'a matrix run whose gate names two rows to leave out is ready as Approve except with the 2 rows listed');
  perform fx.ok((select duplicate_of = m1 from security.aer_review_ready_v1(null) where item_id = m4), 'the same page read twice: the second is a duplicate of the older');
  perform fx.ok((select ready and review_class = 'approve_except' and exception_rows = 1 from security.aer_review_ready_v1(null) where item_id = c_ex), 'a course read with a row to leave out is ready (Approve except), the row listed');
  perform fx.ok((select readiness from pipeline.layer4_item_readiness where item_id = c_ex) = 'technical_blocked', 'the readiness table still calls it technical_blocked (the readiness table is not the definition of ready)');
  perform fx.ok((select not ready and settlement = 'stale' and review_class = 'stale' from security.aer_review_ready_v1(null) where item_id = c_stale)
                and (select readiness from pipeline.layer4_item_readiness where item_id = c_stale) = 'judgement_ready', 'a read of a page the course is no longer bound to is stale, not ready, although the readiness table says judgement_ready (live: Lincoln 3, VUW 1)');
  perform fx.ok((select not ready and settlement = 'stale' from security.aer_review_ready_v1(null) where item_id = c_inactive), 'a read of an inactive course is stale');
  perform fx.ok((select ready and url_locked from security.aer_review_ready_v1(null) where item_id = c_lock) and not (select url_locked from security.aer_review_ready_v1(null) where item_id = c_ok),
                'a lock on the course page address is reported (url_locked) and does not change whether the item is ready (a Platform Admin ruling)');
  -- the counter: duplicates one, stale two, Approve except two among ready
  declare v jsonb := security.work_review_ready_v1('aer'); q jsonb := public.admin_layer4_aer_queue('{}'); a int;
  begin
    perform fx.ok((v->>'duplicates')::int >= 1 and (q->>'ready')::int - (v->>'ready_waiting')::int = (select count(*) from security.aer_review_ready_v1(null) where ready and duplicate_of is not null),
                  'the counter and the Inbox differ only by true duplicates');
    perform fx.ok((select count(*) from security.aer_review_ready_v1(null) where ready) - b_ready = 7 and (v->>'ready_waiting')::int - (v0->>'ready_waiting')::int = 6
                   and (v->>'approve_except')::int - (v0->>'approve_except')::int = 2 and (v->>'stale')::int - (v0->>'stale')::int = 2,
                   'the Inbox gains 7 ready items, the counter 6 (the duplicate is not a second decision); 2 of them Approve except; 2 stale');
  exception when others then raise; end;
  -- nothing was made ready that a person had not been shown: Approve except items carry listed rows
  -- (live 8 Nov 2026: all 38 Approve except items list rows; the seed's matrix gates carry only the reason text, so the course reads are checked here)
  perform fx.ok(not exists (select 1 from security.aer_review_ready_v1(null) where ready and review_class = 'approve_except' and field_code = 'course_entry_first_read' and exception_rows = 0),
                'every Approve except course read in the seed lists at least one row to leave out');
  -- a held item is not ready
  perform fx.ok(not exists (select 1 from security.aer_review_ready_v1(null) where ready and settlement <> 'ready'), 'ready is the Inbox settlement and nothing else');
end $$;

-- 3 readiness for a new item (an item a replay has just created): assessed in the same call, not at the next run -----------------------------------
do $$
declare p uuid := (select id from catalogue.providers order by canonical_name offset 2 limit 1); c uuid; v uuid; res jsonb; n_gate_before int; ready_before int;
        cok jsonb := '{"rule": "E13", "reasons": [], "complete": true, "rows_cut": 0, "joined": [], "audience": [], "shared_page": [], "not_requirement": [], "other_programme": [], "drops_uncovered": []}';
begin
  v := fx.mk_course(p, 'fx-replay', 'https://fx.example/c/replay', 'https://fx.example/c/replay', cok);
  perform fx.ok(not exists (select 1 from pipeline.layer4_item_readiness where item_id = v), 'a new waiting item has no readiness row yet (live: null right after creation)');
  perform fx.ok((select settlement = 'recoverable' and not ready from security.aer_review_ready_v1(null) where item_id = v), 'until it is gated it is held, not ready (not yet checked by the completeness gate)');
  res := security.layer4_readiness_items_v1(array[v, gen_random_uuid()]);
  perform fx.ok((res->>'classified')::int = 1 and (res->>'gates')::int = 1, format('one call classifies it and evaluates its gate (%s)', res));
  perform fx.ok((select readiness = 'judgement_ready' and gate_checked_at is not null and (gate->>'complete')::boolean from pipeline.layer4_item_readiness where item_id = v), 'its readiness row is written with the gate result');
  perform fx.ok((select ready from security.aer_review_ready_v1(null) where item_id = v), 'and it is ready to decide');
  -- a second call inside the recheck window does not evaluate the gate again; a decided item is skipped
  select count(*) into n_gate_before from fx.gate_calls where item_id = v;
  res := security.layer4_readiness_items_v1(array[v]);
  perform fx.ok((res->>'gates')::int = 0 and (select count(*) from fx.gate_calls where item_id = v) = n_gate_before, 'a second call within the recheck time does not run the gate again');
  update pipeline.layer4_review_items set status = 'superseded' where id = v;
  perform fx.ok((security.layer4_readiness_items_v1(array[v])->>'classified')::int = 0, 'an item that is no longer waiting is skipped');
  -- the switch
  insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
    values ('pipeline', 'layer4.readiness_on', 'Layer 4 readiness: classify waiting items', 'fixture', 'number', to_jsonb(0), '0', '1', 'on (1) or off (0)', 1200, 'Layer 4 readiness', 'fixture', 'fixture')
    on conflict (toolset_key, key) do update set value = to_jsonb(0);
  perform fx.ok((security.layer4_readiness_items_v1(array[v])->>'switch') = 'off', 'layer4.readiness_on = 0 stops it');

end $$;

-- 4 nothing was decided, approved, admitted or changed by any of this ----------------------------------------------------------------------------
do $$
declare b record;
begin
  select * into b from before_state;
  perform fx.ok((select count(*) from catalogue.course_entry_requirements where status = 'active') = b.active and (select count(*) from pipeline.layer4_decisions) = b.decisions,
                'no admission and no decision was written');
  perform fx.ok(security.pipeline_num_v1('aer.schedule_layer4_max', 600) = b.lim, 'the limit (aer.schedule_layer4_max) is unchanged');
  perform fx.ok((select count(*) from pipeline.layer4_review_items where status <> 'pending' and status <> 'superseded') = b.decided_items, 'no item was approved or rejected');
end $$;
rollback;
select 'aer-review-ready fixtures: passed';
