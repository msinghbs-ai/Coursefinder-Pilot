-- Workstream B source recovery: every case after the migration (seed.sql; proof.feed_per_run 1). Blocks between begin and rollback leave the
-- state as it was. Each case raises on failure and prints "<id> ok".

-- F1 capacity (S1): beyond the run's free capacity a relinkable course waits for it, it is never recorded as needing paid search
do $f$
declare r jsonb;
begin
  r := security.source_proof_feed_v1();
  if (select route || ':' || state from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000001') <> 'relink:queued' then raise exception 'F1: course 1'; end if;
  if (select route || ':' || state || ':' || (detail->>'wait') from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000002') <> 'relink:held:free_capacity' then
    raise exception 'F1: course 2 is %', (select route || ':' || state from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000002'); end if;
  if exists (select 1 from pipeline.source_proof_requests q join pipeline.coverage_course_pages g on g.course_id = q.course_id where q.route = 'no_route' and g.read_status = 'identity_mismatch') then
    raise exception 'F1: an identity_mismatch course is no_route'; end if;
  if coalesce((r->'routed'->>'relink_wait')::int, 0) < 1 or (select outcome from pipeline.source_proof_feed_runs order by id desc limit 1) <> 'done' then raise exception 'F1: run %', r; end if;
  -- S3 default: relink.statuses ships today's value, so the E16-refused course 3 is still no_route
  if (select route from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000003') <> 'no_route' then raise exception 'F1: course 3 default'; end if;
  raise notice 'F1 ok: course 1 relinked, course 2 held for free capacity (routed %)', r->'routed';
end $f$;

-- F2 the course held for capacity is taken first in the next run
do $f$
begin
  perform security.source_proof_feed_v1();
  if (select route || ':' || state from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000002') <> 'relink:queued' then raise exception 'F2: course 2 not taken first'; end if;
  raise notice 'F2 ok: course 2 taken first in the next run';
end $f$;

-- F3 paid search is never queued for a course whose previous paid search left untried candidates (S7; shown with paid search set to 1)
begin;
do $f$
begin
  update pipeline.platform_toolset_settings set value = '5' where key = 'proof.search_per_run';
  update pipeline.platform_toolset_settings set value = '0' where key = 'proof.feed_per_run';
  update pipeline.source_proof_requests set considered_at = now() - interval '1 day' where course_id in ('c0000000-0000-0000-0000-000000000015', 'c0000000-0000-0000-0000-000000000005');
  perform security.source_proof_feed_v1();
  if (select route from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000015') = 'search' then raise exception 'F3: course 15 searched again'; end if;
  if (select route from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000005') <> 'search' then raise exception 'F3: course 5 (no stored candidates) should be searchable'; end if;
  raise notice 'F3 ok: no new paid search for course 15 (untried stored candidates); course 5 would be searched';
end $f$;
rollback;

-- F4 the D1 recovery cohort: entry, state per course, discovery step, fingerprint; a second run changes nothing
do $f$
declare r jsonb; r2 jsonb; s text;
begin
  r := security.field_absence_recovery_refresh_v1();
  for s in select fr.course_id || '=' || fr.state from pipeline.field_absence_recovery fr order by fr.course_id loop raise notice 'F4 state %', s; end loop;
  if (select state from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000003') <> 'free_route_refused_status' then raise exception 'F4: course 3'; end if;
  if (select state from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000004') <> 'free_route_provider_list' then raise exception 'F4: course 4 (Maori, Level 7)'; end if;
  if (select state from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000005') <> 'needs_authorised_read' then raise exception 'F4: course 5'; end if;
  if (select state || ':' || step from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000006') <> 'free_route_stored_search:6' then raise exception 'F4: course 6'; end if;
  if (select state from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000007') <> 'free_route_refused_status'
     or not (select 'canonical_year' = any (free_routes) from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000007') then raise exception 'F4: course 7'; end if;
  if (select state || ':' || searched_before || ':' || search_credits from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000011') <> 'needs_paid_research:true:4' then
    raise exception 'F4: course 11 %', (select state || ':' || search_credits from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000011'); end if;
  if (select state from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000013') <> 'free_route_capacity' then raise exception 'F4: course 13'; end if;
  if (select state from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000014') <> 'free_route_provider_list' then raise exception 'F4: course 14 (register title)'; end if;
  if (select state from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000015') <> 'free_route_stored_search' then raise exception 'F4: course 15'; end if;
  if exists (select 1 from pipeline.field_absence_recovery where course_id in ('c0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000012')) then raise exception 'F4: entered a course with a route'; end if;
  if exists (select 1 from pipeline.field_absence_recovery where fingerprint is null or refreshed_at is null) then raise exception 'F4: fingerprint'; end if;
  r2 := security.field_absence_recovery_refresh_v1();
  if (r2->>'state_changes')::int <> 0 or (r2->>'entered')::int <> 0 then raise exception 'F4: second run changed %', r2; end if;
  if exists (select 1 from pipeline.field_absence_recovery where fingerprint_changed_at < refreshed_at - interval '1 second') then raise exception 'F4: fingerprint moved'; end if;
  if (select count(*) from pipeline.field_absence_recovery_runs) <> 2 then raise exception 'F4: runs'; end if;
  raise notice 'F4 ok: % entered, states %; second run unchanged', r->>'entered', r->'states';
end $f$;

-- F5 the D1 decision table: measured credits and rates, read-only, paid search reported off
do $f$
declare d jsonb; x jsonb;
begin
  d := security.field_absence_d1_decision_v1();
  if (d->>'paid_search_enabled')::boolean then raise exception 'F5: paid search'; end if;
  if (d->'history'->'title'->>'courses')::int <> 3 or (d->'history'->'title'->>'credits_per_course')::numeric <> 2.67 or (d->'history'->'title'->>'verified_rate')::numeric <> 0.333 then
    raise exception 'F5: history %', d->'history'; end if;
  if (d->'history'->'repeat'->>'courses')::int <> 1 or (d->'history'->'repeat'->>'verified_rate')::numeric <> 0 then raise exception 'F5: repeat %', d->'history'->'repeat'; end if;
  select e into x from jsonb_array_elements(d->'rows') e where e->>'state' = 'needs_paid_research';
  if (x->>'courses')::int <> 1 or (x->>'expected_verified')::numeric <> 0 or x->>'credits_per_verified' is not null then raise exception 'F5: research row %', x; end if;
  select e into x from jsonb_array_elements(d->'rows') e where e->>'state' = 'needs_authorised_read';
  if (x->>'courses')::int <> 1 or (x->>'credits_per_course')::numeric <> 1 then raise exception 'F5: read row %', x; end if;
  raise notice 'F5 ok: %', d->'rows';
end $f$;

-- F6 remedies: no baseline is no pass; a refresh with no movement is no pass; a proven cohort page is a pass
do $f$
declare a jsonb; v jsonb;
begin
  v := security.field_absence_recovery_verify_v1(901);
  if (v->>'passed')::boolean then raise exception 'F6: passed with no baseline'; end if;
  a := security.field_absence_recovery_action_v1(901);
  if not (a->>'ok')::boolean then raise exception 'F6: action %', a; end if;
  insert into pipeline.ops_remedy_runs(issue_id, remedy_code, before, evidence) values (901, 'rem_source_recovery_refresh', a->'evidence'->'before', a->'evidence');
  v := security.field_absence_recovery_verify_v1(901);
  if (v->>'passed')::boolean then raise exception 'F6: passed without movement %', v; end if;
  update pipeline.course_page_proofs set proven = true where course_id = 'c0000000-0000-0000-0000-000000000013';
  v := security.field_absence_recovery_verify_v1(901);
  if not (v->>'passed')::boolean or (v->'measure'->>'proven_delta')::int <> 1 then raise exception 'F6: no pass on a proven page %', v; end if;
  perform security.field_absence_recovery_refresh_v1();
  if (select state from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000013') <> 'recovered_free'
     or (select recovered_at from pipeline.field_absence_recovery where course_id = 'c0000000-0000-0000-0000-000000000013') is null then raise exception 'F6: recovered'; end if;
  raise notice 'F6 ok: verify %', v->>'evidence';
end $f$;

-- F7 the registry: root causes, remedies, authority; an action function that does not exist is refused
do $f$
begin
  if (select count(*) from pipeline.ops_root_causes where code like 'src\_%') <> 9 then raise exception 'F7: root causes'; end if;
  if (select string_agg(code || ':' || authority, ',' order by code) from pipeline.ops_remedies) <> 'rem_page_check_rules:release,rem_relink_free_routes_on:admin,rem_relink_url_normalised:release,rem_source_recovery_refresh:auto' then
    raise exception 'F7: remedies'; end if;
  if (select action_fn::text || ' ' || verify_fn::text from pipeline.ops_remedies where code = 'rem_source_recovery_refresh')
     <> 'security.field_absence_recovery_action_v1(bigint) security.field_absence_recovery_verify_v1(bigint)' then raise exception 'F7: functions'; end if;
  begin
    perform security.ops_remedy_register_v1('rem_x', '{"authority": "auto", "action_fn": "security.no_such_fn(bigint)"}');
    raise exception 'F7: a missing action function was accepted';
  exception when others then if sqlerrm like 'F7%' then raise; end if;
  end;
  raise notice 'F7 ok: 9 root causes, 4 remedies, one auto';
end $f$;

-- F8 course-relink: refused statuses, normalised comparison, title forms, current handbook year, stored candidates (each switch off, then on)
begin;
do $f$
begin
  insert into pipeline.source_proof_requests(course_id, provider_id, route, state, requested_at)
  select c, 'a1000000-0000-0000-0000-000000000001', 'relink', 'queued', now()
    from unnest(array['c0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-000000000014']::uuid[]) c
  on conflict (course_id) do update set route = 'relink', state = 'queued', requested_at = now();
  perform security.course_relink_provider_v1('a1000000-0000-0000-0000-000000000001', 50);
  if exists (select 1 from pipeline.course_relink where course_id in ('c0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000007')) then raise exception 'F8 off: refused status taken'; end if;
  if (select state from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000004') <> 'absent' then raise exception 'F8 off: course 4'; end if;
  if (select state from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000006') <> 'absent' then raise exception 'F8 off: course 6'; end if;
  -- S6 on by default: course 13 is no longer offered its own refused page
  if (select state from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000013') <> 'absent' then raise exception 'F8: course 13 offered its refused page'; end if;
  raise notice 'F8 off ok: switches off keep today''s behaviour; course 13 not offered its own page';
end $f$;
rollback;
do $f$
declare v_c jsonb;
begin
  update pipeline.platform_toolset_settings set value = '["identity_mismatch", "identity_refused", "page_refused", "refused_host", "not_course_page"]' where key = 'relink.statuses';
  update pipeline.platform_toolset_settings set value = '1' where key in ('relink.slug_variants_on', 'relink.year_current_on', 'relink.stored_search_reuse_on');
  insert into pipeline.source_proof_requests(course_id, provider_id, route, state, requested_at)
  select c, 'a1000000-0000-0000-0000-000000000001', 'relink', 'queued', now()
    from unnest(array['c0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-000000000014']::uuid[]) c
  on conflict (course_id) do update set route = 'relink', state = 'queued', requested_at = now();
  perform security.course_relink_tick_v1(50);
  if (select candidates from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000004') <> '["https://u1.example/study/bachelor-of-te-reo-maori"]' then
    raise exception 'F8: course 4 %', (select candidates from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000004'); end if;
  if (select candidates from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000014') <> '["https://u1.example/programs/nursing-master-of-science"]' then raise exception 'F8: course 14'; end if;
  if (select candidates from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000006') <> '["https://u1.example/cand-b"]' then
    raise exception 'F8: course 6 %', (select candidates from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000006'); end if;
  v_c := (select candidates from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000007');
  if v_c <> jsonb_build_array('https://u1.example/handbook/' || extract(year from now())::int || '/courses/X7') then raise exception 'F8: course 7 %', v_c; end if;
  if (select state from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000003') <> 'absent' then raise exception 'F8: course 3 not taken'; end if;
  if (select url from pipeline.coverage_course_pages where course_id = 'c0000000-0000-0000-0000-000000000004') <> 'https://u1.example/study/bachelor-of-te-reo-maori' then raise exception 'F8: not bound for the reader'; end if;
  raise notice 'F8 on ok: refused status taken (3, 7), title forms (4, 14), stored candidate b not rejected c (6), current-year address (7); bound for the reader only';
end $f$;

-- F9 absence input (S4): off, course 12 is not considered; on, it is (no page: it needs discovery)
begin;
do $f$
begin
  perform security.source_proof_feed_v1();
  if exists (select 1 from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000012') then raise exception 'F9 off'; end if;
  update pipeline.platform_toolset_settings set value = '1' where key = 'proof.absence_input_on';
  perform security.source_proof_feed_v1();
  if (select route from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000012') <> 'no_route' then raise exception 'F9 on'; end if;
  raise notice 'F9 ok: absence-only course 12 considered only with proof.absence_input_on';
end $f$;
rollback;

-- F10 shipped state: D1 off, every new route off, the job catalogued with no number in its command
do $f$
begin
  if security.pipeline_num_v1('proof.search_per_run', 0) <> 0 then raise exception 'F10: D1'; end if;
  if (select command from cron.job where jobname = 'field-absence-recovery') ~ '[(,]\s*[0-9]' then raise exception 'F10: number in command'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'field-absence-recovery') then raise exception 'F10: catalogue'; end if;
  if (select count(*) from pipeline.component_register where introduced_in = '20261104030000') <> 4 then raise exception 'F10: register'; end if;
  raise notice 'F10 ok: D1 off, job catalogued, register rows';
end $f$;
