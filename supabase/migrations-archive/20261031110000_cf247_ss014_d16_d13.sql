-- CF-247 StudySearch SS-014 decisions D16 and D13 (Platform Admin mandate 31 Oct 2026 21:54, "SS-014 Recovery and Automation Execution
-- Mandate"; admin docs/platform/nz-enrichment-brief/2026-10-31-studysearch-transformation.md §32).
-- D16 why (measured live 31 Oct 2026): the scholarship Firecrawl hold (security.fc_sch_held_v1, with fc_sch_eligible_v1 and
--   fc_sch_cap_since_v1) is a chain of SQL functions with their own search path, so PostgreSQL plans the nested queries again on every call.
--   The health check calls it about 1,140 times a run (scholarship check 7.0 to 8.5 s live after v2.15.384), and the scholarship worker lanes
--   (svc_scholarship_read_next, _candidate_next, _discover_next, _listing_next) call it per row. In one session, 6,204 calls (every provider,
--   both modes): 20.1 s before and 5.7 s as PL/pgSQL on the first (colder) pass, 8.8 s and 5.4 s warm; 0 different results.
-- D16 what: the three scholarship-specific functions become PL/pgSQL with the same signature, logic, security definer, search path,
--   volatility and grants (md5-guarded). The shared functions they call (coverage_country, fc_courses_v1, fc_setting_num_v1; 48 callers)
--   are not touched.
-- D13 why: 1,467 bound or ambiguous course pages used all 3 read attempts and are never tried again (976 fetch_failed, 325 blocked, 166 never
--   read). D13 approves a bounded, direct-only pilot.
-- D13 what: table pipeline.page_reread_pilot (one row per page, ever: one extra attempt at most); job reread-pilot (daily) records outcomes,
--   stops the pilot by itself if a pilot page was read through Firecrawl or produced Layer 4 review items, then releases up to
--   reread.pilot_daily_max (25, the approved ceiling is also the setting's maximum) eligible pages: last attempt at least
--   reread.pilot_min_days (30) ago, read status fetch_failed, blocked or never read (robots-disallowed, needs-a-browser and gone pages are
--   not eligible), provider published and not flagged unreachable or refusing reads, course not under an SS-007 remediation hold and not held
--   by a person. Releasing gives the page one attempt (read_attempts 2) in the existing read lane; svc_coverage_read_next marks it
--   direct_only and the worker (v0.55.0) never uses Firecrawl for it. Robots rules, rate limits, identity proof, evidence and admission
--   are unchanged. Holds: the AER closure mandate's freeze (QUT reads, B5, R1 exceptions, Layer 4 growth) does not cover free direct reads of
--   course pages; Layer 4 growth from pilot pages stops the pilot.
-- Replaces: security.fc_sch_held_v1, security.fc_sch_eligible_v1, security.fc_sch_cap_since_v1 (same names; PL/pgSQL), public.svc_coverage_read_next (md5-guarded edit)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. Consumer API untouched (G3).

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

-- 1. D16: guard the current definitions, then replace them with PL/pgSQL equivalents
do $$
begin
  if md5(pg_get_functiondef('security.fc_sch_held_v1(uuid,boolean)'::regprocedure)) not in ('60a8580612898506658ba7498a7b23a6', 'f8d6fb4bf9196dfa596b8274819670a6')
     or md5(pg_get_functiondef('security.fc_sch_eligible_v1(uuid)'::regprocedure)) not in ('32746eb4f48a80fe6873ac3e6779eace', '06e6fb6f46698c3f59c5b4e754b3d6e2')
     or md5(pg_get_functiondef('security.fc_sch_cap_since_v1(uuid)'::regprocedure)) not in ('b992a7d4c2913a37e3a296fef682630f', '1db9da2828d2ff996db8ab2d7e789d05') then
    raise exception 'D16: a scholarship hold function differs from the definition this change replaces';
  end if;
end $$;

create or replace function security.fc_sch_cap_since_v1(p_provider_id uuid) returns timestamptz
language plpgsql stable security definer set search_path to '' as $function$
begin
  -- D16 (31 Oct 2026): PL/pgSQL so its query plans are kept for the session; same rule as the SQL version
  return greatest(now() - interval '30 days',  -- fixed: the per-university cap window, unchanged from the SQL version
                  coalesce((select max(o.picked_at) from pipeline.onboarding_pilot o where o.provider_id = p_provider_id), '-infinity'::timestamptz),
                  coalesce((select max(po.started_at) from pipeline.provider_onboarding po where po.provider_id = p_provider_id), '-infinity'::timestamptz));
end $function$;

create or replace function security.fc_sch_eligible_v1(p_provider_id uuid) returns boolean
language plpgsql stable security definer set search_path to '' as $function$
begin
  -- D16 (31 Oct 2026): PL/pgSQL so its query plans are kept for the session; same rule as the SQL version
  return security.coverage_country(p_provider_id) is distinct from 'AU' or security.fc_courses_v1(p_provider_id) >= security.fc_setting_num_v1('scholarship_min_courses', 30);
end $function$;

create or replace function security.fc_sch_held_v1(p_provider_id uuid, p_discovery boolean) returns boolean
language plpgsql stable security definer set search_path to '' as $function$
begin
  -- D16 (31 Oct 2026): PL/pgSQL so its query plans are kept for the session; same rule as the SQL version
  return coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false)
     and ((p_discovery and not security.fc_sch_eligible_v1(p_provider_id))
          or (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and x.purpose like 'sch\_%' and x.at > security.fc_sch_cap_since_v1(p_provider_id))
             >= security.fc_setting_num_v1('scholarship_cap_per_uni', 150));
end $function$;

-- 2. D13: settings, table, read-lane marker, pilot function and job
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'reread.pilot_enabled', 'Re-read pilot: on',
  'Gives course pages that used all their read attempts one more direct read (no Firecrawl, no AI). Switches itself off if a pilot page is read through Firecrawl or produces Layer 4 review items.', 'boolean',
  to_jsonb(true), null, null, null, 983, 'Re-read and retry', 'security.page_reread_pilot_run_v1 (job reread-pilot)', 'Platform Admin 31 Oct 2026 21:54, decision D13: bounded direct-only pilot'),
 ('pipeline', 'reread.pilot_daily_max', 'Re-read pilot: pages a day',
  'Most exhausted pages given one more direct read in a day. 25 is the approved pilot ceiling; more needs a new approval.', 'number',
  to_jsonb(25), 0, 25, 'pages', 984, 'Re-read and retry', 'security.page_reread_pilot_run_v1 (job reread-pilot)', 'Platform Admin 31 Oct 2026 21:54, decision D13: start with a maximum of 25 pages a day'),
 ('pipeline', 'reread.pilot_min_days', 'Re-read pilot: wait after the last attempt',
  'A page is eligible only this long after its last read attempt.', 'number',
  to_jsonb(30), 30, 365, 'days', 985, 'Re-read and retry', 'security.page_reread_pilot_run_v1 (job reread-pilot)', 'Platform Admin 31 Oct 2026 21:54, decision D13: eligible only after 30 days')
