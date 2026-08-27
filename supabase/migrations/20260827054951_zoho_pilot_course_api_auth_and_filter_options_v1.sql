create schema if not exists private;

create table if not exists private.zoho_integration_credentials (
  credential_name text primary key,
  token_sha256 text not null check (token_sha256 ~ '^[0-9a-f]{64}$'),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  rotated_at timestamptz not null default now()
);

revoke all on schema private from public, anon, authenticated;
revoke all on table private.zoho_integration_credentials from public, anon, authenticated;

insert into private.zoho_integration_credentials(credential_name, token_sha256, enabled)
values ('coursefinder_zoho_pilot_v1', '55bddf1edb955057836a9b983b39cd135a90713feb5fa104f7b8aebe1b854e6c', true)
on conflict (credential_name) do update
set token_sha256 = excluded.token_sha256,
    enabled = true,
    rotated_at = now();

create or replace function api.zoho_integration_auth_v1(p_token_sha256 text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, private
as $$
  select exists(
    select 1
    from private.zoho_integration_credentials c
    where c.credential_name = 'coursefinder_zoho_pilot_v1'
      and c.enabled
      and c.token_sha256 = lower(coalesce(p_token_sha256,''))
  );
$$;

revoke all on function api.zoho_integration_auth_v1(text) from public;
revoke all on function api.zoho_integration_auth_v1(text) from anon;
revoke all on function api.zoho_integration_auth_v1(text) from authenticated;
grant execute on function api.zoho_integration_auth_v1(text) to service_role;

create or replace function api.zoho_filter_options_v1(
  p_kind text,
  p_country_code text default null,
  p_query text default null,
  p_limit integer default 10,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, api, ref, search
as $$
declare
  v_kind text := lower(trim(coalesce(p_kind,'')));
  v_country text := upper(nullif(trim(coalesce(p_country_code,'')), ''));
  v_query text := nullif(trim(coalesce(p_query,'')), '');
  v_limit integer := least(greatest(coalesce(p_limit,10),1),50);
  v_offset integer := greatest(coalesce(p_offset,0),0);
  v_total bigint := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if v_kind = 'country' then
    select count(*)
      into v_total
      from ref.countries c
     where exists (
             select 1 from search.course_documents d
             where d.country_id = c.id
           )
       and (
         v_query is null
         or c.name ilike '%'||v_query||'%'
         or c.iso_alpha2::text ilike '%'||v_query||'%'
       );

    select coalesce(jsonb_agg(jsonb_build_object(
             'code', x.iso_alpha2,
             'name', x.name
           ) order by x.name, x.iso_alpha2), '[]'::jsonb)
      into v_items
      from (
        select trim(c.iso_alpha2::text) as iso_alpha2, c.name
          from ref.countries c
         where exists (
                 select 1 from search.course_documents d
                 where d.country_id = c.id
               )
           and (
             v_query is null
             or c.name ilike '%'||v_query||'%'
             or c.iso_alpha2::text ilike '%'||v_query||'%'
           )
         order by c.name, c.iso_alpha2
         limit v_limit offset v_offset
      ) x;

  elsif v_kind = 'subdivision' then
    if v_country is null then
      raise exception using errcode='22023', message='country_code_required';
    end if;

    select count(*)
      into v_total
      from ref.subdivisions s
      join ref.countries c on c.id = s.country_id
     where trim(c.iso_alpha2::text) = v_country
       and exists (
             select 1
             from search.course_documents d
             where d.country_id = c.id
               and s.code = any(coalesce(d.subdivision_codes, '{}'::text[]))
           )
       and (
         v_query is null
         or s.name ilike '%'||v_query||'%'
         or s.code ilike '%'||v_query||'%'
       );

    select coalesce(jsonb_agg(jsonb_build_object(
             'code', x.code,
             'name', x.name,
             'country_code', v_country
           ) order by x.name, x.code), '[]'::jsonb)
      into v_items
      from (
        select s.code, s.name
          from ref.subdivisions s
          join ref.countries c on c.id = s.country_id
         where trim(c.iso_alpha2::text) = v_country
           and exists (
                 select 1
                 from search.course_documents d
                 where d.country_id = c.id
                   and s.code = any(coalesce(d.subdivision_codes, '{}'::text[]))
               )
           and (
             v_query is null
             or s.name ilike '%'||v_query||'%'
             or s.code ilike '%'||v_query||'%'
           )
         order by s.name, s.code
         limit v_limit offset v_offset
      ) x;
  else
    raise exception using errcode='22023', message='invalid_filter_kind';
  end if;

  return jsonb_build_object(
    'contract','zoho-integration-v1',
    'kind',v_kind,
    'items',v_items,
    'total',v_total,
    'limit',v_limit,
    'offset',v_offset,
    'has_more',(v_offset + v_limit) < v_total
  );
end;
$$;

revoke all on function api.zoho_filter_options_v1(text,text,text,integer,integer) from public;
revoke all on function api.zoho_filter_options_v1(text,text,text,integer,integer) from anon;
revoke all on function api.zoho_filter_options_v1(text,text,text,integer,integer) from authenticated;
grant execute on function api.zoho_filter_options_v1(text,text,text,integer,integer) to service_role;
