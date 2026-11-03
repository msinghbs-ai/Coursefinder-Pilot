create or replace function security.enrich_deadline_missing_v1(p_course uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from catalogue.course_intakes x where x.course_id = p_course and x.status = 'active')
     and not exists (select 1 from catalogue.course_intakes x where x.course_id = p_course and x.status = 'active' and x.application_deadline is not null)
$$;
