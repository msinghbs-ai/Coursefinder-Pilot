-- CF-247 F-INT.01 / SRC-01 (Platform Admin data population first delivery mandate, 9 Nov 2026; execution plan
-- docs/platform/nz-enrichment-brief/2026-11-09-intake-autonomous-production-cutover-plan.md sections 1-4): a deterministic, DEFAULT-OFF route that makes an
-- official MAIN-TEACHING academic calendar usable (approved) without a person, only when every safe condition holds; anything else stays proposed with one exact
-- reason. Part of the single intake release candidate (with #931: timed rechecks, the 22P02 fix and the default-off course-page exact-date route).
-- Why (measured read-only on production, 9 Nov 2026): 67 intake_calendar readings are proposed across 51 providers, 179 approved across 78, 31 rejected,
--   central.auto_approve_calendar_dates = 0. 13,240 active undated intake rows have no approved main teaching calendar. Switching the existing
--   auto-approve on would approve readings of the wrong page class (Adelaide "online how-to-apply", a college that is a different provider, pathway and English
--   pages, a six-session online reading): the 5 Nov wrong-document problem. This route applies the structural rules first and approves by rule only what passes.
-- What (existing architecture; no new job, scheduler, engine or screen):
--   1 Settings (G2), section Intake dates / Job sizes, all default off or conservative: central.calendar_qualify_main_teaching (0), batch.calendar_qualify,
--     batch.calendar_qualify_refresh, central.calendar_qualify_blocked_words, central.calendar_qualify_required_words, central.calendar_qualify_blocked_period_words,
--     central.calendar_qualify_min_starts, central.calendar_qualify_max_series, central.calendar_qualify_max_families, central.calendar_qualify_max_evidence_age_days.
--     central.calendar_excluded_words is READ (through security.calendar_scope_v1) and NOT changed: the Platform Admin decides additions (for example
--     internationalcollege, how-to-apply, /online). The qualifier applies the structural words of its own settings in addition, so it does not wait for that decision.
--   2 security.calendar_qualify_check_v1(proposal) (new, STABLE, writes nothing): the verdict of one proposed reading. It qualifies ONLY when all hold:
--       official host of the provider (website, binding.provider_host_aliases, approved pipeline.provider_extra_domains: the E16 rule for own hosts); the address is
--       not an excluded or structural word page (how-to-apply, online, international college, pathway, English, foundation, study abroad, exchange, residential, senior
--       college, single-programme medical, course pages, forms); the address or title names a calendar page; no period is named online, pathway, English,
--       foundation, college and the like; dates come from the existing deterministic reader (security.calendar_proposal_dates_v1) with the year printed in the quote
--       or its heading; at least central.calendar_qualify_min_starts distinct teaching starts fall within intake_dates.max_months_ahead months; the evidence is not
--       older than central.calendar_qualify_max_evidence_age_days; no value was rejected or withdrawn (pipeline.intake_date_rejections, withdrawn events); at most
--       central.calendar_qualify_max_series starts in a numbered series and central.calendar_qualify_max_families period families a year (more is a multi-calendar or
--       online reading that needs a scope check); no contradiction with an approved calendar (a different date for the same period and year) or a calendar set by hand;
--       at least one value the approved calendars do not already hold; no Platform Admin rejection of the same address; no provider-level lock by hand.
--   3 security.calendar_qualify_v1 (new, run inside the existing job policy-auto-approve through an md5-guarded edit of security.policy_auto_approve_v1): with the
--     switch off it does nothing. On, it checks up to batch.calendar_qualify proposals a run (never checked, changed inputs or due), approves the qualifying ones as a
--     MACHINE decision (decided_by null, note "Machine decision (rule calendar-qualify-v1, not a person)", actor system:calendar-qualify-v1 in
--     pipeline.calendar_qualify_decisions and pipeline.admin_control_events) with the evidence (quote, content hash, edition year, captured_at, address) and the before
--     and after of the proposal, and holds the rest with the reason. It does not use or flip central.auto_approve_calendar_dates.
--   4 Withdrawal path: security.calendar_qualify_withdraw_v1 / public.admin_calendar_qualify_withdraw_v1 (Platform Admin): the machine approval is withdrawn (the
--     reading becomes rejected by a person, so the route never approves that address again), the calendar leaves the calendar set (rows are looked at again), and
--     the values it admitted can be withdrawn through the existing governed intake_date_withdraw_v1 (bounded by batch.calendar_qualify_withdraw).
--   5 Bounded refresh of a stale edition through the existing acquisition ladder: for a reading that is otherwise qualified but whose edition is past or whose evidence is
--     older than the limit, the route asks for the document to be read again by the existing provider-facts reads (pipeline.calendar_refresh_requests, status found),
--     with the same eligibility, one open request, once per address, minimum age and the existing credit budget (central.calendar_refresh_credit_budget) as
--     public.svc_calendar_refresh_v1. No new spend authority and no fetch of its own: the stored page is read first (calendar-reread), the free direct read and the
--     budgeted Firecrawl read stay in the existing reads.
-- Consumer API: unchanged (G3). Only security.* functions, pipeline.* tables and settings are added; one public admin function is added (not part of the frozen set).
-- Replaces: md5-guarded edit of security.policy_auto_approve_v1 (189d5c4349f604653f20c8fc854d1cd1, production read 9 Nov 2026)
-- Retires: nothing (central.auto_approve_calendar_dates stays at 0 and is not used by this route)
-- Nothing is dropped or deleted.

create or replace function pg_temp.edit(p_sig text, p_md5 text, p_marker text, p_old text[], p_new text[], p_times int[]) returns text language plpgsql as $e$
declare v text := pg_get_functiondef(p_sig::regprocedure); i int; n int;
begin
  if position(p_marker in v) > 0 then return p_sig || ': already applied'; end if;
  if md5(v) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %, expected %)', p_sig, md5(v), p_md5; end if;
  for i in 1 .. array_length(p_old, 1) loop
    n := (length(v) - length(replace(v, p_old[i], ''))) / length(p_old[i]);
    if n <> p_times[i] then raise exception '%: edit % must apply exactly % time(s), found %', p_sig, i, p_times[i], n; end if;
    v := replace(v, p_old[i], p_new[i]);
  end loop;
  execute v;
  return p_sig || ': edited';
end $e$;

