create table pipeline.layer1_source_operations (
  source_id uuid primary key references pipeline.sources(id) on delete restrict,
  authority_name text not null,
  authority_domains text[] not null check (cardinality(authority_domains)>0),
  expected_format text not null,
  expected_count_kind text not null default 'records',
  active boolean not null default true,
  paused boolean not null default false,
  verification_cadence_days integer not null default 1 check (verification_cadence_days between 1 and 365),
  ingestion_cadence_days integer check (ingestion_cadence_days between 1 and 365),
  variance_warn_percent numeric(6,2) not null default 5 check (variance_warn_percent between 0 and 100),
  variance_block_percent numeric(6,2) not null default 20 check (variance_block_percent between variance_warn_percent and 100),
  min_expected_records bigint check (min_expected_records is null or min_expected_records>=0),
  max_expected_records bigint check (max_expected_records is null or max_expected_records>=0),
  previous_accepted_count bigint check (previous_accepted_count is null or previous_accepted_count>=0),
  last_expected_count bigint check (last_expected_count is null or last_expected_count>=0),
  last_source_hash text,
  last_verified_at timestamptz,
  verification_status text not null default 'unverified' check (verification_status in ('unverified','passed','warning','blocked','failed')),
  verification_message text,
  variance_percent numeric(10,4),
  variance_decision text not null default 'unknown' check (variance_decision in ('unknown','pass','warn','block')),
  next_verification_at timestamptz,
  next_ingestion_at timestamptz,
  last_schedule_status text,
  last_schedule_error text,
  consecutive_failures integer not null default 0 check (consecutive_failures>=0),
  change_reason text not null default 'initial baseline',
  updated_by uuid,
  updated_at timestamptz not null default now()
);

create table pipeline.layer1_source_operation_versions (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references pipeline.sources(id) on delete restrict,
  version_no integer not null check(version_no>0),
  snapshot jsonb not null,
  changed_by uuid,
  change_reason text not null,
  changed_at timestamptz not null default now(),
  unique(source_id,version_no)
);

create table pipeline.layer1_run_queue (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references pipeline.sources(id) on delete restrict,
  country_code char(2) not null,
  mode text not null check (mode in ('validate','dry_run','apply','recheck')),
  status text not null default 'queued' check (status in ('queued','running','completed','failed','cancelled','blocked','no_change')),
  idempotency_key text not null unique,
  requested_by uuid,
  requested_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  current_stage text not null default 'queued',
  heartbeat_at timestamptz,
  expected_count bigint,
  processed_count bigint not null default 0,
  created_count bigint not null default 0,
  updated_count bigint not null default 0,
  unchanged_count bigint not null default 0,
  rejected_count bigint not null default 0,
  conflicted_count bigint not null default 0,
  failed_count bigint not null default 0,
  source_hash text,
  resume_cursor bigint not null default 0,
  actual_job_id uuid references pipeline.jobs(id) on delete set null,
  retry_of_run_id uuid references pipeline.layer1_run_queue(id) on delete set null,
  warning_acknowledged boolean not null default false,
  result jsonb not null default '{}'::jsonb,
  error_text text,
  expires_at timestamptz not null default (now()+interval '30 days'),
  updated_at timestamptz not null default now()
);

create unique index layer1_run_queue_one_active_source_idx on pipeline.layer1_run_queue(source_id) where status in ('queued','running');
create index layer1_run_queue_source_requested_idx on pipeline.layer1_run_queue(source_id,requested_at desc);
create index layer1_run_queue_status_heartbeat_idx on pipeline.layer1_run_queue(status,heartbeat_at);
create index layer1_source_operation_versions_source_idx on pipeline.layer1_source_operation_versions(source_id,version_no desc);

alter table pipeline.layer1_source_operations enable row level security;
alter table pipeline.layer1_source_operation_versions enable row level security;
alter table pipeline.layer1_run_queue enable row level security;
revoke all on pipeline.layer1_source_operations from public,anon,authenticated;
revoke all on pipeline.layer1_source_operation_versions from public,anon,authenticated;
revoke all on pipeline.layer1_run_queue from public,anon,authenticated;

