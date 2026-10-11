CREATE OR REPLACE FUNCTION public.ui_scholarship_detail(p_scholarship_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'scholarship', 'catalogue', 'pipeline', 'auth'
AS $function$
select case when s.id is null then null else jsonb_build_object(
'id',s.id,'stable_key',s.stable_key,'name',s.name,'provider_id',s.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),'type',s.scholarship_type,'audience',s.audience,'nationalities',s.nationalities,'award_value_is_maximum',s.award_value_is_maximum,'description',s.description,'award_value_text',s.award_value_text,'award_duration_basis',s.award_duration_basis,'lifecycle_status',s.lifecycle_status,'publication_status',s.publication_status,'confidence',s.confidence,'source_url',s.source_url,'source_id',s.source_id,'evidence_id',s.evidence_id,
'identifiers',coalesce((select jsonb_agg(to_jsonb(i) order by i.is_primary desc,i.scheme) from scholarship.identifiers i where i.scholarship_id=s.id),'[]'::jsonb),
'cycles',coalesce((select jsonb_agg(to_jsonb(cy) order by cy.academic_year desc nulls last,cy.cycle_code) from scholarship.offering_cycles cy where cy.scholarship_id=s.id),'[]'::jsonb),
'windows',coalesce((select jsonb_agg(to_jsonb(w) order by w.opens_at nulls last,w.label) from scholarship.application_windows w where w.scholarship_id=s.id),'[]'::jsonb),
'scopes',coalesce((select jsonb_agg(to_jsonb(sc) order by sc.scope_type) from scholarship.scopes sc where sc.scholarship_id=s.id),'[]'::jsonb),
'criterion_groups',coalesce((select jsonb_agg(to_jsonb(g) order by g.display_order,g.group_code) from scholarship.criterion_groups g where g.scholarship_id=s.id),'[]'::jsonb),
'criteria',coalesce((select jsonb_agg(to_jsonb(cr) order by cr.criterion_type) from scholarship.criteria cr where cr.scholarship_id=s.id),'[]'::jsonb),
'award_tiers',coalesce((select jsonb_agg(to_jsonb(a) order by a.display_order,a.label) from scholarship.award_tiers a where a.scholarship_id=s.id),'[]'::jsonb),
'coverage',coalesce((select jsonb_agg(to_jsonb(cv) order by cv.coverage_type) from scholarship.coverage cv where cv.scholarship_id=s.id),'[]'::jsonb),
'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'type',e.evidence_type,'source_url',e.source_url,'hash',e.content_hash,'captured_at',e.captured_at) order by e.captured_at desc) from pipeline.evidence_artifacts e where e.id=s.evidence_id or e.entity_id=s.id),'[]'::jsonb)
) end from scholarship.scholarships s left join catalogue.providers p on p.id=s.provider_id where s.id=p_scholarship_id and auth.uid() is not null and security.current_role_rank() >= 1;
$function$
