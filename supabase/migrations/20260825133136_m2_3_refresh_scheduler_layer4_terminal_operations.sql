-- CF-CHG-20260825-038
-- M2.3 bounded refresh scheduler + terminal Layer 4 operational hardening.

alter table pipeline.refresh_policies
  add column if not exists source_id uuid references pipeline.sources(id);

alter table pipeline.refresh_requests
  add column if not exists source_id uuid references pipeline.sources(id),
  add column if not exists evidence_id uuid references pipeline.evidence_artifacts(id),
  add column if not exists layer3_profile_id uuid references pipeline.layer3_model_profiles(id),
  add column if not exists revalidation_ref text;

alter table pipeline.important_links
  add column if not exists related_source_id uuid references pipeline.sources(id);

alter table pipeline.important_dates
  add column if not exists source_id uuid references pipeline.sources(id);

alter table pipeline.refresh_policies drop constraint if exists refresh_policies_check;
alter table pipeline.refresh_policies
  add constraint refresh_policies_bounded_target_check
  check (
    source_id is not null
    or source_profile_id is not null
    or entity_id is not null
    or (layer = 4 and freshness_class = 'event-driven')
  );

alter table pipeline.refresh_requests drop constraint if exists refresh_requests_check;
alter table pipeline.refresh_requests
  add constraint refresh_requests_bounded_target_check
  check (source_id is not null or source_profile_id is not null or entity_id is not null);

create index if not exists refresh_policies_source_idx
  on pipeline.refresh_policies(source_id) where source_id is not null;
create index if not exists refresh_requests_source_idx
  on pipeline.refresh_requests(source_id) where source_id is not null;
create index if not exists refresh_requests_evidence_idx
  on pipeline.refresh_requests(evidence_id) where evidence_id is not null;
create index if not exists refresh_requests_layer3_profile_idx
  on pipeline.refresh_requests(layer3_profile_id) where layer3_profile_id is not null;
create index if not exists important_links_related_source_idx
  on pipeline.important_links(related_source_id) where related_source_id is not null;
create index if not exists important_dates_source_idx
  on pipeline.important_dates(source_id) where source_id is not null;

create table if not exists pipeline.search_refresh_signals (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  review_decision_id uuid not null references pipeline.layer4_decisions(id),
  reason text not null,
  status text not null default 'queued'
    check (status in ('queued','processing','completed','cancelled','blocked')),
  change_control_ref text not null default 'CF-CHG-20260825-038',
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(review_decision_id)
);
alter table pipeline.search_refresh_signals enable row level security;
revoke all on pipeline.search_refresh_signals from public, anon, authenticated;
create index if not exists search_refresh_signals_status_created_idx
  on pipeline.search_refresh_signals(status, created_at);

