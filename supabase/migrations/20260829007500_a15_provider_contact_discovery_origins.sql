-- A15: include already-governed first-party Provider hosts in contact discovery.
create or replace function public.provider_contact_profiles_service(
  p_provider_id uuid default null,
  p_limit integer default 2
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline','catalogue','ref'
as $$
declare v jsonb;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  with base as (
    select
      pcp.*,
      p.canonical_name provider_name,
      (
        select coalesce(jsonb_agg(x.origin order by x.origin),'[]'::jsonb)
        from (
          select distinct
            case
              when s.url ~* '^https?://'
              then regexp_replace(s.url,'^(https?://[^/]+).*$','\1','i')
              else null
            end origin
          from pipeline.sources s
          where s.provider_id=pcp.provider_id
            and s.url is not null
            and s.status='active'
        ) x
        where x.origin is not null
      ) governed_origins
    from pipeline.provider_contact_profiles pcp
    join catalogue.providers p on p.id=pcp.provider_id
    where pcp.enabled=true and pcp.paused=false
      and (p_provider_id is null or pcp.provider_id=p_provider_id)
    order by pcp.last_run_at nulls first, lower(p.canonical_name)
    limit greatest(1,least(coalesce(p_limit,2),5))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'provider_id',provider_id,'country_id',country_id,
    'base_url',base_url,'domain',domain,'enabled',enabled,'paused',paused,
    'title_terms',title_terms,'last_run_at',last_run_at,'last_success_at',last_success_at,
    'provider_name',provider_name,
    'governed_origins',
      case
        when governed_origins @> jsonb_build_array(regexp_replace(base_url,'^(https?://[^/]+).*$','\1','i'))
        then governed_origins
        else governed_origins || jsonb_build_array(regexp_replace(base_url,'^(https?://[^/]+).*$','\1','i'))
      end
  )),'[]'::jsonb) into v
  from base;

  return v;
end $$;

revoke all on function public.provider_contact_profiles_service(uuid,integer) from public,anon,authenticated;
grant execute on function public.provider_contact_profiles_service(uuid,integer) to service_role,postgres;
