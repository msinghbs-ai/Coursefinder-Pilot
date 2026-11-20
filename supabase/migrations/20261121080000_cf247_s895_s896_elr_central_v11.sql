-- CF-247 s895 and s896 (session S1-ELR-Central-Policy, Platform Admin 21 Nov 2026 07:48 AEDT): "populate the remaining source-backed English gaps across all universities
-- from each institution's central English proficiency page by study level at $0 AI and $0 Firecrawl spend, with no hardcoded university or provider coverage exclusions".
-- English language requirements only.
--
-- Found live (rolled-back probes, 21 Nov 2026 07:55 to 08:20 AEDT; head 20261120235000; G3 75/48; manual locks 7,585; 134 active cron jobs):
--   Table 1 (no active English requirement, stored course page bound) is 5,930 active AU, NZ and CA courses (AU 3,538, NZ 1,091, CA 1,301). The central sweep (s886) had
--   read every stored central page (claim left 0). By route (universities / courses): elr-central reading approved 19 / 73; elr-central reading waiting for a person
--   28 / 730 (a conflict, another reading waiting, or the course-page disagreement check); approved policy only, page added no tier 75 / 1,353; page read, no proposal
--   70 / 1,132; page found but not stored 70 / 346 (Firecrawl, not in this $0 lane); no central page 523 / 2,296 (348 private VET, 92 schools).
--   All 319 pages recorded as "the page states no English test requirement by tier" were read as stored Markdown with no value tied to a level; several are genuine
--   requirement pages (Waikato, Flinders, UNBC graduate). No provider or university is excluded by name, type or list anywhere in this route: the claim takes every
--   university in an admission country that has a stored central English page and a course with no English requirement.
--
-- What changes:
--   (s895) reader elr-central-v1.1 (coverage-sweep/elr-central-reader.ts): tables whose columns are study levels and whose rows are tests; "a score of 6.5 in IELTS";
--          and every value found without a study level is reported (untiered lines, band or level scheme), still never spread across levels.
--   (s896) every stored central page of a university without an elr-central reading is read again by v1.1 (reads are keyed by reader version). The writer records the
--          new reasons ("values without a study level", "the page sorts courses into English bands or levels") and keeps the route's parser name elr-central-v1.0, with
--          the reader version in the proposal, so approval, the plan, the apply runs and the regulated-discipline holds are unchanged. No new job, setting or table.
-- G1: no new job (elr-det-sweep carries it). G2: no new value in code. G3 stays 75/48. Spend: none (no model, no Firecrawl).
-- Parity: head 20261120235000 read live 21 Nov 2026 07:55 AEDT; this file is numbered strictly above it and above the open S1-CourseLink file.
-- Replaces: the elr-central-v1.0 page reads (pages are read again by v1.1; v1.0 rows stay as history).
-- Retires: nothing. Nothing dropped, deleted or renamed.
-- Rollback: elr_central.on 0 stops the reads; a v1.1 proposal is rejected in Universities › English like any other.
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: the post-check reads the claim and the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1(); r record;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  for r in select * from (values ('security.elr_central_claim_v1(integer)', '5de9b03b618cf19646faf37c692e3857'), ('security.elr_central_record_v1(jsonb,text)', 'a0e81d9b786d3af6fef39f2be1106dd8'),
                                 ('security.elr_det_sweep_tick_v1()', '95d5c8546cb84604189b9dba0697c272')) v(f, h) loop
    if md5(pg_get_functiondef(r.f::regprocedure)) <> r.h then raise exception 'guard: % is not the text this change was written against', r.f; end if;
  end loop;
end $g$;
create temp table s896_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s896_cron on commit drop as select count(*) n from cron.job where active;

-- (s896) the claim: pages not yet read by elr-central-v1.1
create or replace function security.elr_central_claim_v1(p_providers integer) returns table (fact_source_id uuid, provider_id uuid, evidence_id uuid, storage_path text)
language sql stable security definer set search_path to ''
as $f$
  with pv as (
    select f.provider_id from pipeline.provider_fact_sources f
      join catalogue.providers p on p.id = f.provider_id
      join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
     where f.kind = 'english_policy' and f.evidence_id is not null and f.status <> 'rejected' and f.decision is distinct from 'rejected'
       and not exists (select 1 from pipeline.elr_central_reads r where r.fact_source_id = f.id and r.extractor = 'elr-central-v1.1' and r.outcome <> 'lost')
       and not exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = f.provider_id and o.kind = 'english_policy' and o.parser = 'elr-central-v1.0' and o.status in ('proposed', 'approved'))
       and exists (select 1 from catalogue.courses c where c.provider_id = f.provider_id and c.lifecycle_status = 'active'
                    and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = c.id and r.status = 'active'))
     group by f.provider_id order by f.provider_id limit greatest(p_providers, 0))
  select f.id, f.provider_id, f.evidence_id, e.storage_path
    from pv join pipeline.provider_fact_sources f on f.provider_id = pv.provider_id and f.kind = 'english_policy' and f.evidence_id is not null
              and f.status <> 'rejected' and f.decision is distinct from 'rejected'
    join pipeline.evidence_artifacts e on e.id = f.evidence_id and e.storage_path is not null
   order by f.provider_id, f.rank
$f$;
comment on function security.elr_central_claim_v1(integer) is 'CF-247 s885, s896 (pages are read again by elr-central-v1.1): the stored central English pages of the next universities that still have courses with no English requirement and no elr-central policy. Reads only.';
revoke all on function security.elr_central_claim_v1(integer) from public, anon, authenticated;

