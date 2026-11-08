-- CF-247 SCH / DISC (lane G, Platform Admin mandate 8 Nov 2026 "cross-domain autonomous delivery and closure", lane SCH: "fresh per-provider stages ... honest no-offering
-- proof and no repeating fruitless paid pages"; Controller instruction 8 Nov 2026 14:06 Melbourne: "recover productive eligible work without uncontrolled re-crawls").
--
-- Finding (live read 8 Nov 2026 03:00-03:30 UTC, project fxcwkweaxjtknorudmwp, SELECT only):
--   1. "Zero scholarships" is mostly "not searched, by policy", not "searched, found nothing". 2,359 of 2,826 providers read source_not_discovered (and 2,110 of the
--      20,505 cases). Of the 2,359: 1,208 have no discovery row at all (1,078 Canadian providers, 130 New Zealand private providers: the refill opens AU only plus the
--      pilot list; 659 have no website; 73 are Canadian universities with no active course), 753 are discovery not_eligible (policy), 295 were searched and found nothing
--      (discovery status empty), 62 mapped sources but kept none. One word covered four different facts, so the 72-hour escalation and the work items treated every
--      policy exclusion as a defect of the discovery job, and a searched-and-empty provider had no way to read as "searched, nothing found".
--   2. The 29 "empty" discovery rows whose method is map:budget (28) or map:403 (1) are not searches (13 Oct and earlier); they must never read as searched-zero.
--   3. Suggested listing pages (pipeline.scholarship_listing_pages source suggested, not active) are the only way a large university's catalogue is read: 132 wait,
--      the oldest since 10 Oct. 50 of them (28 providers) belong to admission-eligible providers on their own site and not held; no recovery exists for them (their
--      case state source_found_unread carries no recovery), and sch_cov.recover_listings_on (off) only reaches listings the AI classified from a candidate page.
--   4. A listing page is read again every 7 days whatever it yielded (svc_scholarship_listing_record_v2): an unchanged catalogue is crawled weekly for nothing.
--   5. A candidate page that fails with a time-out, a server error or a credit refusal three times is never read again (svc_scholarship_candidate_next takes attempts < 3);
--      IQ-00129 recorded 202 such scholarship reads on 3 Nov. Live today: 37 candidates at the cap with 408/500/502/402, nearly all on repository or aggregator pages,
--      so the yield is small but the defect is structural.
--   Not a defect (so not changed): 249 unread candidates "due" are 232 held by policy (ineligible or capped provider) and 17 priority-2 rows by design.
--   The 370 active-unpublished scholarships: 243 fail only "no stated award value" (236 text_only: the page states a benefit, not an amount, for example "stipend
--   equivalent to the RTP rate"); that is a publication rule decision for the Platform Admin and is not touched here.
--
-- Change (every new spend path ships OFF; nothing is admitted, decided or published by this migration):
--   * security.scholarship_scope_v1(uuid): why a provider is in or out of scholarship search (one place, read-only).
--   * Two resolved coverage states: searched_none (a successful site map found no scholarship page; the provider is searched again on the existing cadence) and
--     not_in_scope (policy: country not open, provider type not admitted, no website, directory site, no active course, below the course minimum). Providers fall in
--     them only when switch sch_cov.scope_states_on is 1 (ships on: classification only, no work item, no spend). A budget or refused map is never searched_none.
--   * security.scholarship_listing_accept_v1() and job scholarship-listing-accept: under the existing switch sch_cov.recover_listings_on (off), at most
--     batch.sch_coverage_recover suggested listings an hour (sch_cov.recover_per_provider_max a provider), own site, admission-eligible provider, not held, not hidden,
--     only while the scholarship Firecrawl share is not held, each at most once (scholarship_coverage_recoveries, action promote_listing). The page is then read by the
--     normal listing reader; its items become candidates and take the normal AI admission and Layer 4 route.
--   * Listing zero-yield guard: a complete catalogue read whose item set is unchanged is read again after reread.scholarship_listing_unchanged_days (30), not 7.
--   * Park and recover (IQ-00129): security.scholarship_transient_recover_v1() and job scholarship-transient-recover, switch retry.scholarship_transient_recover_on (off):
--     a candidate that stopped at the attempt cap on a time-out, a server error or a credit refusal is parked for retry.scholarship_transient_park_hours, then given one
--     more set of reads, at most retry.scholarship_transient_cycles_max times, only while the scholarship share is not held and the provider is eligible and not held;
--     each cycle and its outcome (read, or failed again) is kept in pipeline.scholarship_read_retry_cycles.
-- Consumer API: untouched (no public.website_v2_*, website_edge_*, zoho_edge_*, api.* function or table is created, read in a new way or changed).
--
-- Live definitions this change edits (read 8 Nov 2026, md5 of pg_get_functiondef), then the md5 after:
--   security.scholarship_coverage_classify_v1(uuid[])                                   7cd322359de3c7f823df240452afc2a8 -> e305eb1354ba06dc5922d0d7b7f3ed19
--   security.scholarship_coverage_items_v1(uuid[])                                      5605660603d40b3917001c37807a09bb -> 6931746c40448bd7182472dd1f8b433e
--   public.svc_scholarship_listing_record_v2(bigint,text,integer,jsonb,text,jsonb)      9207e7fd49ffa0ba7ae5f3aae4bbcbf6 -> 97b5f8cefd83b74c7e09f27a391ab69c
-- Replaces: the provider-level fallback "source_not_discovered" for providers that are out of scope or were searched with no result (inside security.scholarship_coverage_classify_v1 and security.scholarship_coverage_items_v1, in place); the fixed 7-day re-read of an unchanged listing (inside public.svc_scholarship_listing_record_v2, in place)
-- Retires: nothing
-- Nothing is dropped or deleted. No setting is switched on that spends: sch_cov.recover_listings_on stays 0; retry.scholarship_transient_recover_on ships 0.

-- 0 the definitions this change calls, as read live -------------------------------------------------------------------------------------------------
do $g$
declare v_sig text;
begin
  foreach v_sig in array array['security.pipeline_num_v1(text,numeric)', 'security.pipeline_list_v1(text,jsonb)', 'security.lane_paid_hold_v1(text)', 'security.fc_sch_held_v1(uuid,boolean)',
                               'security.fc_sch_eligible_v1(uuid)', 'security.scholarship_admission_provider_ok_v1(uuid)', 'security.third_party_host_v1(text)',
                               'security.url_on_provider_sites(text,uuid)', 'security.provider_sch_search_off_v1(uuid)', 'security.scholarship_url_norm(text)'] loop
    if to_regprocedure(v_sig) is null then raise exception 'this change calls %, which does not exist', v_sig; end if;
  end loop;
  if to_regclass('security.provider_hidden_v1') is null then raise exception 'this change reads security.provider_hidden_v1, which does not exist'; end if;
end $g$;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1 settings (G2): label, range, unit, used_by; every spend path ships off -------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'sch_cov.scope_states_on', 'Scholarship coverage: show out-of-scope and searched-none providers as their own states',
  '1: a provider that is outside scholarship search by policy (country not open, provider type not admitted, no website, directory site, no active course, below the course minimum) reads "not in scope", and a provider whose site map succeeded and found no scholarship page reads "searched, none found" (it is searched again on the normal cadence), instead of "source not discovered". Classification only: no work item, no read, no spend. 0: every such provider reads "source not discovered" as before.',
  'number', to_jsonb(1), 0, 1, 'on (1) or off (0)', 1450, 'Controller instruction 8 Nov 2026: honest no-offering proof; classification only, ships on', 'Scholarship coverage recovery',
  'security.scholarship_coverage_items_v1 (provider case), security.scholarship_coverage_classify_v1 (provider state)'),
 ('pipeline', 'reread.scholarship_listing_unchanged_days', 'Scholarship listings: read a complete catalogue again after, when it has not changed',
  'A scholarship catalogue page read in full whose list of scholarships is the same as at its last read is read again after this many days (a changed catalogue, a partly read one and a failed read keep their own cadence). Stops an unchanged catalogue being paid for every week.',
  'number', to_jsonb(30), 7, 180, 'days', 1451, 'Controller instruction 8 Nov 2026: no repeated zero-yield crawl', 'Scholarship discovery', 'public.svc_scholarship_listing_record_v2'),
 ('pipeline', 'retry.scholarship_transient_recover_on', 'Scholarship pages: retry reads that stopped on a time-out, a server error or a credit refusal',
  '1: a candidate scholarship page that stopped at the attempt cap on an HTTP 408, 425, 429, 5xx or 402 (or no answer) is parked, then given one more set of reads after the park time, at most the cycle limit, only while the scholarship Firecrawl share is not held and the provider is eligible and not held. 0: off.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1452, 'Controller instruction 8 Nov 2026 (IQ-00129): ships off (Firecrawl spend)', 'Scholarship discovery', 'security.scholarship_transient_recover_v1'),
 ('pipeline', 'retry.scholarship_transient_park_hours', 'Scholarship pages: park a transient failure for',
  'A candidate page that stopped on a transient failure is left alone this long before it is retried, so a site or the scraper has time to recover.',
  'number', to_jsonb(48), 1, 720, 'hours', 1453, 'Controller instruction 8 Nov 2026 (IQ-00129)', 'Scholarship discovery', 'security.scholarship_transient_recover_v1'),
 ('pipeline', 'retry.scholarship_transient_cycles_max', 'Scholarship pages: most retry cycles of one page',
  'One candidate page is given at most this many extra sets of reads in its life; a page that fails again each time is then left, with its history kept.',
  'number', to_jsonb(1), 1, 5, 'cycles', 1454, 'Controller instruction 8 Nov 2026 (IQ-00129): no repeated zero-yield crawl', 'Scholarship discovery', 'security.scholarship_transient_recover_v1'),
 ('pipeline', 'batch.scholarship_transient_recover', 'Scholarship pages: retry cycles started per run',
  'Each hourly run starts at most this many retry cycles across all providers.',
  'number', to_jsonb(20), 0, 200, 'pages', 1455, 'Controller instruction 8 Nov 2026 (IQ-00129)', 'Scholarship discovery', 'security.scholarship_transient_recover_v1')
on conflict (toolset_key, key) do nothing;

-- 2 tables (beside the consumer API) -------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.scholarship_read_retry_cycles (
  candidate_id bigint not null,
  cycle int not null,
  provider_id uuid not null,
  reason_class text not null check (reason_class in ('timeout', 'server', 'budget', 'no_answer')),
  http_status int,
  released_at timestamptz not null default now(),
  outcome text check (outcome in ('read', 'failed_again')),
  outcome_at timestamptz,
  primary key (candidate_id, cycle));
comment on table pipeline.scholarship_read_retry_cycles is 'CF-247 (IQ-00129, Controller instruction 8 Nov 2026): each extra set of reads given to a candidate scholarship page that stopped at the attempt cap on a transient failure (time-out, server error, credit refusal), the failure class, and its outcome (read, or failed again). Bounds the retries: a page has at most retry.scholarship_transient_cycles_max cycles. Written only by security.scholarship_transient_recover_v1. Never read by the consumer API.';

-- 3 coverage states: out of scope and searched-none (both resolved; neither escalates) -----------------------------------------------------------------
insert into pipeline.scholarship_coverage_state_codes(code, title, resolved, owner, existing_status, escalate_when, work_event, sort) values
 ('searched_none', 'Searched, none found', true, 'none (resolved: searched again on the discovery cadence)',
  'scholarship_discovery_providers.status empty after a successful site map (method map_search, no map: refusal)', 'never', 'succeeded', 131),
 ('not_in_scope', 'Not in scholarship scope', true, 'Platform Admin (scholarship scope: countries, provider types, pilot list)',
  'security.scholarship_scope_v1: country not open, provider type not admitted, no website, directory site, no active course, below the course minimum, or discovery not_eligible', 'never', 'succeeded', 132)
on conflict (code) do nothing;

-- 4 why a provider is in or out of scholarship search -------------------------------------------------------------------------------------------------------
create or replace function security.scholarship_scope_v1(p_provider_id uuid) returns text
language sql stable security definer set search_path to '' as $function$
  -- CF-247 SCH (8 Nov 2026): the same gates the discovery refill applies, named. in_scope means the refill would queue the provider (or already has).
  select case
           when p.id is null then 'unknown_provider'
           when nullif(btrim(coalesce(p.website, '')), '') is null then 'no_website'
           when security.third_party_host_v1(p.website) or dp.status = 'directory_site' then 'directory_site'
           when not coalesce(k.scholarship_ingestion_enabled, false) then 'country_not_open'
           when dp.status = 'not_eligible' then 'discovery_not_eligible'
           when not (k.iso_alpha2 = any (security.pipeline_list_v1('scholarship.refill_open_countries', '["AU"]'::jsonb))
                     or security.scholarship_admission_provider_ok_v1(p.id)) then 'country_or_type_not_admitted'
           when not exists (select 1 from catalogue.courses co where co.provider_id = p.id and co.lifecycle_status = 'active') then 'no_active_courses'
           when not security.fc_sch_eligible_v1(p.id) then 'below_course_minimum'
           else 'in_scope' end
    from (select 1) one
    left join catalogue.providers p on p.id = p_provider_id
    left join ref.countries k on k.id = p.country_id
    left join pipeline.scholarship_discovery_providers dp on dp.provider_id = p.id
$function$;
revoke all on function security.scholarship_scope_v1(uuid) from public, anon, authenticated;

-- 5 the three guarded edits ------------------------------------------------------------------------------------------------------------------------------
-- 5a the provider case: out of scope, searched none, or (as before) not discovered
select pg_temp.edit_once('security.scholarship_coverage_items_v1(uuid[])', '5605660603d40b3917001c37807a09bb', '6931746c40448bd7182472dd1f8b433e', array[
 [$o$    select pv.id provider_id, 'provider' item_key, 'source_not_discovered' state,
$o$, $n$    select pv.id provider_id, 'provider' item_key,
           -- CF-247 SCH (8 Nov 2026): a successful site map that found no scholarship page is "searched, none found"; a provider outside scholarship search by policy is "not in scope"
           case when security.pipeline_num_v1('sch_cov.scope_states_on', 1) >= 1 and dp.status = 'empty' and coalesce(dp.method, '') ~ 'map_search[(]' and coalesce(dp.method, '') !~ 'map:' then 'searched_none'
                when security.pipeline_num_v1('sch_cov.scope_states_on', 1) >= 1 and security.scholarship_scope_v1(pv.id) <> 'in_scope' then 'not_in_scope'
                else 'source_not_discovered' end state,
$n$],
 [$o$'admission_ok', pv.admit_ok, 'provider_type', pv.ptype) evidence, null::text recovery$o$, $n$'admission_ok', pv.admit_ok, 'provider_type', pv.ptype,
                              'scope', security.scholarship_scope_v1(pv.id)) evidence, null::text recovery$n$]]::text[][], array[1, 1]);