-- 0 the definition this change edits must be the production one (refused otherwise, before anything is written) ------------------------------------
do $g$ begin
  if position('calendar_qualify_v1' in pg_get_functiondef('security.policy_auto_approve_v1()'::regprocedure)) = 0
     and md5(pg_get_functiondef('security.policy_auto_approve_v1()'::regprocedure)) <> '189d5c4349f604653f20c8fc854d1cd1' then
    raise exception 'live security.policy_auto_approve_v1 differs from the definition this change edits (md5 %, expected 189d5c4349f604653f20c8fc854d1cd1)',
      md5(pg_get_functiondef('security.policy_auto_approve_v1()'::regprocedure));
  end if;
end $g$;

-- 1 settings (G2) -----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'central.calendar_qualify_main_teaching', 'Calendars: approve official main teaching calendars by rule',
  '1: a proposed calendar reading is approved without a person ONLY when it is an official main teaching calendar of the provider''s own domestic and international intakes and every check passes (provider''s own website host, not an online, how-to-apply, college, pathway, English, foundation, study abroad, exchange, residential, senior college or single-programme page, a current named edition with at least the minimum number of teaching starts inside the months-ahead limit, the dates read by the deterministic reader with the year quoted, no rejected or withdrawn value, no contradiction with an approved calendar, no hand lock or Platform Admin rejection). Every approval is a machine decision with its evidence and can be withdrawn. 0: nothing is approved by this route; readings stay proposed for a person. It does not use "Calendars: approve deterministic dated readings automatically".',
  'number', to_jsonb(0), 0, 1, 'on/off', 1020, 'Intake dates', 'security.calendar_qualify_v1; job policy-auto-approve (security.policy_auto_approve_v1)',
  'F-INT.01/SRC-01 (9 Nov 2026): off until the Platform Admin switches it on after release and QA (a passing qualification never switches anything on by itself)'),
 ('pipeline', 'batch.calendar_qualify', 'Calendar qualification: readings checked a run',
  'Proposed calendar readings checked by the qualification route in one run of job policy-auto-approve (every 10 minutes). A reading is checked again only when its inputs, the settings or the approved calendars of its provider change, or after "Intake dates: look again at a waiting row after".',
  'number', to_jsonb(25), 1, 100, 'readings', 1021, 'Job sizes', 'security.calendar_qualify_v1; job policy-auto-approve', 'F-INT.01/SRC-01 (9 Nov 2026): bounded work a run'),
 ('pipeline', 'batch.calendar_qualify_refresh', 'Calendar qualification: stale editions asked to be read again a run',
  'At most this many documents a run are handed to the existing provider-facts read because the qualified edition is past or its stored copy is older than the limit. Always within the existing "calendar refresh" credit budget, one open request at a time and once per address. 0 asks for none.',
  'number', to_jsonb(1), 0, 3, 'documents', 1022, 'Job sizes', 'security.calendar_qualify_v1; pipeline.calendar_refresh_requests', 'F-INT.01/SRC-01 (9 Nov 2026): bounded refresh, no new spend authority'),
 ('pipeline', 'batch.calendar_qualify_withdraw', 'Calendar qualification: values withdrawn a call',
  'Most intake values withdrawn in one call of the governed withdrawal of a machine-approved calendar; the call reports the rest and is repeated.',
  'number', to_jsonb(50), 1, 200, 'values', 1023, 'Job sizes', 'security.calendar_qualify_withdraw_v1', 'F-INT.01/SRC-01 (9 Nov 2026): withdrawal path'),
 ('pipeline', 'central.calendar_qualify_blocked_words', 'Calendar qualification: addresses and titles that are not a main teaching calendar',
  'A proposed calendar whose address or page title contains one of these words is never approved by rule (it stays proposed with the reason blocked_word). It adds to "Calendars: addresses that are not a main teaching calendar", which is read as well and is changed only by the Platform Admin.',
  'list', '["how-to-apply","how_to_apply","howtoapply","/apply","/online","online.","studyonline","-online","internationalcollege","international-college","international_college","pathway","english-language","english-pathway","elicos","foundation","study-abroad","exchange","inbound","residential","senior-college","orientation","brochure","flyer","/course/","/courses/","/programs/","/program/","/degrees/","census","exam","graduation","scholarship","medicine","medical","dental","veterinary"]'::jsonb, null, null, 'words', 1024, 'Intake dates', 'security.calendar_qualify_check_v1',
  'F-INT.01/SRC-01 (9 Nov 2026): the wrong-page classes of the 5 Nov 2026 findings (Adelaide online how-to-apply, WSU International College, Macquarie English pathway, residential and senior colleges)'),
 ('pipeline', 'central.calendar_qualify_required_words', 'Calendar qualification: words a calendar page address or title must contain',
  'At least one of these words must be in the address or page title of a reading before it is approved by rule (otherwise the page is not recognised as a calendar page: reason not_a_calendar_page).',
  'list', '["calendar","key-dates","keydates","key_dates","important-dates","important_dates","term-dates","semester-dates","trimester","academic-year","dates","teaching-period","study-period","start-dates","intake"]'::jsonb, null, null, 'words', 1025, 'Intake dates', 'security.calendar_qualify_check_v1',
  'F-INT.01/SRC-01 (9 Nov 2026): page type must be a calendar'),
 ('pipeline', 'central.calendar_qualify_blocked_period_words', 'Calendar qualification: period names that are not a main teaching period',
  'A reading with a period named with one of these words (course names in brackets are ignored) is not approved by rule (reason non_main_period): the document mixes in an online, pathway, English-language, foundation, college, study abroad, exchange, residential or research calendar.',
  'list', '["online","pathway","foundation","english","elicos","study abroad","exchange","residential","college","research","orientation","enrolment","enrollment","census","exam"]'::jsonb, null, null, 'words', 1026, 'Intake dates', 'security.calendar_qualify_check_v1',
  'F-INT.01/SRC-01 (9 Nov 2026): main teaching periods only'),
 ('pipeline', 'central.calendar_qualify_min_starts', 'Calendar qualification: fewest teaching starts a calendar must give',
  'The number of different teaching start dates, with the year quoted, that must fall inside the months-ahead limit for a reading to be approved by rule. A page with fewer is a notice or a single-programme page (reason too_few_starts).',
  'number', to_jsonb(2), 1, 12, 'starts', 1027, 'Intake dates', 'security.calendar_qualify_check_v1', 'F-INT.01/SRC-01 (9 Nov 2026)'),
 ('pipeline', 'central.calendar_qualify_max_series', 'Calendar qualification: most starts in one numbered series a year',
  'More starts of one numbered series in a year (for example session 1 to 6) than this is an online, accelerated or study-period calendar mixed in: the reading stays proposed for a scope check (reason scope_check_series).',
  'number', to_jsonb(4), 2, 12, 'starts', 1028, 'Intake dates', 'security.calendar_qualify_check_v1', 'F-INT.01/SRC-01 (9 Nov 2026): the UTS six-session reading needs a scope check'),
 ('pipeline', 'central.calendar_qualify_max_families', 'Calendar qualification: most different kinds of period in one year',
  'More kinds of period in one year (semester, trimester, term, session, study period, teaching period, main intake and so on) than this means several calendars in one reading: it stays proposed for a scope check (reason scope_check_families).',
  'number', to_jsonb(3), 1, 8, 'kinds', 1029, 'Intake dates', 'security.calendar_qualify_check_v1', 'F-INT.01/SRC-01 (9 Nov 2026)'),
 ('pipeline', 'central.calendar_qualify_max_evidence_age_days', 'Calendar qualification: oldest stored copy of a calendar page',
  'A reading whose stored page copy was captured longer ago than this is not approved by rule (reason evidence_stale); the page is handed to the existing refresh within its credit budget.',
  'number', to_jsonb(120), 7, 400, 'days', 1030, 'Intake dates', 'security.calendar_qualify_check_v1; security.calendar_qualify_v1', 'F-INT.01/SRC-01 (9 Nov 2026): a current edition')
