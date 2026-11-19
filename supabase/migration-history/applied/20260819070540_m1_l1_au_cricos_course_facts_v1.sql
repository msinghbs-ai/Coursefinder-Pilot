alter table catalogue.course_fees
  add column if not exists source_snapshot_at timestamptz;

create index if not exists course_fees_source_snapshot_idx
  on catalogue.course_fees(source_id, source_snapshot_at)
  where source_id is not null;

comment on column catalogue.course_fees.source_snapshot_at is
  'Timestamp/version of the source snapshot that asserted this fee observation. Does not imply a fee year.';

create table if not exists catalogue.course_regulatory_observations (
  id uuid primary key default extensions.gen_random_uuid(),
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  scheme text not null,
  registration_code text not null,
  vet_national_code text,
  dual_qualification boolean,
  foundation_studies boolean,
  work_component boolean,
  work_component_hours_per_week numeric(12,2),
  work_component_weeks numeric(12,2),
  work_component_total_hours numeric(14,2),
  course_language text,
  source_id uuid not null references pipeline.sources(id) on delete restrict,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete restrict,
  source_snapshot_at timestamptz not null,
  content_hash text not null,
  status text not null default 'current'
    check (status in ('current','superseded','withdrawn')),
  valid_from timestamptz,
  valid_to timestamptz,
  observed_at timestamptz not null default now(),
  last_verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_regulatory_observations_snapshot_uq
    unique (course_id, source_id, scheme, registration_code, source_snapshot_at),
  constraint course_regulatory_observations_valid_range_ck
    check (valid_to is null or valid_from is null or valid_to >= valid_from)
);

create index if not exists course_regulatory_observations_current_idx
  on catalogue.course_regulatory_observations(course_id, source_id, scheme, status);

create index if not exists course_regulatory_observations_snapshot_idx
  on catalogue.course_regulatory_observations(source_id, source_snapshot_at);

create index if not exists course_regulatory_observations_evidence_idx
  on catalogue.course_regulatory_observations(evidence_id);

alter table catalogue.course_regulatory_observations enable row level security;

comment on table catalogue.course_regulatory_observations is
  'Time-scoped regulatory course facts asserted by an authoritative registration source. Rows preserve source snapshot and evidence; they do not redefine canonical Course identity.';
comment on column catalogue.course_regulatory_observations.vet_national_code is
  'VET National Code exactly as asserted by the regulatory source. Retained as an observation because it is not unique per Provider/Course identity in current CRICOS data.';
comment on column catalogue.course_regulatory_observations.course_language is
  'Course language exactly as asserted by the regulatory source; source vocabulary is preserved.';
comment on column catalogue.course_regulatory_observations.source_snapshot_at is
  'Source resource last-modified/version timestamp used for replay identity and observation history.';

