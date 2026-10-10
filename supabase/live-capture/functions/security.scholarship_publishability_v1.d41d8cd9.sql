CREATE OR REPLACE FUNCTION security.scholarship_publishability_v1()
 RETURNS TABLE(scholarship_id uuid, publishable boolean, missing text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline'
AS $function$
  select s.id,
         cardinality(m.missing)=0,
         m.missing
    from scholarship.scholarships s
    left join pipeline.scholarship_pages sp on sp.scholarship_id=s.id and sp.read_status='read'
    cross join lateral (select array_remove(array[
        case when s.lifecycle_status<>'active' then 'not active' end,
        case when coalesce(s.source_url,'')='' or security.reference_url_has_use(s.source_url, 'scholarship_placeholder') then 'no provider page' end,
        case when coalesce(s.audience,'') !~* 'international' then 'not for international students' end,
        case when sp.facts is not null and not security.scholarship_from_record_register(s.id) and coalesce(sp.facts->>'eligibility_excerpt','') ~* '(australian citizen|permanent resident|domestic student|new zealand citizen|canadian citizen)'
                  and coalesce(sp.facts->>'eligibility_excerpt','') !~* 'international' then 'provider page limits it to citizens and residents' end,
        case when sp.facts is not null and sp.facts->>'international'='false' and not security.scholarship_from_record_register(s.id) then 'provider page does not mention international students' end,
        case when not ((s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage,s.award_amount) is not null) or exists (select 1 from scholarship.award_tiers t where t.scholarship_id=s.id and t.tier_code like 'page_tier_%') or (security.scholarship_from_record_register(s.id) and exists (select 1 from scholarship.coverage cv where cv.scholarship_id=s.id and cv.coverage_type='tuition_fees' and cv.percentage=100))) then 'no stated award value' end,
        case when exists (select 1 from scholarship.criteria cr where cr.scholarship_id=s.id and cr.status='active' and cr.criterion_type='student_type'
                                and cr.value_json->>'by'='scholarship_sweep' and cr.value_codes='{domestic}')
              and not exists (select 1 from scholarship.criteria cr where cr.scholarship_id=s.id and cr.status='active' and cr.criterion_type='student_type'
                                and coalesce(cr.value_json->>'by','')<>'scholarship_sweep' and 'international'=any(cr.value_codes))
             then 'eligibility lists domestic students only' end,
        case when s.evidence_id is null then 'no evidence' end,
        case when exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id=s.id and h.released_at is null) then 'held after hand-check' end,
        case when sp.facts is not null and coalesce((sp.facts->>'not_offered')::boolean,false) then 'not currently offered (provider page)' end,
        case when sp.facts ? 'english_course' and exists (select 1 from scholarship.course_mappings cm join catalogue.courses c on c.id=cm.course_id
                   left join ref.study_levels sl on sl.id=c.study_level_id where cm.scholarship_id=s.id and cm.mapping_state='mapped' and coalesce(sl.code,'')<>'non_aqf_award')
             then 'English language course linked to other courses' end,
        case when not exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped') then 'no linked course' end,
        case when exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped')
              and not exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped' and cm.mapping_basis<>'explicit_provider_scope')
              and s.name ~* '(engineer|undergrad|postgrad|research|ph\.?d|doctor|master|bachelor|honours|diploma|law|medic|nurs|business|commerce|science|arts|information tech|computing|education|design|music|health|pharm|faculty|school of|college of|mba)'
             then 'course link broader than the scholarship' end,
        -- v2.15.239 (S2): one scholarship, one record; the provider's own, evergreen, most recently updated edition is the one listed
        case when exists (select 1 from scholarship.scholarships o where o.provider_id=s.provider_id and o.id<>s.id and o.lifecycle_status='active'
                    and security.scholarship_series_key_v1(o.name)=security.scholarship_series_key_v1(s.name)
                    and (security.reference_url_has_use(coalesce(o.source_url,''),'scholarship_placeholder')::int, (security.scholarship_series_key_v1(o.name)<>lower(btrim(o.name)))::int, -extract(epoch from o.updated_at), o.id::text)
                      < (security.reference_url_has_use(coalesce(s.source_url,''),'scholarship_placeholder')::int, (security.scholarship_series_key_v1(s.name)<>lower(btrim(s.name)))::int, -extract(epoch from s.updated_at), s.id::text))
             then 'another edition of this scholarship is listed' end,
        case when greatest(s.updated_at,(select e.captured_at from pipeline.evidence_artifacts e where e.id=s.evidence_id)) < now()-interval '12 months' then 'not verified in 12 months' end
      ], null) missing) m
$function$