on conflict (toolset_key, key) do nothing;

-- 2 tables (beside, never into, consumer shapes) --------------------------------------------------------------------------------------------------
create table if not exists pipeline.calendar_qualify_decisions (
  proposal_id uuid primary key references pipeline.provider_policy_proposals(id),
  provider_id uuid not null references catalogue.providers(id),
  fact_source_id uuid not null references pipeline.provider_fact_sources(id),
  rule text not null,
  verdict text not null check (verdict in ('approved', 'held', 'withdrawn')),
  reason text not null,
  detail jsonb not null default '{}'::jsonb,
  actor text not null,
  decided_at timestamptz not null default now(),
  settings_fp text not null,
  cal_set text,
  next_check_at timestamptz,
  evidence_id uuid references pipeline.evidence_artifacts(id),
  content_hash text,
  captured_at timestamptz,
  edition_year int,
  source_url text,
  quotes jsonb,
  before_state jsonb,
  after_state jsonb,
  approved_at timestamptz,
  withdrawn_at timestamptz,
  withdrawn_by uuid,
  withdrawn_reason text);
comment on table pipeline.calendar_qualify_decisions is 'CF-247 F-INT.01/SRC-01 (9 Nov 2026): the verdict of the calendar qualification route for each proposed intake_calendar reading: approved by rule (a MACHINE decision, actor system:calendar-qualify-v1, never a person) with its evidence (address, content hash, captured_at, edition year, quotes) and the before and after of the proposal; or held with the exact reason and the inputs it was judged on (settings fingerprint, calendar set of the provider); or withdrawn by a Platform Admin (when, who, why). One row per reading, replaced when the reading is judged again. Written by security.calendar_qualify_v1 and security.calendar_qualify_withdraw_v1; never read by the consumer API.';
create index if not exists calendar_qualify_decisions_provider_idx on pipeline.calendar_qualify_decisions(provider_id, verdict);
create index if not exists calendar_qualify_decisions_due_idx on pipeline.calendar_qualify_decisions(verdict, next_check_at);
alter table pipeline.calendar_qualify_decisions enable row level security;

create table if not exists pipeline.calendar_qualify_runs (
  id bigserial primary key,
  run_at timestamptz not null default now(),
  examined int not null default 0,
  approved int not null default 0,
  held int not null default 0,
  by_reason jsonb not null default '{}'::jsonb,
  refresh_asked int not null default 0,
  ms int not null default 0,
  error text);
comment on table pipeline.calendar_qualify_runs is 'CF-247 F-INT.01/SRC-01 (9 Nov 2026): one row for each run of the calendar qualification route that had work (readings checked, approved, held by reason, refresh asked, milliseconds) or failed (error). Nothing is written while central.calendar_qualify_main_teaching is 0. Read on the process results and by the release gate; never read by the consumer API.';
create index if not exists calendar_qualify_runs_at_idx on pipeline.calendar_qualify_runs(run_at desc);
alter table pipeline.calendar_qualify_runs enable row level security;

-- a withdrawn value is looked up by provider for every checked reading: only the 17 withdrawn events are indexed
create index if not exists course_intake_date_events_withdrawn_idx on pipeline.course_intake_date_events(provider_id) where outcome = 'withdrawn';

-- 3 the verdict of one proposed reading ------------------------------------------------------------------------------------------------------------
-- Written as one self-contained query (only production functions and tables), so the same text can be run as a SELECT against production for a dry run.
create or replace function security.calendar_qualify_check_v1(p_proposal_id uuid)
returns table(proposal_id uuid, provider_id uuid, fact_source_id uuid, qualifies boolean, reason text, detail jsonb, refreshable boolean,
              edition_year int, evidence_id uuid, content_hash text, captured_at timestamptz, source_url text, quotes jsonb)