create or replace function public.svc_layer1_apply_course_regulatory_facts(
  p_country_code text,
  p_source_id uuid,
  p_evidence_id uuid,
  p_registration_scheme text,
  p_source_snapshot_at timestamptz,
  p_records jsonb,
  p_apply boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, catalogue, ref, pipeline, extensions, pg_temp
as $function$
declare
  r jsonb;
  v_country uuid;
  v_provider uuid;
  v_course uuid;
  v_scheme text;
  v_pcode text;
  v_ccode text;
  v_snapshot_key text;

  v_vet text;
  v_dual boolean;
  v_foundation boolean;
  v_work boolean;
  v_work_hours numeric;
  v_work_weeks numeric;
  v_work_total numeric;
  v_language text;

  v_bool_raw text;
  v_num_raw text;
  v_invalid_boolean int := 0;
  v_invalid_number int := 0;
  v_invalid_fee int := 0;

  v_fact_hash text;
  v_existing_fact_id uuid;
  v_existing_fact_hash text;
  v_existing_fact_status text;

  v_field2_code text;
  v_field2_name text;
  v_field uuid;
  v_broad_field uuid;
  v_broad_code text;

  v_fee_type text;
  v_fee_raw text;
  v_fee_clean text;
  v_fee_key text;
  v_fee_id uuid;
  v_fee_amount numeric;
  v_existing_fee_amount numeric;
  v_existing_fee_status text;

  v_records int := 0;
  v_matched int := 0;
  v_course_missing int := 0;

  v_fact_created int := 0;
  v_fact_updated int := 0;
  v_fact_unchanged int := 0;
  v_fact_superseded int := 0;

  v_fee_created int := 0;
  v_fee_updated int := 0;
  v_fee_unchanged int := 0;
  v_fee_superseded int := 0;
  v_fee_observations int := 0;

  v_secondary_field_mapped int := 0;
  v_secondary_field_unmapped int := 0;
  v_rows int := 0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;

  v_scheme := lower(nullif(trim(p_registration_scheme),''));
  if v_scheme is null then raise exception 'registration scheme required'; end if;
  if p_source_id is null then raise exception 'source_id required'; end if;
  if p_evidence_id is null then raise exception 'evidence_id required'; end if;
  if p_source_snapshot_at is null then raise exception 'source_snapshot_at required'; end if;

  select id into v_country
  from ref.countries
  where upper(trim(iso_alpha2::text)) = upper(trim(p_country_code))
  limit 1;
  if v_country is null then raise exception 'country seed missing: %', p_country_code; end if;

  if not exists(select 1 from pipeline.sources where id=p_source_id) then
    raise exception 'source missing: %', p_source_id;
  end if;
  if not exists(select 1 from pipeline.evidence_artifacts where id=p_evidence_id and source_id=p_source_id) then
    raise exception 'evidence/source mismatch';
  end if;

  v_snapshot_key := to_char(p_source_snapshot_at at time zone 'UTC','YYYYMMDD"T"HH24MISS.US"Z"');

  for r in select value from jsonb_array_elements(coalesce(p_records,'[]'::jsonb))
  loop
    v_records := v_records + 1;
    v_provider := null;
    v_course := null;

    v_pcode := upper(nullif(trim(r->>'provider_code'),''));
    v_ccode := upper(nullif(trim(r->>'course_code'),''));
    if v_pcode is null or v_ccode is null then
      v_course_missing := v_course_missing + 1;
      continue;
    end if;

    select c.id, p.id
      into v_course, v_provider
    from catalogue.provider_registrations pr
    join catalogue.providers p
      on p.id=pr.provider_id and p.country_id=v_country
    join catalogue.courses c
      on c.provider_id=p.id
    join catalogue.course_registrations cr
      on cr.course_id=c.id
    where lower(pr.registration_scheme)=v_scheme
      and upper(pr.registration_code)=v_pcode
      and lower(cr.scheme)=v_scheme
      and upper(cr.registration_code)=v_ccode
      and (cr.country_id is null or cr.country_id=v_country)
    order by c.id
    limit 1;

    if v_course is null then
      v_course_missing := v_course_missing + 1;
      continue;
    end if;
    v_matched := v_matched + 1;

    v_vet := nullif(trim(r->>'vet_national_code'),'');
    v_language := nullif(trim(r->>'course_language'),'');

    v_bool_raw := lower(coalesce(nullif(trim(r->>'dual_qualification'),''),''));
    if v_bool_raw in ('yes','true','y','1') then v_dual := true;
    elsif v_bool_raw in ('no','false','n','0') then v_dual := false;
    else
      v_dual := null;
      if v_bool_raw <> '' then v_invalid_boolean := v_invalid_boolean + 1; end if;
    end if;

    v_bool_raw := lower(coalesce(nullif(trim(r->>'foundation_studies'),''),''));
    if v_bool_raw in ('yes','true','y','1') then v_foundation := true;
    elsif v_bool_raw in ('no','false','n','0') then v_foundation := false;
    else
      v_foundation := null;
      if v_bool_raw <> '' then v_invalid_boolean := v_invalid_boolean + 1; end if;
    end if;

    v_bool_raw := lower(coalesce(nullif(trim(r->>'work_component'),''),''));
    if v_bool_raw in ('yes','true','y','1') then v_work := true;
    elsif v_bool_raw in ('no','false','n','0') then v_work := false;
    else
      v_work := null;
      if v_bool_raw <> '' then v_invalid_boolean := v_invalid_boolean + 1; end if;
    end if;

    v_num_raw := nullif(trim(r->>'work_component_hours_per_week'),'');
    if v_num_raw is null then v_work_hours := null;
    elsif v_num_raw ~ '^[0-9]+(\.[0-9]+)?$' then v_work_hours := v_num_raw::numeric;
    else v_work_hours := null; v_invalid_number := v_invalid_number + 1;
    end if;

    v_num_raw := nullif(trim(r->>'work_component_weeks'),'');
    if v_num_raw is null then v_work_weeks := null;
    elsif v_num_raw ~ '^[0-9]+(\.[0-9]+)?$' then v_work_weeks := v_num_raw::numeric;
    else v_work_weeks := null; v_invalid_number := v_invalid_number + 1;
    end if;

    v_num_raw := nullif(trim(r->>'work_component_total_hours'),'');
    if v_num_raw is null then v_work_total := null;
    elsif v_num_raw ~ '^[0-9]+(\.[0-9]+)?$' then v_work_total := v_num_raw::numeric;
    else v_work_total := null; v_invalid_number := v_invalid_number + 1;
    end if;

    v_fact_hash := encode(extensions.digest(
      jsonb_build_object(
        'vet_national_code',v_vet,
        'dual_qualification',v_dual,
        'foundation_studies',v_foundation,
        'work_component',v_work,
        'work_component_hours_per_week',v_work_hours,
        'work_component_weeks',v_work_weeks,
        'work_component_total_hours',v_work_total,
        'course_language',v_language
      )::text,'sha256'),'hex');

    v_existing_fact_id := null;
    v_existing_fact_hash := null;
    v_existing_fact_status := null;
    select id,content_hash,status
      into v_existing_fact_id,v_existing_fact_hash,v_existing_fact_status
    from catalogue.course_regulatory_observations
    where course_id=v_course
      and source_id=p_source_id
      and scheme=v_scheme
      and registration_code=v_ccode
      and source_snapshot_at=p_source_snapshot_at
    limit 1;

    if v_existing_fact_id is null then
      v_fact_created := v_fact_created + 1;
    elsif v_existing_fact_hash is distinct from v_fact_hash or v_existing_fact_status <> 'current' then
      v_fact_updated := v_fact_updated + 1;
    else
      v_fact_unchanged := v_fact_unchanged + 1;
    end if;

    if p_apply then
      update catalogue.course_regulatory_observations
      set status='superseded',
          valid_to=p_source_snapshot_at,
          updated_at=now()
      where course_id=v_course
        and source_id=p_source_id
        and scheme=v_scheme
        and registration_code=v_ccode
        and source_snapshot_at<>p_source_snapshot_at
        and status='current';
      get diagnostics v_rows = row_count;
      v_fact_superseded := v_fact_superseded + v_rows;

      if v_existing_fact_id is null then
        insert into catalogue.course_regulatory_observations(
          course_id,scheme,registration_code,vet_national_code,
          dual_qualification,foundation_studies,work_component,
          work_component_hours_per_week,work_component_weeks,work_component_total_hours,
          course_language,source_id,evidence_id,source_snapshot_at,content_hash,
          status,valid_from,valid_to,observed_at,last_verified_at
        ) values (
          v_course,v_scheme,v_ccode,v_vet,
          v_dual,v_foundation,v_work,
          v_work_hours,v_work_weeks,v_work_total,
          v_language,p_source_id,p_evidence_id,p_source_snapshot_at,v_fact_hash,
          'current',p_source_snapshot_at,null,now(),now()
        );
      elsif v_existing_fact_hash is distinct from v_fact_hash or v_existing_fact_status <> 'current' then
        update catalogue.course_regulatory_observations
        set vet_national_code=v_vet,
            dual_qualification=v_dual,
            foundation_studies=v_foundation,
            work_component=v_work,
            work_component_hours_per_week=v_work_hours,
            work_component_weeks=v_work_weeks,
            work_component_total_hours=v_work_total,
            course_language=v_language,
            evidence_id=p_evidence_id,
            content_hash=v_fact_hash,
            status='current',
            valid_from=p_source_snapshot_at,
            valid_to=null,
            observed_at=now(),
            last_verified_at=now(),
            updated_at=now()
        where id=v_existing_fact_id;
      else
        update catalogue.course_regulatory_observations
        set last_verified_at=now()
        where id=v_existing_fact_id;
      end if;
    else
      select count(*) into v_rows
      from catalogue.course_regulatory_observations
      where course_id=v_course
        and source_id=p_source_id
        and scheme=v_scheme
        and registration_code=v_ccode
        and source_snapshot_at<>p_source_snapshot_at
        and status='current';
      v_fact_superseded := v_fact_superseded + v_rows;
    end if;

    v_field2_code := nullif(trim(r->>'secondary_field_code'),'');
    v_field2_name := nullif(trim(r->>'secondary_field_name'),'');
    if v_field2_code is not null or v_field2_name is not null then
      v_field := null;
      v_broad_field := null;
      if v_field2_code is not null and v_field2_name is not null and v_field2_code ~ '^[0-9]{4}$' then
        v_broad_code := left(v_field2_code,2);
        select id into v_broad_field from ref.fields_of_study where code='asced-'||v_broad_code limit 1;
        if v_broad_field is not null then
          v_secondary_field_mapped := v_secondary_field_mapped + 1;
          if p_apply then
            insert into ref.fields_of_study(code,name,parent_id,path,depth,status)
            values('asced-'||v_field2_code,v_field2_name,v_broad_field,'asced/'||v_broad_code||'/'||v_field2_code,1,'active')
            on conflict(code) do update
              set name=excluded.name,parent_id=excluded.parent_id,path=excluded.path,status='active',updated_at=now()
            returning id into v_field;

            insert into catalogue.course_field_observations(
              course_id,field_id,source_id,evidence_id,source_field_code,source_field_name,is_primary,status,observed_at,updated_at
            ) values (
              v_course,v_field,p_source_id,p_evidence_id,v_field2_code,v_field2_name,false,'current',now(),now()
            )
            on conflict(course_id,source_id,source_field_code) do update
              set field_id=excluded.field_id,
                  evidence_id=coalesce(excluded.evidence_id,catalogue.course_field_observations.evidence_id),
                  source_field_name=excluded.source_field_name,
                  is_primary=(catalogue.course_field_observations.is_primary or excluded.is_primary),
                  status='current',
                  observed_at=now(),
                  updated_at=now();
          end if;
        else
          v_secondary_field_unmapped := v_secondary_field_unmapped + 1;
        end if;
      else
        v_secondary_field_unmapped := v_secondary_field_unmapped + 1;
      end if;
    end if;

    for v_fee_type, v_fee_raw in
      select x.fee_type, x.raw_value
      from (values
        ('tuition'::text, nullif(trim(r->>'tuition_fee'),'')),
        ('non_tuition'::text, nullif(trim(r->>'non_tuition_fee'),'')),
        ('estimated_total_course_cost'::text, nullif(trim(r->>'estimated_total_course_cost'),''))
      ) as x(fee_type,raw_value)
    loop
      if p_apply then
        update catalogue.course_fees
        set status='superseded',
            valid_to=p_source_snapshot_at::date,
            updated_at=now()
        where course_id=v_course
          and source_id=p_source_id
          and fee_type=v_fee_type
          and basis='registered_total_course'
          and source_snapshot_at is distinct from p_source_snapshot_at
          and status='active';
        get diagnostics v_rows = row_count;
        v_fee_superseded := v_fee_superseded + v_rows;
      else
        select count(*) into v_rows
        from catalogue.course_fees
        where course_id=v_course
          and source_id=p_source_id
          and fee_type=v_fee_type
          and basis='registered_total_course'
          and source_snapshot_at is distinct from p_source_snapshot_at
          and status='active';
        v_fee_superseded := v_fee_superseded + v_rows;
      end if;

      if v_fee_raw is null then
        continue;
      end if;

      v_fee_clean := regexp_replace(v_fee_raw,'[^0-9.-]','','g');
      if v_fee_clean !~ '^-?[0-9]+(\.[0-9]+)?$' then
        v_invalid_fee := v_invalid_fee + 1;
        continue;
      end if;
      v_fee_amount := v_fee_clean::numeric;
      v_fee_observations := v_fee_observations + 1;
      v_fee_key := v_scheme||':'||lower(v_ccode)||':'||v_fee_type||':'||v_snapshot_key;

      v_fee_id := null;
      v_existing_fee_amount := null;
      v_existing_fee_status := null;
      select id,amount,status
        into v_fee_id,v_existing_fee_amount,v_existing_fee_status
      from catalogue.course_fees
      where course_id=v_course
        and source_id=p_source_id
        and source_fee_key=v_fee_key
      limit 1;

      if v_fee_id is null then
        v_fee_created := v_fee_created + 1;
      elsif v_existing_fee_amount is distinct from v_fee_amount or v_existing_fee_status <> 'active' then
        v_fee_updated := v_fee_updated + 1;
      else
        v_fee_unchanged := v_fee_unchanged + 1;
      end if;

      if p_apply then
        if v_fee_id is null then
          insert into catalogue.course_fees(
            course_id,fee_year,audience,fee_type,amount,currency_code,basis,
            notes,valid_from,valid_to,source_id,evidence_id,confidence,
            source_fee_key,status,last_verified_at,source_snapshot_at
          ) values (
            v_course,null,'international',v_fee_type,v_fee_amount,'AUD','registered_total_course',
            'CRICOS registered total-course amount; source value='||v_fee_raw||'; not annualised.',
            p_source_snapshot_at::date,null,p_source_id,p_evidence_id,1.0,
            v_fee_key,'active',now(),p_source_snapshot_at
          );
        elsif v_existing_fee_amount is distinct from v_fee_amount or v_existing_fee_status <> 'active' then
          update catalogue.course_fees
          set amount=v_fee_amount,
              currency_code='AUD',
              audience='international',
              fee_year=null,
              basis='registered_total_course',
              notes='CRICOS registered total-course amount; source value='||v_fee_raw||'; not annualised.',
              valid_from=p_source_snapshot_at::date,
              valid_to=null,
              evidence_id=p_evidence_id,
              confidence=1.0,
              status='active',
              last_verified_at=now(),
              source_snapshot_at=p_source_snapshot_at,
              updated_at=now()
          where id=v_fee_id;
        else
          update catalogue.course_fees
          set last_verified_at=now()
          where id=v_fee_id;
        end if;
      end if;
    end loop;
  end loop;

  return jsonb_build_object(
    'apply',p_apply,
    'records',v_records,
    'matched',v_matched,
    'course_missing',v_course_missing,
    'fact_created',v_fact_created,
    'fact_updated',v_fact_updated,
    'fact_unchanged',v_fact_unchanged,
    'fact_superseded',v_fact_superseded,
    'fee_observations',v_fee_observations,
    'fee_created',v_fee_created,
    'fee_updated',v_fee_updated,
    'fee_unchanged',v_fee_unchanged,
    'fee_superseded',v_fee_superseded,
    'secondary_field_mapped',v_secondary_field_mapped,
    'secondary_field_unmapped',v_secondary_field_unmapped,
    'invalid_boolean_values',v_invalid_boolean,
    'invalid_numeric_values',v_invalid_number,
    'invalid_fee_values',v_invalid_fee,
    'source_snapshot_at',p_source_snapshot_at
  );
end
$function$;

revoke all on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) from public;
revoke all on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) from anon;
revoke all on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) from authenticated;
grant execute on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) to service_role;

