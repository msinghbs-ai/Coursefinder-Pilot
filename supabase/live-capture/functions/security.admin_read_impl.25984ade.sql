CREATE OR REPLACE FUNCTION security.admin_read_impl(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'security', 'catalogue', 'ref', 'pim', 'scholarship', 'pipeline', 'workflow', 'integration', 'search', 'publishing', 'auth'
AS $function$
declare
  v_rank integer := 0;
  v_result jsonb;
  v_id uuid;
  v_limit integer := least(greatest(coalesce((p_args->>'limit')::integer,500),1),2000);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank < 1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  if p_operation='context' then return public.ui_context();
  elsif p_operation='dashboard' then return public.ui_dashboard();
  elsif p_operation='providers' then select coalesce(jsonb_agg(to_jsonb(x) order by x.canonical_name),'[]'::jsonb) into v_result from public.ui_providers_list(v_limit) x; return v_result;
  elsif p_operation='provider_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    select coalesce(public.ui_provider_detail(v_id),'{}'::jsonb)||jsonb_build_object('evidence',coalesce(public.ui_provider_related_evidence(v_id,100,0,null,null)->'rows','[]'::jsonb),'courses',coalesce(public.ui_provider_related_courses(v_id,100,0,null,null,null)->'rows','[]'::jsonb)) into v_result; return v_result;
  elsif p_operation='campuses' then select coalesce(jsonb_agg(to_jsonb(x) order by x.provider_name,x.name),'[]'::jsonb) into v_result from public.ui_campuses_list(v_limit) x; return v_result;
  elsif p_operation='campus_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    select jsonb_build_object('id',ca.id,'stable_key',ca.stable_key,'name',ca.name,'campus_code',ca.campus_code,'provider_id',ca.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),'country_code',co.iso_alpha2,'subdivision_code',sd.code,'subdivision_name',sd.name,'city',ca.city,'address_line1',ca.address_line1,'address_line2',ca.address_line2,'postcode',ca.postcode,'latitude',ca.latitude,'longitude',ca.longitude,'phone',ca.phone,'website',ca.website,'status',ca.status,'publication_status',ca.publication_status,'valid_from',ca.valid_from,'valid_to',ca.valid_to,'last_verified_at',ca.last_verified_at,'created_at',ca.created_at,'updated_at',ca.updated_at,'source',jsonb_build_object('source_id',ca.source_id,'source_label',s.label,'source_type',s.source_type,'source_url',s.url),'evidence',case when e.id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('id',e.id,'type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'captured_at',e.captured_at)) end,'courses',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.canonical_title,'delivery_mode',cc.delivery_mode,'is_primary',cc.is_primary) order by c.canonical_title) from catalogue.course_campuses cc join catalogue.courses c on c.id=cc.course_id where cc.campus_id=ca.id),'[]'::jsonb)) into v_result from catalogue.campuses ca join catalogue.providers p on p.id=ca.provider_id join ref.countries co on co.id=ca.country_id left join ref.subdivisions sd on sd.id=ca.subdivision_id left join pipeline.sources s on s.id=ca.source_id left join pipeline.evidence_artifacts e on e.id=ca.evidence_id where ca.id=v_id; return coalesce(v_result,'{}'::jsonb);
  elsif p_operation='courses' or p_operation='completeness' then select coalesce(jsonb_agg(to_jsonb(x) order by x.provider_name,x.canonical_title),'[]'::jsonb) into v_result from public.ui_course_completeness_list(v_limit) x; return v_result;
  elsif p_operation='course_detail' then
    v_id:=nullif(p_args->>'id','')::uuid;
    select coalesce(public.ui_course_detail(v_id),'{}'::jsonb)||jsonb_build_object(
      'fee_summary',jsonb_build_object(
        'cricos_registered',coalesce((select jsonb_agg(jsonb_build_object('id',cf.id,'fee_type',cf.fee_type,'amount',cf.amount,'currency',cf.currency_code,'basis',cf.basis,'fee_year',cf.fee_year,'audience',cf.audience,'status',cf.status,'source_snapshot_at',cf.source_snapshot_at,'evidence_id',cf.evidence_id) order by cf.fee_type) from catalogue.course_fees cf where cf.course_id=v_id and cf.basis='registered_total_course' and coalesce(cf.status,'active')='active'),'[]'::jsonb),
        'provider_current',coalesce((select jsonb_agg(jsonb_build_object('id',cf.id,'fee_type',cf.fee_type,'amount',cf.amount,'currency',cf.currency_code,'basis',cf.basis,'fee_year',cf.fee_year,'audience',cf.audience,'status',cf.status,'source_snapshot_at',cf.source_snapshot_at,'source_id',cf.source_id,'evidence_id',cf.evidence_id) order by cf.fee_year desc nulls last,cf.created_at desc) from catalogue.course_fees cf where cf.course_id=v_id and cf.basis is distinct from 'registered_total_course' and coalesce(cf.status,'active')='active'),'[]'::jsonb)
      ),
      'regulatory_facts',coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('scheme',o.scheme,'registration_code',o.registration_code,'status',o.status,'course_language',o.course_language,'work_component',o.work_component,'work_component_total_hours',o.work_component_total_hours,'foundation_studies',o.foundation_studies,'dual_qualification',o.dual_qualification,'source_snapshot_at',o.source_snapshot_at,'evidence_id',o.evidence_id)) order by o.source_snapshot_at desc) from catalogue.course_regulatory_observations o where o.course_id=v_id and o.valid_to is null),'[]'::jsonb),
      'campuses',coalesce(public.ui_course_related_campuses(v_id),'[]'::jsonb),
      'evidence',coalesce((select jsonb_agg(distinct jsonb_build_object('id',e.id,'evidence_type',e.evidence_type,'source_url',e.source_url,'storage_path',e.storage_path,'content_hash',e.content_hash,'captured_at',e.captured_at,'valid_from',e.valid_from,'valid_to',e.valid_to)) from pipeline.evidence_artifacts e where e.id in (
        select evidence_id from catalogue.course_fees where course_id=v_id and evidence_id is not null
        union select evidence_id from catalogue.course_registrations where course_id=v_id and evidence_id is not null
        union select evidence_id from catalogue.course_regulatory_observations where course_id=v_id and evidence_id is not null
        union select evidence_id from catalogue.course_links where course_id=v_id and evidence_id is not null
        union select av.evidence_id from pim.attribute_values av join pim.entity_registry er on er.id=av.entity_id where er.entity_type='course' and er.stable_key=(select stable_key from catalogue.courses where id=v_id) and av.evidence_id is not null
      ) or e.entity_id=v_id),'[]'::jsonb)
    ) into v_result;
    return v_result;
  elsif p_operation='scholarships' then select coalesce(jsonb_agg(to_jsonb(x) order by x.provider_name,x.name),'[]'::jsonb) into v_result from public.ui_scholarships_list(v_limit) x; return v_result;
  elsif p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid; return coalesce(public.ui_scholarship_detail(v_id),'{}'::jsonb);
  elsif p_operation='evidence' then if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.captured_at desc),'[]'::jsonb) into v_result from public.ui_evidence_governance_list(v_limit) x; return v_result;
  elsif p_operation='reviews' then if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.priority desc,x.created_at desc),'[]'::jsonb) into v_result from public.ui_review_queue(v_limit) x; return v_result;
  elsif p_operation='attributes' then if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if; select jsonb_build_object('families',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attribute_families_list() x),'[]'::jsonb),'groups',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attribute_groups_list() x),'[]'::jsonb),'attributes',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attributes_list() x),'[]'::jsonb),'options',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_attribute_options_list(v_limit) x),'[]'::jsonb),'completeness_profiles',coalesce((select jsonb_agg(to_jsonb(x)) from public.ui_completeness_profiles_list() x),'[]'::jsonb)) into v_result; return v_result;
  elsif p_operation='jobs' then if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_result from public.ui_jobs_list(v_limit) x; return v_result;
  elsif p_operation='sources' then if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if; select coalesce(jsonb_agg(to_jsonb(x) order by x.country_code,x.source_label),'[]'::jsonb) into v_result from public.ui_regulatory_sources_list() x; return v_result;
  else raise exception 'unsupported admin read operation: %',p_operation using errcode='22023';
  end if;
end$function$
