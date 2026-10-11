CREATE OR REPLACE FUNCTION security.scholarship_publishability_for_v1(p_ids uuid[])
 RETURNS TABLE(scholarship_id uuid, publishable boolean, missing text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline'
AS $function$
  -- 11 Oct 2026: one set of publishing checks for all scholarships (p_ids null) or a few (a record screen); no register
  -- (Study Australia) exemptions; a scholarship with no linked course can be published
  select s.id,
         cardinality(m.missing)=0,
         m.missing
    from scholarship.scholarships s
    left join pipeline.scholarship_pages sp on sp.scholarship_id=s.id and sp.read_status='read'
    left join (select q.id, row_number() over (partition by q.provider_id, q.k order by q.placeholder, q.edition, q.past_year, q.ts desc, q.id::text) rn
                 from (select s0.id, s0.provider_id, security.scholarship_series_key_v1(s0.name) k,
                              0 placeholder,
                              (s0.name ~* '^\s*(\d{4}\s*[-:]|(semester|sem|trimester|term|intake)\s*\d)')::int edition,
                              (coalesce(substring(s0.name from '(20\d\d)')::int, 9999) < extract(year from now())::int)::int past_year,
                              s0.updated_at ts
                         from scholarship.scholarships s0 where s0.lifecycle_status='active'
                          and (p_ids is null or s0.provider_id in (select s1.provider_id from scholarship.scholarships s1 where s1.id = any(p_ids)))) q) ed on ed.id=s.id
    cross join lateral (select array_remove(array[
        case when s.lifecycle_status<>'active' then 'not active' end,
        case when coalesce(s.source_url,'')='' then 'no provider page' end,
        case when coalesce(s.audience,'') !~* 'international' then 'not for international students' end,
        case when sp.facts is not null and coalesce(sp.facts->>'eligibility_excerpt','') ~* '(australian citizen|permanent resident|domestic student|new zealand citizen|canadian citizen)'
                  and coalesce(sp.facts->>'eligibility_excerpt','') !~* 'international' then 'provider page limits it to citizens and residents' end,
        case when sp.facts is not null and sp.facts->>'international'='false' then 'provider page does not mention international students' end,
        case when not ((s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage,s.award_amount) is not null) or exists (select 1 from scholarship.award_tiers t where t.scholarship_id=s.id and t.tier_code like 'page_tier_%')) then 'no stated award value' end,
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
        -- 11 Oct 2026 (Platform Admin): a scholarship not linked to a course is valid and can be published
        case when exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped')
              and not exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped' and cm.mapping_basis<>'explicit_provider_scope')
              and s.name ~* '(engineer|undergrad|postgrad|research|ph\.?d|doctor|master|bachelor|honours|diploma|law|medic|nurs|business|commerce|science|arts|information tech|computing|education|design|music|health|pharm|faculty|school of|college of|mba)'
             then 'course link broader than the scholarship' end,
        -- v2.15.239 (S2): one scholarship, one record; the provider's own, evergreen, current edition is the one listed
        -- (v2.15.241: ranked once per scholarship, not compared pair by pair, so the check stays fast)
        case when ed.rn > 1 then 'another edition of this scholarship is listed' end,
        case when greatest(s.updated_at,(select e.captured_at from pipeline.evidence_artifacts e where e.id=s.evidence_id)) < now()-interval '12 months' then 'not verified in 12 months' end
      ], null) missing) m
   where p_ids is null or s.id = any(p_ids)
$function$
