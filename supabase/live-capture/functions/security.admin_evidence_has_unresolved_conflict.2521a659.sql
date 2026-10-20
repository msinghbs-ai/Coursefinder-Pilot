CREATE OR REPLACE FUNCTION security.admin_evidence_has_unresolved_conflict(p_evidence_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pipeline', 'workflow'
AS $function$
  select exists(
    select 1
    from workflow.review_queue rq
    join pipeline.claims cl on cl.id=rq.candidate_claim_id
    where cl.evidence_id=p_evidence_id
      and lower(coalesce(rq.status,'open')) not in ('closed','resolved','accepted','rejected')
  )
$function$
