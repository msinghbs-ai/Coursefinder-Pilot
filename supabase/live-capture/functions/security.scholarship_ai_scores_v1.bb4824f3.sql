CREATE OR REPLACE FUNCTION security.scholarship_ai_scores_v1(p_prompt integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with last as (
    select distinct on (e.model_code, e.sample_id) e.* from pipeline.scholarship_ai_extractions e
     where e.sample_id is not null and e.prompt_version = p_prompt order by e.model_code, e.sample_id, e.at desc),
  j as (
    select l.model_code, s.id, s.expected x, l.answer a, l.checks k, l.error, l.cost_usd, l.seconds,
           (coalesce((l.answer->>'is_scholarship')::boolean, false) and coalesce((l.answer->>'single_scholarship')::boolean, false)) a_sch,
           (coalesce((s.expected->>'is_scholarship')::boolean, false) and coalesce((s.expected->>'single')::boolean, true)) x_sch
      from last l join pipeline.scholarship_ai_sample s on s.id = l.sample_id and s.active)
  select coalesce(jsonb_object_agg(z.model_code, z.v), '{}'::jsonb) from (
    select j.model_code, jsonb_build_object(
      'pages', count(*), 'errors', count(*) filter (where j.error is not null),
      'scholarship_right', count(*) filter (where j.error is null and j.a_sch = j.x_sch),
      'international_checked', count(*) filter (where j.x ? 'international' and j.x_sch and j.error is null),
      'international_right', count(*) filter (where j.x ? 'international' and j.x_sch and j.error is null and ((j.a->>'audience') in ('international', 'both')) = (j.x->>'international')::boolean),
      'offered_checked', count(*) filter (where j.x ? 'offered' and j.x_sch and j.error is null),
      'offered_right', count(*) filter (where j.x ? 'offered' and j.x_sch and j.error is null and ((j.a->>'offered') <> 'no') = (j.x->>'offered')::boolean),
      'proven', count(*) filter (where j.error is null and j.a_sch and coalesce((j.k->>'name')::boolean, false)),
      'proofs_failed', count(*) filter (where j.error is null and j.a_sch and (not coalesce((j.k->>'name')::boolean, true) or not coalesce((j.k->>'audience')::boolean, true) or not coalesce((j.k->>'value')::boolean, true))),
      'cost_usd', round(coalesce(sum(j.cost_usd), 0), 4), 'cost_per_page', round(coalesce(avg(j.cost_usd), 0), 5), 'seconds_per_page', round(coalesce(avg(j.seconds), 0), 1)) v
      from j group by j.model_code) z
$function$
