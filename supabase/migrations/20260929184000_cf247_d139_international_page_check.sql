-- CF-247 Decision 139 / 167 hand-check (29 Sep 2026): every record carries audience 'international' from its original
-- source, but some provider pages limit the scholarship to Australian/New Zealand citizens and residents (e.g. Monash
-- "Arts Equity Travel Grant") or never mention international students. When the provider page has been read, the page
-- decides: not publishable if it limits eligibility to citizens/residents without mentioning international students,
-- or if it does not mention international students at all.
create or replace function security.scholarship_publishability_v1()
returns table(scholarship_id uuid, publishable boolean, missing text[])
language sql stable security definer set search_path to 'pg_catalog','scholarship','pipeline' as $f$
  select s.id,
         cardinality(m.missing)=0,
         m.missing
    from scholarship.scholarships s
    left join pipeline.scholarship_pages sp on sp.scholarship_id=s.id and sp.read_status='read'
    cross join lateral (select array_remove(array[
        case when s.lifecycle_status<>'active' then 'not active' end,
        case when coalesce(s.source_url,'')='' or s.source_url ~* 'studyaustralia\.gov\.au' then 'no provider page' end,
        case when coalesce(s.audience,'') !~* 'international' then 'not for international students' end,
        case when sp.facts is not null and coalesce(sp.facts->>'eligibility_excerpt','') ~* '(australian citizen|permanent resident|domestic student|new zealand citizen)'
                  and coalesce(sp.facts->>'eligibility_excerpt','') !~* 'international' then 'provider page limits it to citizens and residents' end,
        case when sp.facts is not null and sp.facts->>'international'='false' then 'provider page does not mention international students' end,
        case when not (s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage,s.award_amount) is not null) then 'no stated award value' end,
        case when s.evidence_id is null then 'no evidence' end,
        case when not exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped') then 'no linked course' end,
        case when exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped')
              and not exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped' and cm.mapping_basis<>'explicit_provider_scope')
              and s.name ~* '(engineer|undergrad|postgrad|research|ph\.?d|doctor|master|bachelor|honours|diploma|law|medic|nurs|business|commerce|science|arts|information tech|computing|education|design|music|health|pharm|faculty|school of|college of|mba)'
             then 'course link broader than the scholarship' end,
        case when greatest(s.updated_at,(select e.captured_at from pipeline.evidence_artifacts e where e.id=s.evidence_id)) < now()-interval '12 months' then 'not verified in 12 months' end
      ], null) missing) m
$f$;

-- Applied live 29 Sep 2026; then the first sweep batch was published by hand after a dry run and sample check:
--   select security.scholarship_publish_batch_v1('CF-CHG-20260915-247; Decision 139; Platform Admin approval 29 Sep 2026 09:56 IST (publish and sweep)', true);
--   -> 54 published (27 at Group of Eight universities).