-- 5b the provider state: the two new states before the old fallback
select pg_temp.edit_once('security.scholarship_coverage_classify_v1(uuid[])', '7cd322359de3c7f823df240452afc2a8', 'e305eb1354ba06dc5922d0d7b7f3ed19', array[
 [$o$                         else 'source_not_discovered' end),
$o$, $n$                         when p.states ? 'searched_none' then 'searched_none'
                         when p.states ? 'not_in_scope' then 'not_in_scope'
                         else 'source_not_discovered' end),
$n$]]::text[][], array[1]);

-- 5c a complete catalogue that has not changed is read again after reread.scholarship_listing_unchanged_days
select pg_temp.edit_once('public.svc_scholarship_listing_record_v2(bigint,text,integer,jsonb,text,jsonb)', '9207e7fd49ffa0ba7ae5f3aae4bbcbf6', '97b5f8cefd83b74c7e09f27a391ab69c', array[
 [$o$                             when p_status = 'read' then now() + make_interval(days => security.pipeline_num_v1('reread.scholarship_listing_days', 7)::int)
$o$, $n$                             -- CF-247 SCH (8 Nov 2026): the same whole catalogue as at the last read is not paid for again next week
                             when p_status = 'read' and v_state in ('complete', 'single') and l.read_at is not null and l.item_hash is not distinct from v_hash
                               then now() + make_interval(days => security.pipeline_num_v1('reread.scholarship_listing_unchanged_days', 30)::int)
                             when p_status = 'read' then now() + make_interval(days => security.pipeline_num_v1('reread.scholarship_listing_days', 7)::int)
$n$]]::text[][], array[1]);

