CREATE OR REPLACE FUNCTION public.svc_coverage_tuition_handoff_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  if not exists (select 1 from pipeline.layer3_model_profiles where 'provider_current_tuition_validation'=any(allowed_task_classes) and enabled and not paused and coalesce((quality_benchmark->>'pass')::boolean,false)) then return '[]'::jsonb; end if;
  with pick as (
    select p.course_id
      from pipeline.coverage_course_pages p
      join pipeline.evidence_artifacts e on e.id=p.evidence_id and e.storage_path is not null
      join catalogue.courses co on co.id=p.course_id and co.lifecycle_status='active'
      join catalogue.providers pr on pr.id=p.provider_id
      join pipeline.coverage_admission_countries ca on ca.country_id=pr.country_id and ca.active
     where p.read_status='read' and p.candidates->'fee'->'candidates' @> '[{"international": true}]'::jsonb
       and coalesce(p.candidates->'fee'->>'basis','')<>'total' and security.coverage_identity_allowed(p.provider_id, p.identity_basis, 'tuition') and p.l3_work_item_id is null
       and (p.l3_handoff_at is null or p.l3_handoff_at < now()-interval '1 day')
       and security.coverage_tuition_target_v1(p.candidates->'fee') is not null
       and not exists (select 1 from catalogue.course_fees f where f.course_id=p.course_id and f.fee_type='provider_current_tuition' and f.status='active')
       and not security.layer4_entity_or_parent_blocked('course',p.course_id,'operational')
     order by p.read_at limit greatest(1,least(coalesce(p_limit,50),100)) for update of p skip locked),
  upd as (update pipeline.coverage_course_pages p set l3_handoff_at=now() from pick where p.course_id=pick.course_id returning p.course_id, p.url, p.evidence_id)
  select coalesce(jsonb_agg(jsonb_build_object('course_id',u.course_id,'storage_path',e.storage_path,'url',u.url)),'[]'::jsonb) into v
    from upd u join pipeline.evidence_artifacts e on e.id=u.evidence_id;
  return v;
end $function$
