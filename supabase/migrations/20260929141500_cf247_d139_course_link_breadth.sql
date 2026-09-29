-- CF-247 Decision 139 check after the first batch: every course link in the pilot data is a provider-wide scope
-- (all of a provider's courses). That is right for a provider-wide scholarship, but not for one named for a
-- field or level ("Engineering ... Scholarship", "... Undergraduate Scholarship"): its course links would claim
-- eligibility on courses it does not cover. Such scholarships now need a course link narrower than the whole
-- provider; until then they are not publishable ('course link broader than the scholarship'), and the review
-- withdraws any already published.
create or replace function security.scholarship_publishability_v1()
returns table(scholarship_id uuid, publishable boolean, missing text[])
language sql stable security definer set search_path to 'pg_catalog','scholarship','pipeline' as $f$
  select s.id,
         cardinality(m.missing)=0,
         m.missing
    from scholarship.scholarships s
    cross join lateral (select array_remove(array[
        case when s.lifecycle_status<>'active' then 'not active' end,
        case when coalesce(s.source_url,'')='' or s.source_url ~* 'studyaustralia\.gov\.au' then 'no provider page' end,
        case when coalesce(s.audience,'') !~* 'international' then 'not for international students' end,
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
select security.scholarship_publication_review_v1();