language sql stable security definer set search_path to '' as $function$
  with cfg as (
    select security.pipeline_num_v1('central.calendar_qualify_min_starts', 2)::int min_starts,
           security.pipeline_num_v1('central.calendar_qualify_max_series', 4)::int max_series,
           security.pipeline_num_v1('central.calendar_qualify_max_families', 3)::int max_fam,
           security.pipeline_num_v1('central.calendar_qualify_max_evidence_age_days', 120)::int max_age,
           security.pipeline_num_v1('intake_dates.max_months_ahead', 18)::int ahead,
           (now() at time zone 'Australia/Melbourne')::date today,  -- fixed: the Australian calendar day
           array(select lower(btrim(w)) from jsonb_array_elements_text(case when jsonb_typeof(security.toolset_setting('pipeline', 'central.calendar_qualify_blocked_words')) = 'array' then security.toolset_setting('pipeline', 'central.calendar_qualify_blocked_words') else '[]'::jsonb end) w where btrim(w) <> '') blocked,
           array(select lower(btrim(w)) from jsonb_array_elements_text(case when jsonb_typeof(security.toolset_setting('pipeline', 'central.calendar_qualify_required_words')) = 'array' then security.toolset_setting('pipeline', 'central.calendar_qualify_required_words') else '[]'::jsonb end) w where btrim(w) <> '') required,
           array(select lower(btrim(w)) from jsonb_array_elements_text(case when jsonb_typeof(security.toolset_setting('pipeline', 'central.calendar_qualify_blocked_period_words')) = 'array' then security.toolset_setting('pipeline', 'central.calendar_qualify_blocked_period_words') else '[]'::jsonb end) w where btrim(w) <> '') pblocked,
           array(select lower(btrim(w)) from jsonb_array_elements_text(case when jsonb_typeof(security.toolset_setting('pipeline', 'binding.provider_host_aliases')) = 'array' then security.toolset_setting('pipeline', 'binding.provider_host_aliases') else '[]'::jsonb end) w where btrim(w) <> '') aliases),
  p as (
    select x.id pid, x.provider_id, x.fact_source_id, x.parser, x.url, x.status, x.proposal, x.content_hash,
           coalesce(x.evidence_id, f.evidence_id) evid, f.title ftitle, pr.stable_key, pr.website,
           regexp_replace(lower(coalesce(substring(x.url from '^https?://([^/?#:]+)'), '')), '^www\.', '') host,
           lower(x.url || ' ' || coalesce(f.title, '')) hay
      from pipeline.provider_policy_proposals x
      join pipeline.provider_fact_sources f on f.id = x.fact_source_id
      join catalogue.providers pr on pr.id = x.provider_id
     where x.id = p_proposal_id and x.kind = 'intake_calendar'),
  ev as (select e.id, e.captured_at, e.content_hash from pipeline.evidence_artifacts e join p on e.id = p.evid),
  own as (
    select array(select distinct z.h from (
             select regexp_replace(lower(coalesce(substring(p.website from '^https?://([^/?#:]+)'), '')), '^www\.', '') h
             union all select regexp_replace(lower(btrim(w)), '^www\.', '')
                         from unnest(cfg.aliases) e, lateral regexp_split_to_table(substr(e, strpos(e, '=') + 1), '\s+') w
                        where split_part(e, '=', 1) = lower(p.stable_key)
             union all select regexp_replace(lower(d.domain), '^(https?://)?(www\.)?', '') from pipeline.provider_extra_domains d where d.provider_id = p.provider_id and d.state = 'approved') z
            where z.h <> '') hosts
      from p, cfg),
  d as materialized (
    select x.period, x.on_date, x.year, x.quote, x.year_quote, k.pkey,
           x.year is not null and (x.quote ~ ('\m' || x.year || '\M') or coalesce(x.year_quote, '') ~ ('\m' || x.year || '\M')) year_ok
      from p, security.calendar_proposal_dates_v1(p.pid) x,
           lateral (select btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(lower(coalesce(x.period, '')), '\(.*$', ''), '[_*]+', ' ', 'g'), '^\s*(19|20)\d\d\s*[-–—:]?\s*', ''), '\s+(19|20)\d\d\s*$', ''), '\s+', ' ', 'g')) pkey) k
     where x.kind = 'start' and x.on_date is not null),
  win as (select d.*, regexp_replace(d.pkey, '\s*\d+$', '') fam from d, cfg where d.year_ok and d.on_date >= cfg.today and d.on_date < cfg.today + make_interval(months => cfg.ahead)),
  a as (
    select security.calendar_period_canonical_v1(k.pkey) pk, x.year, x.on_date
      from p, cfg, security.calendar_dated_periods_v2(p.provider_id) x,
           lateral (select btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(lower(coalesce(x.period, '')), '\(.*$', ''), '[_*]+', ' ', 'g'), '^\s*(19|20)\d\d\s*[-–—:]?\s*', ''), '\s+(19|20)\d\d\s*$', ''), '\s+', ' ', 'g')) pkey) k
     where x.kind = 'start' and x.on_date is not null and x.year_ok
       -- an approved calendar of a structurally wrong page (for example a college that is another provider) is not a calendar to be contradicted
       and not exists (select 1 from unnest(cfg.blocked) w where position(w in lower(x.url)) > 0)),
  h as (
    select security.calendar_period_canonical_v1(lower(btrim(e->>'period'))) pk,
           array(select m::int from jsonb_array_elements_text(case when jsonb_typeof(e->'months') = 'array' then e->'months' else '[]'::jsonb end) m) months
      from p, pipeline.provider_policy_proposals x, jsonb_array_elements(case when jsonb_typeof(x.proposal->'periods') = 'array' then x.proposal->'periods' else '[]'::jsonb end) e
     where x.provider_id = p.provider_id and x.kind = 'intake_calendar' and x.status = 'approved' and x.style = 'by_hand'),
  wd as (select e.before_value->>'start_date' s from pipeline.course_intake_date_events e, p where e.provider_id = p.provider_id and e.outcome = 'withdrawn' and e.before_value->>'start_date' is not null),
  fam as (select w.fam, extract(year from w.on_date)::int y, count(distinct w.on_date) n from win w group by 1, 2),
  yr as (select y, count(distinct fam) n from fam group by y),
  f as (
    select p.pid, p.provider_id, p.fact_source_id, p.status, p.url, p.host, p.hay, cfg.*, own.hosts,
           (select z.id from pipeline.provider_policy_proposals z
             where z.provider_id = p.provider_id and z.kind = 'intake_calendar' and z.status = 'rejected' and z.id <> p.pid
               and (z.decided_by is not null or z.decision_note ilike 'platform admin%' or z.decision_note ilike 'withdrawn:%')
               and (z.fact_source_id = p.fact_source_id or regexp_replace(lower(z.url), '^https?://(www\.)?|/+$', '', 'g') = regexp_replace(lower(p.url), '^https?://(www\.)?|/+$', '', 'g'))
             order by z.decided_at desc nulls last limit 1) rej_id,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.provider_id and l.field in ('intakes', 'intake_calendar', 'calendar')) locked,
           exists (select 1 from unnest(own.hosts) o where p.host = o or p.host like '%.' || o) host_ok,
           security.calendar_scope_v1(p.proposal, p.url, p.parser) scope,
           (select w from unnest(cfg.blocked) w where position(w in p.hay) > 0 order by w limit 1) bword,
           exists (select 1 from unnest(cfg.required) w where position(w in p.hay) > 0) required_ok,
           (select w from unnest(cfg.pblocked) w, d where position(w in d.pkey) > 0 order by w limit 1) pword,
           (select count(*) from d) n_all,
           (select count(*) from d where d.year_ok) n_proved,
           (select count(*) from d where d.year_ok and d.on_date >= cfg.today) n_future,
           (select count(distinct w.on_date) from win w) n_win,
           (select min(d.on_date) from d where d.on_date::text in (select s from wd)
               or exists (select 1 from pipeline.intake_date_rejections r where r.provider_id = p.provider_id and (r.start_date = d.on_date or (r.quote is not null and r.quote = d.quote and r.year is not distinct from d.year)))) bad_date,
           coalesce((select max(n) from fam), 0) max_seen_series,
           coalesce((select max(n) from yr), 0) max_seen_fam,
           (select w.pkey || ' ' || w.year from win w join a on a.pk = security.calendar_period_canonical_v1(w.pkey) and a.year = w.year
             where not exists (select 1 from a a2 where a2.pk = a.pk and a2.year = a.year and a2.on_date = w.on_date) order by w.on_date limit 1) contradiction,
           (select w.pkey || ' ' || w.year from win w join h on h.pk = security.calendar_period_canonical_v1(w.pkey)
             where not (extract(month from w.on_date)::int = any (h.months)) order by w.on_date limit 1) hand_contradiction,
           exists (select 1 from win w where not exists (select 1 from a where a.pk = security.calendar_period_canonical_v1(w.pkey) and a.year = w.year)) has_new_value,
           (select e.id from ev e) ev_id, (select e.captured_at from ev e) ev_at, (select e.content_hash from ev e) ev_hash,
           (select max(w.year) from win w) edition_year
      from p, cfg, own),
  r as (
    select f.*,
      case
        when f.status is distinct from 'proposed' then 'not_a_proposed_calendar'
        when coalesce(cardinality(f.blocked), 0) = 0 or coalesce(cardinality(f.required), 0) = 0 or coalesce(cardinality(f.pblocked), 0) = 0 then 'qualifier_settings_missing'
        when f.rej_id is not null then 'platform_admin_rejected_address'
        when f.locked then 'provider_locked_by_hand'
        when not f.host_ok then 'host_not_provider_website'
        when f.scope <> 'main_teaching' then 'excluded_by_calendar_scope'
        when f.bword is not null then 'blocked_word'
        when not f.required_ok then 'not_a_calendar_page'
        when f.pword is not null then 'non_main_period'
        when f.ev_id is null then 'no_evidence'
        when f.n_all = 0 then 'no_dated_starts'
        when f.n_proved = 0 then 'year_not_proved'
        when f.n_win < f.min_starts and f.n_future = 0 then 'edition_not_current'
        when f.n_win < f.min_starts and f.n_win = 0 then 'starts_beyond_window'
        when f.n_win < f.min_starts then 'too_few_starts'
        when f.ev_at < now() - make_interval(days => f.max_age) then 'evidence_stale'
        when f.bad_date is not null then 'rejected_or_withdrawn_value'
        when f.max_seen_series > f.max_series then 'scope_check_series'
        when f.max_seen_fam > f.max_fam then 'scope_check_families'
        when f.hand_contradiction is not null then 'contradicts_hand_set_calendar'
        when f.contradiction is not null then 'contradicts_approved_calendar'
        when not f.has_new_value then 'adds_no_new_value'
        else 'qualifies' end code
      from f)
  select r.pid, r.provider_id, r.fact_source_id, r.code = 'qualifies', r.code,
         jsonb_strip_nulls(jsonb_build_object('host', r.host, 'own_hosts', to_jsonb(r.hosts), 'scope', r.scope, 'word', r.bword, 'period_word', r.pword,
           'starts_in_window', r.n_win, 'starts_proved', r.n_proved, 'starts_all', r.n_all, 'min_starts', r.min_starts, 'months_ahead', r.ahead,
           'max_series_seen', r.max_seen_series, 'max_families_seen', r.max_seen_fam, 'rejected_by', r.rej_id, 'rejected_value', r.bad_date,
           'contradiction', coalesce(r.hand_contradiction, r.contradiction), 'evidence_captured_at', r.ev_at)),
         r.code in ('edition_not_current', 'evidence_stale'),
         r.edition_year, r.ev_id, coalesce(r.ev_hash, (select p.content_hash from p)), r.ev_at, r.url,
         (select jsonb_agg(jsonb_build_object('period', z.pkey, 'date', z.on_date, 'quote', left(z.quote, 200)) order by z.on_date)
            from (select distinct on (w.on_date, w.pkey) w.pkey, w.on_date, w.quote from win w order by w.on_date, w.pkey limit 12) z)  -- fixed: the first twelve starts are kept as the audit quote
    from r
