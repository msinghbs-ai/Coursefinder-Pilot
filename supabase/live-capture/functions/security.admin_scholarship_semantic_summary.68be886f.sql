CREATE OR REPLACE FUNCTION security.admin_scholarship_semantic_summary(p_scholarship_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'scholarship', 'catalogue', 'ref', 'pipeline'
AS $function$
declare
  v_rank integer;
begin
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0) < 1 then
    raise exception 'assigned StudySearch role required' using errcode='42501';
  end if;

  return jsonb_build_object(
    'record_provenance', coalesce((
      select jsonb_build_object(
        'source', case when ps.id is null then null else jsonb_build_object(
          'id',ps.id,'label',ps.label,'type',ps.source_type,'url',ps.url
        ) end,
        'evidence', case when pe.id is null then null else jsonb_build_object(
          'id',pe.id,'type',pe.evidence_type,'source_url',pe.source_url,
          'captured_at',pe.captured_at,'content_hash',pe.content_hash,
          'valid_from',pe.valid_from,'valid_to',pe.valid_to
        ) end
      )
      from scholarship.scholarships s
      left join pipeline.sources ps on ps.id=s.source_id
      left join pipeline.evidence_artifacts pe on pe.id=s.evidence_id
      where s.id=p_scholarship_id
    ), '{}'::jsonb),
    'cycles', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',cy.id,
          'cycle_code',cy.cycle_code,
          'academic_year',cy.academic_year,
          'intake_label',cy.intake_label,
          'valid_from',cy.valid_from,
          'valid_to',cy.valid_to,
          'status',cy.status,
          'metadata',cy.metadata,
          'source',case when cys.id is null then null else jsonb_build_object('id',cys.id,'label',cys.label,'type',cys.source_type,'url',cys.url) end,
          'evidence',case when cye.id is null then null else jsonb_build_object('id',cye.id,'type',cye.evidence_type,'source_url',cye.source_url,'captured_at',cye.captured_at,'content_hash',cye.content_hash) end,
          'application_windows',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',w.id,'round_code',w.round_code,'label',w.label,'opens_at',w.opens_at,'closes_at',w.closes_at,
              'application_method',w.application_method,'application_url',w.application_url,'status',w.status,'metadata',w.metadata,
              'source',case when ws.id is null then null else jsonb_build_object('id',ws.id,'label',ws.label,'type',ws.source_type,'url',ws.url) end,
              'evidence',case when we.id is null then null else jsonb_build_object('id',we.id,'type',we.evidence_type,'source_url',we.source_url,'captured_at',we.captured_at,'content_hash',we.content_hash) end
            ) order by w.opens_at nulls last,w.closes_at nulls last,w.label)
            from scholarship.application_windows w
            left join pipeline.sources ws on ws.id=w.source_id
            left join pipeline.evidence_artifacts we on we.id=w.evidence_id
            where w.scholarship_id=p_scholarship_id and w.cycle_id=cy.id
          ),'[]'::jsonb),
          'scopes',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',sc.id,'scope_type',sc.scope_type,'include_exclude',sc.include_exclude,
              'target',jsonb_strip_nulls(jsonb_build_object(
                'provider',case when p.id is null then null else jsonb_build_object('id',p.id,'stable_key',p.stable_key,'name',p.canonical_name) end,
                'course',case when c.id is null then null else jsonb_build_object('id',c.id,'stable_key',c.stable_key,'name',c.canonical_title) end,
                'course_collection',case when cc.id is null then null else jsonb_build_object('id',cc.id,'stable_key',cc.stable_key,'code',cc.code,'name',cc.name) end,
                'study_level',case when sl.id is null then null else jsonb_build_object('id',sl.id,'code',sl.code,'name',sl.name) end,
                'field',case when f.id is null then null else jsonb_build_object('id',f.id,'code',f.code,'name',f.name) end,
                'country',case when co.id is null then null else jsonb_build_object('id',co.id,'code',co.iso_alpha2,'name',co.name) end,
                'campus',case when ca.id is null then null else jsonb_build_object('id',ca.id,'stable_key',ca.stable_key,'name',ca.name) end
              )),
              'source',case when ss.id is null then null else jsonb_build_object('id',ss.id,'label',ss.label,'type',ss.source_type,'url',ss.url) end,
              'evidence',case when se.id is null then null else jsonb_build_object('id',se.id,'type',se.evidence_type,'source_url',se.source_url,'captured_at',se.captured_at,'content_hash',se.content_hash) end
            ) order by sc.scope_type,sc.include_exclude)
            from scholarship.scopes sc
            left join catalogue.providers p on p.id=sc.provider_id
            left join catalogue.courses c on c.id=sc.course_id
            left join catalogue.course_collections cc on cc.id=sc.course_collection_id
            left join ref.study_levels sl on sl.id=sc.study_level_id
            left join ref.fields_of_study f on f.id=sc.field_id
            left join ref.countries co on co.id=sc.country_id
            left join catalogue.campuses ca on ca.id=sc.campus_id
            left join pipeline.sources ss on ss.id=sc.source_id
            left join pipeline.evidence_artifacts se on se.id=sc.evidence_id
            where sc.scholarship_id=p_scholarship_id and sc.cycle_id=cy.id
          ),'[]'::jsonb),
          'eligibility_groups',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',g.id,'group_code',g.group_code,'label',g.label,'parent_group_id',g.parent_group_id,
              'conjunction',g.conjunction,'is_mandatory',g.is_mandatory,'display_order',g.display_order,
              'source',case when gs.id is null then null else jsonb_build_object('id',gs.id,'label',gs.label,'type',gs.source_type,'url',gs.url) end,
              'evidence',case when ge.id is null then null else jsonb_build_object('id',ge.id,'type',ge.evidence_type,'source_url',ge.source_url,'captured_at',ge.captured_at,'content_hash',ge.content_hash) end,
              'criteria',coalesce((
                select jsonb_agg(jsonb_build_object(
                  'id',cr.id,'criterion_type',cr.criterion_type,'operator',cr.operator,'value_text',cr.value_text,
                  'value_number',cr.value_number,'value_codes',cr.value_codes,'value_json',cr.value_json,'human_text',cr.human_text,
                  'is_mandatory',cr.is_mandatory,'machine_evaluable',cr.machine_evaluable,'status',cr.status,'confidence',cr.confidence,
                  'source',case when crs.id is null then null else jsonb_build_object('id',crs.id,'label',crs.label,'type',crs.source_type,'url',crs.url) end,
                  'evidence',case when cre.id is null then null else jsonb_build_object('id',cre.id,'type',cre.evidence_type,'source_url',cre.source_url,'captured_at',cre.captured_at,'content_hash',cre.content_hash) end
                ) order by cr.criterion_type,cr.id)
                from scholarship.criteria cr
                left join pipeline.sources crs on crs.id=cr.source_id
                left join pipeline.evidence_artifacts cre on cre.id=cr.evidence_id
                where cr.scholarship_id=p_scholarship_id and cr.criterion_group_id=g.id
              ),'[]'::jsonb)
            ) order by g.display_order,g.group_code)
            from scholarship.criterion_groups g
            left join pipeline.sources gs on gs.id=g.source_id
            left join pipeline.evidence_artifacts ge on ge.id=g.evidence_id
            where g.scholarship_id=p_scholarship_id and g.cycle_id=cy.id
          ),'[]'::jsonb),
          'award_tiers',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',a.id,'tier_code',a.tier_code,'label',a.label,'amount',a.amount,'currency_code',a.currency_code,
              'percentage',a.percentage,'basis',a.basis,'maximum_amount',a.maximum_amount,'notes',a.notes,'display_order',a.display_order,
              'source',case when axs.id is null then null else jsonb_build_object('id',axs.id,'label',axs.label,'type',axs.source_type,'url',axs.url) end,
              'evidence',case when axe.id is null then null else jsonb_build_object('id',axe.id,'type',axe.evidence_type,'source_url',axe.source_url,'captured_at',axe.captured_at,'content_hash',axe.content_hash) end
            ) order by a.display_order,a.label)
            from scholarship.award_tiers a
            left join pipeline.sources axs on axs.id=a.source_id
            left join pipeline.evidence_artifacts axe on axe.id=a.evidence_id
            where a.scholarship_id=p_scholarship_id and a.cycle_id=cy.id
          ),'[]'::jsonb),
          'coverage',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',cv.id,'coverage_type',cv.coverage_type,'percentage',cv.percentage,'amount',cv.amount,'currency_code',cv.currency_code,
              'duration_value',cv.duration_value,'duration_unit',cv.duration_unit,'notes',cv.notes,
              'source',case when cvs.id is null then null else jsonb_build_object('id',cvs.id,'label',cvs.label,'type',cvs.source_type,'url',cvs.url) end,
              'evidence',case when cve.id is null then null else jsonb_build_object('id',cve.id,'type',cve.evidence_type,'source_url',cve.source_url,'captured_at',cve.captured_at,'content_hash',cve.content_hash) end
            ) order by cv.coverage_type)
            from scholarship.coverage cv
            left join pipeline.sources cvs on cvs.id=cv.source_id
            left join pipeline.evidence_artifacts cve on cve.id=cv.evidence_id
            where cv.scholarship_id=p_scholarship_id and cv.cycle_id=cy.id
          ),'[]'::jsonb)
        ) order by cy.academic_year desc nulls last,cy.cycle_code
      )
      from scholarship.offering_cycles cy
      left join pipeline.sources cys on cys.id=cy.source_id
      left join pipeline.evidence_artifacts cye on cye.id=cy.evidence_id
      where cy.scholarship_id=p_scholarship_id
    ),'[]'::jsonb),
    'unscoped', jsonb_build_object(
      'application_windows',coalesce((select jsonb_agg(to_jsonb(w) order by w.opens_at nulls last,w.label) from scholarship.application_windows w where w.scholarship_id=p_scholarship_id and w.cycle_id is null),'[]'::jsonb),
      'scopes',coalesce((select jsonb_agg(to_jsonb(sc) order by sc.scope_type) from scholarship.scopes sc where sc.scholarship_id=p_scholarship_id and sc.cycle_id is null),'[]'::jsonb),
      'eligibility_groups',coalesce((select jsonb_agg(to_jsonb(g) order by g.display_order,g.group_code) from scholarship.criterion_groups g where g.scholarship_id=p_scholarship_id and g.cycle_id is null),'[]'::jsonb),
      'criteria',coalesce((select jsonb_agg(to_jsonb(cr) order by cr.criterion_type) from scholarship.criteria cr where cr.scholarship_id=p_scholarship_id and cr.cycle_id is null),'[]'::jsonb),
      'award_tiers',coalesce((select jsonb_agg(to_jsonb(a) order by a.display_order,a.label) from scholarship.award_tiers a where a.scholarship_id=p_scholarship_id and a.cycle_id is null),'[]'::jsonb),
      'coverage',coalesce((select jsonb_agg(to_jsonb(cv) order by cv.coverage_type) from scholarship.coverage cv where cv.scholarship_id=p_scholarship_id and cv.cycle_id is null),'[]'::jsonb)
    )
  );
end;
$function$
