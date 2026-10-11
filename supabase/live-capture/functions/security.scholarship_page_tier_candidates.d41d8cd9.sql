CREATE OR REPLACE FUNCTION security.scholarship_page_tier_candidates()
 RETURNS TABLE(id uuid, source_id uuid, evidence_id uuid, up_to boolean, pcts numeric[], amts numeric[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline'
AS $function$
  with src as (
    select s.id, s.source_id, sp.evidence_id,
           coalesce((sp.facts->'value'->>'up_to')::boolean, false) up_to,
           coalesce((select array_agg(x::numeric order by x::numeric) from jsonb_array_elements_text(coalesce(sp.facts->'value'->'percentages', '[]'::jsonb)) x), '{}'::numeric[]) pcts,
           coalesce((select array_agg(x::numeric order by x::numeric) from jsonb_array_elements_text(coalesce(sp.facts->'value'->'amounts', '[]'::jsonb)) x), '{}'::numeric[]) amts
      from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
     where s.lifecycle_status = 'active' and (s.award_value_type is null or s.award_value_type = 'text_only')
       and sp.read_status = 'read' and sp.facts->'value'->>'type' = 'ambiguous' and coalesce((sp.facts->'value'->>'foreign_currency')::boolean, false) = false
       and not exists (select 1 from scholarship.award_tiers t where t.scholarship_id = s.id)
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field in ('award_amount', 'award_percentage', 'award_value_type', 'award_value_text')))
  select src.id, src.source_id, src.evidence_id, src.up_to, src.pcts, src.amts from src
   where cardinality(src.pcts) + cardinality(src.amts) >= 1 and cardinality(src.pcts) <= 6 and cardinality(src.amts) <= 6
$function$
