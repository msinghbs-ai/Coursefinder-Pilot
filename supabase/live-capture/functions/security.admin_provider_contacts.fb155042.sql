CREATE OR REPLACE FUNCTION security.admin_provider_contacts(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'ref', 'public', 'auth'
AS $function$
declare v_rank integer:=0;v_profile jsonb;v_items jsonb;v_events jsonb;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 select security.current_role_rank() into v_rank;if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
 select jsonb_build_object('profile_id',p.id,'enabled',p.enabled,'paused',p.paused,'base_url',p.base_url,'domain',p.domain,'last_run_at',p.last_run_at,'last_success_at',p.last_success_at,'last_error',p.last_error)
 into v_profile from pipeline.provider_contact_profiles p where p.provider_id=p_provider_id;
 select coalesce(jsonb_agg(row_json order by source_priority,lower(coalesce(row_json->>'territory_text','')),lower(coalesce(row_json->>'job_title','')),lower(coalesce(row_json->>'full_name',''))),'[]'::jsonb)
 into v_items from (
  select case v.source_authority when 'first_party' then 1 when 'manual' then 2 else 3 end source_priority,
  jsonb_build_object('id',c.id,'managed_contact_id',c.id,'source_class',v.source_authority,'managed_source_class',v.source_class,'source_authority',v.source_authority,
   'source_provider',coalesce(v.metadata->>'source_provider',v.source_authority),'full_name',v.full_name,'job_title',v.job_title,'team_name',coalesce(v.team_name,v.functional_area),
   'territory_text',coalesce(v.countries_or_markets,v.region_scope),'territory_codes',coalesce(v.metadata->'territory_codes','[]'::jsonb),'work_email',v.work_email,'work_phone',v.work_phone,
   'professional_profile_url',v.metadata->>'professional_profile_url','source_url',v.source_url,'evidence_id',v.evidence_id,'verification_state',v.verification_state,
   'confidence',v.metadata->'confidence','observed_at',v.effective_from,'last_verified_at',v.verified_on,
   'source_priority',case v.source_authority when 'first_party' then 'preferred' when 'manual' then 'governed_manual' else 'secondary_enrichment' end,
   'record_type',c.record_type,'lifecycle_status',c.lifecycle_status) row_json
  from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id
  where c.provider_id=p_provider_id and c.lifecycle_status in ('active','inactive') order by 1,v.verified_on desc nulls last limit 100
 ) q;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'event_type',e.event_type,'source_class',e.source_class,'before_state',e.before_state,'after_state',e.after_state,'detected_at',e.detected_at,'acknowledged',e.acknowledged) order by e.detected_at desc),'[]'::jsonb)
 into v_events from (select * from pipeline.provider_contact_watch_events where provider_id=p_provider_id order by detected_at desc limit 20)e;
 return jsonb_build_object('profile',coalesce(v_profile,'{}'::jsonb),'items',coalesce(v_items,'[]'::jsonb),'events',coalesce(v_events,'[]'::jsonb),'summary',jsonb_build_object(
  'current_contacts',(select count(*) from pipeline.provider_contacts where provider_id=p_provider_id and lifecycle_status='active'),
  'first_party_contacts',(select count(*) from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id where c.provider_id=p_provider_id and c.lifecycle_status='active' and v.source_authority='first_party'),
  'manual_contacts',(select count(*) from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id where c.provider_id=p_provider_id and c.lifecycle_status='active' and v.source_authority='manual'),
  'enriched_contacts',(select count(*) from pipeline.provider_contacts c join pipeline.provider_contact_versions v on v.id=c.current_version_id where c.provider_id=p_provider_id and c.lifecycle_status='active' and v.source_authority='licensed_enrichment'),
  'unacknowledged_changes',(select count(*) from pipeline.provider_contact_watch_events where provider_id=p_provider_id and acknowledged=false)));
end $function$
