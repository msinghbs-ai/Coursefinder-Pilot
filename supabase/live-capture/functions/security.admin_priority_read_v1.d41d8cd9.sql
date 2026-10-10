CREATE OR REPLACE FUNCTION security.admin_priority_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'ref', 'security'
AS $function$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return jsonb_build_object('can_control',security.current_role_rank()>=5,
    'pins',(select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'target_id',x.target_id,'sort',x.sort,'note',x.note,'at',x.created_at)||coalesce(security.priority_pin_label(x.kind,x.target_id),'{}'::jsonb) order by x.sort),'[]'::jsonb) from pipeline.priority_pins x),
    'ranking',(select coalesce(jsonb_agg(r order by (r->>'rank')::int),'[]'::jsonb) from (
       select jsonb_build_object('rank',pp.rank,'provider_id',pp.provider_id,'name',coalesce(pr.display_name,pr.canonical_name),'state',s.name,'country',k.iso_alpha2,
         'courses',pp.active_courses,'pinned_by',pp.pinned_by,
         'pages_matched',(select count(*) from pipeline.coverage_course_pages g where g.provider_id=pp.provider_id and g.read_status='read' and g.identity_basis is not null),
         'pages_waiting',(select count(*) from pipeline.coverage_course_pages g where g.provider_id=pp.provider_id and g.status in ('bound','ambiguous') and coalesce(g.read_status,'')<>'read' and g.read_attempts<3)) r
         from pipeline.provider_priority pp join catalogue.providers pr on pr.id=pp.provider_id left join ref.subdivisions s on s.id=pr.subdivision_id left join ref.countries k on k.id=pr.country_id
        where pp.rank<=60) y),
    'states',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'country',k.name) order by k.name,s.name),'[]'::jsonb)
                from ref.subdivisions s join ref.countries k on k.id=s.country_id where exists (select 1 from catalogue.providers pr where pr.subdivision_id=s.id)),
    'countries',(select coalesce(jsonb_agg(jsonb_build_object('id',k.id,'name',k.name) order by k.name),'[]'::jsonb)
                from ref.countries k where exists (select 1 from catalogue.providers pr where pr.country_id=k.id)),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='priority' order by created_at desc limit 12) e));
end $function$
