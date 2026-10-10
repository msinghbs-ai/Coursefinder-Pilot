CREATE OR REPLACE FUNCTION security.admin_source_comparison_read_v1(p_entity_type text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'scholarship', 'security', 'auth'
AS $function$
declare
  v_provider jsonb; v_gov jsonb; v_current jsonb; v_weeks numeric; v_reg jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  if p_entity_type = 'scholarship' then
    if not exists (select 1 from scholarship.scholarships where id = p_id) then return null; end if;

    select jsonb_build_object(
             'url', coalesce(sp.final_url, sp.url), 'read_at', sp.read_at, 'read_status', sp.read_status,
             'url_source', sp.url_source, 'evidence_id', sp.evidence_id, 'heading', sp.facts->>'h1',
             'value', sp.facts->'value', 'deadline', sp.facts->'deadline', 'levels', sp.facts->'levels',
             'international', sp.facts->'international')
      into v_provider
      from pipeline.scholarship_pages sp
     where sp.scholarship_id = p_id
     order by (sp.facts is not null) desc, sp.read_at desc nulls last
     limit 1;
    if v_provider is null then
      select jsonb_build_object('url', i.identifier_value, 'evidence_id', i.evidence_id)
        into v_provider from scholarship.identifiers i
       where i.scholarship_id = p_id and i.scheme = 'first_party_detail_url' and coalesce(i.status,'active') = 'active'
       order by i.is_primary desc, i.created_at desc limit 1;
    end if;

    with urls as (
      select s.source_url u from scholarship.scholarships s where s.id = p_id and security.reference_url_has_use(s.source_url, 'scholarship_placeholder')
      union select c.before_value->>'source_url' from pipeline.scholarship_sweep_changes c
        where c.scholarship_id = p_id and security.reference_url_has_use(c.before_value->>'source_url', 'scholarship_placeholder')
    ), ids as (
      select i.identifier_value v from scholarship.identifiers i where i.scholarship_id = p_id and i.scheme = 'study_australia_scholarship_id'
    ), rec as (
      select r.* from pipeline.scholarship_source_records r
       where r.source_record_id in (select v from ids) or r.source_record_url in (select u from urls)
       order by r.observed_at desc nulls last limit 1
    )
    select jsonb_build_object(
             'url', coalesce(rec.source_record_url, (select u from urls limit 1)),
             'observed_at', rec.observed_at, 'evidence_id', rec.evidence_id,
             'value_text', rec.payload->>'award_value_text',
             'amount', rec.payload->'cycles'->0->'award_tiers'->0->'amount',
             'currency', rec.payload->'cycles'->0->'award_tiers'->0->>'currency_code',
             'closing_date', coalesce(rec.payload->>'application_close_date', rec.payload->>'close_date', rec.payload->'cycles'->0->'windows'->0->>'closes_at'),
             'closing_text', coalesce(rec.payload->>'application_close_text', rec.payload->'cycles'->0->'metadata'->>'source_closing_text'),
             'levels_text', coalesce(rec.payload->>'level_of_study_text', rec.payload->'cycles'->0->'metadata'->>'source_level_of_study'),
             'study_levels', rec.payload->'study_levels')
      into v_gov
      from (select 1) one left join rec on true
     where rec.id is not null or exists (select 1 from urls);

    select jsonb_build_object('value_text', s.award_value_text, 'source_url', s.source_url,
             'closing_date', (select min(w.closes_at) from scholarship.application_windows w where w.scholarship_id = s.id))
      into v_current from scholarship.scholarships s where s.id = p_id;

    return jsonb_build_object('entity_type','scholarship','id',p_id,
      'provider', v_provider, 'government', v_gov, 'current', v_current);
  end if;

  if p_entity_type = 'course' then
    if not exists (select 1 from catalogue.courses where id = p_id) then return null; end if;
    select case when c.duration_unit = 'weeks' then c.duration_value end into v_weeks from catalogue.courses c where c.id = p_id;

    select jsonb_build_object(
             'cricos_code', (select o.registration_code from catalogue.course_regulatory_observations o
                               where o.course_id = p_id and o.scheme = 'cricos' order by (o.valid_to is null) desc, o.observed_at desc nulls last limit 1),
             'tuition', (select jsonb_build_object('amount', f.amount, 'currency', f.currency_code, 'basis', f.basis, 'fee_year', f.fee_year,
                                   'evidence_id', f.evidence_id, 'verified_at', f.last_verified_at,
                                   'per_year_estimate', case when v_weeks > 0 and f.basis = 'registered_total_course' then round(f.amount / (v_weeks / 52.0)) end)
                           from catalogue.course_fees f
                          where f.course_id = p_id and f.fee_type = 'tuition' and coalesce(f.status,'active') = 'active'
                          order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1),
             'duration', (select jsonb_build_object('value', c.duration_value, 'unit', c.duration_unit) from catalogue.courses c where c.id = p_id and c.duration_value is not null),
             'campuses', (select coalesce(jsonb_agg(distinct cp.name order by cp.name), '[]'::jsonb)
                            from catalogue.course_campuses cc join catalogue.campuses cp on cp.id = cc.campus_id where cc.course_id = p_id))
      into v_reg;

    select jsonb_build_object(
             'url', coalesce((select g.url from pipeline.coverage_course_pages g where g.course_id = p_id and g.status = 'bound' limit 1),
                             (select l.url from catalogue.course_links l where l.course_id = p_id and l.link_type = 'official_course' and coalesce(l.status,'active') = 'active'
                               order by (l.audience = 'international') desc, l.last_verified_at desc nulls last limit 1)),
             'read_at', (select g.read_at from pipeline.coverage_course_pages g where g.course_id = p_id and g.status = 'bound' limit 1),
             'tuition', (select jsonb_build_object('amount', f.amount, 'currency', f.currency_code, 'basis', f.basis, 'fee_year', f.fee_year,
                                   'evidence_id', f.evidence_id, 'verified_at', f.last_verified_at, 'source_type', s.source_type)
                           from catalogue.course_fees f left join pipeline.sources s on s.id = f.source_id
                          where f.course_id = p_id and f.fee_type = 'provider_current_tuition' and coalesce(f.status,'active') = 'active'
                          order by f.fee_year desc nulls last, f.updated_at desc nulls last limit 1),
             'duration', null, 'campuses', null)
      into v_provider;

    return jsonb_build_object('entity_type','course','id',p_id,'provider', v_provider, 'regulator', v_reg);
  end if;

  raise exception 'unsupported entity type %', p_entity_type using errcode='22023';
end
$function$
