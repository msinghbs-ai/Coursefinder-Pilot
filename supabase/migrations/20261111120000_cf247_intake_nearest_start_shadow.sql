-- CF-247 F-INT Rule B, shadow only (Decision 271, Platform Admin 10 Nov 2026; go-ahead 11 Nov 2026 09:26 AEDT "Go ahead with 1, 2 and 3": item 3 builds Rule B in
-- shadow and audits it; switching it on stays a separate step per provider, after the P0 IQ-00313 containment is lifted for that provider).
-- Evidence (production, read only, 11 Nov 2026 09:4x AEDT): 7,472 of the 9,365 month-only intake rows come from course pages that give the month only
--   ("February, July"); the approved calendar gives the day. A read-only prototype of Rule B over the rows held as "the course page names no study period of the
--   calendar (month only)" gave: 1,139 one start in the stated month, 564 none in the month but one in the next 35 days (Monash and RMIT "February" -> Semester 1
--   on 1 March 2027), 575 ambiguous, 3,635 no future start (calendars still waiting for a 2027 reading), 46 rolling or flexible. It also shows the risk the
--   audit must judge: Southern Cross "June" -> 5 July, UTS and Wollongong November/December -> short summer sessions.
-- What (nothing is admitted; catalogue.course_intakes and pipeline.course_intake_dates are not written):
--   1. table pipeline.intake_nearest_start_shadow: one row per waiting intake, the date Rule B would give, the path (in_month / next_start), the calendar period
--      and quote it would use, or why it gives none (ambiguous / no_start / rolling / page_date_differs / later_cycle).
--   2. security.intake_nearest_start_shadow_v1(): recomputes the table. Rules (Decision 271): only rows whose page names no study period; only dated starts of
--      the provider's approved calendars (security.calendar_dated_periods_v2, rejected values excluded) with the year proved, on or after today and within
--      intake_dates.max_months_ahead; a period named with a blocked period word (central.calendar_qualify_blocked_period_words) never counts; exactly one start
--      date in the stated month, else (none in the month) exactly one within intake_dates.nearest_start_days after the 1st of the month; two or more keep the
--      month; a course whose two stated months would map to the same date is ambiguous; rolling, flexible or continuous wording gives no date; a full date on the
--      course page for that month that differs holds the row.
--   3. settings (G2): intake_dates.nearest_start_days (35, the approved window) and intake_dates.nearest_start_providers (empty list: Rule B admits for no
--      provider). The planner does not read them yet; switching on is a separate change.
--   Audit (11 Nov 2026, 40 rows stratified by provider and path, read against the stored course-page wording and the calendar line): 21 right (Monash 6 and
--   RMIT 6 of 6 each, incl. every next_start "February -> 1 March"; AIM, Kaplan, AIH, Bond, Southern Cross October), 10 unproven, 9 wrong: ACU February ->
--   "term 2, Mon 1 Feb" (a non-semester term), Deakin research degrees -> Trimester 2, Southern Cross June -> 5 July (4), TAFE SA "applications open" read as a
--   start. Two guards follow from it here: research degrees (doctorate, masters_research) give no date, and a calendar line naming applications, census,
--   orientation or enrolment is never a start. The rest is why Rule B stays per provider: Monash and RMIT first.
--   4. the shadow is computed once now; it is recomputed on demand (no job: G1 unchanged).
-- Guards: G1 (no job), G2 (window and list are settings), G3 (no consumer API object), G4 (cf-247-s530).
-- Replaces: nothing.
-- Retires: nothing.
-- Reversal: drop the table and function by paste file; delete the two settings by paste file.

