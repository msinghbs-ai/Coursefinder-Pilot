-- CF-247 (Decision 217, 2 Oct 2026): run the new NZ rules.
--  1. Every NZ page rejected as "not this course" is read again by reader v0.9.1 (title with the same level, labelled
--     NZQA number, NZD fees).
--  2. Every active NZ course with no candidate page and a provider recipe is queued for the course-page search, at the
--     title stage (NZ courses have no CRICOS code). Pages still rejected after step 1 are queued in a later step.
update pipeline.coverage_course_pages g
   set status = 'bound', next_read_at = now(), read_attempts = 0, leased_until = null
  from catalogue.providers p, ref.countries k
 where p.id = g.provider_id and k.id = p.country_id and k.iso_alpha2 = 'NZ' and g.status = 'mismatch';

insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
select c.id, c.provider_id, 'title', 'queued', now()
  from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'NZ'
 where c.lifecycle_status = 'active'
   and exists (select 1 from pipeline.course_link_recipes r where r.provider_id = c.provider_id and r.active)
   and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id)
on conflict (course_id) do nothing;