$function$;
comment on function security.calendar_qualify_check_v1(uuid) is 'CF-247 F-INT.01/SRC-01 (9 Nov 2026): the verdict of one proposed intake_calendar reading for approval by rule (writes nothing): qualifies, or the first failing reason (not_a_proposed_calendar, qualifier_settings_missing, platform_admin_rejected_address, provider_locked_by_hand, host_not_provider_website, excluded_by_calendar_scope, blocked_word, not_a_calendar_page, non_main_period, no_evidence, no_dated_starts, year_not_proved, edition_not_current, starts_beyond_window, too_few_starts, evidence_stale, rejected_or_withdrawn_value, scope_check_series, scope_check_families, contradicts_hand_set_calendar, contradicts_approved_calendar, adds_no_new_value). refreshable is true for edition_not_current and evidence_stale only (every structural check before them passed). Reads the dates only through security.calendar_proposal_dates_v1 and security.calendar_dated_periods_v2.';
revoke all on function security.calendar_qualify_check_v1(uuid) from public, anon, authenticated;

-- the dry run: every proposed reading with its verdict (a read-only function; the Platform Admin''s release gate reads it)
create or replace function security.calendar_qualify_dry_run_v1()
returns table(proposal_id uuid, provider_id uuid, provider text, url text, parser text, qualifies boolean, reason text, detail jsonb)
language sql stable security definer set search_path to '' as $function$
  select x.id, x.provider_id, pr.display_name, x.url, x.parser, c.qualifies, c.reason, c.detail
    from pipeline.provider_policy_proposals x join catalogue.providers pr on pr.id = x.provider_id, lateral security.calendar_qualify_check_v1(x.id) c
   where x.kind = 'intake_calendar' and x.status = 'proposed'
   order by pr.display_name, x.url
$function$;
comment on function security.calendar_qualify_dry_run_v1() is 'CF-247 F-INT.01/SRC-01 (9 Nov 2026): read-only dry run of the calendar qualification route over every proposed intake_calendar reading: provider, address, whether it would qualify and the exact reason otherwise. Writes nothing; works with the switch off.';
revoke all on function security.calendar_qualify_dry_run_v1() from public, anon, authenticated;

