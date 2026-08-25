-- CF-CHG-20260825-038
-- Preserve exact source date precision without manufacturing unsupported clock times.

alter table pipeline.important_dates
  add column if not exists starts_on date,
  add column if not exists ends_on date;

alter table pipeline.important_dates drop constraint if exists important_dates_check;
alter table pipeline.important_dates
  add constraint important_dates_exact_source_value_check
  check (date_precision <> 'exact' or starts_at is not null or starts_on is not null);

create or replace function security.important_date_upsert_v2_impl(
  p_id uuid,
  p_country_code text,
  p_event_type text,
  p_title text,
  p_source_url text,
  p_evidence_id uuid,
  p_scope_type text,
  p_source_id uuid,
  p_source_profile_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_date_precision text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_starts_on date,
  p_ends_on date,
  p_timezone text,
  p_source_wording text,
  p_warning_days integer,
  p_expires_at timestamptz,
  p_refresh_layer smallint
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
declare v_id uuid:=coalesce(p_id,gen_random_uuid());
begin
  if auth.uid() is null or security.current_role_rank()<3 then
    raise exception 'curator role required' using errcode='42501';
  end if;
  if p_warning_days not between 0 and 365 then raise exception 'warning days must be 0..365'; end if;
  if p_date_precision='exact' and p_starts_at is null and p_starts_on is null then
    raise exception 'exact dates require a sourced date or timestamp';
  end if;
  if p_starts_at is not null and p_starts_on is not null then
    raise exception 'store either a sourced timestamp or a sourced date, not both';
  end if;
  if p_ends_at is not null and p_ends_on is not null then
    raise exception 'store either a sourced end timestamp or a sourced end date, not both';
  end if;
  if p_date_precision='source_vague' and nullif(trim(coalesce(p_source_wording,'')),'') is null then
    raise exception 'vague source wording must be retained';
  end if;
  if p_refresh_layer is not null and p_source_id is null and p_source_profile_id is null and p_entity_id is null then
    raise exception 'a refresh-capable Important Date requires a bounded source or entity target';
  end if;

  insert into pipeline.important_dates(
    id,country_code,event_type,title,source_url,evidence_id,scope_type,source_id,source_profile_id,
    entity_type,entity_id,date_precision,starts_at,ends_at,starts_on,ends_on,timezone,source_wording,
    warning_window,expires_at,status,refresh_layer,change_control_ref,created_by,updated_by
  ) values (
    v_id,upper(p_country_code),p_event_type,trim(p_title),trim(p_source_url),p_evidence_id,p_scope_type,
    p_source_id,p_source_profile_id,p_entity_type,p_entity_id,p_date_precision,p_starts_at,p_ends_at,
    p_starts_on,p_ends_on,p_timezone,p_source_wording,make_interval(days=>p_warning_days),p_expires_at,
    'active',p_refresh_layer,'CF-CHG-20260825-038',auth.uid(),auth.uid()
  )
  on conflict(id) do update set
    country_code=excluded.country_code,event_type=excluded.event_type,title=excluded.title,
    source_url=excluded.source_url,evidence_id=excluded.evidence_id,scope_type=excluded.scope_type,
    source_id=excluded.source_id,source_profile_id=excluded.source_profile_id,entity_type=excluded.entity_type,
    entity_id=excluded.entity_id,date_precision=excluded.date_precision,starts_at=excluded.starts_at,
    ends_at=excluded.ends_at,starts_on=excluded.starts_on,ends_on=excluded.ends_on,timezone=excluded.timezone,
    source_wording=excluded.source_wording,warning_window=excluded.warning_window,expires_at=excluded.expires_at,
    refresh_layer=excluded.refresh_layer,updated_by=auth.uid(),updated_at=now();
  return v_id;
end $$;

revoke all on function security.important_date_upsert_v2_impl(
  uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint
) from public, anon, authenticated;
grant execute on function security.important_date_upsert_v2_impl(
  uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint
) to service_role;

create or replace function public.important_date_upsert_v2(
  p_id uuid,
  p_country_code text,
  p_event_type text,
  p_title text,
  p_source_url text,
  p_evidence_id uuid,
  p_scope_type text,
  p_source_id uuid,
  p_source_profile_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_date_precision text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_starts_on date,
  p_ends_on date,
  p_timezone text,
  p_source_wording text,
  p_warning_days integer,
  p_expires_at timestamptz,
  p_refresh_layer smallint
) returns uuid
language sql
set search_path = pg_catalog, security
as $$
  select security.important_date_upsert_v2_impl(
    p_id,p_country_code,p_event_type,p_title,p_source_url,p_evidence_id,p_scope_type,p_source_id,
    p_source_profile_id,p_entity_type,p_entity_id,p_date_precision,p_starts_at,p_ends_at,p_starts_on,
    p_ends_on,p_timezone,p_source_wording,p_warning_days,p_expires_at,p_refresh_layer
  )
$$;
revoke all on function public.important_date_upsert_v2(
  uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint
) from public, anon;
grant execute on function public.important_date_upsert_v2(
  uuid,text,text,text,text,uuid,text,uuid,uuid,text,uuid,text,timestamptz,timestamptz,date,date,text,text,integer,timestamptz,smallint
) to authenticated, service_role;

create or replace function security.important_dates_ticker_impl(p_country_code text default null, p_days integer default 60)
returns jsonb
language plpgsql
stable security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
begin
  if auth.uid() is null or security.current_role_rank()<2 then
    raise exception 'authenticated operator role required' using errcode='42501';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.operational_start nulls last,x.title)
    from (
      select id,country_code,event_type,title,source_url,evidence_id,scope_type,source_id,
             source_profile_id,entity_type,entity_id,date_precision,starts_at,ends_at,starts_on,ends_on,
             timezone,source_wording,warning_window,expires_at,status,refresh_layer,change_control_ref,
             coalesce(starts_at, case when starts_on is null then null
               else starts_on::timestamp at time zone coalesce(nullif(timezone,''),'UTC') end) as operational_start
      from pipeline.important_dates
      where status='active'
        and (p_country_code is null or country_code=upper(p_country_code))
        and (
          starts_at is null and starts_on is null
          or coalesce(starts_at, starts_on::timestamp at time zone coalesce(nullif(timezone,''),'UTC'))
             <= now()+make_interval(days=>least(greatest(p_days,1),365))
        )
    ) x
  ),'[]'::jsonb);
