CREATE OR REPLACE FUNCTION security.ai_spend_today_v1()
 RETURNS TABLE(use text, label text, spent numeric, guard numeric, calls bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with d as (select (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') t),
  s as (
    select 'scholarship_ai' u, coalesce(sum(x.cost_usd), 0) spent, count(*) calls from pipeline.scholarship_ai_extractions x, d where x.at >= d.t
    union all select 'adapter_builder', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.uni_adapter_drafts x, d where x.created_at >= d.t and coalesce(x.cost_usd, 0) > 0
    union all select 'central_ai', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.central_ai_queue x, d where x.created_at >= d.t and coalesce(x.cost_usd, 0) > 0
    union all select 'course_match', coalesce(sum(x.cost_usd), 0), count(*) from pipeline.coverage_ai_match x, d where coalesce(x.decided_at, x.created_at) >= d.t and coalesce(x.cost_usd, 0) > 0)
  select s.u, l.label, round(s.spent, 4), (security.toolset_setting('openrouter', 'guard_' || s.u))::text::numeric, s.calls
    from s join (values ('scholarship_ai', 'Read scholarship pages with AI', 1), ('adapter_builder', 'Adapter proposals', 2), ('central_ai', 'Central pages with AI', 3),
                        ('course_match', 'AI course-page matching', 4)) l(u, label, sort) on l.u = s.u
   order by l.sort
$function$
