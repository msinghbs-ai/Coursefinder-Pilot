-- CF-247 P0 Layer 4 readiness and admission throughput: every case after the migration (seed.sql). Each block raises on failure and prints
-- "<id> ok". Shipped switches: readiness and verification on; arrival guard and settling off.
create temporary table fx_before as
  select (select count(*) from pipeline.layer4_decisions) decisions,
         (select md5(string_agg(entity || entity_id || field || coalesce(mode, '') || set_at, '|' order by entity, entity_id, field)) from pipeline.manual_locks) locks,
         (select md5(string_agg(id || status, '|' order by id)) from pipeline.layer4_review_items where status <> 'pending') decided,
         (select md5(string_agg(c::text, '|' order by c.id)) from catalogue.course_links c) links,
         (select md5(string_agg(f::text, '|' order by f.id)) from catalogue.course_fees f) fees;

-- R1 shipped as decided: readiness and verification on, arrival guard and settling off; the job is catalogued and scheduled without a number
do $f$
begin
  if security.pipeline_num_v1('layer4.readiness_on', -1) <> 1 or security.pipeline_num_v1('layer4.verify_on', -1) <> 1
     or security.pipeline_num_v1('layer4.arrival_guard_on', -1) <> 0 or security.pipeline_num_v1('layer4.reconcile_supersede_on', -1) <> 0 then raise exception 'R1: switches'; end if;
  if (select command from cron.job where jobname = 'layer4-readiness') <> 'select security.layer4_readiness_tick_v1()'
     or (select schedule from cron.job where jobname = 'layer4-readiness') <> '22,52 * * * *'
     or not exists (select 1 from pipeline.automation_catalogue where jobname = 'layer4-readiness') then raise exception 'R1: job'; end if;
  if (select array_agg(tgname order by tgname) from pg_trigger where tgrelid = 'pipeline.layer4_review_items'::regclass and not tgisinternal and (tgname like '%arrival' or tgname in ('layer4_review_items_reroute', 'ops_guard_layer4')))
     <> array['layer4_review_items_reroute', 'layer4_review_items_zz_arrival', 'ops_guard_layer4']::name[] then raise exception 'R1: trigger order'; end if;
  raise notice 'R1 ok: readiness and verification on, arrival guard and settling off; job catalogued; trigger after reroute, before the ops guard';
end $f$;

-- I1 identity: the same page however written; a fee keyed on amount, currency, basis, year and audience; matrix items keyed on their source
do $f$
begin
  if security.layer4_url_key_v1('HTTPS://www.Uni.example/c5/#top') <> 'uni.example/c5' or security.layer4_url_key_v1('http://uni.example/c5') <> 'uni.example/c5' then raise exception 'I1: url'; end if;
  if security.layer4_value_key_v1('provider_current_tuition_validation', '{"amount": 9913.62, "currency_code": "NZD", "basis": "indicative_annual", "fee_year": 2027, "checks": {}}')
     <> security.layer4_value_key_v1('provider_current_tuition_validation', '{"amount": "9913.620", "currency": "nzd", "basis": "Indicative_annual", "fee_year": "2027"}') then raise exception 'I1: fee'; end if;
  if security.layer4_value_key_v1('provider_current_tuition_validation', '{"amount": 100, "currency_code": "AUD", "basis": "annual"}')
     = security.layer4_value_key_v1('provider_current_tuition_validation', '{"amount": 100, "currency_code": "AUD", "basis": "annual", "fee_year": 2027}') then raise exception 'I1: a missing year shifted the key'; end if;
  if security.layer4_scope_key_v1('entry_matrix_first_run', '{"entry_matrix_source_id": "s1"}', '{}') = security.layer4_scope_key_v1('entry_matrix_first_run', '{"entry_matrix_source_id": "s2"}', '{}')
     or security.layer4_scope_key_v1('official_course_url', '{"x": 1}', '{}') <> '' then raise exception 'I1: scope'; end if;
  raise notice 'I1 ok: identity keys (page, fee, matrix source)';
