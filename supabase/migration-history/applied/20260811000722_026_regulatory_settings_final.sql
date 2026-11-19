alter table pipeline.sources add column if not exists last_checked_at timestamptz;
alter table pipeline.sources add column if not exists last_success_at timestamptz;
alter table pipeline.sources add column if not exists last_failure_at timestamptz;
alter table pipeline.sources add column if not exists last_error text;
alter table pipeline.sources add column if not exists metadata jsonb not null default '{}'::jsonb;

drop function if exists public.ui_regulatory_sources_list();
create function public.ui_regulatory_sources_list()
returns table(
  country_id uuid,
  country_code text,
  country_name text,
  catalogue_status text,
  provider_ingestion_enabled boolean,
  course_ingestion_enabled boolean,
  source_id uuid,
  source_type text,
  source_label text,
  source_url text,
  trust_rank smallint,
  source_status text,
  last_checked_at timestamptz,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_error text,
  source_metadata jsonb,
  system_code text,
  system_name text,
  system_type text,
  system_base_url text,
  system_status text,
  system_config jsonb
)
language plpgsql
stable
security definer
set search_path = public, ref, pipeline, integration, security
as $$
declare
  v_rank integer;
begin
  select max(r.rank)
    into v_rank
  from security.user_roles ur
  join security.roles r on r.code = ur.role_code
  where ur.user_id = auth.uid()
    and (ur.expires_at is null or ur.expires_at > now());

  if coalesce(v_rank, 0) < 6 then
    raise exception 'platform_admin role required' using errcode = '42501';
  end if;

  return query
  select
    c.id,
    c.iso_alpha2::text,
    c.name,
    c.catalogue_status,
    c.provider_ingestion_enabled,
    c.course_ingestion_enabled,
    s.id,
    s.source_type,
    s.label,
    s.url,
    s.trust_rank,
    s.status,
    s.last_checked_at,
    s.last_success_at,
    s.last_failure_at,
    s.last_error,
    s.metadata,
    i.code,
    i.name,
    i.system_type,
    i.base_url,
    i.status,
    i.config
  from ref.countries c
  left join pipeline.sources s on s.country_id = c.id and s.provider_id is null
  left join integration.systems i on i.id = s.system_id
  where c.catalogue_status in ('pilot','active')
     or c.provider_ingestion_enabled
     or c.course_ingestion_enabled
  order by c.name, s.trust_rank nulls last, s.label nulls last;
end;
$$;

revoke all on function public.ui_regulatory_sources_list() from public, anon;
grant execute on function public.ui_regulatory_sources_list() to authenticated, service_role;

create or replace function pipeline.resolve_regulatory_sources(p_country_code text)
returns table(
  source_id uuid,
  source_type text,
  source_label text,
  source_url text,
  trust_rank smallint,
  system_code text,
  system_name text,
  system_type text,
  system_base_url text,
  system_config jsonb,
  source_metadata jsonb
)
language sql
stable
security definer
set search_path = pipeline, integration, ref
as $$
  select
    s.id,
    s.source_type,
    s.label,
    s.url,
    s.trust_rank,
    i.code,
    i.name,
    i.system_type,
    i.base_url,
    i.config,
    s.metadata
  from ref.countries c
  join pipeline.sources s on s.country_id = c.id and s.provider_id is null
  left join integration.systems i on i.id = s.system_id
  where upper(c.iso_alpha2::text) = upper(p_country_code)
    and s.status = 'active'
    and coalesce(i.status, 'active') = 'active'
  order by s.trust_rank asc, s.label asc;
$$;

revoke all on function pipeline.resolve_regulatory_sources(text) from public, anon, authenticated;
grant execute on function pipeline.resolve_regulatory_sources(text) to service_role;
