-- CF-CHG-20260830-048
-- M2.4.4: add headroom for the common unfiltered Campus browse.
-- Complex filters/sorts remain on security.admin_catalogue_page.

create index if not exists campuses_lower_name_id_idx
  on catalogue.campuses ((lower(name)), id);

create or replace function security.admin_campus_page_fast(
  p_args jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','catalogue','ref','public','auth'
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_sort text:=lower(coalesce(nullif(p_args->>'sort',''),'name'));
  v_dir text:=lower(coalesce(nullif(p_args->>'direction',''),'asc'));
  v_simple boolean;
  v_total bigint:=0;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode='42501';
  end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then
    raise exception 'assigned CourseFinder role required' using errcode='42501';
  end if;

  v_simple :=
    nullif(trim(coalesce(p_args->>'query','')),'') is null
    and nullif(p_args->>'country_code','') is null
    and nullif(p_args->>'subdivision_code','') is null
    and nullif(p_args->>'provider_id','') is null
    and nullif(p_args->>'status','') is null
    and nullif(p_args->>'publication_status','') is null
    and v_sort in ('name','campus')
    and v_dir='asc';

  if not v_simple then
    return security.admin_catalogue_page('campuses_page',p_args);
  end if;

  select count(*) into v_total from catalogue.campuses;

  with paged as (
    select
      ca.id,ca.stable_key,ca.name,ca.campus_code,ca.provider_id,
      ca.subdivision_id,ca.city,ca.status,ca.publication_status,
      ca.last_verified_at,ca.created_at,ca.updated_at
    from catalogue.campuses ca
    order by lower(ca.name),ca.id
    limit v_limit offset v_offset
  ), enriched as (
    select
      pg.id,pg.stable_key,pg.name,pg.campus_code,pg.provider_id,
      coalesce(p.display_name,p.canonical_name) provider_name,
      co.iso_alpha2::text country_code,co.name country_name,
      sd.code subdivision_code,sd.name subdivision_name,
      pg.city,pg.status,pg.publication_status,pg.last_verified_at,pg.created_at,pg.updated_at,
      coalesce(cc.course_count,0)::int course_count
    from paged pg
    join catalogue.providers p on p.id=pg.provider_id
    join ref.countries co on co.id=p.country_id
    left join ref.subdivisions sd on sd.id=pg.subdivision_id
    left join lateral (
      select count(*)::int course_count
      from catalogue.course_campuses cc
      where cc.campus_id=pg.id
    ) cc on true
  )
  select jsonb_build_object(
    'items',coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb),
    'total',v_total,
    'limit',v_limit,
    'offset',v_offset,
    'sort','name',
    'direction','asc',
    'execution_profile','page_first_unfiltered_v1'
  )
  into v_result
  from enriched e;

  return v_result;
end $$;

revoke all on function security.admin_campus_page_fast(jsonb) from public,anon;
grant execute on function security.admin_campus_page_fast(jsonb) to authenticated,service_role;

do $$
declare v_oid oid; v_def text;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='admin_read'
    and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb'
  limit 1;

  if v_oid is null then raise exception 'public.admin_read not found'; end if;

  select pg_get_functiondef(v_oid) into v_def;

  if position('security.admin_campus_page_fast(p_args)' in v_def)=0 then
    v_def:=replace(
      v_def,
      'if p_operation in (''providers_page'',''campuses_page'',''scholarships_page'') then return security.admin_catalogue_page(p_operation,p_args); end if;',
      'if p_operation=''campuses_page'' then return security.admin_campus_page_fast(p_args); end if;
 if p_operation in (''providers_page'',''scholarships_page'') then return security.admin_catalogue_page(p_operation,p_args); end if;'
    );
    execute v_def;
  end if;
end $$;
