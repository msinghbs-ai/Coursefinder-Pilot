-- CF-CHG-20260905-211 — H5 source-backed PIM candidates + H6 publication controls

create table if not exists pipeline.pim_source_candidates (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('provider','course','campus','scholarship')),
  target_provider_id uuid null,
  source_kind text not null check (source_kind in ('authority','first_party')),
  external_identifier text null,
  source_url text null,
  evidence_id uuid null references pipeline.evidence_artifacts(id),
  candidate_payload jsonb not null default '{}'::jsonb,
  status text not null default 'submitted' check (status in ('submitted','validated','needs_review','ready_for_acquisition','rejected','cancelled')),
  reason text not null,
  decision_reason text null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_by uuid not null,
  updated_at timestamptz not null default now()
);
create index if not exists pim_source_candidates_queue_idx on pipeline.pim_source_candidates(status,entity_type,created_at desc);
create index if not exists pim_source_candidates_provider_idx on pipeline.pim_source_candidates(target_provider_id,created_at desc);
create unique index if not exists pim_source_candidates_active_identity_uq
  on pipeline.pim_source_candidates(entity_type,coalesce(target_provider_id,'00000000-0000-0000-0000-000000000000'::uuid),coalesce(external_identifier,''),coalesce(source_url,''))
  where status in ('submitted','validated','needs_review','ready_for_acquisition');
alter table pipeline.pim_source_candidates enable row level security;
revoke all on pipeline.pim_source_candidates from public,anon,authenticated;

create or replace function public.manual_pim_candidate_register(p_entity_type text,p_target_provider_id uuid default null,p_source_kind text default 'first_party',p_external_identifier text default null,p_source_url text default null,p_evidence_id uuid default null,p_candidate_payload jsonb default '{}'::jsonb,p_reason text default null)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','pipeline','security','auth' as $$
declare v_actor uuid:=auth.uid();v_rank int;v_id uuid;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;
 v_rank:=security.current_role_rank();if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501';end if;
 if p_entity_type not in ('provider','course','campus','scholarship') then raise exception 'invalid entity type' using errcode='22023';end if;
 if p_source_kind not in ('authority','first_party') then raise exception 'invalid source kind' using errcode='22023';end if;
 if p_entity_type in ('course','campus','scholarship') and p_target_provider_id is null then raise exception 'target Provider required' using errcode='22023';end if;
 if p_evidence_id is null and length(trim(coalesce(p_source_url,'')))<8 then raise exception 'source URL or Evidence required' using errcode='22023';end if;
 if p_evidence_id is not null and not exists(select 1 from pipeline.evidence_artifacts where id=p_evidence_id) then raise exception 'Evidence not found' using errcode='22023';end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'reason required' using errcode='22023';end if;
 insert into pipeline.pim_source_candidates(entity_type,target_provider_id,source_kind,external_identifier,source_url,evidence_id,candidate_payload,reason,created_by,updated_by)
 values(p_entity_type,p_target_provider_id,p_source_kind,nullif(trim(coalesce(p_external_identifier,'')),''),nullif(trim(coalesce(p_source_url,'')),''),p_evidence_id,coalesce(p_candidate_payload,'{}'),trim(p_reason),v_actor,v_actor) returning id into v_id;
 return jsonb_build_object('ok',true,'candidate_id',v_id,'status','submitted','canonical_written',false,'published',false);
exception when unique_violation then raise exception 'matching active source-backed candidate already exists' using errcode='23505';
end$$;

create or replace function public.manual_pim_candidates_read(p_status text default null,p_entity_type text default null,p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','public','pipeline','security','auth' as $$
declare v_actor uuid:=auth.uid();v_rank int;v_items jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;
 v_rank:=security.current_role_rank();if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') into v_items from(
  select id,entity_type,target_provider_id,source_kind,external_identifier,source_url,evidence_id,candidate_payload,status,reason,decision_reason,created_by,created_at,updated_by,updated_at
  from pipeline.pim_source_candidates where(p_status is null or status=p_status)and(p_entity_type is null or entity_type=p_entity_type)
  order by created_at desc limit least(greatest(coalesce(p_limit,100),1),200))x;
 return jsonb_build_object('items',v_items);
end$$;