-- 6 suggested listings of eligible providers become listing sources (switch sch_cov.recover_listings_on, off) ----------------------------------------------
create or replace function security.scholarship_listing_accept_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SCH (8 Nov 2026): a suggested scholarship listing page (found, never accepted) of an admission-eligible provider, on its own site, becomes a listing source: the
-- normal listing reader reads it (Firecrawl through the scholarship share), its items become candidates, and each candidate takes the normal AI admission and Layer 4 route.
-- Nothing is admitted, decided or published here. At most batch.sch_coverage_recover a run and sch_cov.recover_per_provider_max a provider; each listing once
-- (pipeline.scholarship_coverage_recoveries is unique on case and action); not while the scholarship Firecrawl share is held.
declare v_max int := security.pipeline_num_v1('batch.sch_coverage_recover', 10)::int; v_pp int := security.pipeline_num_v1('sch_cov.recover_per_provider_max', 3)::int;
        r record; v_k int; v_done int := 0; v_skip int := 0; v_per jsonb := '{}'::jsonb; v_hold text;
begin
  if security.pipeline_num_v1('sch_cov.recover_listings_on', 0) < 1 then return jsonb_build_object('ran', false, 'reason', 'sch_cov.recover_listings_on is 0'); end if;
  v_hold := security.lane_paid_hold_v1('sch_scrape');
  if v_hold is not null then return jsonb_build_object('ran', false, 'reason', 'the scholarship Firecrawl share is held', 'hold', v_hold); end if;
  for r in select l.id, l.provider_id, l.url from pipeline.scholarship_listing_pages l
            where l.source = 'suggested' and not l.active
              and not exists (select 1 from pipeline.scholarship_coverage_recoveries x where x.item_key = 'listing:' || l.id and x.action = 'promote_listing')
            order by l.added_at, l.id loop
    exit when v_done >= v_max;
    if coalesce((v_per->>r.provider_id::text)::int, 0) >= v_pp then continue; end if;
    if not security.scholarship_admission_provider_ok_v1(r.provider_id) or security.fc_sch_held_v1(r.provider_id, true) or security.provider_sch_search_off_v1(r.provider_id)
       or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.provider_id)
       or security.third_party_host_v1(r.url) or not coalesce(security.url_on_provider_sites(r.url, r.provider_id), false) then v_skip := v_skip + 1; continue; end if;
    update pipeline.scholarship_listing_pages l set source = 'auto', active = true, status = 'waiting', next_read_at = now()
     where l.id = r.id and l.source = 'suggested' and not l.active;
    get diagnostics v_k = row_count;
    insert into pipeline.scholarship_coverage_recoveries(provider_id, item_key, action, state_before, detail)
    values (r.provider_id, 'listing:' || r.id, 'promote_listing', 'source_found_unread', jsonb_build_object('listing_id', r.id, 'url', r.url, 'changed', v_k, 'by', 'scholarship_listing_accept_v1'))
    on conflict (item_key, action) do nothing;
    if v_k > 0 then v_done := v_done + 1; v_per := v_per || jsonb_build_object(r.provider_id::text, coalesce((v_per->>r.provider_id::text)::int, 0) + 1); end if;
  end loop;
  return jsonb_build_object('ran', true, 'accepted', v_done, 'skipped', v_skip, 'providers', (select count(*) from jsonb_object_keys(v_per)));
