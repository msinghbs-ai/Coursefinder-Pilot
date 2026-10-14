CREATE OR REPLACE FUNCTION public.svc_central_find_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.provider_id from pipeline.provider_central_search s join catalogue.providers p on p.id = s.provider_id
     where (s.state = 'queued' or (s.state = 'leased' and s.leased_until < now())) and s.attempts < 3
       and p.lifecycle_status = 'active' and p.website ~* '^https?://' and not security.third_party_host_v1(p.website)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)
     order by (s.requested_at is null), s.requested_at, (select count(*) from catalogue.courses c where c.provider_id = s.provider_id and c.lifecycle_status = 'active') desc
     limit greatest(1, least(coalesce(p_limit, 4), 10)) for update of s skip locked),
  upd as (update pipeline.provider_central_search s set state = 'leased', leased_until = now() + interval '10 minutes', attempts = s.attempts + 1, updated_at = now()
            from pick where s.provider_id = pick.provider_id returning s.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', u.provider_id, 'name', coalesce(p.display_name, p.canonical_name), 'website', p.website)), '[]'::jsonb)
    into v from upd u join catalogue.providers p on p.id = u.provider_id;
  return v;
end $function$
