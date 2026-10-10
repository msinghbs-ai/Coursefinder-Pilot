CREATE OR REPLACE FUNCTION public.svc_coverage_reidentify_next(p_limit integer, p_rule text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v from (
    select p.course_id, p.evidence_id, e.storage_path, coalesce(nullif(p.candidates->>'final_url', ''), p.url) url, co.canonical_title title, co.course_code code,
           security.coverage_country(p.provider_id) country
      from pipeline.coverage_course_pages p
      join pipeline.evidence_artifacts e on e.id = p.evidence_id
      join catalogue.courses co on co.id = p.course_id and co.lifecycle_status = 'active'
     where p.status = 'mismatch' and p.read_status = 'identity_mismatch' and coalesce(p.basis, '') <> 'manual' and e.storage_path is not null
       and not exists (select 1 from pipeline.coverage_reidentify_done d where d.course_id = p.course_id and d.evidence_id = p.evidence_id and d.rule = p_rule)
     order by p.course_id limit greatest(1, least(coalesce(p_limit, 100), 400)) for update of p skip locked) x;
  return v;
end $function$
