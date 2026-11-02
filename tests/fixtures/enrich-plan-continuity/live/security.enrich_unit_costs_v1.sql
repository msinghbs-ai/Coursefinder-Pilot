CREATE OR REPLACE FUNCTION security.enrich_unit_costs_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- what each kind of step actually used, last 30 days (estimates follow the platform, nothing is typed in)
  with u as (select security.fc_purpose_group_v1(x.purpose) g, x.purpose, x.units, x.provider_id from pipeline.coverage_vendor_usage x where x.at > now() - interval '30 days')  -- fixed: estimate window
  select jsonb_build_object(
    'site_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g in ('other', 'central')), 0), 1),
    'search_credits_per_course', round(coalesce((select sum(units) / nullif(count(*), 0) from u where purpose = 'course_link_search'), 0), 2),
    'adapter_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g = 'reads'), 0), 1),
    'scholarship_credits', round(coalesce((select sum(units) / nullif(count(distinct provider_id), 0) from u where g = 'scholarships'), 0), 1),
    'enrich_usd_per_item', coalesce((select round(avg(coalesce(e.cost_usd, 0)), 5) from pipeline.field_enrich_items e where e.updated_at > now() - interval '30 days' and e.state in ('filled', 'skipped', 'review', 'failed')), 0),
    'adapter_usd', coalesce((select round(sum(d.cost_usd) / nullif(count(distinct d.provider_id), 0), 4) from pipeline.uni_adapter_drafts d where d.created_at > now() - interval '30 days'), 0),
    'scholarship_usd', coalesce((select round(sum(s.cost_usd) / nullif(count(distinct s.provider_id), 0), 4) from pipeline.scholarship_ai_extractions s where s.at > now() - interval '30 days'), 0))
$function$