create or replace function security.refresh_policy_upsert_v2_impl(
  p_id uuid,
  p_country_code text,
  p_layer smallint,
  p_source_id uuid,
  p_source_profile_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_freshness_class text,
  p_cadence_days integer,
  p_next_due_at timestamptz,
  p_hash_sensitive boolean,
  p_important_date_sensitive boolean,
  p_enabled boolean,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
declare v_id uuid := coalesce(p_id, gen_random_uuid());
begin
  if auth.uid() is null or security.current_role_rank() < 4 then
    raise exception 'pipeline operator role required' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'governance reason required'; end if;
  if p_layer not between 1 and 4 then raise exception 'layer must be 1..4'; end if;
  if p_freshness_class not in ('critical','weekly','monthly','term-cycle','annual','event-driven') then
    raise exception 'invalid freshness class';
  end if;
  if p_layer = 4 and p_freshness_class <> 'event-driven' then
    raise exception 'Layer 4 refresh policy must be event-driven';
  end if;
  if p_layer in (1,2,3) and p_source_id is null and p_source_profile_id is null and p_entity_id is null then
    raise exception 'bounded source, source profile or entity target required';
  end if;
  insert into pipeline.refresh_policies(
    id,country_code,layer,source_id,source_profile_id,entity_type,entity_id,
    freshness_class,cadence_interval,next_due_at,hash_sensitive,
    important_date_sensitive,enabled,change_control_ref
  ) values (
    v_id,upper(nullif(p_country_code,'')),p_layer,p_source_id,p_source_profile_id,p_entity_type,p_entity_id,
    p_freshness_class,case when p_cadence_days is null then null else make_interval(days=>p_cadence_days) end,
    p_next_due_at,p_hash_sensitive,p_important_date_sensitive,p_enabled,'CF-CHG-20260825-038'
  )
  on conflict(id) do update set
    country_code=excluded.country_code,layer=excluded.layer,source_id=excluded.source_id,
    source_profile_id=excluded.source_profile_id,entity_type=excluded.entity_type,entity_id=excluded.entity_id,
    freshness_class=excluded.freshness_class,cadence_interval=excluded.cadence_interval,
    next_due_at=excluded.next_due_at,hash_sensitive=excluded.hash_sensitive,
    important_date_sensitive=excluded.important_date_sensitive,enabled=excluded.enabled,
    change_control_ref=excluded.change_control_ref,updated_at=now();
  return v_id;
end $$;

revoke all on function security.refresh_policy_upsert_v2_impl(uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text)
from public, anon, authenticated;
grant execute on function security.refresh_policy_upsert_v2_impl(uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text)
to service_role;

create or replace function public.refresh_policy_upsert_v2(
  p_id uuid,
  p_country_code text,
  p_layer smallint,
  p_source_id uuid,
  p_source_profile_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_freshness_class text,
  p_cadence_days integer,
  p_next_due_at timestamptz,
  p_hash_sensitive boolean,
  p_important_date_sensitive boolean,
  p_enabled boolean,
  p_reason text
) returns uuid
language sql
set search_path = pg_catalog, security
as $$
  select security.refresh_policy_upsert_v2_impl(
    p_id,p_country_code,p_layer,p_source_id,p_source_profile_id,p_entity_type,p_entity_id,
    p_freshness_class,p_cadence_days,p_next_due_at,p_hash_sensitive,p_important_date_sensitive,p_enabled,p_reason
  )
$$;
revoke all on function public.refresh_policy_upsert_v2(uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text)
from public, anon;
grant execute on function public.refresh_policy_upsert_v2(uuid,text,smallint,uuid,uuid,text,uuid,text,integer,timestamptz,boolean,boolean,boolean,text)
to authenticated, service_role;

create or replace function security.refresh_intelligence_overview_impl(p_limit integer default 100)
returns jsonb
language plpgsql
stable security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
begin
  if auth.uid() is null or security.current_role_rank()<3 then
    raise exception 'curator role required' using errcode='42501';
  end if;
  return jsonb_build_object(
   'policies',coalesce((
     select jsonb_agg(to_jsonb(x) order by x.next_due_at nulls last)
     from (
       select id,country_code,layer,source_id,source_profile_id,entity_type,entity_id,
              freshness_class,cadence_interval,next_due_at,hash_sensitive,important_date_sensitive,
              enabled,change_control_ref,updated_at
       from pipeline.refresh_policies
       order by next_due_at nulls last
       limit least(greatest(p_limit,1),250)
     ) x
   ),'[]'::jsonb),
   'requests',coalesce((
     select jsonb_agg(to_jsonb(x) order by x.created_at desc)
     from (
       select id,requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,
              evidence_id,layer3_profile_id,revalidation_ref,reason,trigger_type,important_date_id,
              status,requested_by,change_control_ref,created_at,completed_at
       from pipeline.refresh_requests
       order by created_at desc
       limit least(greatest(p_limit,1),250)
     ) x
   ),'[]'::jsonb),
   'search_signals',coalesce((
     select jsonb_agg(to_jsonb(x) order by x.created_at desc)
     from (
       select id,entity_type,entity_id,review_decision_id,reason,status,change_control_ref,created_at,completed_at
       from pipeline.search_refresh_signals
       order by created_at desc
       limit least(greatest(p_limit,1),250)
     ) x
   ),'[]'::jsonb)
  );
end $$;

create or replace function security.important_links_list_impl(p_country_code text default null)
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
    select jsonb_agg(to_jsonb(x) order by x.country_code,x.authority_category,x.authority_name)
    from (
      select id,country_code,authority_category,authority_name,owner_label,url,purpose,related_layer,
             related_source_id,related_source_profile_id,last_verified_at,verification_cadence,
             next_verification_at,health_status,change_control_ref,updated_at
      from pipeline.important_links
      where p_country_code is null or country_code=upper(p_country_code)
    ) x
  ),'[]'::jsonb);