end $$;

create or replace function security.refresh_scheduler_tick_impl(
  p_now timestamptz default now(), p_limit integer default 100
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, security, pipeline
as $$
declare v_policy_count int:=0; v_date_count int:=0; v_l3_count int:=0; v_expired_dates int:=0;
begin
  with due as (
    select p.*
    from pipeline.refresh_policies p
    where p.enabled
      and p.layer in (1,2,3)
      and p.freshness_class <> 'event-driven'
      and p.cadence_interval is not null
      and p.next_due_at is not null
      and p.next_due_at <= p_now
    order by p.next_due_at
    limit least(greatest(p_limit,1),500)
    for update skip locked
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,
      reason,trigger_type,requested_by,change_control_ref
    )
    select d.layer,d.country_code,d.source_id,d.source_profile_id,d.entity_type,d.entity_id,
           'Governed '||d.freshness_class||' freshness policy due','freshness_expired',null,d.change_control_ref
    from due d
    where not exists (
      select 1 from pipeline.refresh_requests r
      where r.status in ('queued','running')
        and r.requested_layer=d.layer
        and r.source_id is not distinct from d.source_id
        and r.source_profile_id is not distinct from d.source_profile_id
        and r.entity_id is not distinct from d.entity_id
    )
    returning 1
  ), adv as (
    update pipeline.refresh_policies p
    set next_due_at = greatest(p.next_due_at,p_now) + p.cadence_interval, updated_at=p_now
    where p.id in (select id from due)
    returning 1
  )
  select count(*) into v_policy_count from ins;

  with target_dates as (
    select d.*,
      coalesce(d.starts_at, case when d.starts_on is null then null
        else d.starts_on::timestamp at time zone coalesce(nullif(d.timezone,''),'UTC') end) as operational_start,
      coalesce(d.ends_at, case when d.ends_on is null then null
        else (d.ends_on + 1)::timestamp at time zone coalesce(nullif(d.timezone,''),'UTC') end) as operational_end
    from pipeline.important_dates d
    where d.status='active'
      and d.refresh_layer is not null
      and (d.starts_at is not null or d.starts_on is not null)
      and (d.source_id is not null or d.source_profile_id is not null or d.entity_id is not null)
  ), due_dates as (
    select *
    from target_dates d
    where d.operational_start - d.warning_window <= p_now
      and (d.operational_end is null or d.operational_end >= p_now)
    order by d.operational_start
    limit least(greatest(p_limit,1),500)
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,
      reason,trigger_type,important_date_id,requested_by,change_control_ref
    )
    select d.refresh_layer,d.country_code,d.source_id,d.source_profile_id,d.entity_type,d.entity_id,
           'Important Date warning window: '||d.title,'important_date',d.id,null,d.change_control_ref
    from due_dates d
    where not exists (
      select 1 from pipeline.refresh_requests r
      where r.important_date_id=d.id and r.status in ('queued','running','completed')
    )
    returning 1
  )
  select count(*) into v_date_count from ins;

  with expired as (
    select i.*
    from pipeline.layer3_interpretations i
    where i.status in ('validated','no_candidate')
      and i.interpretation_expires_at is not null
      and i.interpretation_expires_at <= p_now
    order by i.interpretation_expires_at
    limit least(greatest(p_limit,1),500)
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,entity_type,entity_id,evidence_id,layer3_profile_id,revalidation_ref,
      reason,trigger_type,requested_by,change_control_ref
    )
    select 3,i.entity_type,i.entity_id,i.evidence_id,i.profile_id,'EXPIRY:'||i.id::text,
           'Layer 3 interpretation freshness expired','freshness_expired',null,i.change_control_ref
    from expired i
    where not exists (
      select 1 from pipeline.refresh_requests r
      where r.requested_layer=3 and r.evidence_id=i.evidence_id and r.layer3_profile_id=i.profile_id
        and r.status in ('queued','running')
    )
    returning 1
  )
  select count(*) into v_l3_count from ins;

  update pipeline.important_dates
  set status='expired',updated_at=p_now
  where status='active' and expires_at is not null and expires_at<=p_now;
  get diagnostics v_expired_dates = row_count;

  return jsonb_build_object(
    'ok',true,'policy_requests_created',v_policy_count,'important_date_requests_created',v_date_count,
    'layer3_expiry_requests_created',v_l3_count,'important_dates_expired',v_expired_dates,'at',p_now
  );