-- 4 the route (run inside job policy-auto-approve) ------------------------------------------------------------------------------------------------
create or replace function security.calendar_qualify_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare
  v_batch int := security.pipeline_num_v1('batch.calendar_qualify', 25)::int;
  v_refresh int := security.pipeline_num_v1('batch.calendar_qualify_refresh', 1)::int;
  v_days int := security.pipeline_num_v1('intake_dates.revisit_days', 14)::int;
  v_fp text; r record; c record; v_set text; v_before jsonb; v_after jsonb; v_sup int; v_note text;
  v_exam int := 0; v_ok int := 0; v_held int := 0; v_asked int := 0; v_by jsonb := '{}'::jsonb; t0 timestamptz := clock_timestamp();
  v_rule constant text := 'calendar-qualify-v1';  -- fixed: the name of the rule recorded with every decision
begin
  if security.pipeline_num_v1('central.calendar_qualify_main_teaching', 0) <> 1 then return jsonb_build_object('off', true); end if;
  if not pg_try_advisory_xact_lock(hashtext('cf247.calendar_qualify')) then return jsonb_build_object('skipped', 'another run is in progress'); end if;
  v_fp := md5(coalesce((select string_agg(s.key || '=' || (s.value)::text, ';' order by s.key) from pipeline.platform_toolset_settings s
                         where s.toolset_key = 'pipeline' and (s.key like 'central.calendar_qualify%' or s.key in ('central.calendar_excluded_words', 'intake_dates.max_months_ahead', 'binding.provider_host_aliases'))), '') || v_rule);
  begin
    for r in
      select x.id
        from pipeline.provider_policy_proposals x
        left join pipeline.calendar_qualify_decisions q on q.proposal_id = x.id
       where x.kind = 'intake_calendar' and x.status = 'proposed'
         and (q.proposal_id is null or q.settings_fp <> v_fp or q.next_check_at <= now()
              -- the approved or rejected readings of the provider, its rejected values or its withdrawn values changed since the verdict (index lookups, no scan)
              or exists (select 1 from pipeline.provider_policy_proposals z where z.provider_id = x.provider_id and z.kind = 'intake_calendar' and z.status in ('approved', 'rejected') and z.decided_at > q.decided_at)
              or exists (select 1 from pipeline.intake_date_rejections j where j.provider_id = x.provider_id and j.rejected_at > q.decided_at)
              or exists (select 1 from pipeline.course_intake_date_events e where e.provider_id = x.provider_id and e.outcome = 'withdrawn' and e.run_at > q.decided_at))
       order by (q.proposal_id is not null), q.decided_at nulls first, x.created_at, x.id
       limit v_batch
    loop
      v_exam := v_exam + 1;
      select * into c from security.calendar_qualify_check_v1(r.id);
      if c.proposal_id is null then continue; end if;
      v_set := security.calendar_set_v1(c.provider_id);
      v_by := jsonb_set(v_by, array[c.reason], to_jsonb(coalesce((v_by->>c.reason)::int, 0) + 1));
      if c.qualifies then
        select jsonb_build_object('status', x.status, 'decided_by', x.decided_by, 'decided_at', x.decided_at, 'decision_note', x.decision_note) into v_before
          from pipeline.provider_policy_proposals x where x.id = c.proposal_id;
        v_note := left(format('Machine decision (rule %s, not a person): official main teaching calendar of the provider''s own website, edition %s, %s teaching starts with the year quoted, no contradiction with an approved calendar, no rejected or withdrawn value (%s)',
                              v_rule, c.edition_year, jsonb_array_length(coalesce(c.quotes, '[]'::jsonb)), c.source_url), 500);
        update pipeline.provider_policy_proposals set status = 'approved', decided_by = null, decided_at = now(), decision_note = v_note, updated_at = now()
         where id = c.proposal_id and status = 'proposed';
        select jsonb_build_object('status', x.status, 'decided_by', x.decided_by, 'decided_at', x.decided_at, 'decision_note', x.decision_note) into v_after
          from pipeline.provider_policy_proposals x where x.id = c.proposal_id;
        -- another reading of the same document is closed, as the checked-AI approval does; another document is never closed
        update pipeline.provider_policy_proposals
           set status = 'superseded', decided_at = now(), updated_at = now(), decision_note = 'Closed: another reading of this document was approved by rule (' || c.source_url || ')'
         where provider_id = c.provider_id and kind = 'intake_calendar' and status = 'proposed' and id <> c.proposal_id and fact_source_id = c.fact_source_id;
        get diagnostics v_sup = row_count;
        insert into pipeline.calendar_qualify_decisions as q(proposal_id, provider_id, fact_source_id, rule, verdict, reason, detail, actor, decided_at, settings_fp, cal_set, next_check_at,
                 evidence_id, content_hash, captured_at, edition_year, source_url, quotes, before_state, after_state, approved_at)
        values (c.proposal_id, c.provider_id, c.fact_source_id, v_rule, 'approved', c.reason, c.detail || jsonb_build_object('superseded_readings', v_sup), 'system:' || v_rule, now(), v_fp, v_set, null,
                c.evidence_id, c.content_hash, c.captured_at, c.edition_year, c.source_url, c.quotes, v_before, v_after, now())
        on conflict (proposal_id) do update set rule = excluded.rule, verdict = excluded.verdict, reason = excluded.reason, detail = excluded.detail, actor = excluded.actor,
                 decided_at = excluded.decided_at, settings_fp = excluded.settings_fp, cal_set = excluded.cal_set, next_check_at = null, evidence_id = excluded.evidence_id,
                 content_hash = excluded.content_hash, captured_at = excluded.captured_at, edition_year = excluded.edition_year, source_url = excluded.source_url,
                 quotes = excluded.quotes, before_state = excluded.before_state, after_state = excluded.after_state, approved_at = excluded.approved_at,
                 withdrawn_at = null, withdrawn_by = null, withdrawn_reason = null;
        insert into pipeline.admin_control_events(area, action, target, detail, actor)
        values ('policies', 'approve_machine', 'intake_calendar: ' || c.source_url,
                jsonb_build_object('decision', 'F-INT.01/SRC-01 9 Nov 2026: calendar qualification by rule (setting central.calendar_qualify_main_teaching)', 'rule', v_rule, 'actor_kind', 'system',
                                   'actor', 'system:' || v_rule, 'proposal_id', c.proposal_id, 'provider_id', c.provider_id, 'edition_year', c.edition_year, 'content_hash', c.content_hash,
                                   'captured_at', c.captured_at, 'before', v_before, 'after', v_after, 'quotes', c.quotes), null);
        v_ok := v_ok + 1;
      else
        insert into pipeline.calendar_qualify_decisions as q(proposal_id, provider_id, fact_source_id, rule, verdict, reason, detail, actor, decided_at, settings_fp, cal_set, next_check_at,
                 evidence_id, content_hash, captured_at, edition_year, source_url, quotes)
        values (c.proposal_id, c.provider_id, c.fact_source_id, v_rule, 'held', c.reason, c.detail, 'system:' || v_rule, now(), v_fp, v_set, now() + make_interval(days => v_days),
                c.evidence_id, c.content_hash, c.captured_at, c.edition_year, c.source_url, c.quotes)
        on conflict (proposal_id) do update set rule = excluded.rule, verdict = excluded.verdict, reason = excluded.reason, detail = excluded.detail, actor = excluded.actor,
                 decided_at = excluded.decided_at, settings_fp = excluded.settings_fp, cal_set = excluded.cal_set, next_check_at = excluded.next_check_at, evidence_id = excluded.evidence_id,
                 content_hash = excluded.content_hash, captured_at = excluded.captured_at, edition_year = excluded.edition_year, source_url = excluded.source_url, quotes = excluded.quotes
          where q.verdict <> 'withdrawn';
        v_held := v_held + 1;
      end if;
    end loop;
    -- bounded refresh of a stale edition through the existing acquisition ladder (same eligibility, budget and once-per-address rule as public.svc_calendar_refresh_v1)
    if v_refresh > 0 and not exists (select 1 from pipeline.calendar_refresh_requests q where q.status = 'requested') then
      declare v_budget numeric := security.pipeline_num_v1('central.calendar_refresh_credit_budget', 40);
              v_each numeric := security.pipeline_num_v1('central.calendar_refresh_credits_per_read', 5);
              v_age int := security.pipeline_num_v1('central.calendar_refresh_min_age_days', 7)::int;
              v_spent numeric; v_res numeric; z record;
      begin
        select coalesce(sum(greatest(q.credit_estimate, coalesce(q.credits_used, 0))), 0) into v_spent from pipeline.calendar_refresh_requests q;
        for z in
          select f.id, f.provider_id, f.url, f.evidence_id, f.content_hash, f.read_at, q.reason
            from pipeline.calendar_qualify_decisions q
            join pipeline.provider_fact_sources f on f.id = q.fact_source_id
           where q.verdict = 'held' and q.reason in ('edition_not_current', 'evidence_stale')
             and f.kind = 'intake_calendar' and f.evidence_id is not null and f.status not in ('found', 'reading') and f.decided_by is null and f.decision is null
             and not exists (select 1 from pipeline.provider_policy_proposals p where p.fact_source_id = f.id and p.status = 'approved'
                               and (p.decided_by is not null or p.parser = 'set by hand' or coalesce(p.proposal->>'scope', '') not in ('', 'main_teaching')))
             and security.calendar_scope_v1('{}'::jsonb, f.url, null) = 'main_teaching'
             and coalesce(f.read_at, f.updated_at) < now() - make_interval(days => v_age)
             and not exists (select 1 from pipeline.calendar_refresh_requests rq where rq.url = f.url)
           order by q.decided_at, f.id
           limit v_refresh
        loop
          v_res := greatest(v_each, coalesce((select max(c2.credits_used) from pipeline.firecrawl_calls c2 where c2.url = z.url), 0));
          exit when v_spent + v_res > v_budget;
          insert into pipeline.calendar_refresh_requests(fact_source_id, provider_id, url, reader_version, reason, old_evidence_id, old_content_hash, old_read_at, credit_estimate)
          values (z.id, z.provider_id, z.url, (select max(s.reader) from pipeline.calendar_reread_state s where s.fact_source_id = z.id),
                  format('qualification route: %s (the qualified edition is past or its stored copy is older than the limit)', z.reason), z.evidence_id, z.content_hash, z.read_at, v_res)
          on conflict do nothing;
          update pipeline.provider_fact_sources set status = 'found', attempts = 0, updated_at = now() where id = z.id;
          v_spent := v_spent + v_res; v_asked := v_asked + 1;
        end loop;
      end;
    end if;
  exception when others then
    insert into pipeline.calendar_qualify_runs(examined, approved, held, by_reason, refresh_asked, ms, error)
    values (v_exam, v_ok, v_held, v_by, v_asked, (extract(epoch from clock_timestamp() - t0) * 1000)::int, left(sqlerrm, 500));  -- fixed: milliseconds in a second
    return jsonb_build_object('error', left(sqlerrm, 200));
  end;
  if v_exam > 0 or v_asked > 0 then
    insert into pipeline.calendar_qualify_runs(examined, approved, held, by_reason, refresh_asked, ms)
    values (v_exam, v_ok, v_held, v_by, v_asked, (extract(epoch from clock_timestamp() - t0) * 1000)::int);  -- fixed: milliseconds in a second
  end if;
  return jsonb_build_object('examined', v_exam, 'approved', v_ok, 'held', v_held, 'by_reason', v_by, 'refresh_asked', v_asked);