end $$;

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
    select jsonb_agg(to_jsonb(x) order by x.starts_at nulls last,x.title)
    from (
      select id,country_code,event_type,title,source_url,evidence_id,scope_type,source_id,
             source_profile_id,entity_type,entity_id,date_precision,starts_at,ends_at,timezone,
             source_wording,warning_window,expires_at,status,refresh_layer,change_control_ref
      from pipeline.important_dates
      where status='active'
        and (p_country_code is null or country_code=upper(p_country_code))
        and (starts_at is null or starts_at<=now()+make_interval(days=>least(greatest(p_days,1),365)))
    ) x
  ),'[]'::jsonb);
end $$;

create or replace function security.important_date_queue_targeted_refresh_impl(
  p_important_date_id uuid, p_reason text
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
declare v_d pipeline.important_dates%rowtype; v_id uuid;
begin
  if auth.uid() is null or security.current_role_rank()<3 then
    raise exception 'curator role required' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'refresh reason required'; end if;
  select * into v_d from pipeline.important_dates where id=p_important_date_id and status='active';
  if not found then raise exception 'active important date not found'; end if;
  if v_d.refresh_layer is null then raise exception 'important date has no governed refresh layer'; end if;
  if v_d.source_id is null and v_d.source_profile_id is null and v_d.entity_id is null then
    raise exception 'country-wide important date cannot trigger ingestion';
  end if;
  insert into pipeline.refresh_requests(
    requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,reason,
    trigger_type,important_date_id,requested_by,change_control_ref
  ) values (
    v_d.refresh_layer,v_d.country_code,v_d.source_id,v_d.source_profile_id,v_d.entity_type,v_d.entity_id,
    trim(p_reason),'important_date',v_d.id,auth.uid(),v_d.change_control_ref
  ) returning id into v_id;
  return v_id;
end $$;

create or replace function security.layer4_review_context_impl(p_review_item_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
declare v jsonb;
begin
  if auth.uid() is null or security.current_role_rank()<3 then
    raise exception 'curator role required' using errcode='42501';
  end if;
  select jsonb_build_object(
    'review',to_jsonb(r),
    'evidence',jsonb_build_object(
      'id',e.id,'source_id',e.source_id,'source_url',e.source_url,'storage_path',e.storage_path,
      'content_hash',e.content_hash,'mime_type',e.mime_type,'captured_at',e.captured_at,
      'valid_from',e.valid_from,'valid_to',e.valid_to,'review_state',e.review_state,
      'retention_class',e.retention_class,'metadata',e.metadata
    ),
    'layer3',case when i.id is null then null else jsonb_build_object(
      'id',i.id,'profile_id',i.profile_id,'profile_code',p.code,'aggregator_provider',p.aggregator_provider,
      'configured_model',p.model_identifier,'response_model',i.aggregator_response_model,
      'prompt_profile_version',i.prompt_profile_version,'eligibility_reason',i.eligibility_reason,
      'revalidation_ref',i.revalidation_ref,'status',i.status,'candidate_value',i.candidate_value,
      'confidence',i.confidence,'rationale',i.rationale,'evidence_quotes',i.evidence_quotes,
      'validator_result',i.validator_result,'input_tokens',i.input_tokens,'output_tokens',i.output_tokens,
      'estimated_cost_usd',i.estimated_cost_usd,'interpretation_expires_at',i.interpretation_expires_at
    ) end,
    'history',coalesce((
      select jsonb_agg(to_jsonb(d) order by d.created_at)
      from pipeline.layer4_decisions d where d.review_item_id=r.id
    ),'[]'::jsonb)
  ) into v
  from pipeline.layer4_review_items r
  left join pipeline.evidence_artifacts e on e.id=r.evidence_id
  left join pipeline.layer3_interpretations i on i.id=r.layer3_interpretation_id
  left join pipeline.layer3_model_profiles p on p.id=i.profile_id
  where r.id=p_review_item_id;
  if v is null then raise exception 'review item not found'; end if;
  return v;
end $$;

revoke all on function security.layer4_review_context_impl(uuid) from public, anon, authenticated;
grant execute on function security.layer4_review_context_impl(uuid) to service_role;

create or replace function public.layer4_review_context(p_review_item_id uuid)
returns jsonb
language sql
stable
set search_path = pg_catalog, security
as $$ select security.layer4_review_context_impl(p_review_item_id) $$;
revoke all on function public.layer4_review_context(uuid) from public, anon;
grant execute on function public.layer4_review_context(uuid) to authenticated, service_role;

create or replace function security.layer4_review_decide_impl(
  p_review_item_id uuid, p_action text, p_reason text, p_final_value jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, security, pipeline, auth
as $$
declare
  v_actor uuid:=auth.uid(); v_rank int; v_item pipeline.layer4_review_items%rowtype;
  v_final jsonb; v_state text; v_scalar jsonb; v_scalar_id uuid; v_decision uuid;
  v_refresh_id uuid; v_search_signal_id uuid; v_evidence pipeline.evidence_artifacts%rowtype;
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=security.current_role_rank();
  if v_rank<3 then raise exception 'curator role required' using errcode='42501'; end if;
  if p_action not in ('approve','edit_and_approve','reject','request_more_evidence','return_layer2','return_layer3') then
    raise exception 'invalid action';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'decision reason required'; end if;

  select * into v_item from pipeline.layer4_review_items where id=p_review_item_id for update;
  if not found then raise exception 'review item not found'; end if;
  if v_item.status<>'pending' then raise exception 'review item already decided'; end if;
  select * into v_evidence from pipeline.evidence_artifacts where id=v_item.evidence_id;

  v_final:=case when p_action='approve' then v_item.proposed_value when p_action='edit_and_approve' then p_final_value else null end;
  if p_action='edit_and_approve' and p_final_value is null then raise exception 'edited final value required'; end if;

  if p_action in ('approve','edit_and_approve') then
    if v_item.entity_type<>'course' then raise exception 'terminal apply currently supports course scalar facts only'; end if;
    v_scalar:=security.layer4_course_scalar_resolve_impl(v_actor,v_item.entity_id,v_item.field_code,v_final,trim(p_reason));
    v_scalar_id:=nullif(v_scalar->>'resolution_id','')::uuid;
    v_state:=case when p_action='approve' then 'approved' else 'edited_approved' end;
  elsif p_action='reject' then v_state:='rejected';
  elsif p_action='request_more_evidence' then v_state:='more_evidence';
  elsif p_action='return_layer2' then v_state:='returned_layer2';
  else v_state:='returned_layer3'; end if;

  update pipeline.layer4_review_items set status=v_state,decided_at=now() where id=v_item.id;
  insert into pipeline.layer4_decisions(
    review_item_id,action,actor_id,reason,before_value,proposed_value,final_value,evidence_id,
    layer2_state,layer3_state,scalar_resolution_id,change_control_ref
  ) values (
    v_item.id,p_action,v_actor,trim(p_reason),v_item.before_value,v_item.proposed_value,v_final,
    v_item.evidence_id,v_item.layer2_state,v_item.layer3_state,v_scalar_id,v_item.change_control_ref
  ) returning id into v_decision;

  if p_action in ('request_more_evidence','return_layer2') then
    insert into pipeline.refresh_requests(
      requested_layer,source_id,entity_type,entity_id,evidence_id,reason,trigger_type,requested_by,change_control_ref
    ) values (
      2,v_evidence.source_id,v_item.entity_type,v_item.entity_id,v_item.evidence_id,trim(p_reason),
      'layer4_return',v_actor,v_item.change_control_ref
    ) returning id into v_refresh_id;
  elsif p_action='return_layer3' then
    insert into pipeline.refresh_requests(
      requested_layer,source_id,entity_type,entity_id,evidence_id,layer3_profile_id,revalidation_ref,
      reason,trigger_type,requested_by,change_control_ref
    ) values (
      3,v_evidence.source_id,v_item.entity_type,v_item.entity_id,v_item.evidence_id,
      nullif(v_item.layer3_state->>'profile_id','')::uuid,
      'L4:'||v_decision::text,trim(p_reason),'layer4_return',v_actor,v_item.change_control_ref
    ) returning id into v_refresh_id;
  end if;

  if p_action in ('approve','edit_and_approve') then
    insert into pipeline.search_refresh_signals(
      entity_type,entity_id,review_decision_id,reason,change_control_ref
    ) values (
      v_item.entity_type,v_item.entity_id,v_decision,
      'Accepted Layer 4 canonical change: '||trim(p_reason),v_item.change_control_ref
    ) returning id into v_search_signal_id;
  end if;

  return jsonb_build_object(
    'ok',true,'decision_id',v_decision,'review_item_id',v_item.id,'action',p_action,'status',v_state,
    'final_value',v_final,'scalar_resolution_id',v_scalar_id,'refresh_request_id',v_refresh_id,
    'publication_changed',false,'search_refresh_required',v_search_signal_id is not null,
    'search_refresh_signal_id',v_search_signal_id
  );
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
    select d.*
    from pipeline.important_dates d
    where d.status='active'
      and d.refresh_layer is not null
      and d.starts_at is not null
      and d.starts_at - d.warning_window <= p_now
      and (d.ends_at is null or d.ends_at >= p_now)
      and (d.source_id is not null or d.source_profile_id is not null or d.entity_id is not null)
    order by d.starts_at
    limit least(greatest(p_limit,1),500)
  ), ins as (
    insert into pipeline.refresh_requests(
      requested_layer,country_code,source_id,source_profile_id,entity_type,entity_id,
      reason,trigger_type,important_date_id,requested_by,change_control_ref
    )
    select d.refresh_layer,d.country_code,d.source_id,d.source_profile_id,d.entity_type,d.entity_id,
           'Important Date warning window: '||d.title,'important_date',d.id,null,d.change_control_ref
    from target_dates d
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

revoke all on function security.refresh_scheduler_tick_impl(timestamptz,integer) from public, anon, authenticated;
grant execute on function security.refresh_scheduler_tick_impl(timestamptz,integer) to service_role;

-- Seed bounded source-aware policies from already accepted AU/NZ source registry.
insert into pipeline.refresh_policies(
  country_code,layer,source_id,freshness_class,cadence_interval,next_due_at,
  hash_sensitive,important_date_sensitive,enabled,change_control_ref
)
select v.country_code,v.layer,v.source_id,v.freshness_class,v.cadence,v.next_due_at,
       v.hash_sensitive,v.important_date_sensitive,true,'CF-CHG-20260825-038'
from (values
  ('AU',1,'b5680d74-49c5-49a5-b198-a625f3e3fdcf'::uuid,'weekly',interval '7 days',now()+interval '7 days',true,false),
  ('NZ',1,'e410b159-614e-45ef-b8f4-902c7b516257'::uuid,'weekly',interval '7 days',now()+interval '7 days',true,false),
  ('NZ',1,'85138f05-a23f-48c8-bf99-46a18e0aea04'::uuid,'monthly',interval '30 days',now()+interval '30 days',true,false),
  ('AU',2,'37f1776c-77a3-4083-8ec7-7d76ad7a9ad8'::uuid,'monthly',interval '30 days',now()+interval '30 days',true,true),
  ('AU',2,'a37a569c-105e-4d9e-b802-44b68ff7ecc6'::uuid,'annual',interval '365 days',now()+interval '365 days',true,false),
  ('AU',2,'d817ea87-a96c-4e06-adbf-f6c957344d87'::uuid,'annual',interval '365 days',now()+interval '365 days',true,false),
  ('AU',2,'84bd8ff0-4932-49bd-bb99-f09cf118a0c6'::uuid,'annual',interval '365 days',now()+interval '365 days',true,false),
  ('AU',2,'925f5942-7c5e-4408-8307-1c2a4d4117d4'::uuid,'annual',interval '365 days',now()+interval '365 days',true,false),
  ('AU',2,'17a7d379-9448-41ca-bca5-bb7537ffff4b'::uuid,'weekly',interval '7 days',now()+interval '7 days',true,true),
  ('AU',2,'a9443687-678b-436f-9c16-62fcb800af14'::uuid,'weekly',interval '7 days',now()+interval '7 days',true,true)
) as v(country_code,layer,source_id,freshness_class,cadence,next_due_at,hash_sensitive,important_date_sensitive)
where exists (select 1 from pipeline.sources s where s.id=v.source_id)
  and not exists (
    select 1 from pipeline.refresh_policies p
    where p.layer=v.layer and p.source_id=v.source_id and p.entity_id is null and p.source_profile_id is null
  );

-- Seed governed directory only from sources already accepted in the CourseFinder source registry.
insert into pipeline.important_links(
  country_code,authority_category,authority_name,owner_label,url,purpose,related_layer,related_source_id,
  verification_cadence,next_verification_at,health_status,change_control_ref
) values
('AU','regulatory_authority','CRICOS / Australian Government Data Catalogue','Data Operations',
 'https://data.gov.au/data/dataset/cricos','Authoritative regulatory Provider, Course and location dataset discovery.',1,
 'b5680d74-49c5-49a5-b198-a625f3e3fdcf',interval '30 days',now(),'unverified','CF-CHG-20260825-038'),
('AU','statistics_data','Department of Education PRISMS International Student Data','Data Operations',
 'https://www.education.gov.au/download/15221/international-student-enrolment-and-commencement-data-abs-sa4-publication/44345/document/xlsx',
 'Official international-student enrolment and commencement context used by governed PRISMS enrichment.',2,
 '37f1776c-77a3-4083-8ec7-7d76ad7a9ad8',interval '30 days',now(),'unverified','CF-CHG-20260825-038'),
('AU','quality_outcomes','QILT Graduate Outcomes Survey','Data Operations',
 'https://www.qilt.edu.au/docs/default-source/default-document-library/gos_2025_national_report_tables.zip?sfvrsn=643ae941_1',
 'Official QILT outcomes source; retain Provider/study-area grain and never present it as Course-grain evidence.',2,
 'd817ea87-a96c-4e06-adbf-f6c957344d87',interval '90 days',now(),'unverified','CF-CHG-20260825-038'),
('AU','official_scholarship','Study Australia Scholarship Search','Data Operations',
 'https://search.studyaustralia.gov.au/scholarships','Official government scholarship discovery source.',2,
 '17a7d379-9448-41ca-bca5-bb7537ffff4b',interval '30 days',now(),'unverified','CF-CHG-20260825-038'),
('AU','official_scholarship','DFAT Australia Awards Scholarships','Data Operations',
 'https://www.dfat.gov.au/people-to-people/australia-awards/australia-awards-scholarships',
 'Official Australian Government scholarship programme source.',2,
 'a9443687-678b-436f-9c16-62fcb800af14',interval '30 days',now(),'unverified','CF-CHG-20260825-038'),
('NZ','regulatory_authority','NZQA Education Organisations','Data Operations',
 'https://www.nzqa.govt.nz/providers/index.do','Primary accepted New Zealand education organisation authority source.',1,
 'e410b159-614e-45ef-b8f4-902c7b516257',interval '30 days',now(),'unverified','CF-CHG-20260825-038'),
('NZ','statistics_data','Education Counts Tertiary Providers Directory','Data Operations',
 'https://www.educationcounts.govt.nz/directories/list-of-tertiary-providers',
 'Official tertiary-provider directory used as a secondary identity/coverage source.',1,
 '85138f05-a23f-48c8-bf99-46a18e0aea04',interval '30 days',now(),'unverified','CF-CHG-20260825-038')
on conflict(country_code,url) do update set
  authority_category=excluded.authority_category,authority_name=excluded.authority_name,
  owner_label=excluded.owner_label,purpose=excluded.purpose,related_layer=excluded.related_layer,
  related_source_id=excluded.related_source_id,verification_cadence=excluded.verification_cadence,
  next_verification_at=least(pipeline.important_links.next_verification_at,now()),
  change_control_ref=excluded.change_control_ref,updated_at=now();

do $$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname='coursefinder-m2-3-refresh-intelligence-tick';
  if v_job is not null then perform cron.unschedule(v_job); end if;
  perform cron.schedule(
    'coursefinder-m2-3-refresh-intelligence-tick',
    '*/15 * * * *',
    'select security.refresh_scheduler_tick_impl(now(), 100);'
  );
end $$;