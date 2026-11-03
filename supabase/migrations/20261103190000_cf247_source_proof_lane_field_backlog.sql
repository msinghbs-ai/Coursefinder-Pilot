-- CF-247 Platform Admin mandate 3 Nov 2026 12:04 §5 and §6: missing page proof is a discoverable gap fed to the existing source-proof lane, and
-- the per-field backlog is measured by the platform (2026-11-03-continuous-autonomous-engineering-validation-mandate-1204.md).
-- Why (live, read-only, 3 Nov 2026 12:05-12:20 AEDT):
--   * The standing gap queue (v2.15.423, migration 20261103160000) counts a page-only gap of a course without a proven page as "waiting for page
--     proof" (pipeline.course_page_proofs, proven false) and holds it; nothing hands those courses to the engines that find and prove a page.
--     Of missing values on active courses of published providers, only a minority have a page with an identity proof (intakes 20,727 / about
--     9,800; delivery 12,786 / 2,200; campus 5,663 / 1,400; duration 6,548 / 1,800; english 13,570 / 6,200).
--   * How a course gets a proven page today (each lane is automatic and existing): coverage-read reads a bound page (direct first; Firecrawl only
--     for a trusted basis, within the reads share); coverage-reidentify identifies a stored page again under a new rule (no read, once per page
--     and rule); course-relink (security.course_relink_tick_v1, every 10 minutes) builds candidate addresses for a course whose page was refused
--     as another course's page from the university's own verified address forms, its stored lists and other courses' refused pages, binds them and
--     the reader checks them (direct reads; no search, no paid call); course-link-search sends a queued pipeline.course_link_search row to
--     Firecrawl search inside the course-search share and monthly cap (paid); Layer 4 official_course_url holds a link a person must decide
--     (2,828 pending).
--   * course-relink tries a course once: 9,841 courses are "absent" (rule 2) and are never tried again, even when the university's verified
--     pages or stored lists have grown since. 911 courses with missing intakes have no page row and a title search that found nothing.
--   * No platform measure gives, per field, the eligible backlog, the stored-source share, what needs acquisition, what waits on Layer 4, what the
--     official source does not state, the processed and admitted rates and a forecast; the acceptance report carried them as hand counts.
-- What (no new engine, no new worker; one small job that only routes work to existing lanes):
--   1 Source-proof lane: security.source_proof_feed_v1 (job source-proof-feed, twice an hour) takes courses the gap queue found waiting for page
--     proof (pipeline.course_page_proofs, proven false; active course, published provider, a country in course_url.fill_countries) and routes each
--     to the existing lane that can prove a page, recorded in pipeline.source_proof_requests with an input fingerprint:
--       layer4    an official_course_url item is pending: the person decides (nothing sent; publication boundary kept)
--       locked    the official link is locked by hand (official_url, course_url): left alone
--       reading   the bound page is still in the read lane (not read yet, deferred, failed or needing a render, under the reader's 3 tries)
--       relink    the stored page was refused as another course's page: course-relink is asked to try the course again (free: the university's
--                 own address forms, stored lists and page swaps, read directly); up to proof.feed_per_run (50) a run
--       search    otherwise, when the provider has an active search recipe: a pipeline.course_link_search row is queued (or a finished one
--                 queued again) for the existing course-link-search tick, which keeps its own eligibility, share and monthly cap; up to
--                 proof.search_per_run a run (ships 0: paid search is not used until the Platform Admin sets it)
--       no_route  no free route and paid search off or no recipe: held as needing acquisition
--     Bounded and deduplicated: one request a course (primary key); a request is settled when its lane decides (course_relink decided or started
--     again, course_link_search found, verified, none or error) or after proof.request_hold_days; a settled course is tried again only when its
--     fingerprint changes (the page state of security.course_page_key_v1, the provider's stored list and verified page counts, its search
--     recipe), and never after proof.max_attempts tries. Courses are considered proof.scan_per_run at a time, least recently considered first.
--     Order: courses with a register code (CRICOS, official source first), then provider priority.
--   2 course-relink honours a request: security.course_relink_tick_v1 and security.course_relink_provider_v1 (md5-guarded edits, one line each)
--     treat a course with an open relink request made after its last relink decision as not yet relinked
--     (security.source_proof_relink_asked_v1). Once relink decides or starts, the request no longer applies (no loop).
--   3 Per-field backlog: security.field_backlog_v1(country) (read-only; statement time-out 20 s; reads the coverage cache
--     pipeline.course_attribute_coverage, the page bindings, the latest Enrich fields item per course and field, pending Layer 4 items and each
--     engine's own tables): per field (course description, application deadline, provider description, intakes, AER course-level,
--     scholarships, fees, english, campus, delivery, duration, rankings) the eligible backlog split into waiting on Layer 4, not stated by the
--     official source, with a verified stored source page, requiring acquisition; processed and admitted in the last 24 hours and 7 days; the
--     accepted rate over backlog.rate_window_hours and the forecast (null when the rate is 0); and the source-proof lane's own counts.
--     public.admin_pipeline_yield (md5-guarded edit of the v2.15.423 definition) returns it as field_backlog (Platform health › Integration
--     queue › Pipeline yield, PIM Admin and above, the function's own rank check).
-- md5 (before = live v2.15.422 for the relink functions, read 3 Nov 2026 12:10 AEDT; admin_pipeline_yield before = the v2.15.423 definition
-- (migration 20261103160000 on live a9d64bbc...); after = local replay on PostgreSQL 16, tests/fixtures/source-proof/run.sh):
--   security.course_relink_tick_v1(integer)          cad7fad43c0421d52f76315f28c8fbdf -> b159c75a0ed1517fc9305b62984aa141
--   security.course_relink_provider_v1(uuid,integer) c349b4f218c604d2d1937e66ab3a051c -> 8f2f82c7e2ad360a0ade7cdee1f63cce
--   public.admin_pipeline_yield(jsonb)               a38814324515b163a34129b7a9d01dbd -> 34617ad96ea43189509c3f4dd536d50e
-- Spend: proof.search_per_run ships 0, so no Firecrawl search is queued by this change; the relink route reads candidate pages directly (no
--   Firecrawl, no AI). No budget value is raised.
-- Consumer API (G3): untouched.
-- Replaces: security.course_relink_tick_v1, security.course_relink_provider_v1, public.admin_pipeline_yield (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing is dropped or deleted. One job is added (source-proof-feed, active: its free route ships at 50 a run, its paid route at 0).

create or replace function pg_temp.edit_once(p_sig text, p_befores text[], p_afters text[], p_edits text[][], p_times int[]) returns text language plpgsql as $f$
-- one or more known "before" definitions (p_befores[i] becomes p_afters[i]); the edits are the same for each
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; k int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = any (p_afters) then return p_sig || ': already applied'; end if;
  k := array_position(p_befores, md5(v_def));
  if k is null then raise exception 'live % differs from the definitions this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_afters[k] then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_afters[k];
  end if;
  return p_sig || ': applied';
end $f$;

-- 0. what this change builds on: the v2.15.423 page proof (migration 20261103160000) --------------------------------------------------------
do $g$
begin
  if to_regclass('pipeline.course_page_proofs') is null or to_regprocedure('security.course_page_key_v1(uuid)') is null
     or to_regprocedure('security.lane_status_v1()') is null then
    raise exception 'source proof: apply migration 20261103160000 (lanes and gap queue, v2.15.423) first';
  end if;
end $g$;

-- 1. settings (G2) -------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'proof.feed_per_run', 'Source proof: courses sent to free page finding per run',
  'Courses waiting for page proof whose stored page was refused as another course''s page are asked of course-relink (the university''s own address forms and stored lists, read directly; no search, no Firecrawl, no AI) up to this many a run. 0 sends none.',
  'number', to_jsonb(50), 0, 1000, 'courses', 1030, 'Source proof', 'security.source_proof_feed_v1 (job source-proof-feed)', 'Platform Admin mandate 3 Nov 2026 12:04 §6: missing page proof is a discoverable gap fed to the source-proof lane'),
 ('pipeline', 'proof.search_per_run', 'Source proof: courses queued for course-page search per run (paid)',
  'Courses waiting for page proof with no free route are queued for the existing course-page search (Firecrawl search, inside the course-search share and the monthly cap) up to this many a run. 0 queues none. Raising it spends Firecrawl credits.',
  'number', to_jsonb(0), 0, 200, 'courses', 1031, 'Source proof', 'security.source_proof_feed_v1 (job source-proof-feed)', 'Platform Admin mandate 3 Nov 2026 12:04 §6: paid acquisition only with approved authority; ships 0'),
 ('pipeline', 'proof.max_attempts', 'Source proof: tries a course gets',
  'A course is sent to a page-finding lane at most this many times; it is tried again only when its page, its provider''s stored lists or verified pages, or its search recipe change.',
  'number', to_jsonb(3), 1, 10, 'tries', 1032, 'Source proof', 'security.source_proof_feed_v1', 'Platform Admin mandate 3 Nov 2026 12:04 §6: bounded retries'),
 ('pipeline', 'proof.request_hold_days', 'Source proof: a request not taken up is closed after',
  'A request the lane has not decided after this many days is closed as not taken, so the course can be considered again.',
  'number', to_jsonb(7), 1, 60, 'days', 1033, 'Source proof', 'security.source_proof_feed_v1', 'Platform Admin mandate 3 Nov 2026 12:04 §6'),
 ('pipeline', 'proof.scan_per_run', 'Source proof: courses considered per run',
  'Each run considers this many courses waiting for page proof, least recently considered first.',
  'number', to_jsonb(2000), 100, 40000, 'courses', 1034, 'Source proof', 'security.source_proof_feed_v1', 'Platform Admin mandate 3 Nov 2026 12:04 §6: bounded work'),
 ('pipeline', 'backlog.not_stated_reasons', 'Field backlog: reader answers that mean the official page does not state the value',
  'A missing value whose latest Enrich fields item was skipped with a reason starting with one of these counts as not stated by the official source (the page was read); other skips (for example, the page is another course''s) count as needing a page.',
  'list', '["the page does not state it", "the page names no campus", "the same page copy was read for this before and did not state it", "no allowed source had a value"]'::jsonb, null, null, 'reasons', 1041, 'Source proof', 'security.field_backlog_v1', 'Platform Admin mandate 3 Nov 2026 12:04 §5: records not currently supported by official evidence'),
 ('pipeline', 'backlog.rate_window_hours', 'Field backlog: accepted rate measured over',
  'The per-field forecast divides the remaining backlog by the values admitted per hour over this many hours. No forecast is given when nothing was admitted.',
  'number', to_jsonb(168), 24, 720, 'hours', 1040, 'Source proof', 'security.field_backlog_v1 (Platform health, Pipeline yield)', 'Platform Admin mandate 3 Nov 2026 12:04 §5: remaining time from measured throughput')
on conflict (toolset_key, key) do nothing;

-- 2. the source-proof lane's requests -----------------------------------------------------------------------------------------------------
create table if not exists pipeline.source_proof_requests (
  course_id uuid primary key references catalogue.courses(id) on delete cascade,
  provider_id uuid not null,
  route text not null check (route in ('layer4', 'locked', 'reading', 'relink', 'search', 'no_route', 'exhausted')),
  state text not null check (state in ('queued', 'held', 'done')),
  fingerprint text,
  attempts int not null default 0,
  requested_at timestamptz,
  settled_at timestamptz,
  outcome text,
  considered_at timestamptz not null default now(),
  detail jsonb not null default '{}'::jsonb
);
comment on table pipeline.source_proof_requests is 'CF-247 mandate 3 Nov 2026 12:04 §6: the source-proof lane (security.source_proof_feed_v1, job source-proof-feed). One row per course waiting for page proof: the existing lane it was routed to (relink, search) or why it waits (layer4, locked, reading, no_route, exhausted), the input fingerprint of its last try, tries used, and the lane''s outcome. Read by security.field_backlog_v1.';
alter table pipeline.source_proof_requests enable row level security;
create index if not exists source_proof_requests_state_idx on pipeline.source_proof_requests (state, route);
create index if not exists source_proof_requests_considered_idx on pipeline.source_proof_requests (considered_at);

create or replace function security.source_proof_relink_asked_v1(p_course uuid, p_since timestamptz) returns boolean
language sql stable security definer set search_path to '' as $function$
  -- CF-247 mandate 3 Nov 2026 12:04 §6: the source-proof lane asked course-relink to try this course again after its last relink decision
  select exists (select 1 from pipeline.source_proof_requests q where q.course_id = p_course and q.route = 'relink' and q.state = 'queued'
                    and q.requested_at > coalesce(p_since, '-infinity'::timestamptz))
$function$;
revoke all on function security.source_proof_relink_asked_v1(uuid, timestamptz) from public, anon, authenticated;

-- 3. course-relink honours a request (one line each) ----------------------------------------------------------------------------------------
select pg_temp.edit_once('security.course_relink_tick_v1(integer)', array['cad7fad43c0421d52f76315f28c8fbdf'], array['b159c75a0ed1517fc9305b62984aa141'], array[
 [$o$and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%'))$o$,
  $n$and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%') and not security.source_proof_relink_asked_v1(x.course_id, coalesce(x.decided_at, x.started_at)))$n$]], array[1]);
select pg_temp.edit_once('security.course_relink_provider_v1(uuid,integer)', array['c349b4f218c604d2d1937e66ab3a051c'], array['8f2f82c7e2ad360a0ade7cdee1f63cce'], array[
 [$o$and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%'))$o$,
  $n$and not (x.state = 'absent' and x.rule < 2 and x.reason like 'no address%') and not security.source_proof_relink_asked_v1(x.course_id, coalesce(x.decided_at, x.started_at)))$n$]], array[1]);

-- 4. the feed --------------------------------------------------------------------------------------------------------------------------------
create or replace function security.source_proof_feed_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 mandate 3 Nov 2026 12:04 §6 ("Treat missing page proof as a discoverable coverage gap, not a permanent silent skip"): job
-- source-proof-feed. Settles finished requests, then routes courses waiting for page proof (the gap queue's pipeline.course_page_proofs) to the
-- existing lane that can prove a page: course-relink (free) or course-page search (paid, proof.search_per_run, ships 0). Courses waiting on
-- Layer 4, locked by hand or still being read are recorded and left to that process. A course is tried at most proof.max_attempts times, and
-- again only when its input fingerprint changes.
declare v_free int := greatest(0, security.pipeline_num_v1('proof.feed_per_run', 50)::int);
        v_paid int := greatest(0, security.pipeline_num_v1('proof.search_per_run', 0)::int);
        v_max int := greatest(1, security.pipeline_num_v1('proof.max_attempts', 3)::int);
        v_scan int := greatest(1, security.pipeline_num_v1('proof.scan_per_run', 2000)::int);
        v_hold interval := make_interval(days => security.pipeline_num_v1('proof.request_hold_days', 7)::int);
        r record; v_route text; v_act boolean; n jsonb := '{}'::jsonb; v_settled int := 0; v_k int; v_t0 timestamptz := clock_timestamp();
begin
  -- 1. settle: the lane decided (or started again), or the request was not taken up in time
  update pipeline.source_proof_requests q set state = 'done', settled_at = now(), outcome = 'relink_' || x.state,
         detail = q.detail || jsonb_build_object('relink_reason', x.reason, 'result_url', x.result_url)
    from pipeline.course_relink x
   where q.state = 'queued' and q.route = 'relink' and x.course_id = q.course_id and coalesce(x.decided_at, x.started_at) >= q.requested_at;
  get diagnostics v_k = row_count; v_settled := v_settled + v_k;
  update pipeline.source_proof_requests q set state = 'done', settled_at = now(), outcome = 'search_' || s.state,
         detail = q.detail || jsonb_build_object('bound_url', s.bound_url)
    from pipeline.course_link_search s
   where q.state = 'queued' and q.route = 'search' and s.course_id = q.course_id and s.state in ('found', 'verified', 'none', 'error')
     and coalesce(s.done_at, s.sent_at, s.queued_at) >= q.requested_at;
  get diagnostics v_k = row_count; v_settled := v_settled + v_k;
  update pipeline.source_proof_requests q set state = 'done', settled_at = now(), outcome = 'not_taken'
   where q.state = 'queued' and q.requested_at < now() - v_hold;
  get diagnostics v_k = row_count; v_settled := v_settled + v_k;

  -- 2. consider courses waiting for page proof, least recently considered first
  for r in
    with w as (
      select pp.course_id, c.provider_id, c.course_code, pp.page_key, q.fingerprint qfp, coalesce(q.attempts, 0) attempts
        from pipeline.course_page_proofs pp
        join catalogue.courses c on c.id = pp.course_id and c.lifecycle_status = 'active'
        left join pipeline.source_proof_requests q on q.course_id = pp.course_id
       where not pp.proven and coalesce(q.state, '') <> 'queued'
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
         and security.coverage_country(c.provider_id) in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s
                                                           where s.toolset_key = 'pipeline' and s.key = 'course_url.fill_countries')
       order by q.considered_at nulls first, pp.course_id
       limit v_scan),
    prov as materialized (
      select d.provider_id,
             (select count(*) from pipeline.coverage_provider_urls u where u.provider_id = d.provider_id)
             + (select count(*) from pipeline.provider_discovery_links l where l.provider_id = d.provider_id) lists,
             (select count(*) from pipeline.coverage_course_pages g where g.provider_id = d.provider_id and g.read_status = 'read' and g.status = 'bound' and g.identity_basis is not null) verified,
             (select rc.search_domain from pipeline.course_link_recipes rc where rc.provider_id = d.provider_id and rc.active) recipe,
             (select pp2.rank from pipeline.provider_priority pp2 where pp2.provider_id = d.provider_id) prank
        from (select distinct w.provider_id from w) d)
    select w.*, p.recipe, p.prank, g.status gstatus, g.read_status, coalesce(g.read_attempts, 0) read_attempts, s.state sstate,
           md5(concat_ws('|', w.page_key, p.lists, p.verified, p.recipe)) fp,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_id = w.course_id and i.field_code = 'official_course_url' and i.status = 'pending') l4,
           exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = w.course_id and k.field in ('official_url', 'course_url', 'all')) locked
      from w join prov p on p.provider_id = w.provider_id
      left join pipeline.coverage_course_pages g on g.course_id = w.course_id
      left join pipeline.course_link_search s on s.course_id = w.course_id
     order by (coalesce(w.course_code, '') ~ '^[0-9]{6}[0-9A-Z]$') desc, coalesce(p.prank, 100000), w.course_id  -- fixed: the CRICOS code form; official source first
  loop
    v_act := false;
    v_route := case
      when r.l4 then 'layer4'
      when r.locked then 'locked'
      when r.gstatus in ('bound', 'ambiguous') and coalesce(r.read_status, '') in ('', 'deferred', 'fetch_failed', 'needs_render', 'blocked') and r.read_attempts < 3 then 'reading'  -- fixed: the read picker's own try limit
      when r.qfp = r.fp then 'unchanged'   -- tried with these inputs already (the fingerprint is kept from the last try)
      when r.attempts >= v_max then 'exhausted'
      when r.read_status = 'identity_mismatch' and v_free > 0 then 'relink'
      when r.read_status = 'identity_mismatch' then 'no_route'
      when r.recipe is not null and v_paid > 0 and coalesce(r.sstate, 'none') in ('none', 'error') then 'search'
      else 'no_route' end;
    if v_route = 'unchanged' then
      update pipeline.source_proof_requests set considered_at = now() where course_id = r.course_id;
    elsif v_route = 'relink' then
      v_free := v_free - 1; v_act := true;
    elsif v_route = 'search' then
      insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
      values (r.course_id, r.provider_id, case when coalesce(r.course_code, '') ~ '^[0-9]{6}[0-9A-Z]$' then 'cricos' else 'title' end, 'queued', now())  -- fixed: the CRICOS code form
      on conflict (course_id) do update set state = 'queued', stage = excluded.stage, attempts = 0, done_at = null, queued_at = now()
       where pipeline.course_link_search.state in ('none', 'error');
      v_paid := v_paid - 1; v_act := true;
    end if;
    if v_route <> 'unchanged' then
      insert into pipeline.source_proof_requests as q (course_id, provider_id, route, state, fingerprint, attempts, requested_at, settled_at, outcome, considered_at, detail)
      values (r.course_id, r.provider_id, v_route, case when v_act then 'queued' else 'held' end, case when v_act then r.fp end, r.attempts + case when v_act then 1 else 0 end,
              case when v_act then now() end, null, null, now(), jsonb_build_object('read_status', r.read_status, 'search', r.sstate))
      on conflict (course_id) do update set route = excluded.route, state = excluded.state, provider_id = excluded.provider_id,
             fingerprint = coalesce(excluded.fingerprint, q.fingerprint), attempts = excluded.attempts,
             requested_at = coalesce(excluded.requested_at, q.requested_at), settled_at = case when excluded.state = 'queued' then null else q.settled_at end,
             outcome = case when excluded.state = 'queued' then null else q.outcome end, considered_at = now(), detail = q.detail || excluded.detail;
    end if;
    n := jsonb_set(n, array[v_route], to_jsonb(coalesce((n->>v_route)::int, 0) + 1));
  end loop;
  return jsonb_build_object('settled', v_settled, 'routed', n, 'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);  -- fixed: milliseconds
end $function$;
revoke all on function security.source_proof_feed_v1() from public, anon, authenticated;

-- 5. per-field backlog -------------------------------------------------------------------------------------------------------------------------
create or replace function security.field_backlog_v1(p_country text default null) returns jsonb
language plpgsql stable security definer set search_path to '' set statement_timeout to '20s' as $function$
-- CF-247 mandate 3 Nov 2026 12:04 §5: per field, measured by the platform (read-only). Eligible backlog = missing on an active course of a
-- published provider (or an active published provider with active courses, for provider fields), split in this order into: waiting on Layer 4,
-- not stated by the official source (the page was read and does not state it, or the provider has no website), with a verified stored source page
-- (bound, read, identity proof, stored copy, not refused by the page check), and requiring acquisition (the rest). "Not stated" is the coverage
-- state not_on_page or no_website, or a latest Enrich fields item skipped for a reason listed in backlog.not_stated_reasons (a skip for a page
-- that is not the course's own is not "not stated": it needs a page). Processed and admitted in the
-- last 24 hours and 7 days from each engine's own tables; accepted per hour over backlog.rate_window_hours; forecast hours = (eligible - not
-- stated) / accepted per hour, null when nothing was admitted. Course fields read the coverage cache (pipeline.course_attribute_coverage).
declare v_c text := nullif(upper(btrim(p_country)), '');
        v_d1 timestamptz := now() - interval '24 hours';  -- fixed: the mandate's 24-hour window
        v_d7 timestamptz := now() - interval '7 days';    -- fixed: the mandate's 7-day window
        v_rh numeric := greatest(1, security.pipeline_num_v1('backlog.rate_window_hours', 168));
        v_ns text[] := coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s
                                  where s.toolset_key = 'pipeline' and s.key = 'backlog.not_stated_reasons' and jsonb_typeof(s.value) = 'array'), '{}'::text[]);
        v_rs timestamptz; v_course jsonb; v_prov jsonb; v_rows jsonb := '[]'::jsonb; v_proof jsonb; r record; v_t0 timestamptz := clock_timestamp();