end $function$;
revoke all on function security.scholarship_listing_accept_v1() from public, anon, authenticated;

-- 7 park and recover: transient failures get a bounded second chance (IQ-00129) ---------------------------------------------------------------------------
create or replace function security.scholarship_transient_recover_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- CF-247 SCH (IQ-00129, 8 Nov 2026): a candidate page that stopped at the attempt cap (the candidate reader takes attempts below the cap only) on a time-out, a busy or
-- failing server or a credit refusal is parked retry.scholarship_transient_park_hours, then given a fresh set of reads: at most retry.scholarship_transient_cycles_max
-- times in its life, batch.scholarship_transient_recover a run, sch_cov.recover_per_provider_max a provider, only while the scholarship Firecrawl share is not held
-- and the provider is eligible, not held and not hidden. A refusal (403), a missing page (404, 410) and a page judged not a scholarship are not transient and are left.
-- Nothing is admitted here: the page goes back to the normal reader and the normal admission route.
declare v_max int := security.pipeline_num_v1('batch.scholarship_transient_recover', 20)::int; v_park numeric := security.pipeline_num_v1('retry.scholarship_transient_park_hours', 48);
        v_cyc int := security.pipeline_num_v1('retry.scholarship_transient_cycles_max', 1)::int; v_pp int := security.pipeline_num_v1('sch_cov.recover_per_provider_max', 3)::int;
        r record; v_k int; v_done int := 0; v_skip int := 0; v_ok int := 0; v_fail int := 0; v_per jsonb := '{}'::jsonb; v_hold text; v_class text; v_n int;
