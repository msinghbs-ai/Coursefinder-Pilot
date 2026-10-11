CREATE OR REPLACE FUNCTION public.svc_scholarship_read_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.scholarship_id from pipeline.scholarship_pages p join scholarship.scholarships s on s.id=p.scholarship_id and s.lifecycle_status='active'
     where p.next_read_at<=now() and coalesce(p.leased_until,'-infinity')<now() and p.attempts<5
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by p.read_at nulls first limit greatest(1,least(coalesce(p_limit,20),40)) for update of p skip locked),
  upd as (update pipeline.scholarship_pages p set leased_until=now()+interval '10 minutes', attempts=p.attempts+1 from pick where p.scholarship_id=pick.scholarship_id
          returning p.scholarship_id, p.url, p.url_source)
  select coalesce(jsonb_agg(jsonb_build_object('scholarship_id',u.scholarship_id,'url',u.url,'name',s.name,'provider_id',s.provider_id,'currency',scholarship.provider_currency(s.provider_id),'url_source',u.url_source,'names',security.provider_name_list(s.provider_id))),'[]'::jsonb) into v
    from upd u join scholarship.scholarships s on s.id=u.scholarship_id;
  return v;
end $function$
