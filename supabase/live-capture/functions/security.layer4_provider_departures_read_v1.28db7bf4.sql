CREATE OR REPLACE FUNCTION security.layer4_provider_departures_read_v1(p_status text DEFAULT 'needs_review'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'ref'
AS $function$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<4 then raise exception 'Pipeline Operator role required' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'created_at' desc) from (
    select jsonb_build_object(
      'id',d.id,'provider_id',d.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),'country_code',co.iso_alpha2,
      'provider_status',p.lifecycle_status,'courses_retired',d.courses_retired,'status',d.status,'note',d.note,'run_id',d.run_id,
      'created_at',d.created_at,'reviewed_at',d.reviewed_at,'successor_provider_id',d.successor_provider_id,
      'successor_name',(select coalesce(s.display_name,s.canonical_name) from catalogue.providers s where s.id=d.successor_provider_id),
      'suggested_successor',(select jsonb_build_object('provider_id',s.id,'name',coalesce(s.display_name,s.canonical_name),'courses',count(*))
          from pipeline.layer1_course_retirements r join catalogue.providers s on s.id=r.successor_provider_id
         where r.provider_id=d.provider_id and r.successor_provider_id is not null group by s.id, s.display_name, s.canonical_name order by count(*) desc limit 1),
      'registrations',(select coalesce(jsonb_agg(jsonb_build_object('scheme',pr.registration_scheme,'code',pr.registration_code,'status',pr.status)),'[]'::jsonb)
          from catalogue.provider_registrations pr where pr.provider_id=d.provider_id),
      'active_courses',(select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active')) x
    from pipeline.layer1_provider_departures d
    join catalogue.providers p on p.id=d.provider_id
    left join ref.countries co on co.id=p.country_id
    where p_status is null or p_status='all' or d.status=p_status) z),'[]'::jsonb);
end $function$
