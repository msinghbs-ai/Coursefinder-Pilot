CREATE OR REPLACE FUNCTION security.course_entry_eligible_v1()
 RETURNS TABLE(course_id uuid, provider_id uuid, prio bigint, title text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with scope as (select (e.v)::uuid pid, e.o from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.course_read_providers'), '[]'::jsonb)) with ordinality e(v, o))
  select c.id, c.provider_id, scope.o, c.canonical_title
    from catalogue.courses c
    join scope on scope.pid = c.provider_id
    join catalogue.providers p on p.id = c.provider_id
    join ref.countries k on k.id = p.country_id
    join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'
    join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
   where c.lifecycle_status = 'active'
     and coalesce(security.toolset_setting('pipeline', 'entry.course_read_countries'), '["AU"]'::jsonb) ? k.iso_alpha2
     and security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')
$function$