create or replace function public.manual_pim_candidate_decide(p_candidate_id uuid,p_action text,p_reason text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','pipeline','security','auth' as $$
declare v_actor uuid:=auth.uid();v_rank int;v_status text;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;
 v_rank:=security.current_role_rank();if v_rank<5 then raise exception 'PIM Operator role required' using errcode='42501';end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'decision reason required' using errcode='22023';end if;
 v_status:=case p_action when 'validate' then 'validated' when 'review' then 'needs_review' when 'ready' then 'ready_for_acquisition' when 'reject' then 'rejected' when 'cancel' then 'cancelled' end;
 if v_status is null then raise exception 'invalid candidate action' using errcode='22023';end if;
 update pipeline.pim_source_candidates set status=v_status,decision_reason=trim(p_reason),updated_by=v_actor,updated_at=now() where id=p_candidate_id;
 if not found then raise exception 'candidate not found' using errcode='22023';end if;
 return jsonb_build_object('ok',true,'candidate_id',p_candidate_id,'status',v_status,'canonical_written',false,'published',false);
end$$;

create table if not exists pipeline.publication_control_settings(singleton boolean primary key default true check(singleton),auto_publication_enabled boolean not null default false,updated_at timestamptz not null default now());
insert into pipeline.publication_control_settings(singleton,auto_publication_enabled)values(true,false)on conflict(singleton)do nothing;
alter table pipeline.publication_control_settings enable row level security;
revoke all on pipeline.publication_control_settings from public,anon,authenticated;

create or replace function public.publication_control_preview(p_entity_type text,p_entity_ids uuid[],p_target_scope text,p_action text)
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','public','pipeline','security','auth' as $$
declare v_actor uuid:=auth.uid();v_rank int;v_ids uuid[];v_id uuid;v_items jsonb:='[]';v_token text;v_state jsonb;v_auto boolean;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;
 v_rank:=security.current_role_rank();if v_rank<5 then raise exception 'PIM Admin role required' using errcode='42501';end if;
 if p_action not in('publish','unpublish','rollback')then raise exception 'invalid publication action' using errcode='22023';end if;
 if p_target_scope not in('search_api','website','zoho','governed_publication')then raise exception 'invalid target scope' using errcode='22023';end if;
 select array_agg(distinct x order by x)into v_ids from unnest(coalesce(p_entity_ids,'{}'::uuid[]))x;
 if coalesce(array_length(v_ids,1),0)<1 then raise exception 'at least one entity required' using errcode='22023';end if;
 if array_length(v_ids,1)>100 then raise exception 'publication cohort exceeds 100 records' using errcode='22023';end if;
 foreach v_id in array v_ids loop
  if not security.layer4_entity_exists(p_entity_type,v_id)then raise exception 'entity not found: %',v_id using errcode='22023';end if;
  v_state:=public.layer4_publication_state(p_entity_type,v_id,p_target_scope);
  v_items:=v_items||jsonb_build_array(jsonb_build_object('entity_id',v_id,'current_state',v_state));
 end loop;
 select auto_publication_enabled into v_auto from pipeline.publication_control_settings where singleton=true;
 v_token:=md5(p_entity_type||'|'||p_target_scope||'|'||p_action||'|'||array_to_string(v_ids,','));
 return jsonb_build_object('entity_type',p_entity_type,'target_scope',p_target_scope,'action',p_action,'count',array_length(v_ids,1),'confirmation_token',v_token,'items',v_items,'auto_publication_enabled',coalesce(v_auto,false),'mutated',false);
end$$;

create or replace function public.publication_control_execute(p_entity_type text,p_entity_ids uuid[],p_target_scope text,p_action text,p_confirmation_token text,p_reason_code text,p_comment text default null)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public','pipeline','security','auth' as $$
declare v_actor uuid:=auth.uid();v_rank int;v_ids uuid[];v_id uuid;v_expected text;v_event text;v_results jsonb:='[]';v_result jsonb;
begin
 if v_actor is null then raise exception 'authentication required' using errcode='42501';end if;
 v_rank:=security.current_role_rank();if v_rank<5 then raise exception 'PIM Admin role required' using errcode='42501';end if;
 if p_action not in('publish','unpublish','rollback')then raise exception 'invalid publication action' using errcode='22023';end if;
 if p_target_scope not in('search_api','website','zoho','governed_publication')then raise exception 'invalid target scope' using errcode='22023';end if;
 if length(trim(coalesce(p_reason_code,'')))<3 then raise exception 'reason code required' using errcode='22023';end if;
 select array_agg(distinct x order by x)into v_ids from unnest(coalesce(p_entity_ids,'{}'::uuid[]))x;
 if coalesce(array_length(v_ids,1),0)<1 or array_length(v_ids,1)>100 then raise exception 'publication cohort must contain 1 to 100 records' using errcode='22023';end if;
 v_expected:=md5(p_entity_type||'|'||p_target_scope||'|'||p_action||'|'||array_to_string(v_ids,','));
 if coalesce(p_confirmation_token,'')<>v_expected then raise exception 'preview confirmation token mismatch' using errcode='22023';end if;
 v_event:=case p_action when'publish'then'publishable' when'unpublish'then'not_publishable' else'revert'end;
 foreach v_id in array v_ids loop
  v_result:=public.layer4_publication_decide(p_entity_type,v_id,p_target_scope,v_event,'{}','[]',p_reason_code,p_comment,jsonb_build_object('cohort_token',v_expected,'cohort_size',array_length(v_ids,1),'action',p_action));
  v_results:=v_results||jsonb_build_array(jsonb_build_object('entity_id',v_id,'result',v_result));
 end loop;
 return jsonb_build_object('ok',true,'count',array_length(v_ids,1),'target_scope',p_target_scope,'action',p_action,'cohort_token',v_expected,'results',v_results,'consumer_cutover_authorised',false,'auto_publication_enabled',false);
end$$;

revoke all on function public.manual_pim_candidate_register(text,uuid,text,text,text,uuid,jsonb,text) from public,anon;
revoke all on function public.manual_pim_candidates_read(text,text,integer) from public,anon;
revoke all on function public.manual_pim_candidate_decide(uuid,text,text) from public,anon;
revoke all on function public.publication_control_preview(text,uuid[],text,text) from public,anon;
revoke all on function public.publication_control_execute(text,uuid[],text,text,text,text,text) from public,anon;
grant execute on function public.manual_pim_candidate_register(text,uuid,text,text,text,uuid,jsonb,text) to authenticated;
grant execute on function public.manual_pim_candidates_read(text,text,integer) to authenticated;
grant execute on function public.manual_pim_candidate_decide(uuid,text,text) to authenticated;
grant execute on function public.publication_control_preview(text,uuid[],text,text) to authenticated;
grant execute on function public.publication_control_execute(text,uuid[],text,text,text,text,text) to authenticated;
