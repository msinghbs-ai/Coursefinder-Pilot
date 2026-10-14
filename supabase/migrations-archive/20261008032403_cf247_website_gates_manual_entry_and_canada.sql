insert into search.enrichment_source_gates (projection_code, domain_code, source_id, gate_status, approval_ref, approved_at)
select 'courses', d.domain_code, '1e36317a-36b8-409d-a68e-438c8fcee376'::uuid, 'approved', 'CF-CHG-20260915-247 Platform Admin 8 Oct 2026 - manual entry (platform operators) approved for the website projection', now()
from (values ('official_course_url'),('course_intake'),('course_english'),('provider_current_tuition')) d(domain_code)
where not exists (select 1 from search.enrichment_source_gates g where g.projection_code='courses' and g.domain_code=d.domain_code and g.source_id='1e36317a-36b8-409d-a68e-438c8fcee376'::uuid);

insert into search.projection_country_gates (projection_code, country_id, gate_status, approval_ref, approved_at)
select 'courses', c.id, 'approved', 'CF-CHG-20260915-247 Platform Admin 8 Oct 2026 - Canada opened for website search', now()
from ref.countries c
where c.iso_alpha2 = 'CA'
  and not exists (select 1 from search.projection_country_gates g where g.projection_code='courses' and g.country_id=c.id);
