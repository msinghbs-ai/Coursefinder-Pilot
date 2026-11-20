-- CF-247 s910 (session S1-ELR-Bands-And-Crawl, found in the live check after s904 to s909, 21 Nov 2026 09:55 AEDT): elr-det-sweep has failed every run since 08:47 AEDT.
-- English language requirements only.
--
-- Found live (rolled back): the central writer re-read a page whose same text already had an elr-central proposal that was later superseded, and its insert hit the
-- unique key provider_policy_proposals_key (fact_source_id, parser, content_hash). The error raised in the answer read-back, before the lost-call step, so the same answer
-- (request 898146, sent 08:42 AEDT) was read back and failed again on every run, and nothing after it ran: no course-page reads, no central reads, no applies, and the s907
-- fetch had not started (52 pages queued, no Firecrawl used). The latent fault came in with s896 (v1.1 re-reads); s904 kept it.
--
-- What changes:
--   (s910) the central writer: a page text that already has a proposal is not proposed again (on conflict do nothing); its reads are held with that reason.
--          the sweep: each answer is recorded in its own sub-transaction; one that cannot be recorded is marked failed with its error and the run goes on.
-- G1: no new job. G2: no new value. G3 stays 75/48. Spend: none by this change.
-- Parity: head 20261121110000 read live 21 Nov 2026 09:55 AEDT; this file is numbered strictly above it.
-- Replaces: the s904 central writer and sweep run (same behaviour, plus the two fixes).
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';
set local statement_timeout = '60s';  -- fixed: the post-check reads the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1(); r record;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  for r in select * from (values ('security.elr_central_record_v1(jsonb,text)', '0be7443fed0de9e78250a8f5e20db812'), ('security.elr_det_sweep_tick_v1()', '1e9d7b44a5f6c2114c47edc1244d81fc')) v(f, h) loop
    if md5(pg_get_functiondef(r.f::regprocedure)) <> r.h then raise exception 'guard: % is not the text this change was written against', r.f; end if;
  end loop;
end $g$;
create temp table s910_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s910_cron on commit drop as select count(*) n from cron.job where active;

