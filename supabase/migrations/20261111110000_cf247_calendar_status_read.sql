-- CF-247 F-INT calendar status per provider, and a faster calendar re-read (Platform Admin 11 Nov 2026 09:26 AEDT: "Go ahead with 1, 2 and 3":
-- 1 a per-provider calendar status on the admin UI so providers without a usable calendar are marked; 2 raise the calendar re-read to 100 an hour).
-- Evidence (production, read only, 11 Nov 2026 08:5x AEDT): of the 73 providers with intake rows waiting for a date, 7 have an approved 2027 calendar
--   (1,478 rows), 21 have 2027 starts read but not approved (6,406), 37 have a calendar stored with no 2027 start read (4,747) and 8 a calendar found whose
--   read failed (384); none has no calendar at all. 7,472 of the 9,365 month-only rows come from course pages ("adapter pattern"): course pages give the
--   month, the approved calendar gives the day. Job calendar-reread reads 20 stored copies an hour in 8-18 s a run with no Firecrawl; about 330 wait for
--   reader calendar-v2.3 (#1008), so the queue takes about 17 hours.
-- What:
--   1. public.admin_calendar_status_read(p_args): read only, an assigned StudySearch role (rank 3). One row per provider with an intake row waiting for a date
--      (month only, or no start with a failure class): status (approved_2027 / read_2027_not_approved / approved_earlier_edition / stored_no_2027 / read_failed /
--      none_found), rows waiting, calendar sources found and read, the latest qualifier verdict and reason, its next check, and the latest reading's first 2027
--      start. Nothing is written.
--   2. batch.calendar_reread: maximum 60 -> 100, value 20 -> 100. The run reads stored copies only (paid_reads 0); every reading still goes through the
--      qualifier and approval. 100 documents is about 40-90 s a run at the measured 0.4-0.9 s a document, inside the edge function limit.
-- Guards: G1 (no job added), G2 (the batch is a setting; no number in code), G3 (no consumer API object read or changed), G4 (cf-247-s529).
-- Replaces: nothing.
-- Retires: nothing.
-- Reversal: drop public.admin_calendar_status_read by paste file; set batch.calendar_reread back to 20 (maximum 60).

create or replace function public.admin_calendar_status_read(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare v jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  with need as (
    select d.provider_id, count(*) as rows_waiting,
           count(*) filter (where d.start_precision = 'month') as month_only,
           count(*) filter (where d.start_precision is null) as no_start
      from pipeline.course_intake_dates d
     where d.start_precision = 'month' or (d.start_precision is null and d.failure_class is not null)
     group by d.provider_id),
  src as (
    select s.provider_id, count(*) as sources, count(*) filter (where s.status = 'read') as sources_read
      from pipeline.provider_fact_sources s where s.kind = 'intake_calendar' group by s.provider_id),
  dec as (
    select q.provider_id,
           bool_or(q.verdict = 'approved' and q.withdrawn_at is null and q.edition_year >= extract(year from now() at time zone 'Australia/Melbourne')::int + 1) as approved_next,  -- fixed: the next academic year is the calendar's edition
           bool_or(q.verdict = 'approved' and q.withdrawn_at is null) as approved_any
      from pipeline.calendar_qualify_decisions q group by q.provider_id),
  last_dec as (
    select distinct on (q.provider_id) q.provider_id, q.verdict, q.reason, q.source_url, q.next_check_at, q.decided_at
      from pipeline.calendar_qualify_decisions q order by q.provider_id, q.decided_at desc),
  last_read as (   -- the latest reading of each stored calendar
    select distinct on (pp.fact_source_id) pp.provider_id, pp.fact_source_id, pp.proposal, pp.created_at
      from pipeline.provider_policy_proposals pp
      join pipeline.provider_fact_sources s on s.id = pp.fact_source_id and s.kind = 'intake_calendar'
     order by pp.fact_source_id, pp.created_at desc),
  next_start as (
    select r.provider_id, min((st->>'date')) as first_next_start
      from last_read r, jsonb_array_elements(coalesce(r.proposal->'periods', '[]'::jsonb)) per, jsonb_array_elements(coalesce(per->'starts', '[]'::jsonb)) st
     where (st->>'year')::int >= extract(year from now() at time zone 'Australia/Melbourne')::int + 1 and st->>'date' is not null   -- fixed: the next academic year
     group by r.provider_id),
  rows as (
    select n.provider_id, p.display_name as provider, c.iso_alpha2 as country, n.rows_waiting, n.month_only, n.no_start,
           coalesce(s.sources, 0) as sources, coalesce(s.sources_read, 0) as sources_read,
           case when d.approved_next then 'approved_2027'
                when ns.first_next_start is not null then 'read_2027_not_approved'
                when d.approved_any then 'approved_earlier_edition'
                when coalesce(s.sources_read, 0) > 0 then 'stored_no_2027'
                when coalesce(s.sources, 0) > 0 then 'read_failed'
                else 'none_found' end as status,
           ld.verdict as last_verdict, ld.reason as last_reason, ld.source_url as last_address, ld.next_check_at, ld.decided_at as last_decided_at,
           ns.first_next_start
      from need n
      join catalogue.providers p on p.id = n.provider_id
      left join ref.countries c on c.id = p.country_id
      left join src s on s.provider_id = n.provider_id
      left join dec d on d.provider_id = n.provider_id
      left join last_dec ld on ld.provider_id = n.provider_id
      left join next_start ns on ns.provider_id = n.provider_id)
  select jsonb_build_object(
           'generated_at', now(),
           'rows', coalesce((select jsonb_agg(to_jsonb(r) order by r.rows_waiting desc) from rows r), '[]'::jsonb),
           'totals', coalesce((select jsonb_object_agg(t.status, jsonb_build_object('providers', t.providers, 'rows_waiting', t.rows_waiting))
                                 from (select status, count(*) as providers, sum(rows_waiting) as rows_waiting from rows group by status) t), '{}'::jsonb),
           'reread', jsonb_build_object('per_run', security.pipeline_num_v1('batch.calendar_reread', 20),
                                        'waiting', (select count(*) from pipeline.calendar_reread_state w where w.state = 'waiting')))
    into v;
  return v;
end
$function$;

revoke all on function public.admin_calendar_status_read(jsonb) from public, anon;
grant execute on function public.admin_calendar_status_read(jsonb) to authenticated;
comment on function public.admin_calendar_status_read(jsonb) is
  'CF-247 F-INT (Platform Admin 11 Nov 2026): read only. Calendar status of each provider with intake rows waiting for a date: approved 2027 calendar, 2027 starts read but not approved, approved earlier edition, stored with no 2027 start, read failed, or none found; rows waiting, sources, latest qualifier verdict and reason.';

update pipeline.platform_toolset_settings
   set max_value = 100, value = to_jsonb(100),
       reason = 'Platform Admin 11 Nov 2026 09:26 AEDT ("Go ahead with 1, 2 and 3"): read the ~330 stored calendars waiting for reader calendar-v2.3 in about 3-4 hours instead of 17; stored copies only, no Firecrawl (20261111110000)',
       updated_at = now()
 where toolset_key = 'pipeline' and key = 'batch.calendar_reread';

do $p$
begin
  if security.pipeline_num_v1('batch.calendar_reread', 0) <> 100 then raise exception 'post-check: batch.calendar_reread is not 100'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'batch.calendar_reread' and max_value = 100) <> 1 then
    raise exception 'post-check: batch.calendar_reread maximum is not 100'; end if;
end $p$;