begin
  -- outcomes of earlier cycles are recorded whether or not the switch is on
  update pipeline.scholarship_read_retry_cycles y set outcome = case when c.read_status = 'read' then 'read' else 'failed_again' end, outcome_at = now()
    from pipeline.scholarship_page_candidates c
   where y.outcome is null and c.id = y.candidate_id
     and (c.read_status = 'read' or (c.attempts >= 3 and c.read_status in ('scrape_failed', 'blocked', 'gone', 'too_thin', 'not_html')));  -- fixed: 3 is the candidate reader's own attempt cap (svc_scholarship_candidate_next)
  get diagnostics v_ok = row_count;
  select count(*) filter (where outcome = 'failed_again') into v_fail from pipeline.scholarship_read_retry_cycles where outcome_at >= now() - interval '1 hour';  -- fixed: the run's own hourly window
  if security.pipeline_num_v1('retry.scholarship_transient_recover_on', 0) < 1 then return jsonb_build_object('ran', false, 'reason', 'retry.scholarship_transient_recover_on is 0', 'outcomes_recorded', v_ok); end if;
  v_hold := security.lane_paid_hold_v1('sch_scrape');
  if v_hold is not null then return jsonb_build_object('ran', false, 'reason', 'the scholarship Firecrawl share is held', 'hold', v_hold, 'outcomes_recorded', v_ok); end if;
  for r in select c.id, c.provider_id, c.url, c.http_status from pipeline.scholarship_page_candidates c
            where c.read_status = 'scrape_failed' and c.attempts >= 3 and c.admit_status is null and c.matched_scholarship_id is null and c.admitted_scholarship_id is null  -- fixed: 3 is the candidate reader's own attempt cap
              and (c.http_status is null or c.http_status in (402, 408, 425, 429, 500, 502, 503, 504, 520, 522, 524))  -- fixed: the transient HTTP classes the course-page watchdog also retries
              and coalesce(c.read_at, c.found_at) < now() - make_interval(hours => v_park::int)
              and not exists (select 1 from pipeline.scholarship_read_retry_cycles y where y.candidate_id = c.id and y.outcome is null)
            order by c.found_at, c.id loop
    exit when v_done >= v_max;
    select count(*) into v_n from pipeline.scholarship_read_retry_cycles y where y.candidate_id = r.id;
    if v_n >= v_cyc then continue; end if;
    if coalesce((v_per->>r.provider_id::text)::int, 0) >= v_pp then continue; end if;
    if security.fc_sch_held_v1(r.provider_id, true) or security.provider_sch_search_off_v1(r.provider_id) or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.provider_id)
       or security.third_party_host_v1(r.url) or not security.scholarship_admission_provider_ok_v1(r.provider_id) then v_skip := v_skip + 1; continue; end if;
    v_class := case when r.http_status = 402 then 'budget' when r.http_status is null then 'no_answer' when r.http_status in (408, 425, 429) then 'timeout' else 'server' end;
    update pipeline.scholarship_page_candidates c set attempts = 0, next_read_at = now(), leased_until = null where c.id = r.id and c.read_status = 'scrape_failed' and c.attempts >= 3;  -- fixed: 3 is the candidate reader's own attempt cap
    get diagnostics v_k = row_count;
    if v_k > 0 then
      insert into pipeline.scholarship_read_retry_cycles(candidate_id, cycle, provider_id, reason_class, http_status) values (r.id, v_n + 1, r.provider_id, v_class, r.http_status) on conflict do nothing;
      v_done := v_done + 1; v_per := v_per || jsonb_build_object(r.provider_id::text, coalesce((v_per->>r.provider_id::text)::int, 0) + 1);
    end if;
  end loop;
  return jsonb_build_object('ran', true, 'released', v_done, 'skipped', v_skip, 'outcomes_recorded', v_ok, 'failed_again_last_hour', v_fail);