create table if not exists pipeline.intake_nearest_start_shadow (
  intake_id uuid primary key,
  course_id uuid not null,
  provider_id uuid not null,
  stated_month int not null,
  intake_year int,
  target_year int,
  outcome text not null check (outcome in ('would_fill', 'ambiguous', 'no_start', 'rolling', 'page_date_differs', 'research_degree')),
  path text check (path in ('in_month', 'next_start')),
  candidate_date date,
  candidate_dates date[],
  period text,
  calendar_quote text,
  calendar_proposal_id uuid,
  page_quote text,
  computed_at timestamptz not null default now()
);
comment on table pipeline.intake_nearest_start_shadow is 'CF-247 F-INT Rule B shadow (Decision 271): for each intake whose course page gives the month only, the calendar start Rule B would give (in the month, or the one start within intake_dates.nearest_start_days after it) or why it gives none. Read by the audit only; nothing is admitted from it.';
alter table pipeline.intake_nearest_start_shadow enable row level security;
create index if not exists intake_nearest_start_shadow_provider on pipeline.intake_nearest_start_shadow (provider_id, outcome);

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'intake_dates.nearest_start_days', 'Intake dates: a stated month may take the one start this many days after it',
  'Rule B (Decision 271): when a course page gives a month and no calendar start falls in that month, the month takes the one main-teaching start within this many days after the 1st of the month (for example February -> a Semester 1 that begins on 1 March). Two or more starts keep the month only. Shadow only until a provider is listed in "Intake dates: providers using the nearest start".',
  'number', to_jsonb(35), 0, 62, 'days', 1013, 'Intake dates',
  'security.intake_nearest_start_shadow_v1',
  'Decision 271 (Platform Admin 10 Nov 2026): approved window 35 days; shadow first (11 Nov 2026 09:26 AEDT)'),
 ('pipeline', 'intake_dates.nearest_start_providers', 'Intake dates: providers using the nearest start',
  'Providers (ids) for which Rule B may admit dates. Empty: Rule B admits for no provider and only the shadow is computed. A provider is added one at a time after its shadow audit, once the P0 IQ-00313 containment is lifted for it.',
  'list', '[]'::jsonb, null, null, 'provider ids', 1014, 'Intake dates',
  'security.intake_nearest_start_shadow_v1 (shadow); the intake planner after a separate change',
  'Decision 271 (Platform Admin 10 Nov 2026): opt-in per provider, default none')
on conflict (toolset_key, key) do nothing;

create or replace function security.intake_nearest_start_shadow_v1()
returns jsonb
language plpgsql
volatile security definer
set search_path to ''
as $function$
declare
  v_today date := (now() at time zone 'Australia/Melbourne')::date;  -- fixed: the calendar day in Australia (month roll-over)
  v_window int := security.pipeline_num_v1('intake_dates.nearest_start_days', 35)::int;
  v_ahead int := greatest(1, security.pipeline_num_v1('intake_dates.max_months_ahead', 18)::int);
  v_words text[] := coalesce((select array(select jsonb_array_elements_text(s.value)) from pipeline.platform_toolset_settings s
                               where s.toolset_key = 'pipeline' and s.key = 'central.calendar_qualify_blocked_period_words'), '{}');
  v jsonb;
