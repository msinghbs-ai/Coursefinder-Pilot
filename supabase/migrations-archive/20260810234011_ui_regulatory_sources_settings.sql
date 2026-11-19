create or replace function public.ui_regulatory_sources_list()
returns table (
  country_id uuid,
  country_code text,
  country_name text,
  provider_ingestion_enabled boolean,
  course_ingestion_enabled boolean,
  source_id uuid,
  source_type text,
  source_label text,
  source_url text,
  trust_rank smallint,
  source_status text,
  system_code text,
  system_name text,
  system_type text,
  system_base_url text
)
language sql
stable
security definer
set search_path = public, ref, pipeline, integration, security
as $$
  select
    c.id,
    c.iso_alpha2::text,
    c.name,
    c.provider_ingestion_enabled,
    c.course_ingestion_enabled,
    s.id,
    s.source_type,
    s.label,
    s.url,
    s.trust_rank,
    s.status,
    i.code,
    i.name,
    i.system_type,
    i.base_url
  from ref.countries c
  left join pipeline.sources s on s.country_id = c.id and s.provider_id is null
  left join integration.systems i on i.id = s.system_id
  where c.catalogue_status = 'active'
  order by c.name, s.trust_rank nulls last, s.label nulls last;
$$;

revoke all on function public.ui_regulatory_sources_list() from public, anon;
grant execute on function public.ui_regulatory_sources_list() to authenticated;
