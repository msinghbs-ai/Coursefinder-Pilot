CREATE OR REPLACE FUNCTION security.calendar_default_months(p_provider_id uuid)
 RETURNS integer[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- when the Platform Admin set the months by hand, only those count (a parsed document approved as well adds nothing)
  with m as (
    select coalesce((select jsonb_object_agg(e->>'period', (e->'months'->>0)::int)
                       from (select x.proposal from pipeline.provider_policy_proposals x where x.provider_id = p_provider_id and x.kind = 'intake_calendar' and x.status = 'approved' and x.style = 'by_hand' order by x.decided_at desc nulls last limit 1) h,
                            jsonb_array_elements(coalesce(h.proposal->'periods', '[]'::jsonb)) e
                      where jsonb_typeof(e->'months') = 'array' and jsonb_array_length(e->'months') = 1),
                    security.calendar_period_months(p_provider_id)) cal),
  kinds as (select k.kind, k.ord from (values ('trimester', 1), ('semester', 2), ('term', 3), ('session', 4), ('study_period', 5), ('teaching_period', 6)) k(kind, ord)),
  first_kind as (select k.kind from kinds k, m where (m.cal ? (k.kind || ' 1')) order by k.ord limit 1),
  picked as (
    select (m.cal ->> (f.kind || ' 1'))::int m1, (m.cal ->> (f.kind || ' 2'))::int m2 from m, first_kind f)
  select case when p.m1 is null then '{}'::int[] when p.m2 is null or p.m2 = p.m1 then array[p.m1] else array[p.m1, p.m2] end from picked p
$function$