grant select,insert,update,delete on pipeline.layer1_source_operations to service_role;
grant select,insert,update,delete on pipeline.layer1_source_operation_versions to service_role;
grant select,insert,update,delete on pipeline.layer1_run_queue to service_role;

create or replace function security.admin_layer1_operations_read(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql stable security definer
set search_path=pg_catalog,security,pipeline,ref,auth
as $$
declare v_rank integer; v_country text:=upper(nullif(p_args->>'country_code','')); v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
  with src as (
    select s.id source_id,co.iso_alpha2::text country_code,co.name country_name,s.label source_label,s.source_type,s.url source_url,s.status source_status,s.trust_rank,
      s.last_checked_at,s.last_success_at,s.last_failure_at,s.last_error,
      o.authority_name,o.authority_domains,o.expected_format,o.expected_count_kind,o.active,o.paused,o.verification_cadence_days,o.ingestion_cadence_days,
      o.variance_warn_percent,o.variance_block_percent,o.min_expected_records,o.max_expected_records,o.previous_accepted_count,o.last_expected_count,o.last_source_hash,
      o.last_verified_at,o.verification_status,o.verification_message,o.variance_percent,o.variance_decision,o.next_verification_at,o.next_ingestion_at,
      o.last_schedule_status,o.last_schedule_error,o.consecutive_failures,o.updated_at,
      case when o.last_verified_at is null then 'never_verified' when o.paused then 'paused' when o.verification_status in ('blocked','failed') then 'unhealthy' when o.next_verification_at is not null and o.next_verification_at<now() then 'stale' else 'healthy' end source_health,
      case when o.paused then 'Source processing is paused.' when o.verification_status='blocked' then 'Resolve source authority/count blocker before run.' when o.verification_status='failed' then 'Revalidate source before run.' when o.last_verified_at is null then 'Validate source before run.' when o.next_verification_at is not null and o.next_verification_at<now() then 'Source verification is stale; recheck before run.' when o.variance_decision='warn' then 'Review variance warning; explicit acknowledgement required for APPLY.' else 'Source is eligible for governed queueing.' end next_action,
      (select jsonb_build_object('id',q.id,'mode',q.mode,'status',q.status,'requested_at',q.requested_at,'started_at',q.started_at,'completed_at',q.completed_at,'current_stage',q.current_stage,'heartbeat_at',q.heartbeat_at,'expected_count',q.expected_count,'processed_count',q.processed_count,'created_count',q.created_count,'updated_count',q.updated_count,'unchanged_count',q.unchanged_count,'rejected_count',q.rejected_count,'conflicted_count',q.conflicted_count,'failed_count',q.failed_count,'resume_cursor',q.resume_cursor,'actual_job_id',q.actual_job_id,'error_text',q.error_text,'result',q.result) from pipeline.layer1_run_queue q where q.source_id=s.id order by q.requested_at desc limit 1) latest_run,
      (select count(*)::bigint from pipeline.evidence_artifacts e where e.source_id=s.id) evidence_count,
      (select max(e.captured_at) from pipeline.evidence_artifacts e where e.source_id=s.id) latest_evidence_at,
      (select max(j.completed_at) from pipeline.jobs j where j.source_id=s.id and j.status='completed') latest_job_success_at,
      (select count(*)::bigint from pipeline.jobs j where j.source_id=s.id and j.status='running' and j.started_at<now()-interval '30 minutes') stale_running_jobs
    from pipeline.layer1_source_operations o join pipeline.sources s on s.id=o.source_id left join ref.countries co on co.id=s.country_id
    where v_country is null or co.iso_alpha2=v_country
  )
  select jsonb_build_object('sources',coalesce(jsonb_agg(to_jsonb(src) order by country_code,source_label),'[]'::jsonb),'retention',jsonb_build_object('transient_run_queue_days',30,'governed_evidence_deleted_by_housekeeping',false,'source_versions_deleted_by_housekeeping',false),'stuck_threshold_minutes',30,'authority_model','Layer 1 regulatory/authoritative; downstream layers cannot redefine identity.') into v_result from src;
  return v_result;
end $$;
revoke all on function security.admin_layer1_operations_read(jsonb) from public,anon,authenticated;
grant execute on function security.admin_layer1_operations_read(jsonb) to service_role;

create or replace function security.admin_layer1_command(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer
set search_path=pg_catalog,security,pipeline,ref,auth
as $$
declare v_rank integer; v_source uuid; v_reason text; v_id uuid; v_country text; v_mode text; v_version integer; v_warning boolean; v_url text; v_profile jsonb; v_domains text[];
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<6 then raise exception 'platform_admin role required' using errcode='42501'; end if;
  v_source:=nullif(p_args->>'source_id','')::uuid;
  if v_source is null then raise exception 'source_id required' using errcode='22023'; end if;
  v_reason:=trim(coalesce(p_args->>'reason',''));
  if length(v_reason)<5 then raise exception 'governance reason required' using errcode='22023'; end if;
  if p_operation='save_source' then
    select url into v_url from pipeline.sources where id=v_source;
    if not found then raise exception 'source not found' using errcode='22023'; end if;
    v_url:=coalesce(nullif(trim(p_args->>'source_url',''),''),v_url);
    if v_url !~* '^https://[^[:space:]]+$' then raise exception 'https source_url required' using errcode='22023'; end if;
    select array_agg(lower(trim(x))) into v_domains from jsonb_array_elements_text(coalesce(p_args->'authority_domains','[]'::jsonb)) x where trim(x)<>'';
    if coalesce(cardinality(v_domains),0)=0 then raise exception 'at least one authority domain required' using errcode='22023'; end if;
    if length(trim(coalesce(p_args->>'authority_name','')))<3 then raise exception 'authority_name required' using errcode='22023'; end if;
    if length(trim(coalesce(p_args->>'expected_format','')))<2 then raise exception 'expected_format required' using errcode='22023'; end if;
    update pipeline.sources set url=v_url,updated_at=now() where id=v_source;
    insert into pipeline.layer1_source_operations(source_id,authority_name,authority_domains,expected_format,expected_count_kind,active,paused,verification_cadence_days,ingestion_cadence_days,variance_warn_percent,variance_block_percent,min_expected_records,max_expected_records,change_reason,updated_by,updated_at)
    values(v_source,trim(p_args->>'authority_name'),v_domains,trim(p_args->>'expected_format'),coalesce(nullif(trim(p_args->>'expected_count_kind'),''),'records'),coalesce((p_args->>'active')::boolean,true),coalesce((p_args->>'paused')::boolean,false),coalesce(nullif(p_args->>'verification_cadence_days','')::integer,1),nullif(p_args->>'ingestion_cadence_days','')::integer,coalesce(nullif(p_args->>'variance_warn_percent','')::numeric,5),coalesce(nullif(p_args->>'variance_block_percent','')::numeric,20),nullif(p_args->>'min_expected_records','')::bigint,nullif(p_args->>'max_expected_records','')::bigint,v_reason,auth.uid(),now())
    on conflict(source_id) do update set authority_name=excluded.authority_name,authority_domains=excluded.authority_domains,expected_format=excluded.expected_format,expected_count_kind=excluded.expected_count_kind,active=excluded.active,paused=excluded.paused,verification_cadence_days=excluded.verification_cadence_days,ingestion_cadence_days=excluded.ingestion_cadence_days,variance_warn_percent=excluded.variance_warn_percent,variance_block_percent=excluded.variance_block_percent,min_expected_records=excluded.min_expected_records,max_expected_records=excluded.max_expected_records,change_reason=excluded.change_reason,updated_by=auth.uid(),updated_at=now();
    select coalesce(max(version_no),0)+1 into v_version from pipeline.layer1_source_operation_versions where source_id=v_source;
    select to_jsonb(o)-'updated_by' into v_profile from pipeline.layer1_source_operations o where o.source_id=v_source;
    insert into pipeline.layer1_source_operation_versions(source_id,version_no,snapshot,changed_by,change_reason) values(v_source,v_version,v_profile,auth.uid(),v_reason);
    return jsonb_build_object('source_id',v_source,'version_no',v_version,'status','saved');
  elsif p_operation='set_pause' then
    update pipeline.layer1_source_operations set paused=coalesce((p_args->>'paused')::boolean,true),change_reason=v_reason,updated_by=auth.uid(),updated_at=now() where source_id=v_source returning to_jsonb(layer1_source_operations)-'updated_by' into v_profile;
    if not found then raise exception 'source operations profile missing' using errcode='22023'; end if;
    select coalesce(max(version_no),0)+1 into v_version from pipeline.layer1_source_operation_versions where source_id=v_source;
    insert into pipeline.layer1_source_operation_versions(source_id,version_no,snapshot,changed_by,change_reason) values(v_source,v_version,v_profile,auth.uid(),v_reason);
    update pipeline.refresh_policies set enabled=not coalesce((p_args->>'paused')::boolean,true),updated_at=now(),change_control_ref='CF-CHG-20260826-043' where layer=1 and source_id=v_source;
    return jsonb_build_object('source_id',v_source,'paused',v_profile->'paused','version_no',v_version);
  elsif p_operation='queue_run' then
    select to_jsonb(o) into v_profile from pipeline.layer1_source_operations o where o.source_id=v_source;
    if not found then raise exception 'source operations profile missing' using errcode='22023'; end if;
    select co.iso_alpha2::text into v_country from pipeline.sources s join ref.countries co on co.id=s.country_id where s.id=v_source;
    v_mode:=lower(coalesce(nullif(p_args->>'mode',''),'dry_run'));
    if v_mode not in ('validate','dry_run','apply','recheck') then raise exception 'invalid mode' using errcode='22023'; end if;
    if not coalesce((v_profile->>'active')::boolean,false) or coalesce((v_profile->>'paused')::boolean,false) then raise exception 'source is inactive or paused' using errcode='55000'; end if;
    if v_mode in ('dry_run','apply','recheck') then
      if coalesce(v_profile->>'verification_status','') not in ('passed','warning') then raise exception 'source verification must pass before run' using errcode='55000'; end if;
      if nullif(v_profile->>'next_verification_at','')::timestamptz is not null and (v_profile->>'next_verification_at')::timestamptz<now() then raise exception 'source verification is stale' using errcode='55000'; end if;
      if v_profile->>'variance_decision'='block' then raise exception 'record-count variance is blocked' using errcode='55000'; end if;
      v_warning:=v_profile->>'variance_decision'='warn';
      if v_mode='apply' and v_warning and not coalesce((p_args->>'acknowledge_warning')::boolean,false) then raise exception 'variance warning acknowledgement required for APPLY' using errcode='55000'; end if;
    end if;
    insert into pipeline.layer1_run_queue(source_id,country_code,mode,status,idempotency_key,requested_by,expected_count,resume_cursor,source_hash,warning_acknowledged,current_stage,heartbeat_at,retry_of_run_id)
    values(v_source,v_country,v_mode,'queued',coalesce(nullif(p_args->>'idempotency_key',''),md5(v_source::text||':'||v_mode||':'||coalesce(v_profile->>'last_source_hash','nohash')||':'||coalesce(p_args->>'resume_cursor','0')||':'||current_date::text)),auth.uid(),nullif(v_profile->>'last_expected_count','')::bigint,coalesce(nullif(p_args->>'resume_cursor','')::bigint,0),v_profile->>'last_source_hash',coalesce((p_args->>'acknowledge_warning')::boolean,false),'queued',now(),nullif(p_args->>'retry_of_run_id','')::uuid) returning id into v_id;
    return jsonb_build_object('run_id',v_id,'status','queued','country_code',v_country,'mode',v_mode);
  elsif p_operation='cancel_queued' then
    v_id:=nullif(p_args->>'run_id','')::uuid;
    update pipeline.layer1_run_queue set status='cancelled',current_stage='cancelled_before_start',completed_at=now(),updated_at=now(),error_text='Cancelled by Platform Admin: '||v_reason where id=v_id and source_id=v_source and status='queued';
    if not found then raise exception 'only queued run may be cancelled' using errcode='55000'; end if;
    return jsonb_build_object('run_id',v_id,'status','cancelled');
  else raise exception 'unsupported Layer 1 command: %',p_operation using errcode='22023'; end if;
end $$;
revoke all on function security.admin_layer1_command(text,jsonb) from public,anon,authenticated;
grant execute on function security.admin_layer1_command(text,jsonb) to service_role;

create or replace function public.layer1_admin_command(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path=pg_catalog,security
as $$ select security.admin_layer1_command(p_operation,p_args) $$;
revoke all on function public.layer1_admin_command(text,jsonb) from public,anon;
grant execute on function public.layer1_admin_command(text,jsonb) to authenticated;

create or replace function public.svc_layer1_operation_context(p_source_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,pipeline,ref
as $$ select jsonb_build_object('source',to_jsonb(s),'country_code',c.iso_alpha2,'profile',to_jsonb(o)) from pipeline.sources s join pipeline.layer1_source_operations o on o.source_id=s.id left join ref.countries c on c.id=s.country_id where s.id=p_source_id $$;
revoke all on function public.svc_layer1_operation_context(uuid) from public,anon,authenticated;
grant execute on function public.svc_layer1_operation_context(uuid) to service_role;

create or replace function public.svc_layer1_record_validation(p_source_id uuid,p_success boolean,p_expected_count bigint,p_source_hash text,p_message text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,pipeline
as $$
declare v_prev bigint; v_warn numeric; v_block numeric; v_min bigint; v_max bigint; v_var numeric; v_dec text; v_status text; v_next timestamptz;
begin
  select previous_accepted_count,variance_warn_percent,variance_block_percent,min_expected_records,max_expected_records into v_prev,v_warn,v_block,v_min,v_max from pipeline.layer1_source_operations where source_id=p_source_id for update;
  if not found then raise exception 'source operations profile missing'; end if;
  if p_success and p_expected_count is not null and p_expected_count<0 then raise exception 'expected count invalid'; end if;
  if p_success and v_prev is not null and v_prev>0 and p_expected_count is not null then v_var:=round(((p_expected_count-v_prev)::numeric/v_prev::numeric)*100,4); else v_var:=null; end if;
  if not p_success then v_dec:='block'; v_status:='failed';
  elsif p_expected_count is null then v_dec:='warn'; v_status:='warning';
  elsif v_min is not null and p_expected_count<v_min then v_dec:='block'; v_status:='blocked';
  elsif v_max is not null and p_expected_count>v_max then v_dec:='block'; v_status:='blocked';
  elsif v_var is not null and abs(v_var)>=v_block then v_dec:='block'; v_status:='blocked';
  elsif v_var is not null and abs(v_var)>=v_warn then v_dec:='warn'; v_status:='warning';
  else v_dec:='pass'; v_status:='passed'; end if;
  select now()+make_interval(days=>verification_cadence_days) into v_next from pipeline.layer1_source_operations where source_id=p_source_id;
  update pipeline.layer1_source_operations set last_verified_at=now(),verification_status=v_status,verification_message=left(coalesce(p_message,case when p_success then 'Source verified' else 'Source validation failed' end),1000),last_expected_count=p_expected_count,last_source_hash=coalesce(p_source_hash,last_source_hash),variance_percent=v_var,variance_decision=v_dec,next_verification_at=v_next,consecutive_failures=case when p_success then 0 else consecutive_failures+1 end,updated_at=now() where source_id=p_source_id;
  update pipeline.sources set last_checked_at=now(),last_success_at=case when p_success then now() else last_success_at end,last_failure_at=case when p_success then last_failure_at else now() end,last_error=case when p_success then null else left(coalesce(p_message,'validation failed'),1000) end,updated_at=now() where id=p_source_id;
  return jsonb_build_object('source_id',p_source_id,'verification_status',v_status,'expected_count',p_expected_count,'previous_accepted_count',v_prev,'variance_percent',v_var,'variance_decision',v_dec,'next_verification_at',v_next);
end $$;
revoke all on function public.svc_layer1_record_validation(uuid,boolean,bigint,text,text) from public,anon,authenticated;
grant execute on function public.svc_layer1_record_validation(uuid,boolean,bigint,text,text) to service_role;

create or replace function public.svc_layer1_run_progress(p_run_id uuid,p_status text,p_stage text,p_processed bigint default null,p_created bigint default null,p_updated bigint default null,p_unchanged bigint default null,p_rejected bigint default null,p_conflicted bigint default null,p_failed bigint default null,p_actual_job_id uuid default null,p_result jsonb default null,p_error text default null,p_source_hash text default null,p_resume_cursor bigint default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,pipeline
as $$
declare v_source uuid; v_mode text; v_expected bigint;
begin
  if p_status not in ('queued','running','completed','failed','cancelled','blocked','no_change') then raise exception 'invalid status'; end if;
  update pipeline.layer1_run_queue set status=p_status,current_stage=coalesce(nullif(p_stage,''),current_stage),heartbeat_at=now(),started_at=case when p_status='running' then coalesce(started_at,now()) else started_at end,completed_at=case when p_status in ('completed','failed','cancelled','blocked','no_change') then coalesce(completed_at,now()) else completed_at end,processed_count=coalesce(p_processed,processed_count),created_count=coalesce(p_created,created_count),updated_count=coalesce(p_updated,updated_count),unchanged_count=coalesce(p_unchanged,unchanged_count),rejected_count=coalesce(p_rejected,rejected_count),conflicted_count=coalesce(p_conflicted,conflicted_count),failed_count=coalesce(p_failed,failed_count),actual_job_id=coalesce(p_actual_job_id,actual_job_id),result=case when p_result is null then result else p_result end,error_text=case when p_error is null then error_text else left(p_error,1800) end,source_hash=coalesce(p_source_hash,source_hash),resume_cursor=coalesce(p_resume_cursor,resume_cursor),updated_at=now() where id=p_run_id returning source_id,mode,expected_count into v_source,v_mode,v_expected;
  if not found then raise exception 'run not found'; end if;
  if p_status in ('completed','no_change') and v_mode='apply' then update pipeline.layer1_source_operations set previous_accepted_count=coalesce(v_expected,previous_accepted_count),last_source_hash=coalesce(p_source_hash,last_source_hash),next_ingestion_at=case when ingestion_cadence_days is null then null else now()+make_interval(days=>ingestion_cadence_days) end,last_schedule_status='completed',last_schedule_error=null,updated_at=now() where source_id=v_source;
  elsif p_status in ('failed','blocked') then update pipeline.layer1_source_operations set last_schedule_status=p_status,last_schedule_error=left(coalesce(p_error,p_status),1000),consecutive_failures=consecutive_failures+1,updated_at=now() where source_id=v_source; end if;
  return jsonb_build_object('run_id',p_run_id,'status',p_status,'stage',p_stage);
end $$;
revoke all on function public.svc_layer1_run_progress(uuid,text,text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,uuid,jsonb,text,text,bigint) from public,anon,authenticated;
grant execute on function public.svc_layer1_run_progress(uuid,text,text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,uuid,jsonb,text,text,bigint) to service_role;

create or replace function public.svc_layer1_housekeeping()
returns jsonb language plpgsql security definer set search_path=pg_catalog,pipeline
as $$ declare v_deleted bigint; begin delete from pipeline.layer1_run_queue where status in ('completed','failed','cancelled','blocked','no_change') and expires_at<now(); get diagnostics v_deleted=row_count; return jsonb_build_object('deleted_transient_runs',v_deleted,'governed_evidence_deleted',0,'source_versions_deleted',0,'policy','Only expired terminal Layer 1 queue rows are deleted; Evidence, source-operation versions and canonical history are excluded.'); end $$;
revoke all on function public.svc_layer1_housekeeping() from public,anon,authenticated;
grant execute on function public.svc_layer1_housekeeping() to service_role;

insert into pipeline.layer1_source_operations(source_id,authority_name,authority_domains,expected_format,expected_count_kind,active,paused,verification_cadence_days,ingestion_cadence_days,variance_warn_percent,variance_block_percent,previous_accepted_count,last_expected_count,last_source_hash,last_verified_at,verification_status,verification_message,variance_percent,variance_decision,next_verification_at,next_ingestion_at,change_reason)
select s.id,'Australian Government Department of Education / CRICOS',array['data.gov.au'],'CKAN package with authoritative CRICOS CSV resources','course_rows',true,false,1,7,5,20,26648,26648,coalesce(s.metadata->>'course_hash',s.metadata->>'cricos_facts_hash',s.metadata->>'zip_hash'),s.last_success_at,'passed','Seeded from accepted CRICOS Layer 1 run: 26,648 active course rows',0,'pass',now()+interval '1 day',now()+interval '7 days','M2.4.1 accepted baseline' from pipeline.sources s join ref.countries c on c.id=s.country_id where c.iso_alpha2='AU' and s.label='CRICOS Providers, Courses and Locations';
insert into pipeline.layer1_source_operations(source_id,authority_name,authority_domains,expected_format,expected_count_kind,active,paused,verification_cadence_days,ingestion_cadence_days,variance_warn_percent,variance_block_percent,previous_accepted_count,last_expected_count,last_source_hash,last_verified_at,verification_status,verification_message,variance_percent,variance_decision,next_verification_at,next_ingestion_at,change_reason)
select s.id,'New Zealand Qualifications Authority (NZQA)',array['nzqa.govt.nz','www.nzqa.govt.nz'],'NZQA Education Organisations provider directory','provider_rows',true,false,1,7,5,20,coalesce((s.metadata->>'total_providers')::bigint,409),coalesce((s.metadata->>'total_providers')::bigint,409),s.metadata->'evidence_hashes'->>0,s.last_success_at,'passed','Seeded from accepted NZQA Layer 1 provider total',0,'pass',now()+interval '1 day',now()+interval '7 days','M2.4.1 accepted baseline' from pipeline.sources s join ref.countries c on c.id=s.country_id where c.iso_alpha2='NZ' and s.label='NZQA Education Organisations';
insert into pipeline.layer1_source_operation_versions(source_id,version_no,snapshot,change_reason) select o.source_id,1,to_jsonb(o)-'updated_by','M2.4.1 accepted baseline' from pipeline.layer1_source_operations o;
insert into pipeline.refresh_policies(country_code,layer,source_id,freshness_class,cadence_interval,next_due_at,hash_sensitive,important_date_sensitive,enabled,change_control_ref)
select c.iso_alpha2,1,o.source_id,'weekly',make_interval(days=>coalesce(o.ingestion_cadence_days,7)),o.next_ingestion_at,true,false,o.active and not o.paused,'CF-CHG-20260826-043' from pipeline.layer1_source_operations o join pipeline.sources s on s.id=o.source_id join ref.countries c on c.id=s.country_id where not exists(select 1 from pipeline.refresh_policies p where p.layer=1 and p.source_id=o.source_id);

create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security invoker set search_path to 'pg_catalog','public','security'
as $$
declare v_result jsonb; v_id uuid;
begin
  if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
  if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
  if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
  if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
  if p_operation in ('providers_page','campuses_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
  if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
  if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
  if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
  if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
  if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
  if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args); return security.admin_pipeline_ops_sanitise_result(p_operation,v_result); end if;
  if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
  if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid; return security.admin_provider_detail(v_id); end if;
  if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid; return security.admin_campus_detail(v_id); end if;
  v_result:=security.admin_read_impl(p_operation,p_args);
  if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid; return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id)); end if;
  if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid; return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id)); end if;
  return v_result;
end $$;
revoke all on function public.admin_read(text,jsonb) from public,anon;
grant execute on function public.admin_read(text,jsonb) to authenticated;