end $f$;

-- C1 classification on the first run: what is ready for judgement, what is blocked and why, what the platform could settle
do $f$
declare r jsonb; v text;
begin
  r := security.layer4_readiness_tick_v1();
  for v in select x.item_id || ' ' || x.field_code || ' ' || x.readiness || ' ' || array_to_string(x.reasons, ',') || ' ' || x.route from pipeline.layer4_item_readiness x order by x.item_id loop
    raise notice 'C1 %', v; end loop;
  if (r->>'classified')::int <> 19 then raise exception 'C1: classified % (run %)', r->>'classified', r; end if;
  if (select readiness || ':' || route from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000001') <> 'judgement_ready:review:curator' then raise exception 'C1: i1'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') || ':' || route from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000002')
     <> 'technical_blocked:invalid_link:repair:invalid_link' then raise exception 'C1: i2 http address'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000003') <> 'technical_blocked:invalid_link' then raise exception 'C1: i3 social site'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000004') <> 'technical_blocked:manual_lock' then raise exception 'C1: i4 lock'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') || ':' || (resolution->>'covered_by_item') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000005')
     <> 'resolvable:decided_before:10000000-0000-0000-0000-000000000005' then raise exception 'C1: i5 approved before (IQ-00039 shape)'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000006') <> 'resolvable:entity_retired' then raise exception 'C1: i6 retired course (IQ-00061)'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000007') <> 'resolvable:covered_by_active' then raise exception 'C1: i7 already active'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') || ':' || (resolution->'evidence'->>'same_evidence') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000008')
     <> 'resolvable:decided_before:same page content' then raise exception 'C1: i8 rejected fee re-raised (IQ-00040 shape)'; end if;
  if (select readiness from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000009') <> 'judgement_ready' then raise exception 'C1: i9 new evidence must stay for a person'; end if;
  if (select readiness || ':' || route from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000010') <> 'judgement_ready:review:platform_admin'
     or (select readiness || ':' || array_to_string(reasons, ',') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000011') <> 'technical_blocked:completeness_gate' then
    raise exception 'C1: matrix sources (IQ-00038 shape: two sources, not duplicates)'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000012') <> 'technical_blocked:completeness_gate'
     or (select blockers->0->>'why' from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000012') not like 'the reader cut 2 requirement%' then raise exception 'C1: i12 gate'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000013') <> 'technical_blocked:nothing_to_admit' then raise exception 'C1: i13'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000014') <> 'technical_blocked:value_moved' then raise exception 'C1: i14'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') || ':' || (resolution->>'covered_by_item') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000016')
     <> 'resolvable:duplicate_pending:20000000-0000-0000-0000-000000000015' or (select readiness from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000015') <> 'judgement_ready' then
    raise exception 'C1: duplicate (the later one is the repeat, the first stays)'; end if;
  if (select readiness || ':' || array_to_string(reasons, ',') from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000017') <> 'technical_blocked:evidence_stale' then raise exception 'C1: i17 stale page'; end if;
  if (select readiness from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000018') <> 'judgement_ready' then raise exception 'C1: i18'; end if;
  if (select readiness from pipeline.layer4_item_readiness where item_id = '20000000-0000-0000-0000-000000000019') <> 'judgement_ready' then raise exception 'C1: i19 a newer copy is new evidence while the switch is off'; end if;
  if (r->>'gates')::int <> 4 then raise exception 'C1: gates evaluated %', r->>'gates'; end if;
  raise notice 'C1 ok: 19 items classified (judgement-ready, blocked with the blocker and repair route, resolvable with the covering item)';
end $f$;

-- C2 with settling off nothing was decided or superseded: every item still waits; no decision, lock, link or fee changed
do $f$
begin
  if exists (select 1 from pipeline.layer4_review_items where id::text like '20000000%' and status <> 'pending') or exists (select 1 from pipeline.layer4_supersessions) then raise exception 'C2: something was settled while off'; end if;
  if (select decisions from fx_before) <> (select count(*) from pipeline.layer4_decisions) then raise exception 'C2: a decision was written'; end if;
  if (select locks from fx_before) <> (select md5(string_agg(entity || entity_id || field || coalesce(mode, '') || set_at, '|' order by entity, entity_id, field)) from pipeline.manual_locks) then raise exception 'C2: locks'; end if;
  if (select links from fx_before) <> (select md5(string_agg(c::text, '|' order by c.id)) from catalogue.course_links c)
     or (select fees from fx_before) <> (select md5(string_agg(f::text, '|' order by f.id)) from catalogue.course_fees f) then raise exception 'C2: catalogue changed'; end if;
  raise notice 'C2 ok: settling off: all 19 items still wait; no decision, lock, link or fee changed';
end $f$;

-- C3 the gate budget: a second run within the recheck time reclassifies nothing and calls no gate
do $f$
declare r jsonb; v_calls int := (select count(*) from fx.gate_calls);
begin
  r := security.layer4_readiness_tick_v1();
  if (r->>'classified')::int <> 0 or (select count(*) from fx.gate_calls) <> v_calls then raise exception 'C3: %', r; end if;
  update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.gate_batch';
  update pipeline.layer4_item_readiness set classified_at = now() - interval '3 hours', gate_checked_at = now() - interval '3 hours';
  r := security.layer4_readiness_tick_v1();
  if (r->>'gates')::int <> 1 or (select count(*) from fx.gate_calls) <> v_calls + 1 then raise exception 'C3: gate batch % calls %', r->>'gates', (select count(*) from fx.gate_calls) - v_calls; end if;
  -- a held read not re-evaluated this run keeps its last gate result
  if (select count(*) from pipeline.layer4_item_readiness where readiness = 'technical_blocked' and 'completeness_gate' = any (reasons)) <> 2 then raise exception 'C3: a held read was released without a gate'; end if;
  update pipeline.platform_toolset_settings set value = '20' where key = 'layer4.gate_batch';
  raise notice 'C3 ok: nothing reclassified inside the recheck time; layer4.gate_batch bounds gate calls; an unevaluated hold keeps holding';
end $f$;

-- V1 every approval is checked: in the catalogue and on the website projection
do $f$
declare v text;
begin
  for v in select decision_id || ' ' || field_code || ' ' || result || ' ' || coalesce(reason, '') from pipeline.layer4_admission_checks order by decision_id loop raise notice 'V1 %', v; end loop;
  if (select result from pipeline.layer4_admission_checks where decision_id = 'd0000000-0000-0000-0000-000000000001') <> 'admitted_published' then raise exception 'V1: c20'; end if;
  if (select result || ':' || reason from pipeline.layer4_admission_checks where decision_id = 'd0000000-0000-0000-0000-000000000002') <> 'not_admitted:manual_lock_kept' then raise exception 'V1: c21 (the 17 Oct lock case)'; end if;
  if (select result || ':' || reason from pipeline.layer4_admission_checks where decision_id = 'd0000000-0000-0000-0000-000000000003') <> 'admitted_not_published:projection_shows_another_page' then raise exception 'V1: c22'; end if;
  if (select result from pipeline.layer4_admission_checks where decision_id = 'd0000000-0000-0000-0000-000000000004') <> 'admitted_published' then raise exception 'V1: c23 fee'; end if;
  if (select result from pipeline.layer4_admission_checks where decision_id = 'd0000000-0000-0000-0000-000000000005') <> 'admitted' then raise exception 'V1: c24 rows'; end if;
  if exists (select 1 from pipeline.layer4_admission_checks where decision_id = 'd0000000-0000-0000-0000-000000000006') then raise exception 'V1: a rejection was checked'; end if;
  if (select result from pipeline.layer4_admission_checks where decision_id = 'd0000000-0000-0000-0000-000000000007') <> 'waiting' then raise exception 'V1: c26 young'; end if;
  if (select result || ':' || reason from pipeline.layer4_admission_checks where decision_id = 'd0000000-0000-0000-0000-000000000008') <> 'superseded_later:rows_replaced_or_withdrawn' then raise exception 'V1: c28 withdrawn rows'; end if;
  if (select result from pipeline.layer4_admission_checks where decision_id = 'd0000000-0000-0000-0000-000000000009') <> 'not_checked' then raise exception 'V1: c29 scalar fee path'; end if;
  if (select lag_seconds from pipeline.layer4_admission_checks where decision_id = 'd0000000-0000-0000-0000-000000000001') is null then raise exception 'V1: lag'; end if;
  raise notice 'V1 ok: admitted and shown; lock kept (approval never took effect); admitted but the projection shows another page; fee; rows; withdrawn rows are superseded later, not a failure; young approval waits';
end $f$;

-- V2 one issue per kind and reason; the lock case is a decision (P2), the projection case a defect (P1); a second run updates, never duplicates
do $f$
begin
  if (select count(*) from pipeline.integration_issues where fingerprint like 'l4\_not\_%') <> 2 then raise exception 'V2: issues %', (select array_agg(fingerprint) from pipeline.integration_issues where fingerprint like 'l4\_not\_%'); end if;
  if (select severity || ':' || root_cause_class from pipeline.integration_issues where fingerprint = 'l4_not_admitted:official_course_url:manual_lock_kept') <> 'P2:human_decision' then raise exception 'V2: lock issue'; end if;
  if (select severity || ':' || root_cause_class from pipeline.integration_issues where fingerprint = 'l4_not_published:official_course_url:projection_shows_another_page') <> 'P1:code_defect' then raise exception 'V2: projection issue'; end if;
  perform security.layer4_readiness_tick_v1();
  if (select count(*) from pipeline.integration_issues where fingerprint like 'l4\_not\_%') <> 2 then raise exception 'V2: duplicated'; end if;
  raise notice 'V2 ok: two issues (lock kept: P2 decision; not on the website: P1), not duplicated by a second run';
end $f$;

-- O1 the operations controller diagnoses with the registered causes: the lock case needs a decision; the projection case gets the automatic
-- re-check; A's l4_* issues get the specific Layer 4 causes (matrix "duplicates" are a check-key defect; repeats and orphans need the switch)
do $f$
declare v text; r jsonb;
begin
  perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'l4_duplicate:entry_matrix_first_run', 'title', 'Duplicate pending Layer 4 items (entry_matrix_first_run)', 'layer', 'Layer 4',
    'failure', '24 pending items in 2 group(s) share the same entity and field', 'source', 'integration-validate', 'validation_layer', 'V4', 'severity', 'P1', 'root_cause_class', 'code_defect', 'workstream', 'A4'), 'integration-validate');
  perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'l4_regenerated:provider_current_tuition_validation', 'title', 'Layer 4 items regenerated after a decision (provider_current_tuition_validation)',
    'layer', 'Layer 4', 'failure', '50 pending item(s) propose the same value', 'source', 'integration-validate', 'validation_layer', 'V4', 'severity', 'P1', 'root_cause_class', 'code_defect', 'workstream', 'A4'), 'integration-validate');
  perform security.integration_issue_upsert_v1(jsonb_build_object('fingerprint', 'l4_orphan:official_course_url', 'title', 'Orphan pending Layer 4 items (official_course_url)',
    'layer', 'Layer 4', 'failure', '28 pending item(s) whose course or provider is missing', 'source', 'integration-validate', 'validation_layer', 'V4', 'severity', 'P1', 'root_cause_class', 'lifecycle_leak', 'workstream', 'A5'), 'integration-validate');
  r := security.ops_controller_tick_v1();
  for v in select fingerprint || ' -> ' || coalesce(diagnosis->>'root_cause', '-') || ' / ' || coalesce(ops_state, '-') || ' / ' || coalesce(remedy_code, '-') from pipeline.integration_issues
            where fingerprint like 'l4\_%' order by fingerprint loop raise notice 'O1 %', v; end loop;
  if (select diagnosis->>'root_cause' || ':' || ops_state || ':' || remedy_code from pipeline.integration_issues where fingerprint = 'l4_not_admitted:official_course_url:manual_lock_kept')
     <> 'layer4_approval_lock_conflict:needs_decision:layer4_lock_conflict_decision' then raise exception 'O1: lock case'; end if;
  if (select diagnosis->>'root_cause' || ':' || ops_state || ':' || remedy_code from pipeline.integration_issues where fingerprint = 'l4_not_published:official_course_url:projection_shows_another_page')
     <> 'layer4_approval_not_published:verifying:layer4_admission_recheck' then raise exception 'O1: projection case'; end if;
  if (select diagnosis->>'root_cause' || ':' || ops_state from pipeline.integration_issues where fingerprint = 'l4_duplicate:entry_matrix_first_run') <> 'layer4_duplicate_distinct_sources:needs_release' then raise exception 'O1: matrix'; end if;
  if (select diagnosis->>'root_cause' || ':' || ops_state || ':' || remedy_code from pipeline.integration_issues where fingerprint = 'l4_regenerated:provider_current_tuition_validation')
     <> 'layer4_regenerated_after_decision:needs_decision:layer4_settle_switch_decision' then raise exception 'O1: regenerated'; end if;
  if (select diagnosis->>'root_cause' || ':' || ops_state from pipeline.integration_issues where fingerprint = 'l4_orphan:official_course_url') <> 'layer4_orphan_pending:needs_decision' then raise exception 'O1: orphan'; end if;
  if (select (security.ops_authorise_v1('layer4_admission_recheck')->>'permitted')::boolean) is not true
     or security.ops_authorise_v1('layer4_supersede_resolvable')->>'reason' <> 'remedy switched off' then raise exception 'O1: authorise'; end if;
  raise notice 'O1 ok: lock case -> needs_decision; projection -> automatic re-check acted; matrix -> check-key release; repeats and orphans -> the Platform Admin''s switch';
end $f$;

-- O2 the re-check is verified on a later controller run: still failing -> not closed; once the projection shows the page -> verified and closed
do $f$
declare v_issue bigint := (select id from pipeline.integration_issues where fingerprint = 'l4_not_published:official_course_url:projection_shows_another_page');
begin
  update pipeline.ops_remedy_runs set finished_at = now() - interval '2 hours' where issue_id = v_issue;
  update pipeline.integration_issues set next_action_at = now() - interval '1 minute' where id = v_issue;
  perform security.ops_controller_tick_v1();
  if (select status from pipeline.integration_issues where id = v_issue) = 'closed' then raise exception 'O2: closed while still failing'; end if;
  if (select result from pipeline.ops_remedy_runs where issue_id = v_issue order by id limit 1) <> 'verify_failed' then raise exception 'O2: run %', (select result from pipeline.ops_remedy_runs where issue_id = v_issue order by id limit 1); end if;
  -- the projection refreshes; the next run re-checks (action) and a later run verifies
  update search.course_documents set official_course_url = 'https://uni.example/c22' where course_id = 'c0000000-0000-0000-0000-000000000022';
  update pipeline.integration_issues set next_action_at = now() - interval '1 minute' where id = v_issue;
  perform security.ops_controller_tick_v1();
  if (select result from pipeline.layer4_admission_checks where decision_id = 'd0000000-0000-0000-0000-000000000003') <> 'admitted_published' then raise exception 'O2: the re-check did not record the pass'; end if;
  update pipeline.ops_remedy_runs set finished_at = now() - interval '2 hours' where issue_id = v_issue and result = 'acted';
  update pipeline.integration_issues set next_action_at = now() - interval '1 minute' where id = v_issue;
  perform security.ops_controller_tick_v1();
  if (select status || ':' || ops_state from pipeline.integration_issues where id = v_issue) <> 'closed:verified' then
    raise exception 'O2: %', (select status || ':' || coalesce(ops_state, '-') from pipeline.integration_issues where id = v_issue); end if;
  raise notice 'O2 ok: not closed while the page is not shown; re-checked, then verified on a later run and closed';
end $f$;

-- S1 settling on (the Platform Admin's switch): the platform supersedes what it can settle, with the reason and the covering item; it never
-- approves or rejects, never settles a re-raise with new evidence, entry reads or descriptions, and changes no lock, link or fee
do $f$
declare r jsonb; v text;
begin
  update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.reconcile_supersede_on';
  update pipeline.layer4_item_readiness set classified_at = now() - interval '3 hours';
  r := security.layer4_readiness_tick_v1();
  for v in select item_id || ' ' || reason || ' ' || coalesce(covered_by_item::text, '-') || ' ' || mode from pipeline.layer4_supersessions order by item_id loop raise notice 'S1 %', v; end loop;
  if (select array_agg(item_id::text order by item_id) from pipeline.layer4_supersessions) <> array['20000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000006',
       '20000000-0000-0000-0000-000000000007', '20000000-0000-0000-0000-000000000008', '20000000-0000-0000-0000-000000000016'] then raise exception 'S1: superseded set'; end if;
  if exists (select 1 from pipeline.layer4_review_items where id::text like '20000000%' and status not in ('pending', 'superseded')) then raise exception 'S1: an item was decided'; end if;
  if (select status from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000009') <> 'pending'
     or (select status from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000015') <> 'pending' then raise exception 'S1: new evidence or the first of a pair was settled'; end if;
  if (select change_control_ref from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000016') not like '%settled by the platform (duplicate_pending)' then raise exception 'S1: reason on the item'; end if;
  if (select decisions from fx_before) <> (select count(*) from pipeline.layer4_decisions)
     or (select locks from fx_before) <> (select md5(string_agg(entity || entity_id || field || coalesce(mode, '') || set_at, '|' order by entity, entity_id, field)) from pipeline.manual_locks)
     or (select links from fx_before) <> (select md5(string_agg(c::text, '|' order by c.id)) from catalogue.course_links c)
     or (select fees from fx_before) <> (select md5(string_agg(f::text, '|' order by f.id)) from catalogue.course_fees f) then raise exception 'S1: a decision, lock, link or fee changed'; end if;
  if (select count(*) from pipeline.layer4_item_readiness where readiness = 'closed') < 5 then raise exception 'S1: readiness not closed'; end if;
  if ((r->'reconcile'->>'superseded')::int) <> 5 then raise exception 'S1: run %', r; end if;
  -- a second run settles nothing more
  r := security.layer4_readiness_tick_v1();
  if ((r->'reconcile'->>'superseded')::int) <> 0 then raise exception 'S1: second run %', r; end if;
  raise notice 'S1 ok: 5 superseded (approved before, retired course, already active, rejected fee re-raised, repeat), each with its reason; no decision, lock, link or fee changed';
end $f$;

-- S2 the settle remedy runs inside workstream A's authority boundary: superseding is allowed, deciding is refused
do $f$
declare v_issue bigint := (select id from pipeline.integration_issues where fingerprint = 'l4_regenerated:provider_current_tuition_validation'); r jsonb;
begin
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, proposed_value, status, created_at)
  values ('20000000-0000-0000-0000-000000000030', 'course', 'c0000000-0000-0000-0000-000000000007', 'provider_current_tuition_validation', 'e0000000-0000-0000-0000-000000000001',
          '{"basis": "indicative_annual", "amount": 9913.62, "audience": "international", "fee_year": 2027, "currency_code": "NZD"}', 'pending', now());
  r := security.ops_call_v1('security.layer4_remedy_settle_v1(bigint)'::regprocedure, v_issue);
  if not coalesce((r->>'ok')::boolean, false) or (r->'evidence'->>'superseded')::int <> 1 then raise exception 'S2: settle under the guard %', r; end if;
  -- the same boundary refuses a decision
  perform set_config('cf247.ops_remedy', 'on', true);
  begin
    update pipeline.layer4_review_items set status = 'approved' where id = '20000000-0000-0000-0000-000000000001';
    raise exception 'S2: an approval passed the guard';
  exception when insufficient_privilege then null;
  end;
  perform set_config('cf247.ops_remedy', '', true);
  -- with the switch off the remedy refuses and says why
  update pipeline.platform_toolset_settings set value = '0' where key = 'layer4.reconcile_supersede_on';
  r := security.ops_call_v1('security.layer4_remedy_settle_v1(bigint)'::regprocedure, v_issue);
  if coalesce((r->>'ok')::boolean, true) or r->'evidence'->>'reason' not like 'layer4.reconcile_supersede_on is 0%' then raise exception 'S2: off %', r; end if;
  update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.reconcile_supersede_on';
  raise notice 'S2 ok: the remedy supersedes inside A''s boundary; an approval is refused there; with the switch off it refuses and says why';
end $f$;

-- S3 the Platform Admin's choice: a newer copy of the same page address with the same rejected value counts as already decided
do $f$
declare r jsonb;
begin
  if (select status from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000019') <> 'pending' then raise exception 'S3: settled while off'; end if;
  update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.same_page_new_copy_settles';
  r := security.layer4_reconcile_v1('provider_current_tuition_validation', 100);
  if (select status from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000019') <> 'superseded'
     or (select evidence->>'same_evidence' from pipeline.layer4_supersessions where item_id = '20000000-0000-0000-0000-000000000019') <> 'same page address, newer copy' then raise exception 'S3: %', r; end if;
  if (select status from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000009') <> 'pending' then raise exception 'S3: a different page address was settled'; end if;
  update pipeline.platform_toolset_settings set value = '0' where key = 'layer4.same_page_new_copy_settles';
  raise notice 'S3 ok: off: a newer copy waits for a person; on: settled as decided before (same page address, newer copy); another address still waits';
end $f$;

-- A1 the arrival guard (on): a repeat arrives settled, after the reroute trigger; a new question and a non-platform kind still wait
do $f$
begin
  update pipeline.platform_toolset_settings set value = '1' where key = 'layer4.arrival_guard_on';
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value, status)
  values ('20000000-0000-0000-0000-000000000040', 'course', 'c0000000-0000-0000-0000-000000000001', 'official_course_url', '{"course_url": "https://www.uni.example/c1/"}', 'pending'),
         ('20000000-0000-0000-0000-000000000041', 'course', 'c0000000-0000-0000-0000-000000000027', 'official_course_url', '{"course_url": "https://uni.example/c27"}', 'pending'),
         ('20000000-0000-0000-0000-000000000042', 'course', 'c0000000-0000-0000-0000-000000000017', 'course_description_first_read',
          '{"description": "Course seventeen is taught online.", "sentences": [{"text": "Course seventeen is taught online.", "quote": "Course seventeen is taught online."}], "item_id": 7}', 'pending');
  if (select status from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000040') <> 'superseded'
     or (select reason || ':' || covered_by_item || ':' || mode from pipeline.layer4_supersessions where item_id = '20000000-0000-0000-0000-000000000040')
        <> 'duplicate_pending:20000000-0000-0000-0000-000000000001:arrival' then raise exception 'A1: repeat'; end if;
  if (select status_seen from fx.trigger_order where item_id = '20000000-0000-0000-0000-000000000040') <> 'pending' then raise exception 'A1: reroute did not see it first'; end if;
  if (select status from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000041') <> 'pending'
     or (select status from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000042') <> 'pending' then raise exception 'A1: a new question or a description was settled'; end if;
  -- off again: a repeat waits
  update pipeline.platform_toolset_settings set value = '0' where key = 'layer4.arrival_guard_on';
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, proposed_value, status)
  values ('20000000-0000-0000-0000-000000000043', 'course', 'c0000000-0000-0000-0000-000000000001', 'official_course_url', '{"course_url": "https://uni.example/c1"}', 'pending');
  if (select status from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000043') <> 'pending' then raise exception 'A1: off'; end if;
  raise notice 'A1 ok: on: a repeat arrives superseded (after reroute); a new question and a description wait; off: a repeat waits';
end $f$;

-- X1 a supersession is reversed only by the Platform Admin, and the item waits again
do $f$
declare v_id bigint := (select id from pipeline.layer4_supersessions where item_id = '20000000-0000-0000-0000-000000000040');
begin
  update fx.caller set uid = 'e1000000-0000-0000-0000-000000000009', rank = 3;
  begin perform security.layer4_supersession_reverse_v1(v_id, 'not the same page after all'); raise exception 'X1: a curator reversed';
  exception when insufficient_privilege then null; end;
  update fx.caller set rank = 6;
  perform security.layer4_supersession_reverse_v1(v_id, 'not the same page after all');
  if (select status from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000040') <> 'pending'
     or (select reversed_at is null from pipeline.layer4_supersessions where id = v_id) then raise exception 'X1'; end if;
  update fx.caller set uid = null, rank = null;
  raise notice 'X1 ok: a curator is refused; the Platform Admin reverses; the item waits again; the record is kept';
end $f$;

-- T1 the reviewer-throughput view: ready items by kind with measured minutes, blocked by blocker, what the platform settled, admission results
do $f$
declare t jsonb;
begin
  perform security.layer4_readiness_tick_v1();
  t := security.layer4_throughput_v1();
  raise notice 'T1 %', t - 'last_run';
  if (t->'judgement_ready'->'official_course_url'->>'items')::int < 1 or t->'technical_blocked'->'official_course_url'->>'invalid_link' <> '2'
     or t->'technical_blocked'->'official_course_url'->>'manual_lock' <> '1' then raise exception 'T1: kinds'; end if;
  if (t->'pace'->'official_course_url'->>'basis') is null or (t->'judgement_ready'->'official_course_url'->>'minutes_per_item') is null then raise exception 'T1: pace'; end if;
  if (t->'resolved_by_platform'->'last_7d'->>'provider_current_tuition_validation:decided_before')::int <> 3 then raise exception 'T1: settled %', t->'resolved_by_platform'; end if;
  if t->'admission'->'official_course_url'->>'not_admitted:manual_lock_kept' <> '1' then raise exception 'T1: admission'; end if;
  if (select status from pipeline.layer4_review_items where id = '20000000-0000-0000-0000-000000000040') <> 'pending' then raise exception 'T1: a reversed item was settled again'; end if;
  if exists (select 1 from pipeline.layer4_item_readiness x join pipeline.layer4_review_items i on i.id = x.item_id where i.status = 'pending' and x.est_minutes is null) then raise exception 'T1: minutes missing'; end if;
  if (select count(*) from security.layer4_review_order_v1(null, 100) o where o.readiness = 'judgement_ready') < 1
     or (select readiness from security.layer4_review_order_v1(null, 1)) <> 'judgement_ready' then raise exception 'T1: order'; end if;
  raise notice 'T1 ok: throughput view (ready by kind with minutes, blocked by blocker, settled by the platform, admission results); judgement-ready first';
end $f$;

-- Z1 through every case: no decision was written, no lock touched, no link or fee changed
do $f$
begin
  if (select decisions from fx_before) <> (select count(*) from pipeline.layer4_decisions) then raise exception 'Z1: decisions'; end if;
  if (select locks from fx_before) <> (select md5(string_agg(entity || entity_id || field || coalesce(mode, '') || set_at, '|' order by entity, entity_id, field)) from pipeline.manual_locks) then raise exception 'Z1: locks'; end if;
  if (select links from fx_before) <> (select md5(string_agg(c::text, '|' order by c.id)) from catalogue.course_links c)
     or (select fees from fx_before) <> (select md5(string_agg(f::text, '|' order by f.id)) from catalogue.course_fees f) then raise exception 'Z1: catalogue'; end if;
  if exists (select 1 from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected') and id::text not like '10000000%' and id::text not like '40000000%') then raise exception 'Z1: an item was decided'; end if;
  raise notice 'Z1 ok: no decision written, no lock touched, no catalogue value changed by any case';
end $f$;