create or replace function public.svc_layer1_au_cricos_facts_stats()
returns jsonb
language sql
stable
security definer
set search_path = public, catalogue, ref, pipeline
as $function$
  select jsonb_build_object(
    'providers',(
      select count(distinct p.id)
      from catalogue.providers p
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU'
    ),
    'courses',(
      select count(*)
      from catalogue.courses c
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and c.lifecycle_status='active'
    ),
    'current_regulatory_fact_rows',(
      select count(*)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
    ),
    'fact_courses',(
      select count(distinct o.course_id)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
    ),
    'with_vet_national_code',(
      select count(*)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
        and o.vet_national_code is not null
    ),
    'with_dual_qualification',(
      select count(*)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
        and o.dual_qualification is not null
    ),
    'with_foundation_studies',(
      select count(*)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
        and o.foundation_studies is not null
    ),
    'with_work_component',(
      select count(*)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
        and o.work_component is not null
    ),
    'with_work_hours_per_week',(
      select count(*)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
        and o.work_component_hours_per_week is not null
    ),
    'with_work_weeks',(
      select count(*)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
        and o.work_component_weeks is not null
    ),
    'with_work_total_hours',(
      select count(*)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
        and o.work_component_total_hours is not null
    ),
    'with_course_language',(
      select count(*)
      from catalogue.course_regulatory_observations o
      join catalogue.courses c on c.id=o.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU' and lower(o.scheme)='cricos' and o.status='current'
        and o.course_language is not null
    ),
    'active_fee_rows',(
      select count(*)
      from catalogue.course_fees f
      join catalogue.courses c on c.id=f.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU'
        and f.status='active' and f.basis='registered_total_course'
    ),
    'with_cricos_registered_tuition',(
      select count(distinct f.course_id)
      from catalogue.course_fees f
      join catalogue.courses c on c.id=f.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU'
        and f.status='active' and f.basis='registered_total_course' and f.fee_type='tuition'
    ),
    'with_cricos_registered_non_tuition',(
      select count(distinct f.course_id)
      from catalogue.course_fees f
      join catalogue.courses c on c.id=f.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU'
        and f.status='active' and f.basis='registered_total_course' and f.fee_type='non_tuition'
    ),
    'with_cricos_estimated_total_cost',(
      select count(distinct f.course_id)
      from catalogue.course_fees f
      join catalogue.courses c on c.id=f.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU'
        and f.status='active' and f.basis='registered_total_course' and f.fee_type='estimated_total_course_cost'
    ),
    'with_current_provider_fee',(
      select count(distinct f.course_id)
      from catalogue.course_fees f
      join catalogue.courses c on c.id=f.course_id
      join catalogue.providers p on p.id=c.provider_id
      join ref.countries co on co.id=p.country_id
      where trim(co.iso_alpha2::text)='AU'
        and f.status='active'
        and coalesce(f.basis,'') <> 'registered_total_course'
        and f.fee_year is not null
    )
  );
$function$;

revoke all on function public.svc_layer1_au_cricos_facts_stats() from public;
revoke all on function public.svc_layer1_au_cricos_facts_stats() from anon;
revoke all on function public.svc_layer1_au_cricos_facts_stats() from authenticated;
grant execute on function public.svc_layer1_au_cricos_facts_stats() to service_role;
