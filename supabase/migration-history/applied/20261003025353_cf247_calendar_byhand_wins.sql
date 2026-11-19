-- CF-247 (3 Oct 2026, 13:05 AEST). Platform Admin, 12:51: two calendars were approved but the provider's courses did
-- not get intakes. Found: (1) when a calendar is set by hand and a parsed one is approved as well, the parsed months
-- were winning for the same period; (2) a course page that names a period the Platform Admin left as "Not an intake"
-- (Intake 2 empty) was held with "a period has no approved start month", so the months that were approved never
-- reached the course. Both functions are replaced under an md5 guard on their live text.
-- Now: months entered by hand win over parsed ones for the same period; and where the university's calendar was set by
-- hand, a period with no month is treated as "not an intake" and the course gets the months that were approved
-- (at least one period on its page must have a month). Parsed-only calendars keep the old rule: every period named
-- on the page needs a month.
do $g$ begin
  if (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'calendar_period_months') is distinct from 'c8ece1444f3c8e053e2bd6dadfa0fa3b'
  then raise exception 'calendar_period_months changed; not replacing'; end if;
  if (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'security' and p.proname = 'semester_intake_plan_v1') is distinct from '302f0670357709c868ec3b3a9e9fd68e'
  then raise exception 'semester_intake_plan_v1 changed; not replacing'; end if;
end $g$;

create or replace function security.calendar_period_months(p_provider_id uuid)
returns jsonb language sql stable security definer set search_path to '' as $f$
  select coalesce(jsonb_object_agg(s.period, s.start_month), '{}'::jsonb) from (
    select distinct on (e->>'period') e->>'period' as period, (e->'months'->>0)::int as start_month
      from pipeline.provider_policy_proposals x, jsonb_array_elements(coalesce(x.proposal->'periods', '[]'::jsonb)) e
     where x.provider_id = p_provider_id and x.kind = 'intake_calendar' and x.status = 'approved'
       and jsonb_typeof(e->'months') = 'array' and jsonb_array_length(e->'months') = 1
     order by e->>'period', (x.style = 'by_hand') desc nulls last, x.decided_at desc nulls last) s
$f$;

create or replace function security.calendar_set_by_hand(p_provider_id uuid)
returns boolean language sql stable security definer set search_path to '' as $f$
  select exists (select 1 from pipeline.provider_policy_proposals x where x.provider_id = p_provider_id and x.kind = 'intake_calendar' and x.status = 'approved' and x.style = 'by_hand')
$f$;
revoke all on function security.calendar_set_by_hand(uuid) from public, anon, authenticated;

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
  p as (select r.*, security.quoted_study_periods(r.qs) per, security.calendar_period_months(r.pid) cal, security.calendar_set_by_hand(r.pid) byhand from r),
  q as (
    select p.*, (select array_agg(distinct (p.cal->>x)::int order by (p.cal->>x)::int) from unnest(p.per) x where p.cal ? x) mon,
           (select count(*) from unnest(p.per) x where not p.cal ? x) missing
      from p where cardinality(p.per) > 0)
  select q.id, q.cid, q.pid, q.t, q.qs, q.per, q.mon,
         case when q.qs ~* '\m(january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\M' then 'held'
              when q.qs ~* '\m(hong kong|HK|singapore|malaysia|sarawak|dubai|mauritius|sri lanka|vietnam|china|indonesia|online)\M' then 'held'
              when q.cal = '{}'::jsonb then 'no_calendar'
              when q.missing > 0 and not (q.byhand and q.mon is not null) then 'period_unknown'
              when exists (select 1 from catalogue.course_intakes i where i.course_id = q.cid and i.status = 'active') then 'held'
              when exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = q.cid and k.field = 'intakes') then 'held'
              else 'answer' end,
         case when q.qs ~* '\m(january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\M' then 'the quotes also name months'
              when q.qs ~* '\m(hong kong|HK|singapore|malaysia|sarawak|dubai|mauritius|sri lanka|vietnam|china|indonesia|online)\M' then 'the quotes name a campus outside Australia or online study'
              when q.cal = '{}'::jsonb then 'no approved calendar for this university'
              when q.missing > 0 and not (q.byhand and q.mon is not null) then 'a period has no approved start month'
              when exists (select 1 from catalogue.course_intakes i where i.course_id = q.cid and i.status = 'active') then 'the course already has intakes'
              when exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = q.cid and k.field = 'intakes') then 'intakes set by hand'
              end
    from q;
end $f$;