-- (s896) the writer: reads by v1.1, the route name unchanged, the new held reasons
create or replace function security.elr_central_record_v1(p_pages jsonb, p_run text default null) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_x constant text := 'elr-central-v1.1';      -- s896: the reader version of the page reads
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
    returning id into v_id;
    update pipeline.elr_central_reads r set proposal_id = v_id, result = 'proposed: ' || (select string_agg(k, ', ') from jsonb_object_keys(v_defaults) k)
     where r.provider_id = pv.provider_id and r.extractor = v_x and r.outcome = 'read' and r.result is null;
    v_proposed := v_proposed + 1;
  end loop;
  return jsonb_build_object('pages_read', v_read, 'pages_failed', v_failed, 'proposed', v_proposed, 'no_new_tier', v_none, 'skipped', v_skipped, 'extractor', v_x);
end $f$;
comment on function security.elr_central_record_v1(jsonb, text) is 'CF-247 s885, s896 (reads by elr-central-v1.1; values without a study level are held with their reason): records the central English pages the deterministic central reader read, then makes at most one english_policy proposal a university (parser elr-central-v1.0, status proposed) holding only the study-level tiers its approved policy does not give, with that policy''s named courses and exceptions, the conflicts and the regulated disciplines the page gives higher bands for. Approval is the governed route (security.policy_auto_approve_v1 or a person).';
revoke all on function security.elr_central_record_v1(jsonb, text) from public, anon, authenticated;

-- (s896) the sweep: reads back v1.0 and v1.1 answers, sends pages as v1.1
create or replace function security.elr_det_sweep_tick_v1() returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  q record; v_res jsonb; v_rec jsonb; v_harv int := 0; v_bad int := 0; v_lost int := 0; v_sent int := 0; v_pages int := 0;
  v_open int; v_room int; v_batch int; v_per int; v_cur uuid; v_all jsonb; v_items jsonb; v_id bigint; v_claimed int; v_last uuid; i int;
  v_t0 timestamptz := clock_timestamp(); v_c jsonb := '{}'::jsonb; v_cid bigint; v_cpages jsonb; v_capp int := 0; v_cw int := 0; v_cl4 int := 0; ap record; v_ap jsonb; v_l4 int;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247:elr_det_sweep')) then return jsonb_build_object('skipped', 'another run is working'); end if;  -- fixed: one run at a time
  -- 1. answered calls
  for q in select r.id, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.elr_det_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' = 'elr-det-v1.0' then
      v_rec := security.elr_det_record_v1(v_res->'pages', 'request:' || q.id);
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
    if coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' in ('elr-central-v1.0', 'elr-central-v1.1') then
      v_rec := security.elr_central_record_v1(v_res->'pages', 'request:' || q.id);
      update pipeline.elr_central_requests set status = 'done', finished_at = now(), result = v_rec where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.elr_central_requests set status = 'failed', finished_at = now(), result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    update pipeline.elr_central_reads set outcome = 'lost' where request_id = q.id and outcome = 'sent';
  end loop;
  -- 2. calls with no answer in time are given up; their pages go back to the queue
  with l as (update pipeline.elr_det_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_det_pages d set outcome = 'lost' from l where d.request_id = l.id and d.outcome = 'sent';
  get diagnostics v_lost = row_count;
  with l as (update pipeline.elr_central_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_central_reads c set outcome = 'lost' from l where c.request_id = l.id and c.outcome = 'sent';
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
        select (e->>'fact_source_id')::uuid, 'elr-central-v1.1', (e->>'provider_id')::uuid, (e->>'evidence_id')::uuid, 'sent', v_cid, now() from jsonb_array_elements(v_cpages) e
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
    v_c := v_c || jsonb_build_object('central_applied', v_capp, 'central_written', v_cw, 'central_layer4', v_cl4);
  end if;
  return jsonb_build_object('read_back', v_harv, 'failed', v_bad, 'pages_lost', v_lost, 'calls_sent', v_sent, 'pages_sent', v_pages, 'open_before', v_open,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000)) || v_c;
end $f$;
comment on function security.elr_det_sweep_tick_v1() is 'CF-247 s842, s886, s896: one run of the job elr-det-sweep. Also reads stored central English pages (security.elr_central_claim_v1, worker mode elr_central_read, security.elr_central_record_v1), applies approved elr-central policies a few a run and sends their regulated-discipline holds to Layer 4. Reads back the worker''s answers (pg_net) and records them through security.elr_det_record_v1, gives up calls with no answer in time, then sends the next indexed batch of gap course pages to the coverage-sweep worker (mode elr_det_read). $0: no model, no Firecrawl.';
revoke all on function security.elr_det_sweep_tick_v1() from public, anon, authenticated;

update pipeline.automation_catalogue
   set description = replace(description, 'stored central English pages of universities that still have such courses (elr-central)', 'stored central English pages of universities that still have such courses (elr-central-v1.1, every university in an admission country, no exclusions)')
 where jobname = 'elr-det-sweep';

do $c$
declare v_api jsonb; t0 timestamptz; v_ms numeric; v_n int;
begin
  t0 := clock_timestamp();
  select count(*) into v_n from security.elr_central_claim_v1(15);
  v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if v_n = 0 then raise exception 'post-check: the v1.1 claim found no page (expected the stored central pages of universities without an elr-central reading)'; end if;
  if v_ms > 300 then raise exception 'post-check: the central claim took % ms (limit 300 ms)', round(v_ms); end if;
  if (security.elr_central_record_v1('[]'::jsonb, 'post-check')->>'proposed')::int <> 0 then raise exception 'post-check: the central writer answered an empty call wrongly'; end if;
  if (select count(*) from cron.job where active) <> (select n from s896_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s896_locks) then raise exception 'post-check: the manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  raise notice 's896: v1.1 claim % ms for % pages', round(v_ms), v_n;
end $c$;
