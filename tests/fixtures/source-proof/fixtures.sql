-- After the migration: every case of the change.
set client_min_messages = notice;
-- c07 was tried three times already (its inputs have changed since): it is not tried again
insert into pipeline.source_proof_requests(course_id, provider_id, route, state, fingerprint, attempts, requested_at, settled_at, outcome)
values ('c0000000-0000-0000-0000-000000000007', 'a1000000-0000-0000-0000-000000000001', 'relink', 'done', 'old-inputs', 3, now() - interval '20 days', now() - interval '19 days', 'relink_absent');

-- P1: each waiting course is routed to the lane that can prove its page; only free work is sent (proof.search_per_run ships 0)
do $$
declare v jsonb := security.source_proof_feed_v1(); x jsonb;
begin
  select jsonb_object_agg(course_id::text, route || ':' || state) into x from pipeline.source_proof_requests;
  if x <> jsonb_build_object('c0000000-0000-0000-0000-000000000001', 'relink:queued', 'c0000000-0000-0000-0000-000000000002', 'layer4:held',
                             'c0000000-0000-0000-0000-000000000003', 'locked:held', 'c0000000-0000-0000-0000-000000000004', 'reading:held',
                             'c0000000-0000-0000-0000-000000000005', 'no_route:held', 'c0000000-0000-0000-0000-000000000007', 'exhausted:held',
                             'c0000000-0000-0000-0000-000000000010', 'relink:queued', 'c0000000-0000-0000-0000-000000000011', 'no_route:held') then
    raise exception 'P1: %', x; end if;
  if exists (select 1 from pipeline.course_link_search where course_id = 'c0000000-0000-0000-0000-000000000005') then raise exception 'P1: paid search queued while proof.search_per_run is 0'; end if;
  if (select attempts from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000007') <> 3 then raise exception 'P1: an exhausted course used a try'; end if;
  raise notice 'P1 ok: relink c01, c10; layer4 c02; locked c03; reading c04; no_route c05 (paid off), c11 (no recipe); exhausted c07; hidden c06, proven c08 and c09 (not waiting) untouched; %', v->'routed';
end $$;

-- P2: course-relink takes the two requested courses (and only those): c01's address is in the stored list (trying, bound for the reader),
-- c10 has none (absent); c09, refused too but not requested, is left as before
do $$
declare v jsonb := security.course_relink_tick_v1(200); v2 jsonb;
begin
  if (select state from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000001') <> 'trying'
     or (select url from pipeline.coverage_course_pages where course_id = 'c0000000-0000-0000-0000-000000000001') <> 'https://u1.example/study/bachelor-of-applied-science-studies'
     or (select decided_at > now() - interval '1 minute' from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000010') is not true
     or (select decided_at < now() - interval '1 day' from pipeline.course_relink where course_id = 'c0000000-0000-0000-0000-000000000009') is not true then
    raise exception 'P2: tick %, relink %', v, (select jsonb_object_agg(course_id::text, state || ' ' || decided_at::text) from pipeline.course_relink); end if;
  v2 := security.course_relink_tick_v1(200);
  if (v2->>'providers')::int <> 0 then raise exception 'P2: the next tick took a course again (loop): %', v2; end if;
  raise notice 'P2 ok: relink tick % (c01 trying, its stored-list address bound; c10 absent; c09 not requested, untouched); next tick % (no loop)', v, v2;
end $$;

-- P3: the next run settles both from the lane's decision, and tries neither again while its inputs are unchanged
do $$
declare v jsonb := security.source_proof_feed_v1();
begin
  if (select outcome from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000001') <> 'relink_trying'
     or (select outcome from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000010') <> 'relink_absent'
     or (v->>'settled')::int <> 2 then raise exception 'P3: %', v; end if;
  if (select route from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000001') <> 'reading' then raise exception 'P3: c01 should now wait for the reader'; end if;
  v := security.source_proof_feed_v1();
  if exists (select 1 from pipeline.source_proof_requests where state = 'queued') or (v->'routed'->>'unchanged')::int < 1 then raise exception 'P3 second run: %', v; end if;
  raise notice 'P3 ok: settled relink_trying (c01, now in the read lane) and relink_absent (c10); next run tries nothing again (%)', v->'routed';
end $$;

-- P4: the provider's stored lists grow: c10's fingerprint changes and it is tried once more (try 2); c07 stays exhausted
insert into pipeline.provider_discovery_links values ('a1000000-0000-0000-0000-000000000001', 'https://u1.example/new-list-page');
do $$
declare v jsonb := security.source_proof_feed_v1();
begin
  if (select route || ':' || state || ':' || attempts from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000010') <> 'relink:queued:2' then
    raise exception 'P4: %', (select row_to_json(q) from pipeline.source_proof_requests q where course_id = 'c0000000-0000-0000-0000-000000000010'); end if;
  if (select attempts from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000007') <> 3 then raise exception 'P4: c07 tried again'; end if;
  perform security.course_relink_tick_v1(200); perform security.source_proof_feed_v1();
  if (select state || ':' || outcome from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000010') <> 'done:relink_absent' then raise exception 'P4: not settled'; end if;
  raise notice 'P4 ok: changed inputs -> c10 tried again (try 2) and settled; exhausted c07 not tried';
end $$;

-- P5: proof.max_attempts bounds the tries: with 2, c10 is exhausted when its inputs change again
update pipeline.platform_toolset_settings set value = '2' where toolset_key = 'pipeline' and key = 'proof.max_attempts';
insert into pipeline.provider_discovery_links values ('a1000000-0000-0000-0000-000000000001', 'https://u1.example/another-list-page');
do $$
begin
  perform security.source_proof_feed_v1();
  if (select route || ':' || attempts from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000010') <> 'exhausted:2' then raise exception 'P5: %',
    (select row_to_json(q) from pipeline.source_proof_requests q where course_id = 'c0000000-0000-0000-0000-000000000010'); end if;
  raise notice 'P5 ok: c10 exhausted after proof.max_attempts (2) tries, though its inputs changed';
end $$;
update pipeline.platform_toolset_settings set value = '3' where toolset_key = 'pipeline' and key = 'proof.max_attempts';

-- P6: paid search only when proof.search_per_run is above 0, one a run at 1, CRICOS stage for a registered code; the search's result settles it
update pipeline.platform_toolset_settings set value = '1' where toolset_key = 'pipeline' and key = 'proof.search_per_run';
do $$
declare v jsonb := security.source_proof_feed_v1();
begin
  if (select stage || ':' || state from pipeline.course_link_search where course_id = 'c0000000-0000-0000-0000-000000000005') <> 'cricos:queued' then raise exception 'P6: %', v; end if;
  if (select route || ':' || state from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000011') <> 'no_route:held' then raise exception 'P6: c11 has no recipe'; end if;
  update pipeline.course_link_search set state = 'none', done_at = now() where course_id = 'c0000000-0000-0000-0000-000000000005';
  v := security.source_proof_feed_v1();
  if (select outcome from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000005') <> 'search_none' then raise exception 'P6 settle: %', v; end if;
  if (select state from pipeline.course_link_search where course_id = 'c0000000-0000-0000-0000-000000000005') <> 'none' then raise exception 'P6: searched again with unchanged inputs'; end if;
  raise notice 'P6 ok: with proof.search_per_run 1, c05 queued for the existing course-page search (cricos stage); settled search_none; not searched again';
end $$;
update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'pipeline' and key = 'proof.search_per_run';

-- P7: a request the lane never takes up is closed after proof.request_hold_days, so it does not block the course
update pipeline.source_proof_requests set state = 'queued', route = 'relink', requested_at = now() - interval '8 days', outcome = null where course_id = 'c0000000-0000-0000-0000-000000000011';
do $$
begin
  perform security.source_proof_feed_v1();
  if (select outcome from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000011') <> 'not_taken' then raise exception 'P7'; end if;
  raise notice 'P7 ok: a request not taken in 7 days closed as not_taken';
end $$;

-- P8: proof.feed_per_run 0 sends nothing free (a refused page then waits as no_route)
update pipeline.platform_toolset_settings set value = '0' where toolset_key = 'pipeline' and key = 'proof.feed_per_run';
update pipeline.source_proof_requests set fingerprint = 'reset', attempts = 0, state = 'done' where course_id = 'c0000000-0000-0000-0000-000000000010';
do $$
begin
  perform security.source_proof_feed_v1();
  if (select route || ':' || state from pipeline.source_proof_requests where course_id = 'c0000000-0000-0000-0000-000000000010') <> 'no_route:held' then raise exception 'P8: %', (select row_to_json(q) from pipeline.source_proof_requests q where course_id = 'c0000000-0000-0000-0000-000000000010'); end if;
  raise notice 'P8 ok: with proof.feed_per_run 0 nothing is sent to course-relink';
end $$;
update pipeline.platform_toolset_settings set value = '50' where toolset_key = 'pipeline' and key = 'proof.feed_per_run';

-- B1: the per-field backlog: every field present, each split adds up, Layer 4 / not stated / stored / acquisition as seeded; the forecast only
-- with a measured rate
do $$
declare v jsonb := security.field_backlog_v1(null); f jsonb; x jsonb;
begin
  if jsonb_array_length(v->'fields') <> 12 then raise exception 'B1: % fields', jsonb_array_length(v->'fields'); end if;
  for f in select * from jsonb_array_elements(v->'fields') loop
    if (f->>'eligible')::int <> (f->>'waiting_layer4')::int + (f->>'not_supported')::int + (f->>'stored_source')::int + (f->>'requires_acquisition')::int then raise exception 'B1 split: %', f; end if;
    if ((f->>'admitted_in_rate_window')::int = 0) <> (f->'forecast_hours' = 'null'::jsonb) then raise exception 'B1 forecast: %', f; end if;
  end loop;
  select x0 into x from jsonb_array_elements(v->'fields') x0 where x0->>'field' = 'intakes';
  if x->>'eligible' <> '9' or x->>'waiting_layer4' <> '1' or x->>'not_supported' <> '1' or x->>'stored_source' <> '1' or x->>'requires_acquisition' <> '6'
     or x->>'admitted_24h' <> '1' or x->>'processed_24h' <> '2' or (x->>'forecast_hours')::numeric <> 1344 then raise exception 'B1 intakes: %', x; end if;
  select x0 into x from jsonb_array_elements(v->'fields') x0 where x0->>'field' = 'aer_course';
  if x->>'eligible' <> '9' or x->>'waiting_layer4' <> '1' or x->>'forecast_hours' is not null then raise exception 'B1 aer: %', x; end if;
  select x0 into x from jsonb_array_elements(v->'fields') x0 where x0->>'field' = 'course_description';
  if x->>'not_supported' <> '1' or x->>'stored_source' <> '1' then raise exception 'B1 description: %', x; end if;
  select x0 into x from jsonb_array_elements(v->'fields') x0 where x0->>'field' = 'rankings';
  if x->>'not_supported' <> '1' or x->>'note' <> 'no active ranking source' then raise exception 'B1 rankings: %', x; end if;
  if (v->'source_proof'->>'waiting_for_page_proof')::int <> 9 then raise exception 'B1 source proof: %', v->'source_proof'; end if;
  if (security.field_backlog_v1('NZ')->'fields'->3->>'eligible') <> '1' then raise exception 'B1 NZ'; end if;
  raise notice 'B1 ok: 12 fields, each split adds up; intakes 9 = 1 Layer 4 + 1 not stated + 1 stored + 6 acquisition, 1 admitted in 24 h, forecast 1,344 h; AER excludes out-of-scope, no rate -> no forecast; NZ 1; source proof %', v->'source_proof';
end $$;

-- B2: Platform health › Pipeline yield returns it, PIM Admin and above only
do $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true); perform set_config('request.rank', '5', true);
  v := public.admin_pipeline_yield('{"country": "AU"}'::jsonb);
  if v->'field_backlog'->>'country' <> 'AU' or jsonb_array_length(v->'field_backlog'->'fields') <> 12 or v->'lane_status' is null then raise exception 'B2: %', v - 'lanes'; end if;
  perform set_config('request.rank', '4', true);
  begin perform public.admin_pipeline_yield('{}'::jsonb); raise exception 'B2: rank 4 was answered';
  exception when insufficient_privilege then null; end;
  raise notice 'B2 ok: admin_pipeline_yield carries field_backlog (country AU, 12 fields) beside lane_status; rank 4 refused';
end $$;
