CREATE OR REPLACE FUNCTION security.layer4_admission_record_v1(p_decision uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Runs the check for one decision and keeps its latest result (pipeline.layer4_admission_checks).
declare v jsonb := security.layer4_admission_check_v1(p_decision); d record;
begin
  select x.id, x.created_at, r.id rid, r.field_code, r.entity_type, r.entity_id into d
    from pipeline.layer4_decisions x join pipeline.layer4_review_items r on r.id = x.review_item_id where x.id = p_decision;
  if d.id is null then return null; end if;
  insert into pipeline.layer4_admission_checks as c(decision_id, review_item_id, field_code, entity_type, entity_id, decided_at, result, reason, admitted, published, lag_seconds, detail)
  values (d.id, d.rid, d.field_code, d.entity_type, d.entity_id, d.created_at, v->>'result', v->>'reason', (v->>'admitted')::boolean, (v->>'published')::boolean,
          (v->>'lag_seconds')::numeric, coalesce(v->'detail', '{}'::jsonb))
  on conflict (decision_id) do update set result = excluded.result, reason = excluded.reason, admitted = excluded.admitted, published = excluded.published,
     lag_seconds = coalesce(excluded.lag_seconds, c.lag_seconds), detail = excluded.detail, checked_at = now(), checks = c.checks + 1;
  return v->>'result';
end $function$
