insert into scholarship.course_mapping_candidates (scholarship_id, course_id, candidate_reason, evidence_id)
select s.id, c.id, 'provider_owned_but_no_explicit_course_or_provider_scope', s.evidence_id
  from scholarship.scholarships s
  join catalogue.providers p on p.id = s.provider_id
  join ref.countries k on k.id = p.country_id and k.iso_alpha2 in ('CA', 'NZ')
  join catalogue.courses c on c.provider_id = s.provider_id and c.lifecycle_status = 'active'
 where s.lifecycle_status = 'active'
   and not exists (select 1 from scholarship.scopes sc where sc.scholarship_id = s.id)
on conflict (scholarship_id, course_id) do nothing;