begin
  v_rs := now() - make_interval(hours => v_rh::int);
  -- course fields: one pass over the missing values in the coverage cache
  with fm(attribute, field, enrich, l4, label, sort) as (values
         ('description', 'course_description', 'description', array['course_description_first_read'], 'Course description', 1),
         ('deadline', 'application_deadline', 'deadline', array[]::text[], 'Application deadline', 2),
         ('intakes', 'intakes', 'intakes', array[]::text[], 'Intake dates', 4),
         ('academic_entry', 'aer_course', 'entry_requirements', array['course_entry_first_read'], 'Academic entry (course level)', 5),
         ('provider_tuition', 'fees', null, array['provider_current_tuition', 'provider_current_tuition_validation'], 'Fees', 7),
         ('english', 'english', 'english', array['course_english'], 'English requirements', 8),
         ('campus', 'campus', 'campus', array[]::text[], 'Campus', 9),
         ('delivery', 'delivery', 'delivery', array[]::text[], 'Delivery mode', 10),
         ('duration', 'duration', 'duration', array[]::text[], 'Duration', 11)),
  pg as materialized (
    select g.course_id,
           (g.status in ('bound', 'ambiguous') and g.read_status = 'read' and g.identity_basis is not null and e.storage_path is not null
            and not exists (select 1 from pipeline.course_page_proofs y where y.course_id = g.course_id and not y.proven)) stored
      from pipeline.coverage_course_pages g left join pipeline.evidence_artifacts e on e.id = g.evidence_id),
  miss as materialized (
    select a.course_id, a.attribute, a.state from pipeline.course_attribute_coverage a
     where a.attribute in (select fm.attribute from fm) and a.state <> 'admitted' and (v_c is null or a.country_code = v_c)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = a.provider_id)),
  skipped as materialized (
    select distinct on (e.course_id, e.field) e.course_id, e.field, e.state, e.reason from pipeline.field_enrich_items e
     where e.course_id is not null and e.field in (select fm.enrich from fm where fm.enrich is not null)
     order by e.course_id, e.field, e.id desc),
  l4 as materialized (   -- pending Layer 4 items per course and field (a hash join; an exists per row took 14 s on production)
    select distinct i.entity_id course_id, fm.field from pipeline.layer4_review_items i join fm on i.field_code = any (fm.l4) where i.status = 'pending'),
  aer as materialized (select o.course_id, o.outcome from pipeline.aer_course_outcomes o),
  cls as (
    select fm.field, case
             when m.state in ('in_review', 'awaiting_l3') or l4.course_id is not null
                  or (m.attribute = 'academic_entry' and x.outcome = 'awaiting_review') then 'layer4'
             when m.state in ('not_on_page', 'no_website') or (s.state = 'skipped' and s.reason like any (array(select x || '%' from unnest(v_ns) x))) or (m.attribute = 'academic_entry' and x.outcome = 'no_requirement_published') then 'not_supported'
             when coalesce(pg.stored, false) then 'stored'
             else 'acquire' end k
      from miss m join fm on fm.attribute = m.attribute
      left join pg on pg.course_id = m.course_id
      left join skipped s on s.course_id = m.course_id and s.field = fm.enrich
      left join aer x on m.attribute = 'academic_entry' and x.course_id = m.course_id
      left join l4 on l4.course_id = m.course_id and l4.field = fm.field
     where not (m.attribute = 'academic_entry' and coalesce(x.outcome, '') = 'excluded'))   -- out of the AER engine's scope (aer.eligible_countries, provider rules)
  select coalesce(jsonb_object_agg(z.field, z.o), '{}'::jsonb) into v_course from (
    select fm.field, jsonb_build_object('label', fm.label, 'sort', fm.sort, 'level', 'course', 'eligible', count(c.k), 'waiting_layer4', count(*) filter (where c.k = 'layer4'),
                                       'not_supported', count(*) filter (where c.k = 'not_supported'), 'stored_source', count(*) filter (where c.k = 'stored'),
                                       'requires_acquisition', count(*) filter (where c.k = 'acquire')) o
      from fm left join cls c on c.field = fm.field group by fm.field, fm.label, fm.sort) z;

  -- processed and admitted (course fields read by Enrich fields: its items; AER: course entry rows; fees: the fee reader and its rows)
  for r in
    with pc as materialized (select p.id provider_id from catalogue.providers p join ref.countries k on k.id = p.country_id where v_c is null or k.iso_alpha2 = v_c),
    ef as (select case e.field when 'description' then 'course_description' when 'deadline' then 'application_deadline' when 'entry_requirements' then 'aer_course' else e.field end field,
                  count(*) filter (where e.updated_at > v_d1 and e.state in ('filled', 'review', 'skipped', 'failed')) p1, count(*) filter (where e.updated_at > v_d1 and e.state = 'filled') a1,
                  count(*) filter (where e.state in ('filled', 'review', 'skipped', 'failed')) p7, count(*) filter (where e.state = 'filled') a7,
                  0::bigint ar
             from pipeline.field_enrich_items e where e.updated_at > v_d7 and e.course_id is not null and e.provider_id in (select pc.provider_id from pc)
              and e.field in ('description', 'deadline', 'intakes', 'english', 'campus', 'delivery', 'duration', 'entry_requirements') group by 1),
    efr as (select case e.field when 'description' then 'course_description' when 'deadline' then 'application_deadline' when 'entry_requirements' then 'aer_course' else e.field end field, count(*) ar
              from pipeline.field_enrich_items e where e.updated_at > v_rs and e.state = 'filled' and e.course_id is not null and e.provider_id in (select pc.provider_id from pc)
               and e.field in ('description', 'deadline', 'intakes', 'english', 'campus', 'delivery', 'duration', 'entry_requirements') group by 1),
    aer as (select 'aer_course'::text field, count(distinct x.course_id) filter (where x.updated_at > v_d1) p1, count(distinct x.course_id) filter (where x.updated_at > v_d1 and x.status = 'active') a1,
                   count(distinct x.course_id) p7, count(distinct x.course_id) filter (where x.status = 'active') a7,
                   (select count(distinct y.course_id) from catalogue.course_entry_requirements y join catalogue.courses cy on cy.id = y.course_id
                     where y.updated_at > v_rs and y.status = 'active' and cy.provider_id in (select pc.provider_id from pc)) ar
              from catalogue.course_entry_requirements x join catalogue.courses c on c.id = x.course_id
             where x.updated_at > v_d7 and c.provider_id in (select pc.provider_id from pc)),
    fee as (select 'fees'::text field,
                   (select count(*) from pipeline.fee_reader_queue q where q.finished_at > v_d1 and q.provider_id in (select pc.provider_id from pc)) p1,
                   count(distinct f.course_id) filter (where f.created_at > v_d1) a1,
                   (select count(*) from pipeline.fee_reader_queue q where q.finished_at > v_d7 and q.provider_id in (select pc.provider_id from pc)) p7,
                   count(distinct f.course_id) a7,
                   (select count(distinct f2.course_id) from catalogue.course_fees f2 join catalogue.courses c2 on c2.id = f2.course_id
                     where f2.created_at > v_rs and coalesce(f2.status, 'active') = 'active' and f2.basis is distinct from 'registered_total_course'
                       and c2.provider_id in (select pc.provider_id from pc)) ar
              from catalogue.course_fees f join catalogue.courses c on c.id = f.course_id
             where f.created_at > v_d7 and coalesce(f.status, 'active') = 'active' and f.basis is distinct from 'registered_total_course' and c.provider_id in (select pc.provider_id from pc))
    select ef.field, ef.p1, ef.a1, ef.p7, ef.a7, coalesce(efr.ar, 0) ar from ef left join efr on efr.field = ef.field where ef.field <> 'aer_course'
    union all select * from aer union all select * from fee
  loop
    v_course := jsonb_set(v_course, array[r.field], coalesce(v_course->r.field, '{}'::jsonb)
                 || jsonb_build_object('processed_24h', r.p1, 'admitted_24h', r.a1, 'processed_7d', r.p7, 'admitted_7d', r.a7, 'admitted_in_rate_window', r.ar), true);
  end loop;

  -- provider fields: provider description, scholarships, rankings (active, published providers with active courses)
  with pv as materialized (
    select p.id, nullif(btrim(p.description), '') is null no_desc, t.code ptype
      from catalogue.providers p join ref.countries k on k.id = p.country_id left join ref.provider_types t on t.id = p.provider_type_id
     where (v_c is null or k.iso_alpha2 = v_c)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
       and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')),
  d as (select pv.id, case
             when exists (select 1 from pipeline.provider_description_reads dr where dr.provider_id = pv.id and dr.state in ('proposed', 'held'))
                  or exists (select 1 from pipeline.layer4_review_items i where i.entity_id = pv.id and i.field_code = 'provider_description' and i.status = 'pending') then 'layer4'
             when nullif(btrim((select p.website from catalogue.providers p where p.id = pv.id)), '') is null then 'not_supported'
             when exists (select 1 from pipeline.provider_description_reads dr where dr.provider_id = pv.id and dr.evidence_id is not null) then 'stored'
             else 'acquire' end k
          from pv where pv.no_desc),
  s as (select pv.id, case
             when exists (select 1 from pipeline.scholarship_page_candidates c where c.provider_id = pv.id and c.admit_status = 'matched_held') then 'layer4'
             when exists (select 1 from pipeline.scholarship_discovery_providers x where x.provider_id = pv.id and x.status in ('empty', 'directory_site')) then 'not_supported'
             when exists (select 1 from pipeline.scholarship_page_candidates c where c.provider_id = pv.id and c.storage_path is not null and c.admit_status is null) then 'stored'
             else 'acquire' end k
          from pv where not exists (select 1 from scholarship.scholarships x where x.provider_id = pv.id and x.lifecycle_status = 'active')),
  rk as (select pv.id, case when not exists (select 1 from ref.ranking_sources x where x.status = 'active') then 'not_supported' else 'acquire' end k
           from pv where pv.ptype = 'university' and not exists (select 1 from catalogue.provider_rankings x where x.provider_id = pv.id))
  select jsonb_build_object(
    'provider_description', jsonb_build_object('label', 'Provider description', 'sort', 3, 'level', 'provider',
        'eligible', (select count(*) from d), 'waiting_layer4', (select count(*) from d where k = 'layer4'), 'not_supported', (select count(*) from d where k = 'not_supported'),
        'stored_source', (select count(*) from d where k = 'stored'), 'requires_acquisition', (select count(*) from d where k = 'acquire'),
        'processed_24h', (select count(*) from pipeline.provider_description_reads dr where dr.updated_at > v_d1 and dr.provider_id in (select pv.id from pv)),
        'admitted_24h', (select count(*) from pipeline.provider_description_reads dr where dr.published_at > v_d1 and dr.provider_id in (select pv.id from pv)),
        'processed_7d', (select count(*) from pipeline.provider_description_reads dr where dr.updated_at > v_d7 and dr.provider_id in (select pv.id from pv)),
        'admitted_7d', (select count(*) from pipeline.provider_description_reads dr where dr.published_at > v_d7 and dr.provider_id in (select pv.id from pv)),
        'admitted_in_rate_window', (select count(*) from pipeline.provider_description_reads dr where dr.published_at > v_rs and dr.provider_id in (select pv.id from pv))),
    'scholarships', jsonb_build_object('label', 'Scholarships (providers with none)', 'sort', 6, 'level', 'provider',
        'eligible', (select count(*) from s), 'waiting_layer4', (select count(*) from s where k = 'layer4'), 'not_supported', (select count(*) from s where k = 'not_supported'),
        'stored_source', (select count(*) from s where k = 'stored'), 'requires_acquisition', (select count(*) from s where k = 'acquire'),
        'processed_24h', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at > v_d1 and c.provider_id in (select pv.id from pv)),
        'admitted_24h', (select count(*) from pipeline.scholarship_page_candidates c where c.admitted_at > v_d1 and c.admit_status = 'admitted' and c.provider_id in (select pv.id from pv)),
        'processed_7d', (select count(*) from pipeline.scholarship_page_candidates c where c.read_at > v_d7 and c.provider_id in (select pv.id from pv)),
        'admitted_7d', (select count(*) from pipeline.scholarship_page_candidates c where c.admitted_at > v_d7 and c.admit_status = 'admitted' and c.provider_id in (select pv.id from pv)),
        'admitted_in_rate_window', (select count(*) from pipeline.scholarship_page_candidates c where c.admitted_at > v_rs and c.admit_status = 'admitted' and c.provider_id in (select pv.id from pv))),
    'rankings', jsonb_build_object('label', 'Rankings (universities with none)', 'sort', 12, 'level', 'provider',
        'eligible', (select count(*) from rk), 'waiting_layer4', 0, 'not_supported', (select count(*) from rk where k = 'not_supported'),
        'stored_source', 0, 'requires_acquisition', (select count(*) from rk where k = 'acquire'),
        'processed_24h', (select count(*) from catalogue.provider_rankings x where x.verified_at > v_d1 and x.provider_id in (select pv.id from pv)),
        'admitted_24h', (select count(*) from catalogue.provider_rankings x where x.verified_at > v_d1 and x.provider_id in (select pv.id from pv)),
        'processed_7d', (select count(*) from catalogue.provider_rankings x where x.verified_at > v_d7 and x.provider_id in (select pv.id from pv)),
        'admitted_7d', (select count(*) from catalogue.provider_rankings x where x.verified_at > v_d7 and x.provider_id in (select pv.id from pv)),
        'admitted_in_rate_window', (select count(*) from catalogue.provider_rankings x where x.verified_at > v_rs and x.provider_id in (select pv.id from pv)),
        'note', case when not exists (select 1 from ref.ranking_sources x where x.status = 'active') then 'no active ranking source' end))
    into v_prov;

  -- rows with the measured rate and forecast (no rate, no forecast)
  for r in select e.key, e.value v from jsonb_each(v_course || v_prov) e loop
    v_rows := v_rows || (r.v || jsonb_build_object('field', r.key,
      'processed_24h', coalesce((r.v->>'processed_24h')::bigint, 0), 'admitted_24h', coalesce((r.v->>'admitted_24h')::bigint, 0),
      'processed_7d', coalesce((r.v->>'processed_7d')::bigint, 0), 'admitted_7d', coalesce((r.v->>'admitted_7d')::bigint, 0),
      'accepted_per_hour', round(coalesce((r.v->>'admitted_in_rate_window')::numeric, 0) / v_rh, 3),
      'forecast_hours', case when coalesce((r.v->>'admitted_in_rate_window')::numeric, 0) > 0
                             then round(greatest(0, (r.v->>'eligible')::numeric - (r.v->>'not_supported')::numeric) / ((r.v->>'admitted_in_rate_window')::numeric / v_rh)) end,
      'forecast_at', case when coalesce((r.v->>'admitted_in_rate_window')::numeric, 0) > 0
                          then now() + make_interval(secs => (greatest(0, (r.v->>'eligible')::numeric - (r.v->>'not_supported')::numeric) / ((r.v->>'admitted_in_rate_window')::numeric / v_rh) * 3600)::double precision) end));
  end loop;
  select coalesce(jsonb_agg(x order by (x->>'sort')::int), '[]'::jsonb) into v_rows from jsonb_array_elements(v_rows) x;

  -- the source-proof lane
  v_proof := jsonb_build_object(
    'waiting_for_page_proof', (select count(*) from pipeline.course_page_proofs y where not y.proven),
    'requests', coalesce((select jsonb_object_agg(z.k, z.n) from (select q.route || ':' || q.state k, count(*) n from pipeline.source_proof_requests q group by 1) z), '{}'::jsonb),
    'settled_24h', (select count(*) from pipeline.source_proof_requests q where q.settled_at > v_d1),
    'outcomes_24h', coalesce((select jsonb_object_agg(z.o, z.n) from (select q.outcome o, count(*) n from pipeline.source_proof_requests q where q.settled_at > v_d1 group by 1) z), '{}'::jsonb),
    'free_per_run', security.pipeline_num_v1('proof.feed_per_run', 50), 'paid_search_per_run', security.pipeline_num_v1('proof.search_per_run', 0));
  return jsonb_build_object('at', now(), 'country', v_c, 'rate_window_hours', v_rh, 'fields', v_rows, 'source_proof', v_proof,
                            'coverage_cache_at', (select max(a.computed_at) from pipeline.course_attribute_coverage a where a.attribute = 'intakes'),
                            'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);  -- fixed: milliseconds
end $function$;
revoke all on function security.field_backlog_v1(text) from public, anon, authenticated;

select pg_temp.edit_once('public.admin_pipeline_yield(jsonb)', array['a38814324515b163a34129b7a9d01dbd'], array['34617ad96ea43189509c3f4dd536d50e'], array[
 [$o$|| jsonb_build_object('lane_status', security.lane_status_v1());$o$,
  $n$|| jsonb_build_object('lane_status', security.lane_status_v1())
         -- CF-247 mandate 3 Nov 2026 12:04 §5: the per-field backlog, measured by the platform
         || jsonb_build_object('field_backlog', security.field_backlog_v1(nullif(p_args->>'country', '')));$n$]], array[1]);

-- 6. the job (G1, G2: its command has no number) --------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('source-proof-feed', 'Course pages', 49, 'Find pages for courses waiting for page proof',
  'Twice an hour: courses the standing gap queue holds as waiting for page proof are routed to the existing page-finding lanes: course-relink is asked to try a course whose stored page was refused (free, proof.feed_per_run), and, only when proof.search_per_run is above 0 (paid, ships 0), the course-page search is queued. Courses waiting on Layer 4, locked by hand or still being read are left to that process. A course is tried at most proof.max_attempts times, and again only when its page, its provider''s stored lists or verified pages, or its search recipe change (pipeline.source_proof_requests).',
  4, false, 'pages')
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'source-proof-feed') then
    perform cron.schedule('source-proof-feed', '14,44 * * * *', $c$select security.source_proof_feed_v1()$c$);
  end if;