end $function$;
comment on function security.calendar_qualify_v1() is 'CF-247 F-INT.01/SRC-01 (9 Nov 2026): the calendar qualification route. Off (central.calendar_qualify_main_teaching = 0, the default): returns at once, writes nothing. On: checks up to batch.calendar_qualify proposed intake_calendar readings (never checked, changed inputs or due), approves the qualifying ones as a machine decision (decided_by null, actor system:calendar-qualify-v1) with evidence and before/after, holds the others with the exact reason, and hands a stale edition to the existing refresh within its credit budget. Called by security.policy_auto_approve_v1 (job policy-auto-approve). A failure is recorded in pipeline.calendar_qualify_runs and never stops the other approvals.';
revoke all on function security.calendar_qualify_v1() from public, anon, authenticated;

-- 5 the withdrawal path ---------------------------------------------------------------------------------------------------------------------------
create or replace function security.calendar_qualify_withdraw_v1(p_proposal uuid, p_reason text, p_actor uuid, p_withdraw_values boolean default true) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare q pipeline.calendar_qualify_decisions%rowtype; x pipeline.provider_policy_proposals%rowtype; v_batch int := security.pipeline_num_v1('batch.calendar_qualify_withdraw', 50)::int;
        v_ids uuid[]; v_total int; i uuid; v_res jsonb := '[]'::jsonb; v_done int := 0; v_before jsonb;
