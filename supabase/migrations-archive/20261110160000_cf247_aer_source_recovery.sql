-- CF-247 AER source recovery (Platform Admin directive 10 Nov 2026 14:02: "rapidly increase source-backed entry-requirement coverage across ALL eligible AU/NZ providers").
-- Guards: G1 (no job added), G2 (no operational value in code; the only constants are technical and marked `-- fixed:`), G3 (no consumer API object is read or changed),
--   Decision 260 (housekeeping), "a passing qualification never switches anything on by itself" (no setting, switch or job state is changed), Layer 4 decisions stay with a person.
-- Replaces: security.aer_schedule_tick_v1 (md5-guarded edit: parked holds no longer use the Layer 4 capacity), security.aer_current_findings_v1 (md5-guarded edit: the no_source finding names its actual route), security.data_delivery_v1 (anchored edit: one new key, aer_sources); the edits are taken back by supabase/held/aer_source_recovery_forward_recovery.sql
-- Retires: nothing
--
-- Evidence (production, read only, 10 Nov 2026 AEDT, project fxcwkweaxjtknorudmwp):
--   * 1,437 of the 1,497 open AER findings are root cause no_source: an eligible provider with no row in pipeline.entry_matrix_sources. They are NOT one cause. Grouped by what the platform already holds for each provider:
--       875 providers (7,746 courses)  course pages are stored and bound; the free course route reads the requirements from them, but no read has started (see cause 1)
--       373 providers                   nothing stored: no entry-requirements link, no bound course page (parked: needs a new page search, which spends credits)
--       168 providers (1,169 courses)   course pages stored but matched to the course by title only (exact_title, title_level, degree_name, adapter_title), not admitted for entry requirements (Platform Admin decision)
--        17 providers (547 courses)     a stored link already scores as the provider's entry-requirements page on its own website; job aer-source-stored-find would attach it, but it is switched off
--         3 providers                   only a general entry-requirements page is stored, under the score for a suggestion
--         1 provider                    a stored entry page on a website another active provider also uses (identity)
--   * Cause 1, the capacity. security.aer_schedule_tick_v1 stops all new course reads (and the refresh of entry pages that have a matrix item waiting) while Layer 4 holds 600 or more entry-requirement items.
--     It counts 605 pending items, of which 213 are PARKED by the technical lane (pipeline.work_items lane aer_technical, stage parked, action park): 151 row-limit holds that wait for a Platform Admin row limit, 25 human-input holds,
--     22 duplicates (the lane's own record says "the duplicate is parked ... and is not counted as a decision"), 15 stale reads. Not one of those is a decision a Layer 4 reviewer can make, yet each uses a place, so the job has
--     read nothing since 8 Nov (every run in the last 30 hours: back_pressure true, course_reads 0, refusal none, room 20). Counted without them there are 392 items and 208 places of room.
--     The same limit (aer.schedule_layer4_max) is kept; wc.aer_fair_on and the fair scheduler are untouched.
-- What this changes:
--   1. security.aer_parked_items_v1() NEW: the pending entry-requirement Layer 4 items the technical lane has parked (stage parked and action park), with the lane's exact reason and next action.
--   2. security.aer_schedule_tick_v1 (md5-guarded): while wc.aer_fair_on is off, the capacity count leaves those parked items out; the run record and the result carry parked_not_counted. Nothing else changes: the daily cap, the batch,
--      the per-provider turn, the AI guards, the item gate and every Layer 4 decision are as before. A read it starts still goes to a person in Layer 4.
--   3. security.aer_no_source_route_v1() NEW (read only): for each eligible provider with no source, the route (source_page_stored, source_page_host_shared, course_pages_waiting, course_pages_unconfirmed, weak_page_only,
--      nothing_stored), the reason in plain words, the next action, whether it is parked, and the figures behind it. Page rules are security.entry_source_score_v1 (the worker's) and central.min_suggest_score (floor 3, fixed).
--   4. security.aer_current_findings_v1 (md5-guarded): the no_source finding's evidence gains route, reason, next_action, parked, courses_waiting, best_url, best_score (additive; fingerprint, root cause and counts unchanged).
--   5. security.data_delivery_aer_v1() NEW (read only) and security.data_delivery_v1 (one new key aer_sources for stream aer): eligible providers, providers with sources and with active rows, active/proposed rows, sources by status and
--      recovered by the stored-link step, remaining gaps by route with next action, parked holds by rule with exact reason, other findings, last and next run of each AER job, and the active blockers.
-- No setting, schedule, ledger, finding or data row is changed by this migration; no job is added; nothing is fetched, read by AI or admitted. Nothing is dropped or deleted.
-- Live definitions this change edits (pg_proc.prosrc md5, read 10 Nov 2026), before -> after:
--   security.aer_schedule_tick_v1(boolean) 705375f3705eb739cbc2bc2b9d64de53 -> f995e9521198ae57ab0401564e4e5a20
--   security.aer_current_findings_v1() a9796f1cf7a3308c01972f2a4226eb90 -> 13b3a30c15b10135a2441158fc80f48c
--   security.data_delivery_v1() 849453412a8b9a448118e7b87362752a -> 04b560cfb6b79758e2b694c96771be33
-- The two guarded edits stop (and nothing is applied) when the live body is neither the one they replace nor the one they write. The Data Delivery edit is one anchored line and is applied to whatever the live body is, once.

do $g$
declare r record;
begin
  for r in select * from (values ('security.aer_schedule_tick_v1(boolean)'), ('security.aer_current_findings_v1()'), ('security.data_delivery_v1()'), ('security.entry_source_score_v1(text,text)'),
                                 ('security.aer_eligible_v1()'), ('security.aer_schedule_courses_v1(integer,boolean)'), ('security.coverage_identity_allowed(uuid,text,text)'), ('security.site_host_v1(text)'),
                                 ('security.pipeline_num_v1(text,numeric)'), ('security.cron_next_run_v1(text,timestamp with time zone)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.work_items') is null or to_regclass('pipeline.aer_gap_findings') is null or to_regclass('pipeline.aer_provider_coverage') is null or to_regclass('pipeline.aer_schedule_runs') is null
     or to_regclass('pipeline.aer_source_stored_find') is null or to_regclass('pipeline.coverage_provider_urls') is null or to_regclass('pipeline.provider_discovery_links') is null then
    raise exception 'a table this change reads is missing';
  end if;
end $g$;

-- 1. the parked holds ------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_parked_items_v1() returns table(item_id uuid, provider_id uuid, field_code text, failure_class text, reason text, next_action text, parked_since timestamptz)
language sql stable security definer set search_path = ''
as $f$
  -- the technical lane's own record of a hold that waits for a setting, a person or another copy of the page (stage parked, action park); a transient hold being retried (action retry_backoff) is not parked
  select i.id, w.provider_id, i.field_code, w.failure_class, w.unresolved_blocker->>'reason', w.unresolved_blocker->>'next_action', w.first_blocked_at
    from pipeline.work_items w
    join pipeline.layer4_review_items i on i.id::text = w.entity
   where w.lane = 'aer_technical' and w.work_kind = 'l4_item' and w.stage = 'parked' and w.unresolved_blocker->>'action' = 'park'
     and i.status = 'pending' and i.field_code in ('course_entry_first_read', 'entry_matrix_first_run')  -- fixed: the two entry-requirement item kinds the scheduled reading counts
$f$;
comment on function security.aer_parked_items_v1() is 'CF-247 (10 Nov 2026): the pending entry-requirement Layer 4 items that the technical lane has parked with their exact reason and next action (row limit, human input, duplicate, stale read). A parked hold is not a decision a reviewer can make, so security.aer_schedule_tick_v1 does not count it against aer.schedule_layer4_max.';
revoke all on function security.aer_parked_items_v1() from public, anon, authenticated;

-- 2. the route of each provider with no source ------------------------------------------------------------------------------------------------
create or replace function security.aer_no_source_route_v1() returns table(provider_id uuid, route text, reason text, next_action text, parked boolean, courses_waiting integer, best_url text, best_score numeric)
language sql stable security definer set search_path = ''
as $f$
  with m as (select greatest(security.pipeline_num_v1('central.min_suggest_score', 4), 3) v),  -- fixed: the worker never suggests a page that scores under 3
  np as (select e.provider_id, security.site_host_v1(p.website) ph
           from security.aer_eligible_v1() e join catalogue.providers p on p.id = e.provider_id
          where not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id)),
  -- only links that can score at all are scored (every page rule needs one of these words)
  lk as materialized (
    select u.provider_id, u.url, u.title from pipeline.coverage_provider_urls u join np on np.provider_id = u.provider_id
     where lower(u.url || ' ' || coalesce(u.title, '')) ~ 'equivalen|requirement|qualification|admission|entry'
    union all
    select l.provider_id, l.url, l.anchor_text from pipeline.provider_discovery_links l join np on np.provider_id = l.provider_id
     where lower(l.url || ' ' || coalesce(l.anchor_text, '')) ~ 'equivalen|requirement|qualification|admission|entry'),
  sc as materialized (select lk.provider_id, lk.url, security.entry_source_score_v1(lk.url, lk.title) score, security.site_host_v1(lk.url) uh from lk),
  best as (select distinct on (sc.provider_id) sc.provider_id, sc.url, sc.score
             from sc join np on np.provider_id = sc.provider_id
            where sc.score is not null and (sc.uh = np.ph or right(sc.uh, length(np.ph) + 1) = '.' || np.ph)
            order by sc.provider_id, sc.score desc, length(sc.url), sc.url),
  crs as (select c.provider_id, count(*)::int n from security.aer_schedule_courses_v1(100000, true) c group by 1),  -- fixed: every course the scheduled reading could read, not a page of them
  bnd as (select c.provider_id, g.identity_basis, count(*) n
            from catalogue.courses c join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'
            join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null
           where c.lifecycle_status = 'active' and c.provider_id in (select np.provider_id from np) group by 1, 2),
  bid as (select b.provider_id, sum(b.n)::int n_bound,
                 coalesce(sum(b.n) filter (where not security.coverage_identity_allowed(b.provider_id, b.identity_basis, 'entry_requirements')), 0)::int n_unconfirmed
            from bnd b group by 1),
  sh as (select np.provider_id, exists (select 1 from catalogue.providers o where o.id <> np.provider_id and o.lifecycle_status = 'active' and np.ph is not null and security.site_host_v1(o.website) = np.ph) shared from np),
  x as (select np.provider_id, b.url, b.score, m.v min_score, coalesce(crs.n, 0) courses, coalesce(bid.n_unconfirmed, 0) unconfirmed, coalesce(sh.shared, false) shared,
               case when b.score >= m.v and coalesce(sh.shared, false) then 'source_page_host_shared'
                    when b.score >= m.v then 'source_page_stored'
                    when coalesce(crs.n, 0) > 0 then 'course_pages_waiting'
                    when coalesce(bid.n_unconfirmed, 0) > 0 then 'course_pages_unconfirmed'
                    when b.score is not null then 'weak_page_only'
                    else 'nothing_stored' end route
          from np cross join m left join best b on b.provider_id = np.provider_id left join crs on crs.provider_id = np.provider_id
          left join bid on bid.provider_id = np.provider_id left join sh on sh.provider_id = np.provider_id)
  select x.provider_id, x.route,
         case x.route
           when 'source_page_stored' then 'A stored link on the provider''s own website scores ' || x.score || ' as its international entry-requirements page: ' || x.url
           when 'source_page_host_shared' then 'A stored entry-requirements page exists, but its website is also used by another active provider, so it is not attached by itself: ' || x.url
           when 'course_pages_waiting' then x.courses || ' course pages are stored and matched to their course; the entry requirements are read from them, one course at a time.'
           when 'course_pages_unconfirmed' then x.unconfirmed || ' course pages are stored but matched to their course by title only, which is not admitted for entry requirements.'
           when 'weak_page_only' then 'Only a general entry-requirements page is stored (score ' || x.score || ', under the ' || x.min_score || ' needed for a suggestion): ' || x.url
           else 'Nothing is stored to read: no entry-requirements link and no matched course page.' end,
         case x.route
           when 'source_page_stored' then 'Job aer-source-stored-find attaches it for the entry matrix reader once Entry pages from stored links: on is 1; a person decides the first read in Layer 4.'
           when 'source_page_host_shared' then 'A person confirms which provider the website and the page belong to.'
           when 'course_pages_waiting' then 'Scheduled entry reading (job aer-scheduled-read) reads them while Layer 4 has room; a person decides every first read in Layer 4.'
           when 'course_pages_unconfirmed' then 'Platform Admin decision: admit title-matched pages for entry requirements, or a person confirms each course page.'
           when 'weak_page_only' then 'Lower Find central pages: minimum score (not under 3), or a person confirms the page.'
           else 'Parked. A new page search of the provider''s website (it uses Firecrawl credits, when the budget allows) or a person adds the entry-requirements page.' end,
         x.route in ('nothing_stored', 'course_pages_unconfirmed', 'source_page_host_shared', 'weak_page_only'),
         case when x.courses > 0 then x.courses end, x.url, x.score
    from x
$f$;
comment on function security.aer_no_source_route_v1() is 'CF-247 (10 Nov 2026): for each AER-eligible provider with no entry-requirements source, the route the platform can take from what it already stores (a stored entry page on the provider''s own website, stored and matched course pages, matched by title only, a general page only, or nothing), the reason, the next action and whether the provider is parked. Read only; used by the no_source finding and Data Delivery.';
revoke all on function security.aer_no_source_route_v1() from public, anon, authenticated;

-- 3. Data Delivery: the AER stream ------------------------------------------------------------------------------------------------------------
create or replace function security.data_delivery_aer_v1() returns jsonb
language plpgsql stable security definer set search_path = ''
as $aer$
-- data-delivery-aer-v1
declare v_max int := security.pipeline_num_v1('aer.schedule_layer4_max', 600)::int; -- derived: the limit the scheduled reading tests (same setting and default)
begin
  return (
  with pc as (select * from pipeline.aer_provider_coverage where eligible),
  cov as (select jsonb_build_object(
            'eligible', count(*), 'with_source', count(*) filter (where sources > 0), 'source_read', count(*) filter (where sources_read > 0),
            'with_active_rows', count(*) filter (where matrix_active > 0 or course_req_active > 0),
            'waiting_for_layer4', count(*) filter (where course_req_proposed > 0 or coalesce((layer4->>'matrix_pending')::int, 0) > 0 or coalesce((layer4->>'course_awaiting_review')::int, 0) > 0),
            'active_course_rows', coalesce(sum(course_req_active), 0), 'active_matrix_rows', coalesce(sum(matrix_active), 0),
            'proposed_course_rows', coalesce(sum(course_req_proposed), 0), 'counted_at', max(updated_at)) j from pc),
  bycc as (select coalesce(jsonb_agg(jsonb_build_object('cc', x.country, 'eligible', x.n, 'with_active_rows', x.a, 'with_source', x.s) order by x.country), '[]'::jsonb) j
             from (select country, count(*) n, count(*) filter (where matrix_active > 0 or course_req_active > 0) a, count(*) filter (where sources > 0) s from pc group by 1) x),
  disp as (select coalesce(jsonb_object_agg(x.disposition, x.n), '{}'::jsonb) j from (select disposition, count(*) n from pc group by 1) x),
  gaps as (select coalesce(jsonb_agg(jsonb_build_object('route', x.route, 'providers', x.n, 'courses_waiting', x.c, 'parked', x.p, 'example_reason', x.r, 'next_action', x.a) order by x.n desc), '[]'::jsonb) j
             from (select coalesce(f.evidence->>'route', 'not_classified') route, count(*) n, sum(coalesce((f.evidence->>'courses_waiting')::int, 0)) c,
                          bool_or(coalesce((f.evidence->>'parked')::boolean, false)) p, min(f.evidence->>'reason') r, min(f.evidence->>'next_action') a
                     from pipeline.aer_gap_findings f where f.root_cause = 'no_source' and f.state <> 'resolved' group by 1) x),
  other as (select coalesce(jsonb_agg(jsonb_build_object('cause', x.root_cause, 'findings', x.n) order by x.n desc), '[]'::jsonb) j
              from (select root_cause, count(*) n from pipeline.aer_gap_findings where state <> 'resolved' and root_cause <> 'no_source' group by 1) x),
  prk as (select coalesce(jsonb_agg(jsonb_build_object('class', x.failure_class, 'items', x.n, 'providers', x.pv, 'reason', x.r, 'next_action', x.a) order by x.n desc), '[]'::jsonb) j, coalesce(sum(x.n), 0) total
            from (select failure_class, count(*) n, count(distinct provider_id) pv, min(reason) r, min(next_action) a from security.aer_parked_items_v1() group by 1) x),
  lastrun as (select coalesce((select to_jsonb(x) from (select ran_at, course_reads, corrections, matrix_pages, layer4_waiting, in_progress, back_pressure, room, refusal, detail->'parked_not_counted' parked_not_counted
                                           from pipeline.aer_schedule_runs order by ran_at desc limit 1) x), '{}'::jsonb) j),
  jobs as (select coalesce(jsonb_agg(jsonb_build_object('job', c.jobname, 'active', c.active, 'schedule', c.schedule, 'next_run', case when c.active then security.cron_next_run_v1(c.schedule, now()) end) order by c.jobname), '[]'::jsonb) j
             from cron.job c where c.jobname in ('aer-scheduled-read', 'aer-source-stored-find', 'entry-matrix-read', 'aer-replay')),
  sf as (select jsonb_build_object('switch_on', security.pipeline_num_v1('aer.source_stored_find_on', 0) >= 1, 'providers_checked', count(*), 'sources_attached', coalesce(sum(attached), 0), 'last_checked_at', max(checked_at)) j,
                coalesce(security.pipeline_num_v1('aer.source_stored_find_on', 0) >= 1, false) on_ from pipeline.aer_source_stored_find),
  srcs as (select coalesce(jsonb_object_agg(x.status, x.n), '{}'::jsonb) j, coalesce(sum(x.n), 0) total from (select status, count(*) n from pipeline.entry_matrix_sources group by 1) x),
  rv as (select coalesce(jsonb_object_agg(x.readiness, x.n), '{}'::jsonb) j from (select readiness, count(*) n from pipeline.aer_review_readiness where settled_at is null group by 1) x),
  stored_waiting as (select coalesce(sum((g->>'providers')::int), 0) n from gaps, jsonb_array_elements(gaps.j) g where g->>'route' = 'source_page_stored'),
  blk as (select coalesce(jsonb_agg(v.t), '[]'::jsonb) j
            from lastrun, sf, stored_waiting, lateral (values
              (case when lastrun.j->>'refusal' is not null then 'Scheduled entry reading is refused: ' || (lastrun.j->>'refusal') end),
              (case when coalesce((lastrun.j->>'back_pressure')::boolean, false)
                    then 'Layer 4 is full for entry requirements: ' || (lastrun.j->>'layer4_waiting') || ' items waiting against the limit of ' || v_max || ' (parked holds not counted: ' || coalesce(lastrun.j->>'parked_not_counted', 'not counted by this run') || '); no new course read starts until decisions are made' end),
              (case when not sf.on_ and stored_waiting.n > 0 then stored_waiting.n || ' providers have a stored entry page that waits for the switch Entry pages from stored links' end)) v(t)
           where v.t is not null)
  select jsonb_build_object('known', true, 'counted_at', now(), 'unit', 'providers', 'coverage', cov.j, 'by_country', bycc.j, 'dispositions', disp.j,
           'sources', jsonb_build_object('total', srcs.total, 'by_status', srcs.j, 'stored_find', sf.j),
           'gaps', gaps.j, 'other_findings', other.j, 'parked', jsonb_build_object('items', prk.total, 'by_rule', prk.j),
           'layer4_readiness', rv.j, 'last_run', lastrun.j, 'jobs', jobs.j, 'blockers', blk.j)
    from cov, bycc, disp, gaps, other, prk, lastrun, jobs, sf, srcs, rv, blk);
exception when others then
  return jsonb_build_object('known', false, 'reason', left(sqlerrm, 200));
end $aer$;
comment on function security.data_delivery_aer_v1() is 'CF-247 AER Data Delivery (Platform Admin 10 Nov 2026): eligible providers, providers with a source and with active rows, active and proposed rows, sources by status and attached by the stored-link step, the remaining gaps by route with the next action, parked holds by rule with the exact reason, other findings, readiness for Layer 4, the last run and the next run of each AER job, and the active blockers. Read only, counted live; called by security.data_delivery_v1 for the stream aer as the key aer_sources.';
revoke all on function security.data_delivery_aer_v1() from public, anon, authenticated;

-- 4. the guarded edits ------------------------------------------------------------------------------------------------------------------------
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_schedule_tick_v1(boolean)', '705375f3705eb739cbc2bc2b9d64de53', 'f995e9521198ae57ab0401564e4e5a20', true,
     array[$o$v_rr jsonb; v_tech jsonb;$o$,
           $o$  v_bp := v_l4 + v_prog >= v_l4max;$o$,
           $o$'fair', v_fair, 'room_ready', v_rr, 'technical', v_tech));$o$,
           $o$|| jsonb_build_object('fair', v_fair, 'room_ready', v_rr, 'technical', v_tech);$o$],
     array[$n$v_rr jsonb; v_tech jsonb; v_parked int := 0;$n$,
           $n$  -- 10 Nov 2026 (AER source recovery): a hold the technical lane has parked with its reason (row limit, human input, duplicate, stale read) waits for a setting, a person or another copy of the page;
  -- it is not a decision a reviewer can make, so it does not use the capacity (security.aer_parked_items_v1). The limit itself is unchanged. With wc.aer_fair_on the count below is replaced as before.
  select count(*) into v_parked from security.aer_parked_items_v1();
  v_bp := v_l4 - v_parked + v_prog >= v_l4max;$n$,
           $n$'fair', v_fair, 'room_ready', v_rr, 'technical', v_tech, 'parked_not_counted', v_parked));$n$,
           $n$|| jsonb_build_object('fair', v_fair, 'room_ready', v_rr, 'technical', v_tech, 'parked_not_counted', v_parked);$n$]),
    ('security.aer_current_findings_v1()', 'a9796f1cf7a3308c01972f2a4226eb90', '13b3a30c15b10135a2441158fc80f48c', true,
     array[$o$jsonb_build_object('country', e.country) evidence$o$,
           $o$from el e where not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id)$o$],
     array[$n$(jsonb_build_object('country', e.country) || coalesce(jsonb_strip_nulls(jsonb_build_object('route', r.route, 'reason', r.reason, 'next_action', r.next_action, 'parked', r.parked,
                                                                                                    'courses_waiting', r.courses_waiting, 'best_url', r.best_url, 'best_score', r.best_score)), '{}'::jsonb)) evidence$n$,
           $n$from el e left join security.aer_no_source_route_v1() r on r.provider_id = e.provider_id where not exists (select 1 from pipeline.entry_matrix_sources s where s.provider_id = e.provider_id)$n$]),
    ('security.data_delivery_v1()', '849453412a8b9a448118e7b87362752a', '04b560cfb6b79758e2b694c96771be33', false,
     array[$o$'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,$o$],
     array[$n$'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,
      'aer_sources', case when s.stream = 'aer' then security.data_delivery_aer_v1() end,$n$])
  ) v(sig, md5_before, md5_after, must_match, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then
      if r.must_match then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
      -- Data Delivery is edited by several streams: the edit is one anchored line, applied once to whatever is live
      if position('data_delivery_aer_v1' in v_src) > 0 then raise notice '%: already carries the AER key', r.sig; continue; end if;
    end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if r.must_match and md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
    raise notice '%: applied', r.sig;
  end loop;
end $m$;

-- 5. register, post-check --------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_parked_items_v1', 'Layer 2', 'Pending entry-requirement Layer 4 items the technical lane has parked, with the lane''s reason and next action (not counted against the Layer 4 limit)', 'active', '{}', '20261110160000'),
 ('function', 'security.aer_no_source_route_v1', 'Layer 2', 'The route of each AER-eligible provider with no entry-requirements source, from what is already stored, with reason and next action (read only)', 'active', '{}', '20261110160000'),
 ('function', 'security.data_delivery_aer_v1', 'Platform', 'AER Data Delivery: eligible providers, sources recovered and remaining gaps, parked holds, last and next run, blockers (read only, live)', 'active', '{}', '20261110160000')
on conflict do nothing;

do $post$ begin
  if position('aer_parked_items_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_schedule_tick_v1(boolean)'::regprocedure)) = 0 then raise exception 'post-check: the scheduled reading does not use the parked holds'; end if;
  if position('v_l4max' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_schedule_tick_v1(boolean)'::regprocedure)) = 0 then raise exception 'post-check: the Layer 4 limit was lost'; end if;
  if position('aer_no_source_route_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_current_findings_v1()'::regprocedure)) = 0 then raise exception 'post-check: the no_source finding does not name its route'; end if;
  if position('data_delivery_aer_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_v1()'::regprocedure)) = 0 then raise exception 'post-check: Data Delivery does not call the AER counts'; end if;
  if position('data_delivery_pdesc_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_v1()'::regprocedure)) = 0 then raise exception 'post-check: the provider AI call was lost'; end if;
end $post$;
