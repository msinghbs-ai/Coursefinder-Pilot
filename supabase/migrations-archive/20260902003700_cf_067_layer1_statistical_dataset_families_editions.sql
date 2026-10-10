begin;

create table if not exists pipeline.layer1_dataset_families(
  id uuid primary key default gen_random_uuid(),
  country_id uuid references ref.countries(id) on delete restrict,
  family_code text not null unique,
  label text not null,
  dataset_class text not null default 'statistics' check(dataset_class in ('regulatory','statistics','rankings')),
  source_system text not null,
  edition_strategy text not null default 'annual' check(edition_strategy in ('annual','periodic','snapshot')),
  comparison_enabled boolean not null default true,
  retain_all_editions boolean not null default true,
  current_source_id uuid references pipeline.sources(id) on delete set null,
  status text not null default 'active' check(status in ('active','paused','retired')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists pipeline.layer1_dataset_editions(
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references pipeline.layer1_dataset_families(id) on delete restrict,
  source_id uuid not null unique references pipeline.sources(id) on delete restrict,
  edition_key text not null,
  edition_year integer,
  period_start date,
  period_end date,
  status text not null default 'retained' check(status in ('current','retained','withdrawn','review')),
  observation_count bigint,
  first_seen_at timestamptz not null default now(),
  last_verified_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  unique(family_id,edition_key)
);

create index if not exists layer1_dataset_editions_family_period_idx
  on pipeline.layer1_dataset_editions(family_id,period_end desc nulls last,edition_year desc nulls last,edition_key desc);

alter table pipeline.layer1_dataset_families enable row level security;
alter table pipeline.layer1_dataset_editions enable row level security;
revoke all on pipeline.layer1_dataset_families,pipeline.layer1_dataset_editions from public,anon,authenticated;
grant select,insert,update,delete on pipeline.layer1_dataset_families,pipeline.layer1_dataset_editions to service_role;

with au as (select id from ref.countries where iso_alpha2='AU')
insert into pipeline.layer1_dataset_families(country_id,family_code,label,dataset_class,source_system,edition_strategy,comparison_enabled,retain_all_editions,metadata)
select au.id,v.family_code,v.label,'statistics',v.source_system,v.strategy,true,true,
       jsonb_build_object('identity_authority',false,'operational_surface','layer1_statistics','comparison_axis',case when v.strategy='annual' then 'year' else 'period' end)
from au cross join (values
  ('au_qilt_gos','QILT Graduate Outcomes Survey','QILT','annual'),
  ('au_qilt_ses','QILT Student Experience Survey','QILT','annual'),
  ('au_qilt_gosl','QILT Graduate Outcomes Survey – Longitudinal','QILT','annual'),
  ('au_qilt_ess','QILT Employer Satisfaction Survey','QILT','annual'),
  ('au_prisms_student_flow','PRISMS International Student Flow','PRISMS','periodic')
) v(family_code,label,source_system,strategy)
on conflict(family_code) do update set
  label=excluded.label,dataset_class=excluded.dataset_class,source_system=excluded.source_system,
  edition_strategy=excluded.edition_strategy,comparison_enabled=true,retain_all_editions=true,
  metadata=pipeline.layer1_dataset_families.metadata||excluded.metadata,updated_at=now();

with candidates as (
 select s.id source_id,
        case
          when s.metadata->>'survey_code'='qilt_gos' then 'au_qilt_gos'
          when s.metadata->>'survey_code'='qilt_ses' then 'au_qilt_ses'
          when s.metadata->>'survey_code'='qilt_gosl' then 'au_qilt_gosl'
          when s.metadata->>'survey_code'='qilt_ess' then 'au_qilt_ess'
          when upper(coalesce(s.metadata->>'source_system',''))='PRISMS' then 'au_prisms_student_flow'
        end family_code,
        coalesce(s.metadata->>'collection_version',s.metadata->>'edition_year',
                 substring(s.label from '(20[0-9]{2}(?:-[0-9]{2})?)')) edition_key,
        case when coalesce(s.metadata->>'collection_version',s.metadata->>'edition_year','') ~ '^20[0-9]{2}'
             then substring(coalesce(s.metadata->>'collection_version',s.metadata->>'edition_year') from 1 for 4)::integer
             else null end edition_year,
        nullif(s.metadata->>'period_start','')::date period_start,
        nullif(s.metadata->>'period_end','')::date period_end,
        coalesce(s.last_success_at,s.last_checked_at) last_verified_at
 from pipeline.sources s
 where upper(coalesce(s.metadata->>'source_system',s.metadata->>'publisher','')) in ('QILT','PRISMS')
)
insert into pipeline.layer1_dataset_editions(family_id,source_id,edition_key,edition_year,period_start,period_end,status,observation_count,last_verified_at,metadata)
select f.id,c.source_id,coalesce(c.edition_key,'unknown'),c.edition_year,c.period_start,c.period_end,'retained',
       case when f.source_system='QILT'
            then (select count(*)::bigint from catalogue.provider_outcomes po where po.source_id=c.source_id)
            else (select count(*)::bigint from catalogue.student_flow_observations so where so.source_id=c.source_id) end,
       c.last_verified_at,
       jsonb_build_object('retained_for_comparison',true,'identity_authority',false)
from candidates c join pipeline.layer1_dataset_families f on f.family_code=c.family_code
where c.family_code is not null
on conflict(source_id) do update set
 edition_key=excluded.edition_key,edition_year=excluded.edition_year,period_start=excluded.period_start,period_end=excluded.period_end,
 observation_count=excluded.observation_count,last_verified_at=excluded.last_verified_at,
 metadata=pipeline.layer1_dataset_editions.metadata||excluded.metadata;

with ranked as (
 select e.id,e.family_id,e.source_id,row_number() over(partition by e.family_id order by e.period_end desc nulls last,e.edition_year desc nulls last,e.edition_key desc,e.first_seen_at desc) rn
 from pipeline.layer1_dataset_editions e
)
update pipeline.layer1_dataset_editions e set status=case when r.rn=1 then 'current' else 'retained' end
from ranked r where r.id=e.id;

update pipeline.layer1_dataset_families f
set current_source_id=x.source_id,updated_at=now()
from (
 select distinct on(e.family_id) e.family_id,e.source_id
 from pipeline.layer1_dataset_editions e
 order by e.family_id,(e.status='current') desc,e.period_end desc nulls last,e.edition_year desc nulls last,e.edition_key desc
) x
where x.family_id=f.id;

update pipeline.sources s
set metadata=coalesce(s.metadata,'{}'::jsonb)||jsonb_build_object(
 'dataset_family_code',f.family_code,
 'dataset_family_label',f.label,
 'edition_key',e.edition_key,
 'edition_year',e.edition_year,
 'edition_status',e.status,
 'retain_for_comparison',true
),updated_at=now()
from pipeline.layer1_dataset_editions e join pipeline.layer1_dataset_families f on f.id=e.family_id
where s.id=e.source_id;

create or replace function pipeline.sync_layer1_statistical_edition(p_source_id uuid)
returns void language plpgsql security definer
set search_path to 'pg_catalog','pipeline','ref','catalogue'
as $$
declare v pipeline.sources%rowtype; v_family_code text; v_family pipeline.layer1_dataset_families%rowtype;
        v_key text; v_year integer; v_start date; v_end date; v_count bigint; v_prior uuid;
begin
 select * into v from pipeline.sources where id=p_source_id;
 if v.id is null then return; end if;
 if upper(coalesce(v.metadata->>'source_system',v.metadata->>'publisher','')) not in ('QILT','PRISMS') then return; end if;
 v_family_code:=case
   when v.metadata->>'survey_code'='qilt_gos' then 'au_qilt_gos'
   when v.metadata->>'survey_code'='qilt_ses' then 'au_qilt_ses'
   when v.metadata->>'survey_code'='qilt_gosl' then 'au_qilt_gosl'
   when v.metadata->>'survey_code'='qilt_ess' then 'au_qilt_ess'
   when upper(coalesce(v.metadata->>'source_system',''))='PRISMS' then 'au_prisms_student_flow'
 end;
 if v_family_code is null then return; end if;
 select * into v_family from pipeline.layer1_dataset_families where family_code=v_family_code;
 v_key:=coalesce(v.metadata->>'collection_version',v.metadata->>'edition_year',substring(v.label from '(20[0-9]{2}(?:-[0-9]{2})?)'),'unknown');
 v_year:=case when v_key ~ '^20[0-9]{2}' then substring(v_key from 1 for 4)::integer else null end;
 v_start:=nullif(v.metadata->>'period_start','')::date;
 v_end:=nullif(v.metadata->>'period_end','')::date;
 if v_family.source_system='QILT' then select count(*)::bigint into v_count from catalogue.provider_outcomes where source_id=v.id;
 else select count(*)::bigint into v_count from catalogue.student_flow_observations where source_id=v.id; end if;

 insert into pipeline.layer1_dataset_editions(family_id,source_id,edition_key,edition_year,period_start,period_end,status,observation_count,last_verified_at,metadata)
 values(v_family.id,v.id,v_key,v_year,v_start,v_end,'retained',v_count,coalesce(v.last_success_at,v.last_checked_at),
        jsonb_build_object('retained_for_comparison',true,'identity_authority',false))
 on conflict(source_id) do update set edition_key=excluded.edition_key,edition_year=excluded.edition_year,period_start=excluded.period_start,period_end=excluded.period_end,
 observation_count=excluded.observation_count,last_verified_at=excluded.last_verified_at,metadata=pipeline.layer1_dataset_editions.metadata||excluded.metadata;

 select f.current_source_id into v_prior from pipeline.layer1_dataset_families f where f.id=v_family.id;
 if v_prior is null or not exists(
   select 1 from pipeline.layer1_dataset_editions cur join pipeline.layer1_dataset_editions neu on neu.source_id=v.id
   where cur.source_id=v_prior and neu.family_id=cur.family_id
     and coalesce(neu.period_end,make_date(coalesce(neu.edition_year,0),12,31),date '0001-01-01')
         <= coalesce(cur.period_end,make_date(coalesce(cur.edition_year,0),12,31),date '0001-01-01')
 ) then
   update pipeline.layer1_dataset_editions set status='retained' where family_id=v_family.id and source_id<>v.id and status='current';
   update pipeline.layer1_dataset_editions set status='current' where source_id=v.id;
   update pipeline.layer1_dataset_families set current_source_id=v.id,updated_at=now() where id=v_family.id;
   update pipeline.sources set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('edition_status','retained','retain_for_comparison',true) where id=v_prior and v_prior is not null;
   update pipeline.sources set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('dataset_family_code',v_family.family_code,'dataset_family_label',v_family.label,'edition_key',v_key,'edition_year',v_year,'edition_status','current','retain_for_comparison',true) where id=v.id;

   if not exists(select 1 from pipeline.layer1_source_operations where source_id=v.id) then
     insert into pipeline.layer1_source_operations(
       source_id,authority_name,authority_domains,expected_format,expected_count_kind,active,paused,
       verification_cadence_days,ingestion_cadence_days,variance_warn_percent,variance_block_percent,
       previous_accepted_count,last_expected_count,last_verified_at,verification_status,verification_message,
       variance_percent,variance_decision,next_verification_at,next_ingestion_at,change_reason,updated_at
     )
     select v.id,o.authority_name,o.authority_domains,o.expected_format,'observations',true,false,
       o.verification_cadence_days,o.ingestion_cadence_days,o.variance_warn_percent,o.variance_block_percent,
       v_count,v_count,coalesce(v.last_success_at,v.last_checked_at),'passed',
       'New statistical edition registered automatically; retained editions remain available for comparison.',
       0,'pass',now()+(o.verification_cadence_days||' days')::interval,
       now()+(coalesce(o.ingestion_cadence_days,30)||' days')::interval,
       'CF-CHG-20260902-067 automatic statistical edition rollover',now()
     from pipeline.layer1_source_operations o where o.source_id=v_prior
     limit 1;
   end if;
 end if;
end $$;

revoke all on function pipeline.sync_layer1_statistical_edition(uuid) from public,anon,authenticated;
grant execute on function pipeline.sync_layer1_statistical_edition(uuid) to service_role;

create or replace function security.admin_layer1_operations_read(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog','security','pipeline','ref','auth'
as $$
declare v_rank integer; v_country text:=upper(nullif(p_args->>'country_code','')); v_result jsonb;
begin
 if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
 select security.current_role_rank() into v_rank;
 if coalesce(v_rank,0)<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 with src as (
  select s.id source_id,coalesce(co.iso_alpha2::text,case when s.metadata->>'scope'='global' then 'GLOBAL' end) country_code,
   coalesce(co.name,case when s.metadata->>'scope'='global' then 'Global' end) country_name,
   s.label source_label,s.source_type,s.url source_url,s.status source_status,s.trust_rank,s.last_checked_at,s.last_success_at,s.last_failure_at,s.last_error,
   s.metadata->>'dataset_class' dataset_class,s.metadata->>'source_system' source_system,
   coalesce((s.metadata->>'edition_year')::integer,e.edition_year) edition_year,
   coalesce(s.metadata->>'edition_key',e.edition_key) edition_key,
   coalesce(s.metadata->>'edition_status',e.status) edition_status,
   f.family_code dataset_family_code,f.label dataset_family_label,f.edition_strategy,
   coalesce(f.comparison_enabled,false) comparison_enabled,coalesce(f.retain_all_editions,false) retain_all_editions,
   case when f.id is null then true else f.current_source_id=s.id end edition_is_current,
   coalesce((select count(*) from pipeline.layer1_dataset_editions eh where eh.family_id=f.id),1)::integer retained_edition_count,
   case when f.id is null then '[]'::jsonb else coalesce((
     select jsonb_agg(jsonb_build_object(
       'source_id',eh.source_id,'edition_key',eh.edition_key,'edition_year',eh.edition_year,
       'period_start',eh.period_start,'period_end',eh.period_end,'status',eh.status,
       'observation_count',eh.observation_count,'last_verified_at',eh.last_verified_at,
       'source_label',hs.label,'source_url',hs.url
     ) order by eh.period_end desc nulls last,eh.edition_year desc nulls last,eh.edition_key desc)
     from pipeline.layer1_dataset_editions eh join pipeline.sources hs on hs.id=eh.source_id where eh.family_id=f.id
   ),'[]'::jsonb) end editions,
   s.metadata->>'acquisition_mode' acquisition_mode,s.metadata->>'scope' source_scope,
   o.authority_name,o.authority_domains,o.expected_format,o.expected_count_kind,o.active,o.paused,o.verification_cadence_days,o.ingestion_cadence_days,
   o.variance_warn_percent,o.variance_block_percent,o.min_expected_records,o.max_expected_records,o.previous_accepted_count,o.last_expected_count,
   o.previous_accepted_hash,o.last_source_hash,o.last_verified_at,o.verification_status,o.verification_message,o.variance_percent,o.variance_decision,
   o.next_verification_at,o.next_ingestion_at,o.last_schedule_status,o.last_schedule_error,o.consecutive_failures,o.updated_at,
   coalesce((select max(v.version_no) from pipeline.layer1_source_operation_versions v where v.source_id=s.id),0) source_config_version,
   case when o.last_verified_at is null then 'never_verified' when o.paused then 'paused' when o.verification_status in ('blocked','failed') then 'unhealthy'
        when exists(select 1 from pipeline.layer1_run_queue q where q.source_id=s.id and q.status='running' and coalesce(q.heartbeat_at,q.started_at,q.requested_at)<now()-interval '30 minutes') then 'stuck'
        when o.next_verification_at is not null and o.next_verification_at<now() then 'stale' else 'healthy' end source_health,
   case when o.paused then 'Source processing is paused.'
        when exists(select 1 from pipeline.layer1_run_queue q where q.source_id=s.id and q.status='running' and coalesce(q.heartbeat_at,q.started_at,q.requested_at)<now()-interval '30 minutes') then 'Running job heartbeat is stale; Platform Admin may recover it after confirming the prior worker is no longer active.'
        when o.verification_status='blocked' then 'Resolve source authority/count blocker before run.'
        when o.verification_status='failed' then 'Revalidate source before run.'
        when o.last_verified_at is null then 'Validate source before run.'
        when o.next_verification_at is not null and o.next_verification_at<now() then 'Source verification is stale; recheck before run.'
        when o.variance_decision='warn' then 'Review variance warning; explicit acknowledgement required for APPLY.'
        else 'Source is eligible for governed queueing.' end next_action,
   (select jsonb_build_object('id',q.id,'mode',q.mode,'status',q.status,'requested_at',q.requested_at,'started_at',q.started_at,'completed_at',q.completed_at,
      'current_stage',q.current_stage,'heartbeat_at',q.heartbeat_at,'stuck',q.status='running' and coalesce(q.heartbeat_at,q.started_at,q.requested_at)<now()-interval '30 minutes',
      'expected_count',q.expected_count,'processed_count',q.processed_count,
      'progress_percent',case when q.expected_count is null or q.expected_count=0 then null else round(least(100,(q.processed_count::numeric/q.expected_count::numeric)*100),1) end,
      'queue_position',case when q.status='queued' then 1 else null end,
      'runtime_seconds',case when q.started_at is null then null else greatest(0,round(extract(epoch from (coalesce(q.completed_at,now())-q.started_at))::numeric,1)) end,
      'created_count',q.created_count,'updated_count',q.updated_count,'unchanged_count',q.unchanged_count,'rejected_count',q.rejected_count,'conflicted_count',q.conflicted_count,
      'failed_count',q.failed_count,'resume_cursor',q.resume_cursor,'actual_job_id',q.actual_job_id,'retry_of_run_id',q.retry_of_run_id,'error_text',q.error_text,'result',q.result)
    from pipeline.layer1_run_queue q where q.source_id=s.id order by q.requested_at desc limit 1) latest_run,
   (select count(*)::bigint from pipeline.layer1_run_queue q where q.source_id=s.id and q.status='queued') queue_depth,
   (select count(*)::bigint from pipeline.evidence_artifacts ev where ev.source_id=s.id) evidence_count,
   (select max(ev.captured_at) from pipeline.evidence_artifacts ev where ev.source_id=s.id) latest_evidence_at,
   (select max(j.completed_at) from pipeline.jobs j where j.source_id=s.id and j.status='completed') latest_job_success_at,
   (select count(*)::bigint from pipeline.jobs j where j.source_id=s.id and j.status='running' and j.started_at<now()-interval '30 minutes') stale_running_jobs,
   p.enabled schedule_enabled,p.cadence_interval,p.next_due_at schedule_next_due_at,p.freshness_class schedule_freshness_class,p.hash_sensitive schedule_hash_sensitive,p.updated_at schedule_policy_updated_at
  from pipeline.layer1_source_operations o
  join pipeline.sources s on s.id=o.source_id
  left join ref.countries co on co.id=s.country_id
  left join pipeline.layer1_dataset_editions e on e.source_id=s.id
  left join pipeline.layer1_dataset_families f on f.id=e.family_id
  left join pipeline.refresh_policies p on p.layer=1 and p.source_id=s.id
  where (v_country is null or co.iso_alpha2=v_country or (v_country='GLOBAL' and s.metadata->>'scope'='global'))
 )
 select jsonb_build_object(
   'sources',coalesce(jsonb_agg(to_jsonb(src) order by country_code,coalesce(dataset_family_label,source_label),edition_is_current desc,edition_key desc),'[]'::jsonb),
   'retention',jsonb_build_object('transient_run_queue_days',30,'governed_evidence_deleted_by_housekeeping',false,'source_versions_deleted_by_housekeeping',false,
      'statistical_editions_retained_for_comparison',true),
   'stuck_threshold_minutes',30,
   'alerts',jsonb_build_object('stale_source','next verification overdue','abnormal_variance','configured warn/block thresholds','failed_validation','verification_status failed/blocked',
      'stuck_job','queue heartbeat older than 30 minutes','repeated_failure','consecutive_failures > 1','schedule_failure','source operation schedule error',
      'storage_growth','Evidence count and storage capacity remain governed by Evidence operations'),
   'authority_model','Layer 1 regulatory/authoritative plus governed statistical ingestion; statistical editions retain identity_authority=false.'
 ) into v_result from src;
 return v_result;
end $$;

revoke all on function security.admin_layer1_operations_read(jsonb) from public,anon,authenticated;
grant execute on function security.admin_layer1_operations_read(jsonb) to service_role;

commit;