begin
  if coalesce(btrim(p_reason), '') = '' or length(btrim(p_reason)) < 8 then raise exception 'give the reason for the withdrawal' using errcode = '22023'; end if;  -- fixed: a reason of a few words
  select * into q from pipeline.calendar_qualify_decisions where proposal_id = p_proposal for update;
  if q.proposal_id is null or q.verdict not in ('approved', 'withdrawn') then raise exception 'this reading was not approved by the qualification route' using errcode = '22023'; end if;
  select * into x from pipeline.provider_policy_proposals where id = p_proposal for update;
  if q.verdict = 'approved' then
    v_before := jsonb_build_object('status', x.status, 'decided_by', x.decided_by, 'decision_note', x.decision_note);
    -- rejected by a person: the rejection memory keeps the route from approving this address again; the calendar set changes, so the rows are looked at again
    update pipeline.provider_policy_proposals set status = 'rejected', decided_by = p_actor, decided_at = now(), decision_note = left('Withdrawn: ' || btrim(p_reason), 500), updated_at = now() where id = p_proposal;
    update pipeline.calendar_qualify_decisions set verdict = 'withdrawn', withdrawn_at = now(), withdrawn_by = p_actor, withdrawn_reason = left(btrim(p_reason), 500), next_check_at = null where proposal_id = p_proposal;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'withdraw_machine_approval', 'intake_calendar: ' || x.url,
            jsonb_build_object('rule', q.rule, 'proposal_id', p_proposal, 'provider_id', x.provider_id, 'reason', left(btrim(p_reason), 500), 'before', v_before, 'content_hash', q.content_hash), p_actor);
  end if;
  select array_agg(d.intake_id order by d.intake_id), count(*) into v_ids, v_total from pipeline.course_intake_dates d
   where d.proposal_id = p_proposal and d.outcome = 'filled';
  if p_withdraw_values and coalesce(v_total, 0) > 0 then
    foreach i in array v_ids loop
      exit when v_done >= v_batch;
      v_res := v_res || security.intake_date_withdraw_v1(i, 'Calendar withdrawn: ' || btrim(p_reason), p_actor::text, false);
      v_done := v_done + 1;
    end loop;
    insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by, set_at)
    select distinct 'course', (e->>'course_id')::uuid, 'intakes', 'value', p_actor, now() from jsonb_array_elements(v_res) e where (e->>'withdrawn')::boolean
    on conflict (entity, entity_id, field) do nothing;
  end if;
  return jsonb_build_object('proposal_id', p_proposal, 'withdrawn', true, 'values_admitted', coalesce(v_total, 0), 'values_withdrawn_now', (select count(*) from jsonb_array_elements(v_res) e where (e->>'withdrawn')::boolean),
                            'values_remaining', greatest(coalesce(v_total, 0) - v_done, 0));
end $function$;
comment on function security.calendar_qualify_withdraw_v1(uuid, text, uuid, boolean) is 'CF-247 F-INT.01/SRC-01 (9 Nov 2026): withdraws a calendar the qualification route approved: the reading becomes rejected by the named person (the route never approves that address again), the decision row records who, when and why, the calendar leaves the calendar set, and the intake values it admitted are withdrawn through the existing security.intake_date_withdraw_v1 (at most batch.calendar_qualify_withdraw a call; the call reports the rest and is repeated; each course is held by a lock, as the governed withdrawal does).';
revoke all on function security.calendar_qualify_withdraw_v1(uuid, text, uuid, boolean) from public, anon, authenticated;

create or replace function public.admin_calendar_qualify_withdraw_v1(p_proposal uuid, p_reason text, p_withdraw_values boolean default true) returns jsonb
language plpgsql security definer set search_path to '' as $function$
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  return security.calendar_qualify_withdraw_v1(p_proposal, p_reason, auth.uid(), p_withdraw_values);
end $function$;
comment on function public.admin_calendar_qualify_withdraw_v1(uuid, text, boolean) is 'CF-247 F-INT.01/SRC-01 (9 Nov 2026): the Platform Admin''s withdrawal of a calendar approved by the qualification route (see security.calendar_qualify_withdraw_v1). Not part of the consumer API.';
revoke all on function public.admin_calendar_qualify_withdraw_v1(uuid, text, boolean) from public, anon;
grant execute on function public.admin_calendar_qualify_withdraw_v1(uuid, text, boolean) to authenticated;

-- 6 run inside the existing job policy-auto-approve (md5-guarded edit) ----------------------------------------------------------------------------
select pg_temp.edit('security.policy_auto_approve_v1()', '189d5c4349f604653f20c8fc854d1cd1', 'calendar_qualify_v1',
  array[$o$begin
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'central.auto_approve'), false) then$o$],
  array[$n$begin
  -- CF-247 F-INT.01/SRC-01 (9 Nov 2026): official main teaching calendars are qualified by rule when central.calendar_qualify_main_teaching = 1 (default 0: returns at once);
  -- a failure is recorded in pipeline.calendar_qualify_runs inside the function and never stops the approvals below
  perform security.calendar_qualify_v1();
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'central.auto_approve'), false) then$n$],
  array[1]);

-- 7 housekeeping: the register and the job description -------------------------------------------------------------------------------------------
update pipeline.automation_catalogue set description = description || ' It also runs the calendar qualification route (security.calendar_qualify_v1), which approves official main teaching calendars by rule only while central.calendar_qualify_main_teaching is 1.'
 where jobname = 'policy-auto-approve' and position('calendar_qualify_v1' in description) = 0;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.calendar_qualify_decisions', 'Layer 2', 'Intake dates', 'Verdict and evidence of the calendar qualification route for each proposed calendar reading (approved by rule as a machine decision, held with the reason, or withdrawn)', 'active', '{}', '20261109060000'),
 ('table', 'pipeline.calendar_qualify_runs', 'Layer 2', 'Intake dates', 'One row for each run of the calendar qualification route that had work: checked, approved, held by reason, refresh asked, milliseconds, error', 'active', '{}', '20261109060000'),
 ('function', 'security.calendar_qualify_check_v1', 'Layer 2', 'Intake dates', 'Read-only verdict of one proposed calendar reading for approval by rule (official main teaching calendar checks)', 'active', '{}', '20261109060000'),
 ('function', 'security.calendar_qualify_v1', 'Layer 2', 'Intake dates', 'Calendar qualification route run by job policy-auto-approve; default off (central.calendar_qualify_main_teaching)', 'active', '{}', '20261109060000'),
 ('function', 'security.calendar_qualify_withdraw_v1', 'Layer 2', 'Intake dates', 'Withdrawal of a machine-approved calendar and of the values it admitted (Platform Admin through public.admin_calendar_qualify_withdraw_v1)', 'active', '{}', '20261109060000')
on conflict (kind, name) do nothing;
