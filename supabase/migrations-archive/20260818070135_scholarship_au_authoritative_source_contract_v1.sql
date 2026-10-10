create table if not exists pipeline.scholarship_source_qualifications (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references ref.countries(id),
  source_key text not null unique,
  authority_name text not null,
  source_url text not null,
  source_class text not null,
  identifier_scheme text not null,
  stable_identifier_strategy text not null,
  provider_mapping_strategy text,
  cycle_strategy text not null,
  evidence_strategy text not null,
  qualification_status text not null check (qualification_status in ('qualified','bounded','deferred','rejected')),
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table pipeline.scholarship_source_qualifications enable row level security;
revoke all on pipeline.scholarship_source_qualifications from public, anon, authenticated;
grant select, insert, update, delete on pipeline.scholarship_source_qualifications to service_role;

create table if not exists pipeline.scholarship_source_records (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references pipeline.sources(id) on delete cascade,
  source_record_id text not null,
  source_record_url text not null,
  source_provider_id text,
  source_provider_cricos text,
  source_provider_name text,
  content_hash text not null,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  payload jsonb not null,
  observed_at timestamptz not null default now(),
  applied_at timestamptz,
  status text not null default 'captured' check (status in ('captured','validated','applied','unmapped','rejected')),
  error_text text,
  created_at timestamptz not null default now(),
  unique(source_id, source_record_id, content_hash)
);

create index if not exists scholarship_source_records_lookup_idx
  on pipeline.scholarship_source_records(source_id, source_record_id, observed_at desc);
create index if not exists scholarship_source_records_evidence_idx
  on pipeline.scholarship_source_records(evidence_id) where evidence_id is not null;
create index if not exists scholarship_source_records_payload_gin
  on pipeline.scholarship_source_records using gin(payload);

alter table pipeline.scholarship_source_records enable row level security;
revoke all on pipeline.scholarship_source_records from public, anon, authenticated;
grant select, insert, update, delete on pipeline.scholarship_source_records to service_role;

create unique index if not exists pipeline_sources_scholarship_source_key_uidx
  on pipeline.sources ((metadata->>'scholarship_source_key'))
  where metadata ? 'scholarship_source_key';

create or replace function scholarship.deterministic_uuid(p_key text)
returns uuid
language sql
immutable
strict
security invoker
set search_path = ''
as $$
  select (
    substr(md5(p_key),1,8) || '-' ||
    substr(md5(p_key),9,4) || '-' ||
    '5' || substr(md5(p_key),14,3) || '-' ||
    'a' || substr(md5(p_key),18,3) || '-' ||
    substr(md5(p_key),21,12)
  )::uuid
$$;

revoke all on function scholarship.deterministic_uuid(text) from public, anon, authenticated;
grant execute on function scholarship.deterministic_uuid(text) to service_role;

create or replace function public.svc_scholarship_prepare_source(
  p_source_key text,
  p_label text,
  p_url text,
  p_source_type text default 'scholarship_catalogue',
  p_trust_rank smallint default 95,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_country uuid;
  v_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role required';
  end if;
  if nullif(btrim(p_source_key),'') is null or nullif(btrim(p_url),'') is null then
    raise exception 'source key and url required';
  end if;

  select id into v_country from ref.countries where iso_alpha2='AU';
  if v_country is null then raise exception 'AU country missing'; end if;

  select id into v_id
  from pipeline.sources
  where metadata->>'scholarship_source_key'=p_source_key
  limit 1;

  if v_id is null then
    insert into pipeline.sources(source_type,country_id,url,label,trust_rank,status,metadata)
    values (
      p_source_type,v_country,p_url,p_label,p_trust_rank,'active',
      coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object(
        'layer','2A',
        'domain','scholarship',
        'scholarship_source_key',p_source_key,
        'identity_authority',false
      )
    )
    returning id into v_id;
  else
    update pipeline.sources
       set source_type=p_source_type,
           url=p_url,
           label=p_label,
           trust_rank=p_trust_rank,
           status='active',
           metadata=metadata || coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object(
             'layer','2A','domain','scholarship','scholarship_source_key',p_source_key,'identity_authority',false
           ),
           updated_at=now()
     where id=v_id;
  end if;
  return v_id;
end
$$;

revoke all on function public.svc_scholarship_prepare_source(text,text,text,text,smallint,jsonb) from public, anon, authenticated;
grant execute on function public.svc_scholarship_prepare_source(text,text,text,text,smallint,jsonb) to service_role;

create or replace function public.svc_scholarship_register_evidence(
  p_source_id uuid,
  p_source_url text,
  p_storage_path text,
  p_content_hash text,
  p_mime_type text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if auth.role() <> 'service_role' then raise exception 'service_role required'; end if;
  select id into v_id
  from pipeline.evidence_artifacts
  where source_id=p_source_id
    and content_hash=p_content_hash
    and coalesce(source_url,'')=coalesce(p_source_url,'')
  order by captured_at desc limit 1;

  if v_id is null then
    insert into pipeline.evidence_artifacts(
      source_id,evidence_type,source_url,storage_path,content_hash,mime_type,captured_at,metadata
    ) values (
      p_source_id,'source_snapshot',p_source_url,p_storage_path,p_content_hash,p_mime_type,now(),
      coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object('layer','2A','domain','scholarship')
    ) returning id into v_id;
  end if;
  return v_id;
end
$$;

revoke all on function public.svc_scholarship_register_evidence(uuid,text,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.svc_scholarship_register_evidence(uuid,text,text,text,text,jsonb) to service_role;

create or replace function public.svc_scholarship_resolve_au_provider(p_cricos text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select pr.provider_id
  from catalogue.provider_registrations pr
  join catalogue.providers p on p.id=pr.provider_id
  join ref.countries c on c.id=p.country_id
  where c.iso_alpha2='AU'
    and pr.registration_scheme='cricos'
    and upper(btrim(pr.registration_code))=upper(btrim(p_cricos))
    and coalesce(pr.status,'active') not in ('inactive','cancelled','archived')
  order by pr.valid_to nulls first, pr.checked_at desc nulls last
  limit 1
$$;

revoke all on function public.svc_scholarship_resolve_au_provider(text) from public, anon, authenticated;
grant execute on function public.svc_scholarship_resolve_au_provider(text) to service_role;

create or replace function public.svc_scholarship_apply_records(
  p_source_id uuid,
  p_evidence_id uuid,
  p_records jsonb,
  p_mode text default 'apply'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r jsonb;
  cyc jsonb;
  win jsonb;
  sc jsonb;
  grp jsonb;
  crt jsonb;
  tier jsonb;
  cov jsonb;
  v_source_key text;
  v_identifier_scheme text;
  v_source_record_id text;
  v_stable_key text;
  v_entity_id uuid;
  v_scholarship_id uuid;
  v_provider_id uuid;
  v_cycle_id uuid;
  v_group_id uuid;
  v_parent_group_id uuid;
  v_target_id uuid;
  v_seen int := 0;
  v_changed int := 0;
  v_unmapped int := 0;
  v_cycles int := 0;
  v_windows int := 0;
  v_scopes int := 0;
  v_groups int := 0;
  v_criteria int := 0;
  v_tiers int := 0;
  v_coverage int := 0;
begin
  if auth.role() <> 'service_role' then raise exception 'service_role required'; end if;
  if p_mode not in ('dry_run','apply') then raise exception 'mode must be dry_run or apply'; end if;
  if jsonb_typeof(p_records) <> 'array' then raise exception 'records must be JSON array'; end if;

  select metadata->>'scholarship_source_key' into v_source_key
  from pipeline.sources where id=p_source_id;
  if nullif(v_source_key,'') is null then raise exception 'scholarship source not prepared'; end if;

  for r in select value from jsonb_array_elements(p_records)
  loop
    v_seen := v_seen + 1;
    v_source_record_id := nullif(btrim(r->>'source_record_id'),'');
    v_identifier_scheme := coalesce(nullif(btrim(r->>'identifier_scheme'),''), v_source_key || '_id');
    if v_source_record_id is null then raise exception 'source_record_id required'; end if;
    if nullif(btrim(r->>'name'),'') is null then raise exception 'scholarship name required for %',v_source_record_id; end if;

    v_provider_id := null;
    if nullif(btrim(r->>'provider_cricos'),'') is not null then
      select public.svc_scholarship_resolve_au_provider(r->>'provider_cricos') into v_provider_id;
      if v_provider_id is null then v_unmapped := v_unmapped + 1; end if;
    end if;

    if p_mode='dry_run' then
      continue;
    end if;

    select scholarship_id into v_scholarship_id
    from scholarship.identifiers
    where source_id=p_source_id and scheme=v_identifier_scheme and identifier_value=v_source_record_id
    limit 1;

    if v_scholarship_id is null then
      v_stable_key := 'scholarship:AU:' || v_source_key || ':' || lower(v_source_record_id);
      v_entity_id := scholarship.deterministic_uuid(v_stable_key);

      insert into pim.entity_registry(id,entity_type,stable_key,lifecycle_status)
      values(v_entity_id,'scholarship',v_stable_key,'active')
      on conflict(stable_key) do update set updated_at=now()
      returning id into v_scholarship_id;
    else
      select stable_key into v_stable_key from scholarship.scholarships where id=v_scholarship_id;
      if v_stable_key is null then v_stable_key := 'scholarship:AU:' || v_source_key || ':' || lower(v_source_record_id); end if;
      update pim.entity_registry set lifecycle_status='active',updated_at=now() where id=v_scholarship_id;
    end if;

    insert into scholarship.scholarships(
      id,stable_key,provider_id,name,scholarship_type,description,audience,award_value_text,
      application_required,application_open_date,application_close_date,academic_year,source_url,
      lifecycle_status,publication_status,source_id,evidence_id,confidence,updated_at
    ) values (
      v_scholarship_id,v_stable_key,v_provider_id,r->>'name',r->>'scholarship_type',r->>'description',
      r->>'audience',r->>'award_value_text',coalesce((r->>'application_required')::boolean,true),
      nullif(r->>'application_open_date','')::date,nullif(r->>'application_close_date','')::date,
      nullif(r->>'academic_year','')::int,r->>'source_url','active','unpublished',p_source_id,p_evidence_id,
      coalesce(nullif(r->>'confidence','')::numeric,1.0),now()
    )
    on conflict(id) do update set
      provider_id=excluded.provider_id,
      name=excluded.name,
      scholarship_type=excluded.scholarship_type,
      description=excluded.description,
      audience=excluded.audience,
      award_value_text=excluded.award_value_text,
      application_required=excluded.application_required,
      application_open_date=excluded.application_open_date,
      application_close_date=excluded.application_close_date,
      academic_year=excluded.academic_year,
      source_url=excluded.source_url,
      lifecycle_status='active',
      source_id=excluded.source_id,
      evidence_id=excluded.evidence_id,
      confidence=excluded.confidence,
      updated_at=now();

    insert into scholarship.identifiers(id,scholarship_id,scheme,identifier_value,source_id,evidence_id,is_primary,status)
    values(
      scholarship.deterministic_uuid(v_stable_key || ':identifier:' || v_identifier_scheme || ':' || v_source_record_id),
      v_scholarship_id,v_identifier_scheme,v_source_record_id,p_source_id,p_evidence_id,true,'active'
    )
    on conflict(source_id,scheme,identifier_value) do update set
      scholarship_id=excluded.scholarship_id,evidence_id=excluded.evidence_id,is_primary=true,status='active';

    for cyc in select value from jsonb_array_elements(coalesce(r->'cycles','[]'::jsonb))
    loop
      if nullif(btrim(cyc->>'cycle_code'),'') is null then raise exception 'cycle_code required'; end if;
      v_cycle_id := scholarship.deterministic_uuid(v_stable_key || ':cycle:' || (cyc->>'cycle_code'));
      insert into scholarship.offering_cycles(
        id,scholarship_id,cycle_code,academic_year,intake_label,valid_from,valid_to,status,source_id,evidence_id,metadata
      ) values (
        v_cycle_id,v_scholarship_id,cyc->>'cycle_code',nullif(cyc->>'academic_year','')::int,cyc->>'intake_label',
        nullif(cyc->>'valid_from','')::date,nullif(cyc->>'valid_to','')::date,coalesce(cyc->>'status','active'),
        p_source_id,p_evidence_id,coalesce(cyc->'metadata','{}'::jsonb)
      )
      on conflict(scholarship_id,cycle_code) do update set
        academic_year=excluded.academic_year,intake_label=excluded.intake_label,valid_from=excluded.valid_from,
        valid_to=excluded.valid_to,status=excluded.status,source_id=excluded.source_id,evidence_id=excluded.evidence_id,
        metadata=excluded.metadata;
      v_cycles := v_cycles + 1;

      for win in select value from jsonb_array_elements(coalesce(cyc->'windows','[]'::jsonb))
      loop
        if nullif(btrim(win->>'window_key'),'') is null then raise exception 'window_key required'; end if;
        insert into scholarship.application_windows(
          id,scholarship_id,cycle_id,round_code,label,opens_at,closes_at,application_method,application_url,status,
          source_id,evidence_id,metadata
        ) values (
          scholarship.deterministic_uuid(v_stable_key || ':cycle:' || (cyc->>'cycle_code') || ':window:' || (win->>'window_key')),
          v_scholarship_id,v_cycle_id,win->>'round_code',win->>'label',nullif(win->>'opens_at','')::timestamptz,
          nullif(win->>'closes_at','')::timestamptz,win->>'application_method',win->>'application_url',
          coalesce(win->>'status','unknown'),p_source_id,p_evidence_id,coalesce(win->'metadata','{}'::jsonb)
        )
        on conflict(id) do update set
          round_code=excluded.round_code,label=excluded.label,opens_at=excluded.opens_at,closes_at=excluded.closes_at,
          application_method=excluded.application_method,application_url=excluded.application_url,status=excluded.status,
          source_id=excluded.source_id,evidence_id=excluded.evidence_id,metadata=excluded.metadata;
        v_windows := v_windows + 1;
      end loop;

      for sc in select value from jsonb_array_elements(coalesce(cyc->'scopes','[]'::jsonb))
      loop
        if nullif(btrim(sc->>'scope_key'),'') is null then raise exception 'scope_key required'; end if;
        v_target_id := null;
        if sc->>'scope_type'='provider' then
          if nullif(sc->>'target_code','') is not null then
            select public.svc_scholarship_resolve_au_provider(sc->>'target_code') into v_target_id;
          else v_target_id := v_provider_id;
          end if;
        elsif sc->>'scope_type'='study_level' then
          select id into v_target_id from ref.study_levels where code=sc->>'target_code' and status='active' limit 1;
        elsif sc->>'scope_type'='country' then
          select id into v_target_id from ref.countries where iso_alpha2=upper(sc->>'target_code') limit 1;
        elsif sc->>'scope_type' <> 'global' then
          raise exception 'unsupported v1 scope type %',sc->>'scope_type';
        end if;
        if sc->>'scope_type' <> 'global' and v_target_id is null then
          raise exception 'unresolved scope % target %',sc->>'scope_type',sc->>'target_code';
        end if;

        insert into scholarship.scopes(
          id,scholarship_id,scope_type,provider_id,study_level_id,country_id,include_exclude,source_id,evidence_id,cycle_id
        ) values (
          scholarship.deterministic_uuid(v_stable_key || ':cycle:' || (cyc->>'cycle_code') || ':scope:' || (sc->>'scope_key')),
          v_scholarship_id,sc->>'scope_type',case when sc->>'scope_type'='provider' then v_target_id end,
          case when sc->>'scope_type'='study_level' then v_target_id end,
          case when sc->>'scope_type'='country' then v_target_id end,
          coalesce(sc->>'include_exclude','include'),p_source_id,p_evidence_id,v_cycle_id
        ) on conflict(id) do update set
          provider_id=excluded.provider_id,study_level_id=excluded.study_level_id,country_id=excluded.country_id,
          include_exclude=excluded.include_exclude,source_id=excluded.source_id,evidence_id=excluded.evidence_id,cycle_id=excluded.cycle_id;
        v_scopes := v_scopes + 1;
      end loop;

      for grp in select value from jsonb_array_elements(coalesce(cyc->'criterion_groups','[]'::jsonb))
      loop
        if nullif(btrim(grp->>'group_code'),'') is null then raise exception 'group_code required'; end if;
        v_parent_group_id := null;
        if nullif(btrim(grp->>'parent_group_code'),'') is not null then
          v_parent_group_id := scholarship.deterministic_uuid(v_stable_key || ':cycle:' || (cyc->>'cycle_code') || ':group:' || (grp->>'parent_group_code'));
        end if;
        v_group_id := scholarship.deterministic_uuid(v_stable_key || ':cycle:' || (cyc->>'cycle_code') || ':group:' || (grp->>'group_code'));
        insert into scholarship.criterion_groups(
          id,scholarship_id,cycle_id,parent_group_id,group_code,label,conjunction,is_mandatory,display_order,source_id,evidence_id
        ) values (
          v_group_id,v_scholarship_id,v_cycle_id,v_parent_group_id,grp->>'group_code',grp->>'label',
          coalesce(grp->>'conjunction','all'),coalesce((grp->>'is_mandatory')::boolean,true),
          coalesce(nullif(grp->>'display_order','')::int,0),p_source_id,p_evidence_id
        )
        on conflict(scholarship_id,group_code) do update set
          cycle_id=excluded.cycle_id,parent_group_id=excluded.parent_group_id,label=excluded.label,
          conjunction=excluded.conjunction,is_mandatory=excluded.is_mandatory,display_order=excluded.display_order,
          source_id=excluded.source_id,evidence_id=excluded.evidence_id;
        v_groups := v_groups + 1;
      end loop;

      for crt in select value from jsonb_array_elements(coalesce(cyc->'criteria','[]'::jsonb))
      loop
        if nullif(btrim(crt->>'criterion_key'),'') is null then raise exception 'criterion_key required'; end if;
        v_group_id := null;
        if nullif(btrim(crt->>'group_code'),'') is not null then
          v_group_id := scholarship.deterministic_uuid(v_stable_key || ':cycle:' || (cyc->>'cycle_code') || ':group:' || (crt->>'group_code'));
        end if;
        insert into scholarship.criteria(
          id,scholarship_id,criterion_type,operator,value_text,value_number,value_codes,value_json,human_text,
          is_mandatory,machine_evaluable,status,source_id,evidence_id,confidence,cycle_id,criterion_group_id
        ) values (
          scholarship.deterministic_uuid(v_stable_key || ':cycle:' || (cyc->>'cycle_code') || ':criterion:' || (crt->>'criterion_key')),
          v_scholarship_id,crt->>'criterion_type',crt->>'operator',crt->>'value_text',nullif(crt->>'value_number','')::numeric,
          case when jsonb_typeof(crt->'value_codes')='array' then array(select jsonb_array_elements_text(crt->'value_codes')) else null end,
          crt->'value_json',crt->>'human_text',coalesce((crt->>'is_mandatory')::boolean,true),
          coalesce((crt->>'machine_evaluable')::boolean,false),coalesce(crt->>'status','active'),p_source_id,p_evidence_id,
          coalesce(nullif(crt->>'confidence','')::numeric,1.0),v_cycle_id,v_group_id
        ) on conflict(id) do update set
          criterion_type=excluded.criterion_type,operator=excluded.operator,value_text=excluded.value_text,
          value_number=excluded.value_number,value_codes=excluded.value_codes,value_json=excluded.value_json,
          human_text=excluded.human_text,is_mandatory=excluded.is_mandatory,machine_evaluable=excluded.machine_evaluable,
          status=excluded.status,source_id=excluded.source_id,evidence_id=excluded.evidence_id,confidence=excluded.confidence,
          cycle_id=excluded.cycle_id,criterion_group_id=excluded.criterion_group_id;
        v_criteria := v_criteria + 1;
      end loop;

      for tier in select value from jsonb_array_elements(coalesce(cyc->'award_tiers','[]'::jsonb))
      loop
        if nullif(btrim(tier->>'tier_code'),'') is null then raise exception 'tier_code required'; end if;
        insert into scholarship.award_tiers(
          id,scholarship_id,tier_code,label,amount,currency_code,percentage,basis,maximum_amount,notes,display_order,
          cycle_id,source_id,evidence_id
        ) values (
          scholarship.deterministic_uuid(v_stable_key || ':cycle:' || (cyc->>'cycle_code') || ':tier:' || (tier->>'tier_code')),
          v_scholarship_id,tier->>'tier_code',tier->>'label',nullif(tier->>'amount','')::numeric,tier->>'currency_code',
          nullif(tier->>'percentage','')::numeric,tier->>'basis',nullif(tier->>'maximum_amount','')::numeric,tier->>'notes',
          coalesce(nullif(tier->>'display_order','')::int,0),v_cycle_id,p_source_id,p_evidence_id
        ) on conflict(id) do update set
          label=excluded.label,amount=excluded.amount,currency_code=excluded.currency_code,percentage=excluded.percentage,
          basis=excluded.basis,maximum_amount=excluded.maximum_amount,notes=excluded.notes,display_order=excluded.display_order,
          cycle_id=excluded.cycle_id,source_id=excluded.source_id,evidence_id=excluded.evidence_id;
        v_tiers := v_tiers + 1;
      end loop;

      for cov in select value from jsonb_array_elements(coalesce(cyc->'coverage','[]'::jsonb))
      loop
        if nullif(btrim(cov->>'coverage_key'),'') is null then raise exception 'coverage_key required'; end if;
        insert into scholarship.coverage(
          id,scholarship_id,coverage_type,percentage,amount,currency_code,duration_value,duration_unit,notes,
          source_id,evidence_id,cycle_id
        ) values (
          scholarship.deterministic_uuid(v_stable_key || ':cycle:' || (cyc->>'cycle_code') || ':coverage:' || (cov->>'coverage_key')),
          v_scholarship_id,cov->>'coverage_type',nullif(cov->>'percentage','')::numeric,nullif(cov->>'amount','')::numeric,
          cov->>'currency_code',nullif(cov->>'duration_value','')::numeric,cov->>'duration_unit',cov->>'notes',
          p_source_id,p_evidence_id,v_cycle_id
        ) on conflict(id) do update set
          coverage_type=excluded.coverage_type,percentage=excluded.percentage,amount=excluded.amount,
          currency_code=excluded.currency_code,duration_value=excluded.duration_value,duration_unit=excluded.duration_unit,
          notes=excluded.notes,source_id=excluded.source_id,evidence_id=excluded.evidence_id,cycle_id=excluded.cycle_id;
        v_coverage := v_coverage + 1;
      end loop;
    end loop;

    v_changed := v_changed + 1;
  end loop;

  return jsonb_build_object(
    'mode',p_mode,'seen',v_seen,'changed',v_changed,'unmappedProviders',v_unmapped,
    'cycles',v_cycles,'windows',v_windows,'scopes',v_scopes,'criterionGroups',v_groups,
    'criteria',v_criteria,'awardTiers',v_tiers,'coverage',v_coverage
  );
end
$$;

revoke all on function public.svc_scholarship_apply_records(uuid,uuid,jsonb,text) from public, anon, authenticated;
grant execute on function public.svc_scholarship_apply_records(uuid,uuid,jsonb,text) to service_role;

create or replace function public.svc_scholarship_source_record(
  p_source_id uuid,
  p_source_record_id text,
  p_source_record_url text,
  p_source_provider_id text,
  p_source_provider_cricos text,
  p_source_provider_name text,
  p_content_hash text,
  p_evidence_id uuid,
  p_payload jsonb,
  p_status text default 'captured',
  p_error_text text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if auth.role() <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.scholarship_source_records(
    source_id,source_record_id,source_record_url,source_provider_id,source_provider_cricos,source_provider_name,
    content_hash,evidence_id,payload,status,error_text,observed_at,applied_at
  ) values (
    p_source_id,p_source_record_id,p_source_record_url,p_source_provider_id,p_source_provider_cricos,p_source_provider_name,
    p_content_hash,p_evidence_id,p_payload,p_status,p_error_text,now(),case when p_status='applied' then now() end
  )
  on conflict(source_id,source_record_id,content_hash) do update set
    evidence_id=excluded.evidence_id,payload=excluded.payload,source_record_url=excluded.source_record_url,
    source_provider_id=excluded.source_provider_id,source_provider_cricos=excluded.source_provider_cricos,
    source_provider_name=excluded.source_provider_name,status=excluded.status,error_text=excluded.error_text,
    observed_at=now(),applied_at=case when excluded.status='applied' then now() else pipeline.scholarship_source_records.applied_at end
  returning id into v_id;
  return v_id;
end
$$;

revoke all on function public.svc_scholarship_source_record(uuid,text,text,text,text,text,text,uuid,jsonb,text,text) from public, anon, authenticated;
grant execute on function public.svc_scholarship_source_record(uuid,text,text,text,text,text,text,uuid,jsonb,text,text) to service_role;

insert into pipeline.scholarship_source_qualifications(
  country_id,source_key,authority_name,source_url,source_class,identifier_scheme,stable_identifier_strategy,
  provider_mapping_strategy,cycle_strategy,evidence_strategy,qualification_status,notes,metadata
)
select c.id,'au_study_australia_scholarships','Australian Trade and Investment Commission (Study Australia)',
  'https://search.studyaustralia.gov.au/scholarships','government_catalogue','study_australia_scholarship_id',
  '32-hex source-local identifier in canonical scholarship detail URL',
  'Study Australia provider source key -> provider page CRICOS -> exact catalogue.provider_registrations(cricos)',
  'source record remains Scholarship; dated/recurring availability represented as offering cycles and application windows',
  'capture source HTML privately in evidence bucket with SHA-256 and pipeline.evidence_artifacts lineage',
  'qualified','Primary AU provider-scholarship discovery source. Name matching is prohibited for identity or provider resolution.',
  jsonb_build_object('layer','2A','identity_authority',false,'publication_after_gate',false)
from ref.countries c where c.iso_alpha2='AU'
on conflict(source_key) do update set updated_at=now(),qualification_status='qualified',notes=excluded.notes,metadata=excluded.metadata;

insert into pipeline.scholarship_source_qualifications(
  country_id,source_key,authority_name,source_url,source_class,identifier_scheme,stable_identifier_strategy,
  provider_mapping_strategy,cycle_strategy,evidence_strategy,qualification_status,notes,metadata
)
select c.id,'au_dfat_australia_awards','Department of Foreign Affairs and Trade',
  'https://www.dfat.gov.au/people-to-people/australia-awards','government_program','dfat_award_scheme',
  'DFAT/OASIS scheme code (AAS) is the enduring Scholarship identifier; intake year is an Offering Cycle',
  'program scope uses participating institutions/country profiles; no provider-name identity',
  'OASIS AAS 2027 -> Scholarship AAS + cycle 2027; country-specific dates become application windows',
  'capture official DFAT/OASIS HTML/PDF snapshots privately with SHA-256 and evidence lineage',
  'qualified','Used for compound eligibility, cycle/window and entitlement/coverage modelling.',
  jsonb_build_object('layer','2A','identity_authority',false,'handbook_version','June 2026')
from ref.countries c where c.iso_alpha2='AU'
on conflict(source_key) do update set updated_at=now(),qualification_status='qualified',notes=excluded.notes,metadata=excluded.metadata;

insert into pipeline.scholarship_source_qualifications(
  country_id,source_key,authority_name,source_url,source_class,identifier_scheme,stable_identifier_strategy,
  provider_mapping_strategy,cycle_strategy,evidence_strategy,qualification_status,notes,metadata
)
select c.id,'au_education_rtp','Australian Government Department of Education',
  'https://www.education.gov.au/research-block-grants/research-training-program','government_program','doi',
  'persistent government DOI 10.82133/C42F-K220 for RTP program identity',
  'provider applications are administered by eligible higher education providers; provider windows require first-party provider evidence',
  'central RTP is an enduring Scholarship/program; provider-specific rounds must be separate cycles/windows when sourced',
  'capture official Department pages and provider evidence before provider-specific facts are applied',
  'bounded','Qualified for program identity and coverage; bounded from central application-window ingestion because timing is provider-administered.',
  jsonb_build_object('layer','2A','identity_authority',false,'persistent_identifier','10.82133/C42F-K220')
from ref.countries c where c.iso_alpha2='AU'
on conflict(source_key) do update set updated_at=now(),qualification_status='bounded',notes=excluded.notes,metadata=excluded.metadata;