-- (s910) the central writer
create or replace function security.elr_central_record_v1(p_pages jsonb, p_run text default null) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_x constant text := 'elr-central-v1.2';      -- s904: the reader version of the page reads
  v_route constant text := 'elr-central-v1.0';  -- s896: the governed route's parser name, unchanged (policy-auto-approve and the apply runs know it)
  pv record; pg jsonb; b record; t text; v_tiers text[] := array['undergraduate', 'postgraduate', 'research', 'vet'];
  v_merged jsonb; v_conf jsonb; v_disc jsonb; v_defaults jsonb; v_base_tiers text[]; v_best jsonb; v_best_n int; v_n int; v_id uuid; v_reason text;
  v_read int := 0; v_failed int := 0; v_proposed int := 0; v_none int := 0; v_skipped int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_pages) <> 'array' then raise exception 'p_pages must be an array'; end if;
  -- every page first: read or failed
  for pg in select * from jsonb_array_elements(p_pages) loop
    continue when nullif(pg->>'fact_source_id', '') is null;
    insert into pipeline.elr_central_reads as r (fact_source_id, extractor, provider_id, evidence_id, outcome, sha256, reading, result, read_at)
    values ((pg->>'fact_source_id')::uuid, v_x, (pg->>'provider_id')::uuid, nullif(pg->>'evidence_id', '')::uuid, case when pg ? 'error' then 'failed' else 'read' end,
            pg->>'sha256', pg->'reading', case when pg ? 'error' then left(pg->>'error', 160) end, now())
    on conflict (fact_source_id, extractor) do update set outcome = excluded.outcome, sha256 = excluded.sha256, reading = excluded.reading, result = excluded.result, read_at = now();
    if pg ? 'error' then v_failed := v_failed + 1; else v_read := v_read + 1; end if;
  end loop;
  -- then one decision a university
  for pv in select distinct (e->>'provider_id')::uuid provider_id from jsonb_array_elements(p_pages) e where nullif(e->>'provider_id', '') is not null and not (e ? 'error') loop
    v_reason := null;
    if exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = pv.provider_id and o.kind = 'english_policy' and o.parser = v_route and o.status in ('proposed', 'approved')) then
      v_reason := 'the university already has an elr-central reading';
    end if;
    -- the approved policy in force for the university (not an elr-central one): its tiers are never replaced
    select o.* into b from pipeline.provider_policy_proposals o
     where o.provider_id = pv.provider_id and o.kind = 'english_policy' and o.status = 'approved' and o.parser is distinct from v_route order by o.decided_at desc nulls last limit 1;
    v_base_tiers := coalesce((select array_agg(k) from jsonb_each(coalesce(b.proposal->'defaults', '{}'::jsonb)) d(k, v) where jsonb_typeof(d.v) = 'array' and jsonb_array_length(d.v) > 0), '{}');
    -- merge the university's pages: one value per tier and test, else a conflict
    v_defaults := '{}'::jsonb; v_conf := '[]'::jsonb;
    for t in select unnest(v_tiers) loop
      with q as (
        select r->>'test_code' code, r from jsonb_array_elements(p_pages) e, jsonb_array_elements(case when jsonb_typeof(e->'reading'->'defaults'->t) = 'array' then e->'reading'->'defaults'->t else '[]'::jsonb end) r
         where (e->>'provider_id')::uuid = pv.provider_id and not (e ? 'error')),
      g as (select code, count(distinct (r->>'overall_score')::numeric) nv, (array_agg(r))[1] r1 from q group by code)
      select coalesce(jsonb_agg(g.r1) filter (where g.nv = 1), '[]'::jsonb), coalesce(jsonb_agg(jsonb_build_object('tier', t, 'test_code', g.code)) filter (where g.nv > 1), '[]'::jsonb)
        into v_merged, v_disc from g;
      v_conf := v_conf || v_disc
             || coalesce((select jsonb_agg(c) from jsonb_array_elements(p_pages) e, jsonb_array_elements(coalesce(e->'reading'->'conflicts', '[]'::jsonb)) c
                          where (e->>'provider_id')::uuid = pv.provider_id and c->>'tier' = t), '[]'::jsonb);
      if jsonb_array_length(v_merged) > 0 and not (t = any (v_base_tiers)) then v_defaults := v_defaults || jsonb_build_object(t, v_merged); end if;
    end loop;
    v_disc := coalesce((select jsonb_agg(distinct d) from jsonb_array_elements(p_pages) e, jsonb_array_elements(coalesce(e->'reading'->'discipline_higher', '[]'::jsonb)) d
                         where (e->>'provider_id')::uuid = pv.provider_id), '[]'::jsonb);
    if v_reason is null and v_defaults = '{}'::jsonb then
      v_reason := case when exists (select 1 from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and (e->'reading'->>'readings')::int > 0)
                       then 'no tier the approved policy lacks (or every value conflicts)'
                       -- s896: values on the page but none tied to a study level (for example a page that sorts courses into English bands): held, never spread across levels
                       -- s905: the values a page gives each named English band are kept as band definitions and used only for a course whose own page names that band
                       when exists (select 1 from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and jsonb_typeof(e->'reading'->'band_defs') = 'object'
                                      and e->'reading'->'band_defs' <> '{}'::jsonb)
                       then 'values by English band: used only for courses whose page names the band (elr-band-v1.0)'
                       when exists (select 1 from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and (e->'reading'->>'bands')::boolean)
                       then 'values without a study level: the page sorts courses into English bands or levels'
                       when exists (select 1 from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and coalesce((e->'reading'->>'values_found')::int, 0) > 0)
                       then 'values without a study level'
                       else 'the page states no English test requirement by tier' end;
    end if;
    if v_reason is not null then
      update pipeline.elr_central_reads r set result = v_reason where r.provider_id = pv.provider_id and r.extractor = v_x and r.outcome = 'read' and r.result is null;
      if v_reason like 'the university already%' then v_skipped := v_skipped + 1; else v_none := v_none + 1; end if;
      continue;
    end if;
    -- the page that gives the most of these tiers is the proposal's document
    v_best := null; v_best_n := -1;
    for pg in select e from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and not (e ? 'error') loop
      select count(*) into v_n from jsonb_object_keys(v_defaults) k where jsonb_typeof(pg->'reading'->'defaults'->k) = 'array';
      if v_n > v_best_n then v_best := pg; v_best_n := v_n; end if;
    end loop;
    insert into pipeline.provider_policy_proposals (provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, style, proposal, status)
    select pv.provider_id, f.id, 'english_policy', v_route, v_best->>'sha256', f.evidence_id, f.url, 'level_default',
           jsonb_build_object('parser', v_route, 'reader', v_x, 'style', 'level_default', 'defaults', v_defaults,
                              'named', coalesce(b.proposal->'named', '[]'::jsonb), 'exceptions', coalesce(b.proposal->'exceptions', '[]'::jsonb),
                              'discipline_higher', v_disc, 'conflicts', v_conf, 'caveats', jsonb_build_array('read_deterministically'), 'signals', '[]'::jsonb,
                              'supplements', b.id, 'run', p_run,
                              'source_note', 'Read deterministically from the stored central English page (no AI, no Firecrawl); only the study-level tiers the approved policy does not already give'),
           'proposed'
      from pipeline.provider_fact_sources f where f.id = (v_best->>'fact_source_id')::uuid
    -- s910: the same page text read before has a proposal already (superseded or rejected by a person or a newer reading): it is not proposed again
    on conflict (fact_source_id, parser, content_hash) do nothing
    returning id into v_id;
    if v_id is null then
      update pipeline.elr_central_reads r set result = 'held: this page text was read before and its reading was superseded or rejected'
       where r.provider_id = pv.provider_id and r.extractor = v_x and r.outcome = 'read' and r.result is null;
      v_skipped := v_skipped + 1; continue;
    end if;
    update pipeline.elr_central_reads r set proposal_id = v_id, result = 'proposed: ' || (select string_agg(k, ', ') from jsonb_object_keys(v_defaults) k)
     where r.provider_id = pv.provider_id and r.extractor = v_x and r.outcome = 'read' and r.result is null;
    v_proposed := v_proposed + 1;
  end loop;
  return jsonb_build_object('pages_read', v_read, 'pages_failed', v_failed, 'proposed', v_proposed, 'no_new_tier', v_none, 'skipped', v_skipped, 'extractor', v_x);