end $function$;
revoke all on function security.scholarship_transient_recover_v1() from public, anon, authenticated;

-- 8 jobs (G1), catalogue first --------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('scholarship-listing-accept', 'Scholarships', 60, 'Scholarship listings: accept suggested catalogue pages',
  'Every hour at :33: a suggested scholarship catalogue page of an admission-eligible provider, on its own site, becomes a listing source (read once by the normal listing reader, then on its cadence); at most batch.sch_coverage_recover a run, each once. Nothing happens while sch_cov.recover_listings_on is 0 or the scholarship Firecrawl share is held. Admits, decides and publishes nothing.',
  5, true, null),
 ('scholarship-transient-recover', 'Scholarships', 61, 'Scholarship pages: retry transient read failures',
  'Every hour at :37: a candidate scholarship page that stopped at the attempt cap on a time-out, a server error or a credit refusal is parked, then given one more set of reads (at most retry.scholarship_transient_cycles_max, batch.scholarship_transient_recover a run), only while the scholarship Firecrawl share is not held. Switch retry.scholarship_transient_recover_on (off). Records each cycle and its outcome. Admits nothing.',
  5, true, null)
on conflict (jobname) do nothing;
do $j$
begin
  if not exists (select 1 from cron.job where jobname = 'scholarship-listing-accept') then
    perform cron.schedule('scholarship-listing-accept', '33 * * * *', 'select security.scholarship_listing_accept_v1()');
  end if;
  if not exists (select 1 from cron.job where jobname = 'scholarship-transient-recover') then
    perform cron.schedule('scholarship-transient-recover', '37 * * * *', 'select security.scholarship_transient_recover_v1()');
  end if;