on conflict do nothing;

create table if not exists pipeline.page_reread_pilot (
  course_id uuid primary key,
  provider_id uuid not null,
  url text not null,
  released_at timestamptz not null default now(),
  before_state jsonb not null,
  outcome_at timestamptz,
  outcome_read_status text,
  outcome_http integer,
  outcome_fetched_via text,
  outcome_identity_basis text,
  outcome_evidence boolean,
  layer4_items integer,
  fields_filled integer,
  note text
);
create index if not exists page_reread_pilot_released_idx on pipeline.page_reread_pilot (released_at);
comment on table pipeline.page_reread_pilot is 'StudySearch decision D13 (Platform Admin 31 Oct 2026 21:54): bounded direct-only re-read pilot. One row per course page ever given its one extra read attempt (released by job reread-pilot, security.page_reread_pilot_run_v1), with the page state before and the outcome after (read status, HTTP status, how it was fetched, identity proof, evidence, Layer 4 items and enrichment values filled for the course since release). While a row has no outcome the read lane marks the page direct_only, so the worker never uses Firecrawl for it. Never read by the consumer API.';
alter table pipeline.page_reread_pilot enable row level security;
revoke all on pipeline.page_reread_pilot from public, anon, authenticated;

select pg_temp.edit_once('public.svc_coverage_read_next(integer)', '748954a5d74f30e91aa2b24e8b785dc4', '2ac1114dd4a5da99d8ddb742f7d0c1be', array[
 array[$o$'manual',coalesce(u.basis='manual',false),$o$, $n$'manual',coalesce(u.basis='manual',false),'direct_only',exists (select 1 from pipeline.page_reread_pilot rr where rr.course_id=u.course_id and rr.outcome_at is null),$n$]],
 array[1]);