end $f$;
comment on function security.elr_central_record_v1(jsonb, text) is 'CF-247 s885, s896, s904, s910 (a page text with an earlier proposal is not proposed again; reads by elr-central-v1.2; values without a study level are held with their reason; band values are kept by s905): records the central English pages the deterministic central reader read, then makes at most one english_policy proposal a university (parser elr-central-v1.0, status proposed) holding only the study-level tiers its approved policy does not give, with that policy''s named courses and exceptions, the conflicts and the regulated disciplines the page gives higher bands for. Approval is the governed route (security.policy_auto_approve_v1 or a person).';
revoke all on function security.elr_central_record_v1(jsonb, text) from public, anon, authenticated;

-- (s910) the sweep run
create or replace function security.elr_det_sweep_tick_v1() returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  q record; v_res jsonb; v_rec jsonb; v_harv int := 0; v_bad int := 0; v_lost int := 0; v_sent int := 0; v_pages int := 0;
  v_open int; v_room int; v_batch int; v_per int; v_cur uuid; v_all jsonb; v_items jsonb; v_id bigint; v_claimed int; v_last uuid; i int;
  v_t0 timestamptz := clock_timestamp(); v_c jsonb := '{}'::jsonb; v_bid bigint; v_bpages jsonb; v_fid bigint; v_fitems jsonb; v_od uuid; v_bd int := 0; v_cid bigint; v_cpages jsonb; v_capp int := 0; v_cw int := 0; v_cl4 int := 0; ap record; v_ap jsonb; v_l4 int;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247:elr_det_sweep')) then return jsonb_build_object('skipped', 'another run is working'); end if;  -- fixed: one run at a time
  -- 1. answered calls
  for q in select r.id, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.elr_det_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' = 'elr-det-v1.0' then
      begin  -- s910: one answer that cannot be recorded is marked failed with its error; it never stops the run
      v_rec := security.elr_det_record_v1(v_res->'pages', 'request:' || q.id);
      exception when others then
        v_rec := jsonb_build_object('record_error', left(sqlerrm, 300));
        update pipeline.elr_det_requests set status = 'failed', finished_at = now(), result = v_rec where id = q.id;
        v_bad := v_bad + 1; continue;
      end;
      update pipeline.elr_det_requests set status = 'done', finished_at = now(), result = v_rec where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.elr_det_requests set status = 'failed', finished_at = now(), result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    update pipeline.elr_det_pages set outcome = 'lost' where request_id = q.id and outcome = 'sent';
  end loop;
  -- 1b. answered central-page calls (s886)
  for q in select r.id, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.elr_central_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' in ('elr-central-v1.0', 'elr-central-v1.1', 'elr-central-v1.2') then
      begin  -- s910: one answer that cannot be recorded is marked failed with its error; it never stops the run
      v_rec := security.elr_central_record_v1(v_res->'pages', 'request:' || q.id);
      v_bd := v_bd + security.elr_band_defs_record_v1(v_res->'pages', v_res->>'extractor');  -- s905: the values each named band states
      exception when others then
        v_rec := jsonb_build_object('record_error', left(sqlerrm, 300));
        update pipeline.elr_central_requests set status = 'failed', finished_at = now(), result = v_rec where id = q.id;
        v_bad := v_bad + 1; continue;
      end;
      update pipeline.elr_central_requests set status = 'done', finished_at = now(), result = v_rec where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.elr_central_requests set status = 'failed', finished_at = now(), result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    update pipeline.elr_central_reads set outcome = 'lost' where request_id = q.id and outcome = 'sent';
  end loop;
  -- 1c. answered band calls (s906) and fetch calls (s907)
  for q in select r.id, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.elr_band_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' = 'elr-band-v1.0' then
      begin  -- s910: one answer that cannot be recorded is marked failed with its error; it never stops the run
      v_rec := security.elr_band_record_v1(v_res->'pages', 'request:' || q.id);
      exception when others then
        v_rec := jsonb_build_object('record_error', left(sqlerrm, 300));
        update pipeline.elr_band_requests set status = 'failed', finished_at = now(), result = v_rec where id = q.id;
        v_bad := v_bad + 1; continue;
      end;
      update pipeline.elr_band_requests set status = 'done', finished_at = now(), result = v_rec where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.elr_band_requests set status = 'failed', finished_at = now(), result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    update pipeline.elr_band_pages set outcome = 'lost' where request_id = q.id and outcome = 'sent';
  end loop;
  for q in select r.id, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.elr_central_fetch_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' = 'elr-central-fetch-v1.0' then
      update pipeline.elr_central_fetches f set status = case x->>'outcome' when 'read' then 'stored' when 'refused' then 'refused' else 'failed' end,
             done_at = now(), result = x - 'id'
        from jsonb_array_elements(coalesce(v_res->'fetched', '[]'::jsonb)) x where f.fact_source_id = (x->>'id')::uuid and f.request_id = q.id;
      update pipeline.elr_central_fetch_requests set status = 'done', finished_at = now(), result = jsonb_build_object('fetched', jsonb_array_length(coalesce(v_res->'fetched', '[]'::jsonb)), 'ms', v_res->'ms') where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.elr_central_fetch_requests set status = 'failed', finished_at = now(), result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    -- a page the answer does not name is not fetched again (it may have been charged): it is marked lost for a person to look at
    update pipeline.elr_central_fetches set status = 'lost', done_at = now() where request_id = q.id and status = 'sent';
  end loop;
  -- 2. calls with no answer in time are given up; their pages go back to the queue
  with l as (update pipeline.elr_det_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_det_pages d set outcome = 'lost' from l where d.request_id = l.id and d.outcome = 'sent';
  get diagnostics v_lost = row_count;
  with l as (update pipeline.elr_central_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_central_reads c set outcome = 'lost' from l where c.request_id = l.id and c.outcome = 'sent';
  with l as (update pipeline.elr_band_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_band_pages b set outcome = 'lost' from l where b.request_id = l.id and b.outcome = 'sent';
  -- a fetch call with no answer is never sent again by itself (the pages may have been charged)
  with l as (update pipeline.elr_central_fetch_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_central_fetches f set status = 'lost', done_at = now() from l where f.request_id = l.id and f.status = 'sent';
  -- 3. the next batch
  if security.pipeline_num_v1('elr_det.sweep_on', 1) < 1 then
    return jsonb_build_object('read_back', v_harv, 'failed', v_bad, 'pages_lost', v_lost, 'sent', 0, 'sweep', 'off', 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  end if;
  select count(*) into v_open from pipeline.elr_det_requests where status = 'sent';
  v_per := greatest(5, least(40, security.pipeline_num_v1('elr_det.pages_per_call', 25)::int));
  v_room := security.pipeline_num_v1('elr_det.in_flight_max', 8)::int - v_open;
  v_batch := least(security.pipeline_num_v1('batch.elr_det_sweep', 200)::int, greatest(v_room, 0) * v_per);
  if v_batch > 0 then
    select s.cursor_id into v_cur from pipeline.elr_det_state s where s.id = 1 for update;
    select coalesce(jsonb_agg(jsonb_build_object('course_id', c.course_id, 'evidence_id', c.evidence_id, 'storage_path', c.storage_path) order by c.course_id), '[]'::jsonb)
      into v_all from security.elr_det_claim_v1(v_cur, v_batch) c;
    v_claimed := jsonb_array_length(v_all);
    v_last := case when v_claimed > 0 then (v_all->(v_claimed - 1)->>'course_id')::uuid end;
    i := 0;
    while i * v_per < v_claimed loop
      select jsonb_agg(e.v order by e.n) into v_items from jsonb_array_elements(v_all) with ordinality e(v, n) where e.n > i * v_per and e.n <= (i + 1) * v_per;
      v_id := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_det_read', 'items', v_items));
      insert into pipeline.elr_det_requests (id, pages) values (v_id, jsonb_array_length(v_items));
      insert into pipeline.elr_det_pages as d (course_id, evidence_id, extractor, outcome, request_id, sent_at)
      select (e->>'course_id')::uuid, (e->>'evidence_id')::uuid, 'elr-det-v1.0', 'sent', v_id, now() from jsonb_array_elements(v_items) e
      on conflict (course_id, evidence_id, extractor) do update set outcome = 'sent', request_id = excluded.request_id, sent_at = now(), result = null where d.outcome = 'lost';
      v_sent := v_sent + 1; v_pages := v_pages + jsonb_array_length(v_items); i := i + 1;
    end loop;
    update pipeline.elr_det_state set cursor_id = case when v_claimed < v_batch then '00000000-0000-0000-0000-000000000000'::uuid else v_last end,
           passes = passes + case when v_claimed < v_batch then 1 else 0 end, updated_at = now() where id = 1;
  end if;
  -- 4. central English pages (s886): one call a run for the next universities, only when none is waiting
  if security.pipeline_num_v1('elr_central.on', 1) >= 1 then
    if not exists (select 1 from pipeline.elr_central_requests where status = 'sent') then
      select coalesce(jsonb_agg(jsonb_build_object('fact_source_id', c.fact_source_id, 'provider_id', c.provider_id, 'evidence_id', c.evidence_id, 'storage_path', c.storage_path)), '[]'::jsonb)
        into v_cpages from security.elr_central_claim_v1(security.pipeline_num_v1('batch.elr_central', 6)::int) c;
      if jsonb_array_length(v_cpages) > 0 then
        v_cid := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_central_read', 'items', v_cpages));
        insert into pipeline.elr_central_requests (id, pages) values (v_cid, jsonb_array_length(v_cpages));
        insert into pipeline.elr_central_reads as r (fact_source_id, extractor, provider_id, evidence_id, outcome, request_id, sent_at)
        select (e->>'fact_source_id')::uuid, 'elr-central-v1.2', (e->>'provider_id')::uuid, (e->>'evidence_id')::uuid, 'sent', v_cid, now() from jsonb_array_elements(v_cpages) e
        on conflict (fact_source_id, extractor) do update set outcome = 'sent', request_id = excluded.request_id, sent_at = now(), result = null where r.outcome = 'lost';
        v_c := v_c || jsonb_build_object('central_pages_sent', jsonb_array_length(v_cpages));
      end if;
    end if;
    -- 5. apply approved central policies, a few a run; send their regulated-discipline holds to Layer 4
    for ap in select o.id, o.evidence_id, o.url, o.proposal from pipeline.provider_policy_proposals o left join pipeline.elr_central_applies a on a.proposal_id = o.id
               where o.kind = 'english_policy' and o.status = 'approved' and o.parser = 'elr-central-v1.0'
                 and (a.applied_at is null or a.applied_at < now() - make_interval(hours => security.pipeline_num_v1('elr_central.reapply_hours', 6)::int))
               order by a.applied_at nulls first, o.decided_at limit security.pipeline_num_v1('elr_central.apply_per_run', 2)::int loop
      begin
        v_ap := security.provider_english_apply_v1(ap.id);
        with h as (
          select pl.course_id, substring(pl.reason from '^regulated discipline \(([^)]+)\)') disc
            from security.provider_english_plan_v1(ap.id) pl
           where pl.outcome = 'held' and pl.reason like 'regulated discipline%'
             and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = pl.course_id and r.status = 'active')
             and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = pl.course_id and i.field_code = 'course_english' and i.status = 'pending')
           limit security.pipeline_num_v1('elr_central.l4_per_run', 50)::int)
        insert into pipeline.layer4_review_items (entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, escalation_reason, change_control_ref)
        select 'course', h.course_id, 'course_english', ap.evidence_id, '{}'::jsonb,
               jsonb_build_object('english_requirements', '[]'::jsonb, 'source', 'elr-central-v1.0', 'policy_id', ap.id,
                                  'central_page_says', (select coalesce(jsonb_agg(d), '[]'::jsonb) from jsonb_array_elements(coalesce(ap.proposal->'discipline_higher', '[]'::jsonb)) d where d->>'discipline' = h.disc)),
               jsonb_build_object('source', 'elr_central', 'policy', ap.id, 'page', ap.url, 'discipline', h.disc),
               'Regulated discipline (' || h.disc || '): the university''s central English page gives higher English bands for these courses, so the general default is not used. Set this course''s requirement from its course or faculty page.',
               'CF-CHG-20260915-247'
          from h;
        get diagnostics v_l4 = row_count;
        insert into pipeline.elr_central_applies as a (proposal_id, applied_at, runs, written, layer4)
        values (ap.id, now(), 1, coalesce((v_ap->>'written')::int, 0), v_l4)
        on conflict (proposal_id) do update set applied_at = now(), runs = a.runs + 1, written = a.written + excluded.written, layer4 = a.layer4 + excluded.layer4, last_error = null;
        v_capp := v_capp + 1; v_cw := v_cw + coalesce((v_ap->>'written')::int, 0); v_cl4 := v_cl4 + v_l4;
      exception when others then
        insert into pipeline.elr_central_applies as a (proposal_id, applied_at, runs, last_error) values (ap.id, now(), 1, left(sqlerrm, 200))
        on conflict (proposal_id) do update set applied_at = now(), runs = a.runs + 1, last_error = excluded.last_error;
      end;
    end loop;
    v_c := v_c || jsonb_build_object('central_applied', v_capp, 'central_written', v_cw, 'central_layer4', v_cl4, 'band_defs', v_bd);
  end if;
  -- 6. course pages of universities whose central page defines English bands (s906): one call a run, only when none is waiting
  if security.pipeline_num_v1('elr_band.on', 1) >= 1 and not exists (select 1 from pipeline.elr_band_requests where status = 'sent') then
    select coalesce(jsonb_agg(jsonb_build_object('course_id', b.course_id, 'evidence_id', b.evidence_id, 'storage_path', b.storage_path, 'bands', to_jsonb(b.bands))), '[]'::jsonb)
      into v_bpages from security.elr_band_claim_v1(security.pipeline_num_v1('batch.elr_band', 40)::int) b;
    if jsonb_array_length(v_bpages) > 0 then
      v_bid := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_band_read', 'items', v_bpages));
      insert into pipeline.elr_band_requests (id, pages) values (v_bid, jsonb_array_length(v_bpages));
      insert into pipeline.elr_band_pages as p (course_id, evidence_id, extractor, outcome, request_id, sent_at)
      select (e->>'course_id')::uuid, (e->>'evidence_id')::uuid, 'elr-band-v1.0', 'sent', v_bid, now() from jsonb_array_elements(v_bpages) e
      on conflict (course_id, evidence_id, extractor) do update set outcome = 'sent', request_id = excluded.request_id, sent_at = now(), result = null where p.outcome = 'lost';
      v_c := v_c || jsonb_build_object('band_pages_sent', jsonb_array_length(v_bpages));
    end if;
  end if;
  -- 7. the one-off fetch of known, unstored central English pages (s907): one call a run while its on-demand request is open; closed when the queue is empty
  if security.pipeline_num_v1('elr_central_fetch.on', 1) >= 1 and not exists (select 1 from pipeline.elr_central_fetch_requests where status = 'sent') then
    select coalesce(jsonb_agg(jsonb_build_object('id', f.fact_source_id, 'provider_id', f.provider_id, 'url', f.url, 'country', f.country)), '[]'::jsonb)
      into v_fitems from security.elr_central_fetch_claim_v1(security.pipeline_num_v1('batch.elr_central_fetch', 10)::int) f;
    if jsonb_array_length(v_fitems) > 0 then
      v_fid := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_central_fetch', 'items', v_fitems));
      insert into pipeline.elr_central_fetch_requests (id, pages) values (v_fid, jsonb_array_length(v_fitems));
      update pipeline.elr_central_fetches f set status = 'sent', request_id = v_fid, sent_at = now() from jsonb_array_elements(v_fitems) e where f.fact_source_id = (e->>'id')::uuid and f.status = 'queued';
      v_c := v_c || jsonb_build_object('central_fetch_sent', jsonb_array_length(v_fitems));
    else
      -- nothing left to send for an open request: close it and keep its report (actual use and the credit left)
      for v_od in select distinct f.on_demand_id from pipeline.elr_central_fetches f join pipeline.on_demand_requests r on r.id = f.on_demand_id
                   where r.state = 'open' and not exists (select 1 from pipeline.elr_central_fetches g where g.on_demand_id = f.on_demand_id and g.status in ('queued', 'sent')) loop
        insert into pipeline.elr_central_fetch_state as s (on_demand_id, closed_at, report) values (v_od, now(), security.on_demand_close_v1(v_od))
        on conflict (on_demand_id) do update set closed_at = now(), report = excluded.report;
        v_c := v_c || jsonb_build_object('central_fetch_closed', v_od);
      end loop;
    end if;
  end if;
  return jsonb_build_object('read_back', v_harv, 'failed', v_bad, 'pages_lost', v_lost, 'calls_sent', v_sent, 'pages_sent', v_pages, 'open_before', v_open,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000)) || v_c;
end $f$;
comment on function security.elr_det_sweep_tick_v1() is 'CF-247 s842, s886, s896, s904 to s907, s910 (each answer is recorded on its own; one that fails is marked failed and the run goes on): one run of the job elr-det-sweep. Also keeps the values central pages give each named English band (s905), reads the band named on course pages of those universities (worker mode elr_band_read, security.elr_band_record_v1), and runs the one-off bounded fetch of known central English pages under its on-demand request (worker mode elr_central_fetch, s907). Also reads stored central English pages (security.elr_central_claim_v1, worker mode elr_central_read, security.elr_central_record_v1), applies approved elr-central policies a few a run and sends their regulated-discipline holds to Layer 4. Reads back the worker''s answers (pg_net) and records them through security.elr_det_record_v1, gives up calls with no answer in time, then sends the next indexed batch of gap course pages to the coverage-sweep worker (mode elr_det_read). $0: no model, no Firecrawl.';
revoke all on function security.elr_det_sweep_tick_v1() from public, anon, authenticated;

do $c$
declare v_api jsonb; v jsonb;
begin
  if (security.elr_central_record_v1('[]'::jsonb, 'post-check')->>'proposed')::int <> 0 then raise exception 'post-check: the central writer answered an empty call wrongly'; end if;
  if (select count(*) from cron.job where active) <> (select n from s910_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s910_locks) then raise exception 'post-check: the manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
