CREATE OR REPLACE FUNCTION security.ops_learning_record_v1(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- A lane records an outcome of a known pattern: code, entity, evidence_signature, performed_by, success, stage_advanced, observed, cost_usd, credits.
declare v_ok boolean := coalesce((p->>'success')::boolean, false); v_id bigint;
begin
  if not exists (select 1 from pipeline.ops_remedy_knowledge where code = p->>'code') then raise exception 'no recovery pattern %', p->>'code' using errcode = '22023'; end if;
  insert into pipeline.ops_remedy_outcomes(knowledge_code, issue_id, fingerprint, entity, performed_by, applied_at, expected, observed, success, stage_advanced, cost_usd, credits, evidence_signature, evidence)
  values (p->>'code', (p->>'issue_id')::bigint, p->>'fingerprint', p->>'entity', coalesce(p->>'performed_by', 'platform'), coalesce((p->>'applied_at')::timestamptz, now()), p->>'expected',
          coalesce(p->'observed', '{}'::jsonb), v_ok, (p->>'stage_advanced')::boolean, coalesce((p->>'cost_usd')::numeric, 0), coalesce((p->>'credits')::numeric, 0), p->>'evidence_signature',
          coalesce(p->'evidence', '{}'::jsonb))
  returning id into v_id;
  update pipeline.ops_remedy_knowledge k set applied = k.applied + 1, verified = k.verified + case when v_ok then 1 else 0 end, failed = k.failed + case when v_ok then 0 else 1 end,
         no_yield_streak = case when v_ok then 0 else k.no_yield_streak + 1 end, last_outcome_at = greatest(k.last_outcome_at, now()),
         cost_usd = k.cost_usd + coalesce((p->>'cost_usd')::numeric, 0), credits = k.credits + coalesce((p->>'credits')::numeric, 0)
   where k.code = p->>'code';
  return jsonb_build_object('outcome', v_id);
end $function$
;