create or replace function security.page_reread_pilot_run_v1() returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_on boolean := coalesce((security.toolset_setting('pipeline', 'reread.pilot_enabled') #>> '{}')::boolean, false);
        v_max int := least(security.pipeline_num_v1('reread.pilot_daily_max', 25), 25)::int;  -- fixed: 25 a day is the approved ceiling (D13)
        v_days int := greatest(security.pipeline_num_v1('reread.pilot_min_days', 30), 30)::int;  -- fixed: never sooner than 30 days (D13)
        v_today timestamptz := ((now() at time zone 'Australia/Melbourne')::date)::timestamp at time zone 'Australia/Melbourne';
        v_rec int := 0; v_rel int := 0; v_stop text;
begin
  -- 1. a release the read lane has not attempted in 3 days is closed, and its page is exhausted again (so no later read can use Firecrawl)
  update pipeline.coverage_course_pages p set read_attempts = greatest(p.read_attempts, 3)
    from pipeline.page_reread_pilot r
   where r.course_id = p.course_id and r.outcome_at is null and r.released_at < now() - interval '3 days'  -- fixed: a release not attempted in 3 days is closed
     and (p.read_at is null or p.read_at <= r.released_at);
  -- 2. outcomes: a released page is attempted once by the read lane; record what happened
  with o as (
    update pipeline.page_reread_pilot r set outcome_at = now(), outcome_read_status = p.read_status, outcome_http = p.http_status, outcome_fetched_via = p.fetched_via,
           outcome_identity_basis = p.identity_basis, outcome_evidence = p.evidence_id is not null and p.evidence_id is distinct from (r.before_state ->> 'evidence_id')::uuid,
           layer4_items = (select count(*) from pipeline.layer4_review_items l where l.entity_id = r.course_id and l.created_at > r.released_at),
           fields_filled = (select count(*) from pipeline.field_enrich_items i where i.course_id = r.course_id and i.state = 'filled' and i.updated_at > r.released_at)
      from pipeline.coverage_course_pages p
     where p.course_id = r.course_id and r.outcome_at is null
       and ((p.read_at > r.released_at and coalesce(p.leased_until, '-infinity') < now()) or r.released_at < now() - interval '3 days')  -- fixed: a release not attempted in 3 days is closed
    returning r.course_id)
  select count(*) into v_rec from o;
  -- 3. stop conditions: Firecrawl used for a pilot page, or Layer 4 grew from one
  if exists (select 1 from pipeline.page_reread_pilot r where r.outcome_fetched_via = 'firecrawl' or coalesce(r.layer4_items, 0) > 0) then
    v_stop := 'a pilot page was read through Firecrawl or produced Layer 4 review items';
    if v_on then
      update pipeline.platform_toolset_settings set value = 'false'::jsonb, reason = 'Stopped by the pilot itself (D13): ' || v_stop, updated_at = now()
       where toolset_key = 'pipeline' and key = 'reread.pilot_enabled';
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('toolsets', 'setting', 'pipeline.reread.pilot_enabled', jsonb_build_object('before', true, 'after', false, 'reason', 'D13 stop condition: ' || v_stop), null);
    end if;
    return jsonb_build_object('recorded', v_rec, 'released', 0, 'stopped', v_stop);
  end if;
  if not v_on then return jsonb_build_object('recorded', v_rec, 'released', 0, 'pilot', 'off'); end if;
  -- 4. release today's eligible pages, never more than the daily ceiling, each page once ever
  with c as (
    select p.course_id, p.provider_id, p.url, jsonb_build_object('read_status', p.read_status, 'read_at', p.read_at, 'read_attempts', p.read_attempts, 'http_status', p.http_status,
             'next_read_at', p.next_read_at, 'fetched_via', p.fetched_via, 'evidence_id', p.evidence_id, 'status', p.status) before_state
      from pipeline.coverage_course_pages p
     where p.status in ('bound', 'ambiguous') and p.read_attempts >= 3 and coalesce(p.leased_until, '-infinity') < now()
       and (p.read_status is null or p.read_status in ('fetch_failed', 'blocked'))
       and coalesce(p.read_at, p.bound_at) <= now() - make_interval(days => v_days)
       and not exists (select 1 from pipeline.page_reread_pilot r where r.course_id = p.course_id)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)
       and not security.course_held_v1(p.course_id)
       and not exists (select 1 from pipeline.enrichment_flags f where f.entity = 'provider' and f.provider_id = p.provider_id and f.cleared_at is null
                        and f.reason_code in ('site_unreachable', 'pages_refuse_reading', 'manual_hold'))
       and not exists (select 1 from pipeline.enrichment_flags f where f.entity = 'course' and f.entity_key = p.course_id::text and f.cleared_at is null
                        and (f.reason_code = 'manual_hold' or f.raised_by_kind = 'person'))
     order by coalesce(p.read_at, p.bound_at)
     limit greatest(v_max - (select count(*) from pipeline.page_reread_pilot r where r.released_at >= v_today), 0)),
  ins as (insert into pipeline.page_reread_pilot(course_id, provider_id, url, before_state) select c.course_id, c.provider_id, c.url, c.before_state from c returning course_id)
  update pipeline.coverage_course_pages p set read_attempts = 2, next_read_at = now(), leased_until = null from ins where p.course_id = ins.course_id;
  get diagnostics v_rel = row_count;
  return jsonb_build_object('recorded', v_rec, 'released', v_rel, 'daily_max', v_max, 'min_days', v_days);
end $function$;
revoke all on function security.page_reread_pilot_run_v1() from public, anon, authenticated;

create or replace function security.page_reread_pilot_summary_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object(
    'released', count(*), 'attempted', count(*) filter (where r.outcome_at is not null),
    'read', count(*) filter (where r.outcome_read_status = 'read'), 'identity_proved', count(*) filter (where r.outcome_identity_basis is not null and r.outcome_read_status = 'read'),
    'new_evidence', count(*) filter (where r.outcome_evidence), 'fields_filled', coalesce(sum(r.fields_filled), 0),
    'firecrawl_reads', count(*) filter (where r.outcome_fetched_via = 'firecrawl'), 'layer4_items', coalesce(sum(r.layer4_items), 0),
    'by_outcome', coalesce((select jsonb_object_agg(x.s, x.n) from (select coalesce(r2.outcome_read_status, 'waiting') s, count(*) n from pipeline.page_reread_pilot r2 group by 1) x), '{}'::jsonb),
    'exhausted_not_yet_tried', (select count(*) from pipeline.coverage_course_pages p where p.status in ('bound', 'ambiguous') and p.read_attempts >= 3
                          and (p.read_status is null or p.read_status in ('fetch_failed', 'blocked'))
                          and not exists (select 1 from pipeline.page_reread_pilot r3 where r3.course_id = p.course_id)),
    'enabled', coalesce((security.toolset_setting('pipeline', 'reread.pilot_enabled') #>> '{}')::boolean, false))
  from pipeline.page_reread_pilot r
$function$;
revoke all on function security.page_reread_pilot_summary_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('reread-pilot', 'Course pages', 88, 'Re-read pilot (exhausted pages)',
  'Daily at 05:41 (Melbourne): gives course pages that used all their read attempts one more direct read, at most Re-read pilot: pages a day (25), only 30 days after the last attempt, each page once. No Firecrawl and no AI: the read lane marks these pages direct only. Records each outcome and switches the pilot off by itself if a pilot page is read through Firecrawl or produces Layer 4 review items (decision D13).',
  6, false, null)
on conflict (jobname) do nothing;
select cron.schedule('reread-pilot', '41 18 * * *', $$select security.page_reread_pilot_run_v1()$$);

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'reread-pilot', 'Layer 2', 'Course pages', 'D13: bounded direct-only re-read pilot for exhausted course pages', 'active', '{}', '20261031110000'),
 ('table', 'pipeline.page_reread_pilot', 'Layer 2', 'Course pages', 'D13: one row per page given its one extra read, with outcome', 'active', '{}', '20261031110000'),
 ('function', 'security.page_reread_pilot_run_v1', 'Layer 2', 'Course pages', 'D13: job reread-pilot (outcomes, stop conditions, release)', 'active', '{}', '20261031110000'),
 ('function', 'security.page_reread_pilot_summary_v1', 'Layer 2', 'Course pages', 'D13: pilot measurements', 'active', '{}', '20261031110000')
on conflict do nothing;

-- post-check
do $$
begin
  if (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = 'security.fc_sch_held_v1(uuid,boolean)'::regprocedure) <> 'plpgsql' then
    raise exception 'D16 post-check: fc_sch_held_v1 is not PL/pgSQL'; end if;
  if (select count(*) from catalogue.providers c where security.fc_sch_held_v1(c.id, true) is null) > 0 then
    raise exception 'D16 post-check: fc_sch_held_v1 returned null'; end if;
  if not exists (select 1 from cron.job j join pipeline.automation_catalogue a on a.jobname = j.jobname where j.jobname = 'reread-pilot' and j.active) then
    raise exception 'D13 post-check: job reread-pilot is not scheduled and catalogued'; end if;
  if (select max_value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'reread.pilot_daily_max') <> 25 then
    raise exception 'D13 post-check: the daily ceiling must be 25'; end if;
end $$;
do $$
begin
  if md5(pg_get_functiondef('security.fc_sch_held_v1(uuid,boolean)'::regprocedure)) <> 'f8d6fb4bf9196dfa596b8274819670a6'
     or md5(pg_get_functiondef('security.fc_sch_eligible_v1(uuid)'::regprocedure)) <> '06e6fb6f46698c3f59c5b4e754b3d6e2'
     or md5(pg_get_functiondef('security.fc_sch_cap_since_v1(uuid)'::regprocedure)) <> '1db9da2828d2ff996db8ab2d7e789d05' then
    raise exception 'D16 post-check: a replaced function has an unexpected definition'; end if;
end $$;