begin
  delete from pipeline.intake_nearest_start_shadow;
  with rows as (
    select d.intake_id, d.course_id, d.provider_id, d.page_quote, i.intake_year,
           coalesce(l.code, '') in ('doctorate', 'masters_research') as research,
           array_position(array['january','february','march','april','may','june','july','august','september','october','november','december'], lower(btrim(i.intake_label))) as m
      from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id
      join catalogue.courses co on co.id = d.course_id left join ref.study_levels l on l.id = co.study_level_id
     where d.start_precision = 'month' and i.start_date is null
       and d.reason = 'the course page names no study period of the calendar (month only)'),
  provs as (select distinct provider_id from rows),
  cal as (
    select p.provider_id, s.period, s.on_date, s.quote, s.proposal_id
      from provs p cross join lateral security.calendar_dated_periods_v2(p.provider_id) s
     where s.kind = 'start' and s.year_ok and s.on_date is not null
       and s.on_date >= v_today and s.on_date < (v_today + make_interval(months => v_ahead))
       and not exists (select 1 from unnest(v_words) w where s.period ilike '%' || w || '%')
       -- audit 11 Nov 2026: a calendar line that is an application, census, orientation or enrolment date is never a teaching start (TAFE SA "applications open")
       and coalesce(s.quote, '') !~* '(applications?\s+(open|close)|census|orientation|o-?week|enrol)'
       and not exists (select 1 from pipeline.intake_date_rejections j where j.provider_id = p.provider_id and j.proposal_id is not distinct from s.proposal_id
                          and j.quote is not distinct from s.quote and j.year is not distinct from extract(year from s.on_date)::int)),
  y as (
    select r.*, coalesce(r.intake_year,
             case when make_date(extract(year from v_today)::int, r.m, 1) >= date_trunc('month', v_today)::date
                  then extract(year from v_today)::int else extract(year from v_today)::int + 1 end) as y0
      from rows r where r.m is not null),
  c as (
    select y.*,
           (select array_agg(distinct k.on_date order by k.on_date) from cal k where k.provider_id = y.provider_id
               and k.on_date >= make_date(y.y0, y.m, 1) and k.on_date < (make_date(y.y0, y.m, 1) + interval '1 month')::date) as s1,
           (select array_agg(distinct k.on_date order by k.on_date) from cal k where k.provider_id = y.provider_id
               and k.on_date >= (make_date(y.y0, y.m, 1) + interval '1 month')::date and k.on_date <= make_date(y.y0, y.m, 1) + v_window) as s2
      from y),
  o as (
    select c.*,
           case when cardinality(c.s1) = 1 then 'in_month' when c.s1 is null and cardinality(c.s2) = 1 then 'next_start' end as path,
           case when cardinality(c.s1) = 1 then c.s1[1] when c.s1 is null and cardinality(c.s2) = 1 then c.s2[1] end as cand,
           coalesce(c.s1, c.s2) as cands
      from c),
  g as (   -- a course whose two stated months would take the same date is ambiguous
    select o.*, count(*) over (partition by o.course_id, o.cand) as same_date_months from o)
  insert into pipeline.intake_nearest_start_shadow(intake_id, course_id, provider_id, stated_month, intake_year, target_year, outcome, path, candidate_date, candidate_dates,
                                                    period, calendar_quote, calendar_proposal_id, page_quote)
  select g.intake_id, g.course_id, g.provider_id, g.m, g.intake_year, g.y0,
         case when g.research then 'research_degree'   -- audit 11 Nov 2026: a research degree is not dated from the coursework calendar (Deakin PhD -> Trimester 2)
              when g.page_quote ~* '(rolling|flexible|continuous|any ?time|multiple intakes|throughout the year)' then 'rolling'
              when g.cand is null and g.cands is null then 'no_start'
              when g.cand is null then 'ambiguous'
              when g.same_date_months > 1 then 'ambiguous'
              when exists (select 1 from regexp_matches(coalesce(g.page_quote, ''),
                             '(\d{1,2})(?:st|nd|rd|th)?[\s-]+(' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[g.m] || ')[a-z]*', 'gi') x
                           where x[1]::int <> extract(day from g.cand)::int) then 'page_date_differs'
              else 'would_fill' end,
         g.path, g.cand, g.cands,
         (select k.period from cal k where k.provider_id = g.provider_id and k.on_date = g.cand order by k.period limit 1),
         (select k.quote from cal k where k.provider_id = g.provider_id and k.on_date = g.cand order by k.period limit 1),
         (select k.proposal_id from cal k where k.provider_id = g.provider_id and k.on_date = g.cand order by k.period limit 1),
         left(g.page_quote, 300)
    from g;
  select jsonb_build_object('computed_at', now(), 'window_days', v_window,
           'by_outcome', coalesce((select jsonb_object_agg(t.k, t.n) from (select outcome || coalesce(':' || path, '') k, count(*) n from pipeline.intake_nearest_start_shadow group by 1) t), '{}'::jsonb))
    into v;
  return v;
end
$function$;

revoke all on function security.intake_nearest_start_shadow_v1() from public, anon, authenticated;
comment on function security.intake_nearest_start_shadow_v1() is
  'CF-247 F-INT Rule B shadow (Decision 271): recomputes pipeline.intake_nearest_start_shadow. Writes only that table; admits nothing.';

select security.intake_nearest_start_shadow_v1();

do $p$
begin
  if (select count(*) from pipeline.intake_nearest_start_shadow) = 0
     and exists (select 1 from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id
                  where d.start_precision = 'month' and i.start_date is null and d.reason = 'the course page names no study period of the calendar (month only)') then
    raise exception 'post-check: the shadow is empty'; end if;
  if security.pipeline_num_v1('intake_dates.month_unique_match', 0) <> 0 then raise exception 'post-check: intake_dates.month_unique_match must stay 0 (P0 IQ-00313)'; end if;
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'intake_dates.nearest_start_providers') <> '[]'::jsonb then
    raise exception 'post-check: no provider may use the nearest start yet'; end if;
end $p$;