end $$;

-- Verification outcomes are operational health observations, not proof of semantic authority.
update pipeline.important_links l
set health_status = case
      when l.url='https://www.educationcounts.govt.nz/directories/list-of-tertiary-providers' then 'degraded'
      else 'healthy'
    end,
    last_verified_at=now(),
    next_verification_at=now()+l.verification_cadence,
    updated_at=now()
where l.change_control_ref='CF-CHG-20260825-038';

-- Exact source day, no fabricated clock time.
insert into pipeline.important_dates(
  country_code,event_type,title,source_url,scope_type,source_id,entity_type,entity_id,
  date_precision,starts_on,timezone,source_wording,warning_window,expires_at,status,refresh_layer,
  change_control_ref
)
select 'AU','provider_application_window','UQ Semester 1 2027 international application deadline',
       'https://study.uq.edu.au/admissions/undergraduate/submit-your-application',
       'provider','9d1ce891-c80e-4f4e-b8ef-e0ffb1b0dd05'::uuid,'provider',
       'e55396d2-869a-46ef-9d17-841c7eab1313'::uuid,
       'exact','2026-11-30'::date,'Australia/Brisbane',
       'Semester 1: 30 November of the previous year',
       interval '45 days','2026-12-01T00:00:00+10'::timestamptz,'active',2,'CF-CHG-20260825-038'
where not exists (
  select 1 from pipeline.important_dates
  where source_url='https://study.uq.edu.au/admissions/undergraduate/submit-your-application'
    and title='UQ Semester 1 2027 international application deadline'
);

insert into pipeline.important_dates(
  country_code,event_type,title,source_url,scope_type,source_id,entity_type,entity_id,
  date_precision,starts_on,timezone,source_wording,warning_window,expires_at,status,refresh_layer,
  change_control_ref
)
select 'AU','intake_date','UQ Semester 1 2027 classes start',
       'https://about.uq.edu.au/academic-calendar',
       'provider','9d1ce891-c80e-4f4e-b8ef-e0ffb1b0dd05'::uuid,'provider',
       'e55396d2-869a-46ef-9d17-841c7eab1313'::uuid,
       'exact','2027-02-22'::date,'Australia/Brisbane',
       '22 Feb – Classes start',
       interval '60 days','2027-02-23T00:00:00+10'::timestamptz,'active',2,'CF-CHG-20260825-038'
where not exists (
  select 1 from pipeline.important_dates
  where source_url='https://about.uq.edu.au/academic-calendar'
    and title='UQ Semester 1 2027 classes start'
);

-- Deliberately vague source wording: no target and no refresh layer.
insert into pipeline.important_dates(
  country_code,event_type,title,source_url,scope_type,date_precision,timezone,source_wording,
  warning_window,expires_at,status,refresh_layer,change_control_ref
)
select 'AU','scholarship_window','Australia Awards Fellowships Round 22 expected opening',
       'https://www.dfat.gov.au/people-people/australia-awards/australia-awards-fellowships/applying-australia-awards-fellowship',
       'country_reference','source_vague','Australia/Sydney',
       'Applications for Australia Awards Fellowships Round 22 are expected to open in the final quarter of 2026.',
       interval '0 days','2027-01-01T00:00:00+11'::timestamptz,'active',null,'CF-CHG-20260825-038'
where not exists (
  select 1 from pipeline.important_dates
  where source_url='https://www.dfat.gov.au/people-people/australia-awards/australia-awards-fellowships/applying-australia-awards-fellowship'
    and title='Australia Awards Fellowships Round 22 expected opening'
);