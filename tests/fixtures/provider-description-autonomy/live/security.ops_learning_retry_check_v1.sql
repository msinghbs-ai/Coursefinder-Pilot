CREATE OR REPLACE FUNCTION security.ops_learning_retry_check_v1(p_code text, p_entity text, p_signature text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 (direction 4 Nov 2026 18:08 §3, §4): for a lane that repeats an attempt outside the controller (the AER recovery selector, Course Link rules):
-- may this pattern be tried on this entity with this evidence signature (stored copy, reader and settings)? Refused when the pattern lost automatic
-- eligibility, or when the same entity and signature already failed; allowed when the signature changed.
  select case when k.code is null then jsonb_build_object('allowed', true, 'reason', 'no recorded pattern')
              when not k.auto_eligible and k.authority = 'auto' and exists (select 1 from pipeline.ops_remedy_outcomes o where o.knowledge_code = k.code and o.entity = p_entity
                                                                          and o.evidence_signature = p_signature and not o.success)
                then jsonb_build_object('allowed', false, 'reason', 'the same evidence already failed, and the pattern lost automatic eligibility: ' || coalesce(k.eligibility_reason, ''))
              when exists (select 1 from pipeline.ops_remedy_outcomes o where o.knowledge_code = k.code and o.entity = p_entity and o.evidence_signature = p_signature and not o.success)
                then jsonb_build_object('allowed', false, 'reason', 'the same evidence already failed for this item: ' || k.no_retry_condition)
              when not k.auto_eligible and k.authority <> 'auto'
                then jsonb_build_object('allowed', false, 'reason', 'needs ' || k.authority || ' authority: ' || coalesce(k.eligibility_reason, k.reuse_conditions))
              else jsonb_build_object('allowed', true, 'reason', 'evidence changed or never tried') end
    from (select 1) d left join pipeline.ops_remedy_knowledge k on k.code = p_code
$function$
;