end $j$;

-- 9 register (housekeeping) ----------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'scholarship-listing-accept', 'Layer 2', 'Scholarships', 'Suggested scholarship catalogue pages of eligible providers become listing sources (switch off)', 'active', '{}', '20261108160000'),
 ('job', 'scholarship-transient-recover', 'Layer 2', 'Scholarships', 'Bounded park-and-recover of transient scholarship page read failures (switch off)', 'active', '{}', '20261108160000'),
 ('function', 'security.scholarship_scope_v1', 'Layer 2', 'Scholarships', 'Why a provider is in or out of scholarship search', 'active', '{}', '20261108160000'),
 ('table', 'pipeline.scholarship_read_retry_cycles', 'Layer 2', 'Scholarships', 'Retry cycles of transiently failed scholarship candidate pages and their outcomes', 'active', '{}', '20261108160000')
on conflict do nothing;

-- 10 post-check -------------------------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if md5(pg_get_functiondef('security.scholarship_coverage_items_v1(uuid[])'::regprocedure)) <> '6931746c40448bd7182472dd1f8b433e' then raise exception 'post-check: scholarship_coverage_items_v1'; end if;
  if md5(pg_get_functiondef('security.scholarship_coverage_classify_v1(uuid[])'::regprocedure)) <> 'e305eb1354ba06dc5922d0d7b7f3ed19' then raise exception 'post-check: scholarship_coverage_classify_v1'; end if;
  if md5(pg_get_functiondef('public.svc_scholarship_listing_record_v2(bigint,text,integer,jsonb,text,jsonb)'::regprocedure)) <> '97b5f8cefd83b74c7e09f27a391ab69c' then raise exception 'post-check: svc_scholarship_listing_record_v2'; end if;
  if (select count(*) from pipeline.scholarship_coverage_state_codes) <> 15 then raise exception 'post-check: 15 states'; end if;
  if (select count(*) from cron.job where jobname in ('scholarship-listing-accept', 'scholarship-transient-recover')) <> 2 then raise exception 'post-check: jobs'; end if;
  if (select count(*) from pipeline.automation_catalogue where jobname in ('scholarship-listing-accept', 'scholarship-transient-recover')) <> 2 then raise exception 'post-check: catalogue'; end if;
end $$;
