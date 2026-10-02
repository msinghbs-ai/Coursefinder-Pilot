-- CF-247 (Decision 228, 2 Oct 2026). Platform Admin, 16:42, by multiple choice: "Semesters to months".
-- About 420 intake reviews wait because the course page names only its study periods ("Semester 1, 2027", "Commencing
-- in Trimester 1", "Term 1 & 3") and the AI check, rightly, would not turn them into months. A university's own
-- calendar says when each period starts.
--  * Each university's start month for each study period comes from its academic calendar, approved by a Platform
--    Admin (Coverage › Attributes › Academic calendars), or set by the Platform Admin by hand from the calendar. Only a
--    period with one start month is used.
--  * A waiting intake review is answered from the calendar only when every period its quotes name has an approved
--    start month, the quotes name no month themselves, the course has no intakes yet and none set by hand, and the quotes
--    do not name a campus outside Australia. The months are written as the course's intakes with the course page as
--    evidence, and the review is closed with both the page's words and the calendar months kept.
--  * The job provider-calendar-intakes answers them every 10 minutes after a calendar is approved or set (an approval
--    request itself writes nothing, so it stays within the time limit of a signed-in request).

-- 1. the approved start month of each study period, per university (latest decision wins; one month only)
create or replace function security.calendar_period_months(p_provider_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_object_agg(s.period, s.start_month), '{}'::jsonb) from (
    select distinct on (e->>'period') e->>'period' as period, (e->'months'->>0)::int as start_month
      from pipeline.provider_policy_proposals x, jsonb_array_elements(coalesce(x.proposal->'periods', '[]'::jsonb)) e
     where x.provider_id = p_provider_id and x.kind = 'intake_calendar' and x.status = 'approved'
       and jsonb_typeof(e->'months') = 'array' and jsonb_array_length(e->'months') = 1
     order by e->>'period', x.decided_at desc nulls last) s
$f$;
revoke all on function security.calendar_period_months(uuid) from public, anon, authenticated;

-- 2. the study periods named in a review's quotes ("Semester 1 & 2", "Term 1, 2027", "Trimester one")
create or replace function security.quoted_study_periods(p_quotes text)
returns text[] language sql immutable as $f$
  select coalesce(array_agg(distinct p order by p), '{}') from (
    select regexp_replace(lower(m[1]), '^(study|teaching) period$', '\1_period') || ' ' ||
           case lower(n) when 'one' then '1' when 'two' then '2' when 'three' then '3' when 'four' then '4'
                         when 'i' then '1' when 'ii' then '2' when 'iii' then '3' else n end p
      from regexp_matches(coalesce(p_quotes, ''), '\m(semester|trimester|term|session|study period|teaching period)s?\s+(\d|one|two|three|four|iii|ii|i)\M((?:\s*(?:&|and|,|/)\s*(?:\d)\M)*)', 'gi') m
      cross join lateral unnest(array[m[2]] || coalesce((select array_agg(x[1]) from regexp_matches(coalesce(m[3], ''), '(\d)', 'g') x), '{}')) n) s
$f$;

-- 3. the plan for waiting intake reviews whose quotes name only study periods
create or replace function security.semester_intake_plan_v1(p_provider_id uuid default null)
returns table(review_id uuid, course_id uuid, provider_id uuid, title text, quotes text, periods text[], months int[], outcome text, reason text)
language plpgsql stable security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security' as $f$
begin
  return query
  with r as (
    select l.id, l.entity_id cid, c.provider_id pid, c.canonical_title t,
           (select string_agg(q, ' | ') from jsonb_array_elements_text(coalesce(l.layer3_state->'answer'->'quotes', '[]'::jsonb)) q) qs
      from pipeline.layer4_review_items l join catalogue.courses c on c.id = l.entity_id
     where l.status = 'pending' and l.entity_type = 'course' and l.field_code = 'course_intake' and l.before_value is null and l.evidence_id is not null
       and (p_provider_id is null or c.provider_id = p_provider_id)),
  p as (select r.*, security.quoted_study_periods(r.qs) per, security.calendar_period_months(r.pid) cal from r),
  q as (
    select p.*, (select array_agg(distinct (p.cal->>x)::int order by (p.cal->>x)::int) from unnest(p.per) x where p.cal ? x) mon,
           (select count(*) from unnest(p.per) x where not p.cal ? x) missing
      from p where cardinality(p.per) > 0)
  select q.id, q.cid, q.pid, q.t, q.qs, q.per, q.mon,
         case when q.qs ~* '\m(january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\M' then 'held'
              when q.qs ~* '\m(hong kong|HK|singapore|malaysia|sarawak|dubai|mauritius|sri lanka|vietnam|china|indonesia|online)\M' then 'held'
              when q.cal = '{}'::jsonb then 'no_calendar'
              when q.missing > 0 then 'period_unknown'
              when exists (select 1 from catalogue.course_intakes i where i.course_id = q.cid and i.status = 'active') then 'held'
              when exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = q.cid and k.field = 'intakes') then 'held'
              else 'answer' end,
         case when q.qs ~* '\m(january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\M' then 'the quotes also name months'
              when q.qs ~* '\m(hong kong|HK|singapore|malaysia|sarawak|dubai|mauritius|sri lanka|vietnam|china|indonesia|online)\M' then 'the quotes name a campus outside Australia or online study'
              when q.cal = '{}'::jsonb then 'no approved calendar for this university'
              when q.missing > 0 then 'a period has no approved start month'
              when exists (select 1 from catalogue.course_intakes i where i.course_id = q.cid and i.status = 'active') then 'the course already has intakes'
              when exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = q.cid and k.field = 'intakes') then 'intakes set by hand'
              end
    from q;
end $f$;
revoke all on function security.semester_intake_plan_v1(uuid) from public, anon, authenticated;
