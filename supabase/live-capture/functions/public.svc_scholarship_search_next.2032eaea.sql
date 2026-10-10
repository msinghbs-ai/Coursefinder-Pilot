CREATE OR REPLACE FUNCTION public.svc_scholarship_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'scholarship', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.id, s.name, s.provider_id, coalesce(d.site_origin,d.website) site, d.allowed_hosts from scholarship.scholarships s
      join pipeline.scholarship_discovery_providers d on d.provider_id=s.provider_id and d.status in ('mapped','empty','failed')
     where s.lifecycle_status='active' and security.reference_url_has_use(s.source_url, 'scholarship_placeholder')
       and not exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id=s.id and not (sp.url_source='discovered' and sp.read_status in ('name_mismatch','robots_disallowed','gone')))
       and not exists (select 1 from pipeline.scholarship_page_searches q where q.scholarship_id=s.id)
     order by d.priority, s.provider_id, s.name limit greatest(1,least(coalesce(p_limit,5),20))),
  ins as (insert into pipeline.scholarship_page_searches(scholarship_id,status) select id,'leased' from pick on conflict do nothing returning scholarship_id)
  select coalesce(jsonb_agg(jsonb_build_object('scholarship_id',p.id,'name',p.name,'provider_id',p.provider_id,'site',p.site,'hosts',to_jsonb(p.allowed_hosts),'names',security.provider_name_list(p.provider_id))),'[]'::jsonb)
    into v from pick p join ins on ins.scholarship_id=p.id;
  return v;
end $function$