end $j$;
update pipeline.automation_catalogue set description = description || ' Also tries again a course the source-proof lane asks for (job source-proof-feed), once per request.'
 where jobname = 'course-relink' and description not like '%source-proof%';

-- 7. component register ---------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.source_proof_requests', 'Layer 2', 'Course pages', 'Source-proof lane: route, fingerprint, tries and outcome per course waiting for page proof', 'active', '{}', '20261103190000'),
 ('function', 'security.source_proof_feed_v1', 'Layer 2', 'Course pages', 'Job source-proof-feed: routes courses waiting for page proof to existing lanes', 'active', '{}', '20261103190000'),
 ('function', 'security.source_proof_relink_asked_v1', 'Layer 2', 'Course pages', 'course-relink tries a course again on request', 'active', '{}', '20261103190000'),
 ('function', 'security.field_backlog_v1', 'Platform', 'Platform upkeep', 'Per-field backlog, rates and forecast (Pipeline yield)', 'active', '{}', '20261103190000'),
 ('job', 'source-proof-feed', 'Layer 2', 'Course pages', 'Routes courses waiting for page proof to course-relink (and, when set, course-page search)', 'active', '{}', '20261103190000')
on conflict do nothing;

-- 8. post-check -----------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'proof.search_per_run') <> 0 then
    raise exception 'source proof post-check: proof.search_per_run must ship 0 (paid search)'; end if;
  if (select command from cron.job where jobname = 'source-proof-feed') <> 'select security.source_proof_feed_v1()' then
    raise exception 'source proof post-check: job source-proof-feed runs another command'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'source-proof-feed') then
    raise exception 'source proof post-check: job source-proof-feed is not catalogued'; end if;
end $$;
