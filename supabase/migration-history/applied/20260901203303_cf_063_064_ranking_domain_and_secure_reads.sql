
create schema if not exists ranking;

create table if not exists ranking.systems (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique check (code in ('qs_wur','the_wur')),
  publisher_name text not null,
  ranking_name text not null,
  official_url text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists ranking.editions (
  id uuid primary key default extensions.gen_random_uuid(),
  system_id uuid not null references ranking.systems(id),
  edition_year integer not null check (edition_year between 2000 and 2100),
  publication_date date,
  methodology_version text,
  methodology_url text,
  source_url text not null,
  source_artifact_id uuid references pipeline.evidence_artifacts(id),
  retrieved_at timestamptz,
  source_fingerprint text,
  source_revision text not null default 'initial',
  access_status text not null default 'pending' check (access_status in ('pending','public','registered','licensed_upload','restricted','unavailable')),
  licensing_note text,
  status text not null default 'pending' check (status in ('pending','qualified','parsed','reconciled','accepted','superseded','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(system_id, edition_year, source_revision)
);

create table if not exists ranking.publisher_institutions (
  id uuid primary key default extensions.gen_random_uuid(),
  system_id uuid not null references ranking.systems(id),
  publisher_institution_id text,
  profile_url text,
  institution_name text not null,
  country_text text,
  location_text text,
  first_seen_edition integer,
  last_seen_edition integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists ranking_publisher_institution_stable_uidx
  on ranking.publisher_institutions(system_id, publisher_institution_id)
  where publisher_institution_id is not null;

create index if not exists ranking_publisher_institution_name_idx
  on ranking.publisher_institutions(system_id, lower(institution_name), lower(coalesce(country_text,'')));

create table if not exists ranking.provider_mappings (
  id uuid primary key default extensions.gen_random_uuid(),
  publisher_institution_id uuid not null references ranking.publisher_institutions(id),
  provider_id uuid not null references catalogue.providers(id),
  mapping_method text not null,
  confidence numeric(5,4),
  status text not null default 'candidate' check (status in ('candidate','accepted','rejected','superseded')),
  valid_from timestamptz not null default now(),
  valid_to timestamptz,
  evidence_artifact_id uuid references pipeline.evidence_artifacts(id),
  reviewed_by uuid,
  reviewed_at timestamptz,
  note text,
  created_at timestamptz not null default now()
);

create unique index if not exists ranking_provider_mapping_active_uidx
  on ranking.provider_mappings(publisher_institution_id)
  where status='accepted' and valid_to is null;

create index if not exists ranking_provider_mapping_provider_idx
  on ranking.provider_mappings(provider_id, status);

create table if not exists ranking.observations (
  id uuid primary key default extensions.gen_random_uuid(),
  edition_id uuid not null references ranking.editions(id),
  publisher_institution_id uuid not null references ranking.publisher_institutions(id),
  provider_id uuid references catalogue.providers(id),
  rank_display text,
  rank_exact integer check (rank_exact is null or rank_exact > 0),
  rank_low integer check (rank_low is null or rank_low > 0),
  rank_high integer check (rank_high is null or rank_high > 0),
  is_tied boolean not null default false,
  rank_status text not null default 'unknown' check (rank_status in ('ranked_exact','ranked_band','reporter','unranked','not_eligible','unknown')),
  overall_score numeric,
  source_row_ordinal integer,
  source_row_payload jsonb not null default '{}'::jsonb,
  evidence_artifact_id uuid references pipeline.evidence_artifacts(id),
  created_at timestamptz not null default now(),
  unique(edition_id, publisher_institution_id)
);

create index if not exists ranking_observation_provider_idx
  on ranking.observations(provider_id, edition_id);

create index if not exists ranking_observation_rank_idx
  on ranking.observations(edition_id, rank_exact)
  where rank_exact is not null;

create table if not exists ranking.indicator_observations (
  id uuid primary key default extensions.gen_random_uuid(),
  observation_id uuid not null references ranking.observations(id) on delete cascade,
  indicator_code text not null,
  indicator_label text,
  value_numeric numeric,
  value_display text,
  unit text,
  methodology_version text,
  created_at timestamptz not null default now(),
  unique(observation_id, indicator_code)
);

create table if not exists ranking.manual_imports (
  id uuid primary key default extensions.gen_random_uuid(),
  system_id uuid not null references ranking.systems(id),
  edition_year integer not null check (edition_year between 2000 and 2100),
  publisher_name text not null,
  source_url text not null,
  methodology_url text,
  licensing_note text not null,
  revision_note text,
  original_filename text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size >= 0),
  content_hash text not null,
  storage_path text not null,
  evidence_artifact_id uuid references pipeline.evidence_artifacts(id),
  status text not null default 'uploaded' check (status in ('uploaded','validated','parsed','needs_review','reconciled','applied','rejected')),
  validation_summary jsonb not null default '{}'::jsonb,
  parse_summary jsonb not null default '{}'::jsonb,
  uploaded_by uuid not null,
  uploaded_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(system_id, edition_year, content_hash)
);

create index if not exists ranking_manual_import_status_idx
  on ranking.manual_imports(status, uploaded_at desc);

alter table ranking.systems enable row level security;
alter table ranking.editions enable row level security;
alter table ranking.publisher_institutions enable row level security;
alter table ranking.provider_mappings enable row level security;
alter table ranking.observations enable row level security;
alter table ranking.indicator_observations enable row level security;
alter table ranking.manual_imports enable row level security;

revoke all on schema ranking from public, anon, authenticated;
revoke all on all tables in schema ranking from public, anon, authenticated;
grant usage on schema ranking to service_role;
grant select, insert, update, delete on all tables in schema ranking to service_role;

insert into ranking.systems(code,publisher_name,ranking_name,official_url)
values
 ('qs_wur','QS Quacquarelli Symonds','QS World University Rankings','https://www.topuniversities.com/world-university-rankings'),
 ('the_wur','Times Higher Education','Times Higher Education World University Rankings','https://www.timeshighereducation.com/world-university-rankings/latest/world-ranking')
on conflict(code) do update set
 publisher_name=excluded.publisher_name,
 ranking_name=excluded.ranking_name,
 official_url=excluded.official_url,
 updated_at=now();

create or replace function security.admin_provider_rankings(p_provider_id uuid, p_limit integer default 10)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','ranking','auth'
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(p_limit,10),1),10);
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  select coalesce(jsonb_object_agg(code,payload),'{}'::jsonb)
  into v_result
  from (
    select s.code,
      jsonb_build_object(
        'system_code',s.code,
        'publisher_name',s.publisher_name,
        'ranking_name',s.ranking_name,
        'latest',(
          select jsonb_strip_nulls(jsonb_build_object(
            'edition_year',e.edition_year,
            'rank_display',o.rank_display,
            'rank_exact',o.rank_exact,
            'rank_low',o.rank_low,
            'rank_high',o.rank_high,
            'rank_status',o.rank_status,
            'is_tied',o.is_tied,
            'overall_score',o.overall_score,
            'source_url',e.source_url,
            'methodology_url',e.methodology_url,
            'evidence_artifact_id',o.evidence_artifact_id
          ))
          from ranking.observations o
          join ranking.editions e on e.id=o.edition_id
          where o.provider_id=p_provider_id and e.system_id=s.id and e.status='accepted'
          order by e.edition_year desc,e.updated_at desc
          limit 1
        ),
        'history',coalesce((
          select jsonb_agg(x order by (x->>'edition_year')::integer desc)
          from (
            select jsonb_strip_nulls(jsonb_build_object(
              'edition_year',e.edition_year,
              'rank_display',o.rank_display,
              'rank_exact',o.rank_exact,
              'rank_low',o.rank_low,
              'rank_high',o.rank_high,
              'rank_status',o.rank_status,
              'is_tied',o.is_tied,
              'overall_score',o.overall_score,
              'methodology_version',e.methodology_version
            )) x
            from ranking.observations o
            join ranking.editions e on e.id=o.edition_id
            where o.provider_id=p_provider_id and e.system_id=s.id and e.status='accepted'
            order by e.edition_year desc,e.updated_at desc
            limit v_limit
          ) h
        ),'[]'::jsonb)
      ) payload
    from ranking.systems s
    where s.active
  ) z;

  return coalesce(v_result,'{}'::jsonb);
end
$$;

create or replace function security.admin_ranking_read(p_operation text, p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','security','ranking','catalogue','ref','auth'
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_system text:=nullif(p_args->>'system_code','');
  v_year integer:=nullif(p_args->>'edition_year','')::integer;
  v_provider uuid:=nullif(p_args->>'provider_id','')::uuid;
  v_query text:=nullif(btrim(p_args->>'query'),'');
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  if p_operation='ranking_summary' then
    return jsonb_build_object(
      'systems',coalesce((
        select jsonb_agg(jsonb_build_object(
          'code',s.code,
          'publisher_name',s.publisher_name,
          'ranking_name',s.ranking_name,
          'official_url',s.official_url,
          'latest_edition',(select max(e.edition_year) from ranking.editions e where e.system_id=s.id and e.status='accepted'),
          'accepted_editions',(select count(*) from ranking.editions e where e.system_id=s.id and e.status='accepted'),
          'observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted'),
          'mapped_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and o.provider_id is not null),
          'unmapped_observations',(select count(*) from ranking.observations o join ranking.editions e on e.id=o.edition_id where e.system_id=s.id and e.status='accepted' and o.provider_id is null)
        ) order by s.code)
        from ranking.systems s where s.active
      ),'[]'::jsonb),
      'manual_imports',case when v_rank>=4 then (
        select jsonb_build_object(
          'total',count(*),
          'uploaded',count(*) filter(where status='uploaded'),
          'needs_review',count(*) filter(where status='needs_review'),
          'applied',count(*) filter(where status='applied')
        ) from ranking.manual_imports
      ) else null end
    );
  elsif p_operation='ranking_filters' then
    return jsonb_build_object(
      'systems',coalesce((select jsonb_agg(jsonb_build_object('code',code,'label',ranking_name) order by code) from ranking.systems where active),'[]'::jsonb),
      'years',coalesce((select jsonb_agg(y order by y desc) from (select distinct edition_year y from ranking.editions) q),'[]'::jsonb),
      'statuses',jsonb_build_array('ranked_exact','ranked_band','reporter','unranked','not_eligible','unknown')
    );
  elsif p_operation='ranking_observations' then
    return (
      with filtered as (
        select
          o.id,s.code system_code,s.publisher_name,s.ranking_name,e.edition_year,e.methodology_version,e.methodology_url,e.source_url,
          pi.institution_name publisher_institution_name,pi.country_text,
          o.provider_id,coalesce(p.display_name,p.canonical_name) provider_name,
          o.rank_display,o.rank_exact,o.rank_low,o.rank_high,o.is_tied,o.rank_status,o.overall_score,o.evidence_artifact_id
        from ranking.observations o
        join ranking.editions e on e.id=o.edition_id
        join ranking.systems s on s.id=e.system_id
        join ranking.publisher_institutions pi on pi.id=o.publisher_institution_id
        left join catalogue.providers p on p.id=o.provider_id
        where e.status='accepted'
          and (v_system is null or s.code=v_system)
          and (v_year is null or e.edition_year=v_year)
          and (v_provider is null or o.provider_id=v_provider)
          and (v_query is null or pi.institution_name ilike '%'||v_query||'%' or coalesce(p.display_name,p.canonical_name) ilike '%'||v_query||'%')
      )
      select jsonb_build_object(
        'total',(select count(*) from filtered),
        'limit',v_limit,
        'offset',v_offset,
        'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.system_code,x.edition_year desc,coalesce(x.rank_exact,x.rank_low,999999),x.publisher_institution_name)
          from (select * from filtered order by system_code,edition_year desc,coalesce(rank_exact,rank_low,999999),publisher_institution_name limit v_limit offset v_offset) x),'[]'::jsonb)
      )
    );
  elsif p_operation='ranking_imports' then
    if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
    return (
      select jsonb_build_object(
        'total',(select count(*) from ranking.manual_imports),
        'limit',v_limit,'offset',v_offset,
        'items',coalesce((
          select jsonb_agg(to_jsonb(x) order by x.uploaded_at desc)
          from (
            select mi.id,s.code system_code,mi.edition_year,mi.publisher_name,mi.source_url,mi.methodology_url,
              mi.licensing_note,mi.revision_note,mi.original_filename,mi.mime_type,mi.byte_size,mi.content_hash,
              mi.storage_path,mi.evidence_artifact_id,mi.status,mi.validation_summary,mi.parse_summary,mi.uploaded_at
            from ranking.manual_imports mi join ranking.systems s on s.id=mi.system_id
            order by mi.uploaded_at desc limit v_limit offset v_offset
          ) x
        ),'[]'::jsonb)
      )
    );
  else
    raise exception 'unsupported ranking read operation: %',p_operation using errcode='22023';
  end if;
end
$$;

revoke all on function security.admin_provider_rankings(uuid,integer) from public;
revoke all on function security.admin_ranking_read(text,jsonb) from public;
grant execute on function security.admin_provider_rankings(uuid,integer) to authenticated;
grant execute on function security.admin_ranking_read(text,jsonb) to authenticated;
