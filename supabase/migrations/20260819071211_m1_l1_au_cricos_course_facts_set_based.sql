-- Set-based AU CRICOS facts reconciliation.
-- The RPC is service-role only and never writes Search.

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
  v_country uuid;
  v_scheme text;
  v_snapshot_key text;
  v_records int := 0;
  v_matched int := 0;
  v_course_missing int := 0;
  v_fact_created int := 0;
  v_fact_updated int := 0;
  v_fact_unchanged int := 0;
  v_fact_superseded int := 0;
  v_fee_observations int := 0;
  v_fee_created int := 0;
  v_fee_updated int := 0;
  v_fee_unchanged int := 0;
  v_fee_superseded int := 0;
  v_secondary_field_mapped int := 0;
  v_secondary_field_unmapped int := 0;
  v_invalid_boolean int := 0;
  v_invalid_number int := 0;
  v_invalid_fee int := 0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'service_role required';
  end if;
  v_scheme := lower(nullif(trim(p_registration_scheme),''));
  if v_scheme is null then raise exception 'registration scheme required'; end if;
  if p_source_id is null then raise exception 'source_id required'; end if;
  if p_evidence_id is null then raise exception 'evidence_id required'; end if;
  if p_source_snapshot_at is null then raise exception 'source_snapshot_at required'; end if;

  select id into v_country from ref.countries
  where upper(trim(iso_alpha2::text))=upper(trim(p_country_code)) limit 1;
  if v_country is null then raise exception 'country seed missing: %',p_country_code; end if;
  if not exists(select 1 from pipeline.sources where id=p_source_id) then raise exception 'source missing: %',p_source_id; end if;
  if not exists(select 1 from pipeline.evidence_artifacts where id=p_evidence_id and source_id=p_source_id) then raise exception 'evidence/source mismatch'; end if;

  v_snapshot_key := to_char(p_source_snapshot_at at time zone 'UTC','YYYYMMDD"T"HH24MISS.US"Z"');

  drop table if exists pg_temp.cf_cricos_fact_raw;
  drop table if exists pg_temp.cf_cricos_fact_resolved;
  drop table if exists pg_temp.cf_cricos_fee_grid;

  create temp table cf_cricos_fact_raw on commit drop as
  select
    ord::int as ord,
    upper(nullif(trim(value->>'provider_code'),'')) as provider_code,
    upper(nullif(trim(value->>'course_code'),'')) as course_code,
    nullif(trim(value->>'vet_national_code'),'') as vet_national_code,
    nullif(trim(value->>'dual_qualification'),'') as dual_raw,
    nullif(trim(value->>'foundation_studies'),'') as foundation_raw,
    nullif(trim(value->>'work_component'),'') as work_raw,
    nullif(trim(value->>'work_component_hours_per_week'),'') as work_hours_raw,
    nullif(trim(value->>'work_component_weeks'),'') as work_weeks_raw,
    nullif(trim(value->>'work_component_total_hours'),'') as work_total_raw,
    nullif(trim(value->>'course_language'),'') as course_language,
    nullif(trim(value->>'secondary_field_code'),'') as secondary_field_code,
    nullif(trim(value->>'secondary_field_name'),'') as secondary_field_name,
    nullif(trim(value->>'tuition_fee'),'') as tuition_raw,
    nullif(trim(value->>'non_tuition_fee'),'') as non_tuition_raw,
    nullif(trim(value->>'estimated_total_course_cost'),'') as total_cost_raw
  from jsonb_array_elements(coalesce(p_records,'[]'::jsonb)) with ordinality as x(value,ord);

  create temp table cf_cricos_fact_resolved on commit drop as
  select
    i.*,
    p.id as provider_id,
    c.id as course_id,
    case lower(coalesce(i.dual_raw,''))
      when 'yes' then true when 'true' then true when 'y' then true when '1' then true
      when 'no' then false when 'false' then false when 'n' then false when '0' then false else null end as dual_qualification,
    case lower(coalesce(i.foundation_raw,''))
      when 'yes' then true when 'true' then true when 'y' then true when '1' then true
      when 'no' then false when 'false' then false when 'n' then false when '0' then false else null end as foundation_studies,
    case lower(coalesce(i.work_raw,''))
      when 'yes' then true when 'true' then true when 'y' then true when '1' then true
      when 'no' then false when 'false' then false when 'n' then false when '0' then false else null end as work_component,
    case when i.work_hours_raw ~ '^[0-9]+(\.[0-9]+)?$' then i.work_hours_raw::numeric end as work_component_hours_per_week,
    case when i.work_weeks_raw ~ '^[0-9]+(\.[0-9]+)?$' then i.work_weeks_raw::numeric end as work_component_weeks,
    case when i.work_total_raw ~ '^[0-9]+(\.[0-9]+)?$' then i.work_total_raw::numeric end as work_component_total_hours
  from cf_cricos_fact_raw i
  left join catalogue.provider_registrations pr
    on lower(pr.registration_scheme)=v_scheme and upper(pr.registration_code)=i.provider_code
  left join catalogue.providers p
    on p.id=pr.provider_id and p.country_id=v_country
  left join catalogue.course_registrations cr
    on lower(cr.scheme)=v_scheme and upper(cr.registration_code)=i.course_code
    and (cr.country_id is null or cr.country_id=v_country)
  left join catalogue.courses c
    on c.id=cr.course_id and c.provider_id=p.id;

  alter table cf_cricos_fact_resolved add column fact_hash text;
  update cf_cricos_fact_resolved r
  set fact_hash=encode(extensions.digest(jsonb_build_object(
    'vet_national_code',r.vet_national_code,
    'dual_qualification',r.dual_qualification,
    'foundation_studies',r.foundation_studies,
    'work_component',r.work_component,
    'work_component_hours_per_week',r.work_component_hours_per_week,
    'work_component_weeks',r.work_component_weeks,
    'work_component_total_hours',r.work_component_total_hours,
    'course_language',r.course_language
  )::text,'sha256'),'hex');

  select count(*),count(*) filter(where course_id is not null),count(*) filter(where course_id is null)
  into v_records,v_matched,v_course_missing from cf_cricos_fact_resolved;

  select
    count(*) filter(where dual_raw is not null and lower(dual_raw) not in ('yes','true','y','1','no','false','n','0')) +
    count(*) filter(where foundation_raw is not null and lower(foundation_raw) not in ('yes','true','y','1','no','false','n','0')) +
    count(*) filter(where work_raw is not null and lower(work_raw) not in ('yes','true','y','1','no','false','n','0')),
    count(*) filter(where work_hours_raw is not null and work_hours_raw !~ '^[0-9]+(\.[0-9]+)?$') +
    count(*) filter(where work_weeks_raw is not null and work_weeks_raw !~ '^[0-9]+(\.[0-9]+)?$') +
    count(*) filter(where work_total_raw is not null and work_total_raw !~ '^[0-9]+(\.[0-9]+)?$')
  into v_invalid_boolean,v_invalid_number
  from cf_cricos_fact_resolved;

  select
    count(*) filter(where o.id is null),
    count(*) filter(where o.id is not null and (o.content_hash is distinct from r.fact_hash or o.status<>'current')),
    count(*) filter(where o.id is not null and o.content_hash is not distinct from r.fact_hash and o.status='current')
  into v_fact_created,v_fact_updated,v_fact_unchanged
  from cf_cricos_fact_resolved r
  left join catalogue.course_regulatory_observations o
    on o.course_id=r.course_id and o.source_id=p_source_id and o.scheme=v_scheme
    and o.registration_code=r.course_code and o.source_snapshot_at=p_source_snapshot_at
  where r.course_id is not null;

  select count(*) into v_fact_superseded
  from catalogue.course_regulatory_observations o
  join cf_cricos_fact_resolved r on r.course_id=o.course_id and r.course_code=o.registration_code
  where r.course_id is not null and o.source_id=p_source_id and o.scheme=v_scheme
    and o.source_snapshot_at<>p_source_snapshot_at and o.status='current';

  select
    count(*) filter(where (r.secondary_field_code is not null or r.secondary_field_name is not null)
      and r.secondary_field_code ~ '^[0-9]{4}$' and r.secondary_field_name is not null and b.id is not null),
    count(*) filter(where (r.secondary_field_code is not null or r.secondary_field_name is not null)
      and not (r.secondary_field_code ~ '^[0-9]{4}$' and r.secondary_field_name is not null and b.id is not null))
  into v_secondary_field_mapped,v_secondary_field_unmapped
  from cf_cricos_fact_resolved r
  left join ref.fields_of_study b on b.code='asced-'||left(r.secondary_field_code,2)
  where r.course_id is not null;

  create temp table cf_cricos_fee_grid on commit drop as
  select
    r.course_id,r.course_code,x.fee_type,x.raw_value,
    regexp_replace(coalesce(x.raw_value,''),'[^0-9.-]','','g') as clean_value,
    case when x.raw_value is null then true
      when regexp_replace(x.raw_value,'[^0-9.-]','','g') ~ '^-?[0-9]+(\.[0-9]+)?$' then true
      else false end as is_valid,
    case when x.raw_value is not null and regexp_replace(x.raw_value,'[^0-9.-]','','g') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then regexp_replace(x.raw_value,'[^0-9.-]','','g')::numeric else null end as amount,
    v_scheme||':'||lower(r.course_code)||':'||x.fee_type||':'||v_snapshot_key as source_fee_key
  from cf_cricos_fact_resolved r
  cross join lateral (values
    ('tuition'::text,r.tuition_raw),
    ('non_tuition'::text,r.non_tuition_raw),
    ('estimated_total_course_cost'::text,r.total_cost_raw)
  ) x(fee_type,raw_value)
  where r.course_id is not null;

  select count(*) filter(where raw_value is not null and is_valid),
         count(*) filter(where raw_value is not null and not is_valid)
  into v_fee_observations,v_invalid_fee from cf_cricos_fee_grid;

  select
    count(*) filter(where f.id is null),
    count(*) filter(where f.id is not null and (f.amount is distinct from g.amount or f.status<>'active')),
    count(*) filter(where f.id is not null and f.amount is not distinct from g.amount and f.status='active')
  into v_fee_created,v_fee_updated,v_fee_unchanged
  from cf_cricos_fee_grid g
  left join catalogue.course_fees f
    on f.course_id=g.course_id and f.source_id=p_source_id and f.source_fee_key=g.source_fee_key
  where g.raw_value is not null and g.is_valid;

  select count(distinct f.id) into v_fee_superseded
  from catalogue.course_fees f
  join cf_cricos_fee_grid g on g.course_id=f.course_id and g.fee_type=f.fee_type
  where f.source_id=p_source_id and f.basis='registered_total_course'
    and f.source_snapshot_at is distinct from p_source_snapshot_at and f.status='active';

  if p_apply then
    update catalogue.course_regulatory_observations o
    set status='superseded',valid_to=p_source_snapshot_at,updated_at=now()
    from cf_cricos_fact_resolved r
    where r.course_id=o.course_id and r.course_code=o.registration_code
      and r.course_id is not null and o.source_id=p_source_id and o.scheme=v_scheme
      and o.source_snapshot_at<>p_source_snapshot_at and o.status='current';

    insert into catalogue.course_regulatory_observations(
      course_id,scheme,registration_code,vet_national_code,dual_qualification,foundation_studies,
      work_component,work_component_hours_per_week,work_component_weeks,work_component_total_hours,
      course_language,source_id,evidence_id,source_snapshot_at,content_hash,status,valid_from,valid_to,
      observed_at,last_verified_at
    )
    select
      r.course_id,v_scheme,r.course_code,r.vet_national_code,r.dual_qualification,r.foundation_studies,
      r.work_component,r.work_component_hours_per_week,r.work_component_weeks,r.work_component_total_hours,
      r.course_language,p_source_id,p_evidence_id,p_source_snapshot_at,r.fact_hash,'current',p_source_snapshot_at,null,
      now(),now()
    from cf_cricos_fact_resolved r where r.course_id is not null
    on conflict on constraint course_regulatory_observations_snapshot_uq do update
      set vet_national_code=excluded.vet_national_code,
          dual_qualification=excluded.dual_qualification,
          foundation_studies=excluded.foundation_studies,
          work_component=excluded.work_component,
          work_component_hours_per_week=excluded.work_component_hours_per_week,
          work_component_weeks=excluded.work_component_weeks,
          work_component_total_hours=excluded.work_component_total_hours,
          course_language=excluded.course_language,
          evidence_id=excluded.evidence_id,
          content_hash=excluded.content_hash,
          status='current',valid_from=excluded.valid_from,valid_to=null,
          observed_at=now(),last_verified_at=now(),updated_at=now();

    insert into ref.fields_of_study(code,name,parent_id,path,depth,status)
    select distinct 'asced-'||r.secondary_field_code,r.secondary_field_name,b.id,
      'asced/'||left(r.secondary_field_code,2)||'/'||r.secondary_field_code,1,'active'
    from cf_cricos_fact_resolved r
    join ref.fields_of_study b on b.code='asced-'||left(r.secondary_field_code,2)
    where r.course_id is not null and r.secondary_field_code ~ '^[0-9]{4}$' and r.secondary_field_name is not null
    on conflict(code) do update set name=excluded.name,parent_id=excluded.parent_id,path=excluded.path,status='active',updated_at=now();

    insert into catalogue.course_field_observations(
      course_id,field_id,source_id,evidence_id,source_field_code,source_field_name,is_primary,status,observed_at,updated_at
    )
    select r.course_id,f.id,p_source_id,p_evidence_id,r.secondary_field_code,r.secondary_field_name,false,'current',now(),now()
    from cf_cricos_fact_resolved r
    join ref.fields_of_study f on f.code='asced-'||r.secondary_field_code
    where r.course_id is not null and r.secondary_field_code ~ '^[0-9]{4}$' and r.secondary_field_name is not null
    on conflict(course_id,source_id,source_field_code) do update
      set field_id=excluded.field_id,evidence_id=excluded.evidence_id,source_field_name=excluded.source_field_name,
          is_primary=(catalogue.course_field_observations.is_primary or excluded.is_primary),status='current',observed_at=now(),updated_at=now();

    update catalogue.course_fees f
    set status='superseded',valid_to=p_source_snapshot_at::date,updated_at=now()
    from cf_cricos_fee_grid g
    where g.course_id=f.course_id and g.fee_type=f.fee_type
      and f.source_id=p_source_id and f.basis='registered_total_course'
      and f.source_snapshot_at is distinct from p_source_snapshot_at and f.status='active';

    insert into catalogue.course_fees(
      course_id,fee_year,audience,fee_type,amount,currency_code,basis,notes,valid_from,valid_to,
      source_id,evidence_id,confidence,source_fee_key,status,last_verified_at,source_snapshot_at
    )
    select
      g.course_id,null,'international',g.fee_type,g.amount,'AUD','registered_total_course',
      'CRICOS registered total-course amount; source value='||g.raw_value||'; not annualised.',
      p_source_snapshot_at::date,null,p_source_id,p_evidence_id,1.0,g.source_fee_key,'active',now(),p_source_snapshot_at
    from cf_cricos_fee_grid g
    where g.raw_value is not null and g.is_valid
    on conflict (course_id,source_id,source_fee_key)
      where source_id is not null and source_fee_key is not null
    do update set amount=excluded.amount,currency_code='AUD',audience='international',fee_year=null,
      basis='registered_total_course',notes=excluded.notes,valid_from=excluded.valid_from,valid_to=null,
      evidence_id=excluded.evidence_id,confidence=1.0,status='active',last_verified_at=now(),
      source_snapshot_at=excluded.source_snapshot_at,updated_at=now();
  end if;

  return jsonb_build_object(
    'apply',p_apply,'records',v_records,'matched',v_matched,'course_missing',v_course_missing,
    'fact_created',v_fact_created,'fact_updated',v_fact_updated,'fact_unchanged',v_fact_unchanged,'fact_superseded',v_fact_superseded,
    'fee_observations',v_fee_observations,'fee_created',v_fee_created,'fee_updated',v_fee_updated,'fee_unchanged',v_fee_unchanged,'fee_superseded',v_fee_superseded,
    'secondary_field_mapped',v_secondary_field_mapped,'secondary_field_unmapped',v_secondary_field_unmapped,
    'invalid_boolean_values',v_invalid_boolean,'invalid_numeric_values',v_invalid_number,'invalid_fee_values',v_invalid_fee,
    'source_snapshot_at',p_source_snapshot_at
  );
end
$function$;

revoke all on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) from public;
revoke all on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) from anon;
revoke all on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) from authenticated;
grant execute on function public.svc_layer1_apply_course_regulatory_facts(text,uuid,uuid,text,timestamptz,jsonb,boolean) to service_role;
