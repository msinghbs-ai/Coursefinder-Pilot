CREATE OR REPLACE FUNCTION security.layer3_tier_evidence(p_task text, p_profile uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pipeline'
AS $function$
  select jsonb_build_object('cases',count(*),'right',count(*) filter (where h.outcome in ('exact','exact_not_stated')),
           'wrong',count(*) filter (where h.outcome='wrong_admitted'),'cost_per_call_usd',round(avg(h.cost_usd),6),
           'right_pct',case when count(*)>0 then round(100.0*count(*) filter (where h.outcome in ('exact','exact_not_stated'))/count(*),1) end,
           'eligible',count(*)>=30 and count(*) filter (where h.outcome='wrong_admitted')=0 and count(*) filter (where h.outcome in ('exact','exact_not_stated'))::numeric/nullif(count(*),0)>=0.80)
    from pipeline.layer3_holdout_results h join pipeline.layer3_holdout_cases c on c.id=h.case_id
   where h.profile_id=p_profile and c.task_class=p_task
$function$
