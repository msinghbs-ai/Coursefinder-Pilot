CREATE OR REPLACE FUNCTION security.enrich_coverage_snapshot_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_at timestamptz := date_trunc('minute', now()); v int;
begin
  insert into pipeline.enrich_coverage_snapshots(at, country_code, field, courses, filled)
  select v_at, s.cc, f.field, count(*),
         count(*) filter (where case f.field when 'campus' then s.has_campus when 'duration' then s.duration_value is not null when 'level' then s.study_level_id is not null
                                           when 'delivery' then nullif(btrim(s.delivery_mode), '') is not null when 'field_of_study' then s.primary_field_id is not null
                                           when 'international' then s.open_to_international is not null else false end)
    from (select k.iso_alpha2::text cc, c.duration_value, c.study_level_id, c.delivery_mode, c.primary_field_id, c.open_to_international,
                 exists (select 1 from catalogue.course_campuses x where x.course_id = c.id) has_campus
            from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
           where c.lifecycle_status = 'active') s
   cross join (select e.field from security.enrich_fields_v1() e where e.level = 'course') f
   group by s.cc, f.field
  on conflict do nothing;
  get diagnostics v = row_count;
  insert into pipeline.enrich_coverage_snapshots(at, country_code, field, courses, filled)
  select v_at, k.iso_alpha2::text, 'provider_address', count(*), count(*) filter (where nullif(btrim(p.address_line1), '') is not null)
    from catalogue.providers p join ref.countries k on k.id = p.country_id
   where coalesce(p.lifecycle_status, 'active') = 'active' and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
   group by k.iso_alpha2
  on conflict do nothing;
  return v;
end $function$
