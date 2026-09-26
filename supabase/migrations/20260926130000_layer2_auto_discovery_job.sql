-- Package 7 (Decisions 141, 146): automatic catalogue discovery.
-- Every 5 minutes (no-op while automation is off): settle identity checks in progress, then start
-- new providers within the Platform Admin limits, trying each provider's ranked candidates from
-- stored evidence through the same submit path and three-course identity check (3 of 3).
alter table pipeline.layer2_provider_catalogue_submissions add column if not exists origin text not null default 'person' check (origin in ('person','automatic'));

create table if not exists pipeline.layer2_auto_discovery_attempts(
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  run_id uuid,
  candidate_url text,
  score int,
  evidence_id uuid,
  status text not null check (status in ('checking','passed','failed','error','needs_person')),
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists layer2_auto_discovery_attempts_provider_idx on pipeline.layer2_auto_discovery_attempts(provider_id, created_at desc);
create index if not exists layer2_auto_discovery_attempts_status_idx on pipeline.layer2_auto_discovery_attempts(status) where status='checking';
alter table pipeline.layer2_auto_discovery_attempts enable row level security;
revoke all on pipeline.layer2_auto_discovery_attempts from public, anon, authenticated;

-- Submit path gains an origin (default person); behaviour otherwise unchanged.
drop function if exists security.layer2_provider_catalogue_submit_impl(uuid,uuid,text,text,boolean);
create or replace function security.layer2_provider_catalogue_submit_impl(p_actor uuid, p_provider_id uuid, p_catalogue_url text, p_reason text, p_dry_run boolean, p_origin text default 'person')
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','extensions'
as $function$
declare v_url text := btrim(coalesce(p_catalogue_url,'')); v_host text; v_site_hosts text[]; lp pipeline.layer2_source_profiles%rowtype;
  v_run uuid; v_ids uuid[]; v_cfg jsonb; v_hash text; v_validation jsonb; v_ver uuid; v_no int; v_dispatch jsonb; v_out jsonb;
  v_origin text := case when p_origin='automatic' then 'automatic' else 'person' end;
begin
  if v_url !~ '^https://[^[:space:]]+$' then raise exception 'the catalogue page must be a full https:// address' using errcode='22023'; end if;
  if length(btrim(coalesce(p_reason,''))) < 8 then raise exception 'a reason of at least 8 characters is required' using errcode='22023'; end if;
  v_host := security.site_host(v_url);
  select array_agg(distinct h) into v_site_hosts from (
    select security.site_host(p.website) h from catalogue.providers p where p.id=p_provider_id
    union select security.site_host(s.url) from pipeline.sources s where s.provider_id=p_provider_id and s.url !~* '(hotcourses|studyin|idp\.com)') x where h is not null and h<>'';
  if v_site_hosts is null or not (v_host = any(v_site_hosts) or exists(select 1 from unnest(v_site_hosts) h where v_host like '%.'||h)) then
    raise exception 'the address must be on the provider''s own website (%)', array_to_string(v_site_hosts,', ') using errcode='22023'; end if;
  select sp.* into lp from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
   where s.provider_id=p_provider_id and sp.authority_class='qualification_candidate' and sp.domain='course_facts' and sp.enabled and not sp.paused
   order by sp.updated_at desc limit 1;
  if lp.id is null then raise exception 'this provider has no qualification-candidate Layer 2 profile yet' using errcode='22023'; end if;
  select qi.run_id into v_run from pipeline.layer2_scale_qualification_items qi
   where qi.provider_id=p_provider_id and qi.status in ('layer3_required','layer4_required')
   group by qi.run_id having count(*)>=3 order by max(qi.created_at) desc limit 1;
  if v_run is null then raise exception 'this provider has no qualification run waiting on its course-page pattern' using errcode='22023'; end if;
  select array_agg(x.course_id order by x.sample_rank) into v_ids from (select qi.course_id, qi.sample_rank from pipeline.layer2_scale_qualification_items qi
    where qi.run_id=v_run and qi.provider_id=p_provider_id and qi.status in ('layer3_required','layer4_required') order by qi.sample_rank limit 3) x;
  if coalesce(array_length(v_ids,1),0)<>3 then raise exception 'three control courses are required' using errcode='22023'; end if;
  select configuration into v_cfg from pipeline.layer2_source_profile_versions where id=lp.current_version_id;
  if v_cfg is null then raise exception 'the provider profile has no current configuration' using errcode='22023'; end if;
  v_cfg := jsonb_set(jsonb_set(v_cfg,'{discovery_strategy}',jsonb_build_object('type','catalogue_link_scan','catalogue_url',v_url,'course_acquisition_budget_ms',60000,'qualification_control_sample_size',3),true),
                     '{url_patterns}',coalesce(v_cfg->'url_patterns','[]'::jsonb)||jsonb_build_array(v_url),true);
  v_cfg := jsonb_set(v_cfg,'{source_authority}',to_jsonb(case when v_origin='automatic' then 'first_party_candidate_under_evidence_ranked_pattern' else 'first_party_candidate_under_person_supplied_pattern' end),true);
  v_cfg := jsonb_set(v_cfg,'{change_control_ref}',to_jsonb('CF-CHG-20260915-247'::text),true);
  v_validation := security.layer2_validate_profile_config(v_cfg);
  if not coalesce((v_validation->>'valid')::boolean,false) then raise exception 'the resulting Layer 2 profile is invalid: %', v_validation using errcode='22023'; end if;
  v_out := jsonb_build_object('provider_id',p_provider_id,'catalogue_url',v_url,'run_id',v_run,'profile_id',lp.id,'control_course_ids',to_jsonb(v_ids),'identity_control_required','3_of_3','dry_run',p_dry_run,'origin',v_origin);
  if not p_dry_run then
    v_hash := encode(extensions.digest(v_cfg::text,'sha256'),'hex');
    select coalesce(max(version_no),0)+1 into v_no from pipeline.layer2_source_profile_versions where profile_id=lp.id;
    insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref,uat_ref,created_by)
    values (lp.id,v_no,v_cfg,v_hash,'valid',v_validation,'CF-CHG-20260915-247',case when v_origin='automatic' then 'Decision-146-evidence-ranked-pattern' else 'Decision-141-person-supplied-pattern' end,p_actor) returning id into v_ver;
    update pipeline.layer2_source_profiles set current_version_id=v_ver, updated_at=now() where id=lp.id;
    update pipeline.layer2_scale_qualification_items qi set status='source_pattern_candidate',
      outcome=coalesce(qi.outcome,'{}'::jsonb)||jsonb_build_object('stage','course_page_source_pattern_validation','source_pattern_origin',case when v_origin='automatic' then 'evidence_ranked' else 'person_supplied' end,
        'catalogue_candidate_url',v_url,'pattern_dispatch_version_id',v_ver,'control_course_ids',to_jsonb(v_ids),'identity_control_required','3_of_3','submitted_by',p_actor,
        'canonical_mutation_authorised',false,'search_mutation_authorised',false,'publication_mutation_authorised',false)
     where qi.run_id=v_run and qi.provider_id=p_provider_id and qi.status in ('layer3_required','layer4_required');
    v_dispatch := security.layer2_discovery_scope_dispatch_v2(lp.id, v_ids, 3, null, v_ids);
    v_out := v_out || jsonb_build_object('profile_version_id',v_ver,'dispatch',v_dispatch,'provider_qualified',false,'next','three-course identity check running');
  end if;
  insert into pipeline.layer2_provider_catalogue_submissions(provider_id,catalogue_url,reason,actor_id,dry_run,outcome,origin) values (p_provider_id,v_url,btrim(p_reason),p_actor,p_dry_run,v_out,v_origin);
  return v_out;
end $function$;
revoke all on function security.layer2_provider_catalogue_submit_impl(uuid,uuid,text,text,boolean,text) from public, anon, authenticated;

-- The discovery job.
create or replace function security.layer2_auto_discovery_tick_v1()
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','public'
as $function$
declare s pipeline.layer2_auto_discovery_settings%rowtype; r record; a record; c jsonb; v_actor uuid; v_in_flight int; v_today int;
  v_settled int:=0; v_started int:=0; v_url text; v_tried int; v_res jsonb; v_status text;
begin
  select * into s from pipeline.layer2_auto_discovery_settings where id=1;
  if not coalesce(s.enabled,false) then return jsonb_build_object('enabled',false); end if;

  -- 1. Settle identity checks in progress (the reconcile decides pass, fail or timeout).
  for r in select distinct run_id from pipeline.layer2_auto_discovery_attempts where status='checking' and run_id is not null loop
    perform public.layer2_scale_pattern_reconcile(r.run_id);
  end loop;
  for a in select * from pipeline.layer2_auto_discovery_attempts where status='checking' loop
    select case when bool_or(qi.status='profile_qualified') then 'passed'
                when bool_or(qi.status='source_pattern_candidate') then 'checking' else 'failed' end
      into v_status from pipeline.layer2_scale_qualification_items qi where qi.run_id=a.run_id and qi.provider_id=a.provider_id;
    if v_status in ('passed','failed') then
      update pipeline.layer2_auto_discovery_attempts set status=v_status, resolved_at=now(),
        detail=detail||jsonb_build_object('reconciled_at',now()) where id=a.id;
      v_settled := v_settled+1;
    end if;
  end loop;

  -- 2. Start new providers within the limits.
  select count(distinct provider_id) into v_in_flight from pipeline.layer2_auto_discovery_attempts where status='checking';
  select count(distinct provider_id) into v_today from pipeline.layer2_auto_discovery_attempts
   where created_at >= date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne' and status<>'needs_person';
  v_actor := public.layer2_automation_actor();
  for r in
    with w as (
      select c2.provider_id, count(*) waiting from pipeline.au_nz_enrichment_backlog_v1 b join catalogue.courses c2 on c2.id=b.course_id
      where b.field_key='official_course_url' and b.backlog_state='awaiting_source_profile_qualification' and b.country_code='AU' group by 1)
    select w.provider_id, w.waiting from w
    where exists(select 1 from pipeline.layer2_scale_qualification_items qi where qi.provider_id=w.provider_id and qi.status in ('layer3_required','layer4_required'))
      and not exists(select 1 from pipeline.layer2_auto_discovery_attempts x where x.provider_id=w.provider_id and x.status in ('checking','passed','needs_person'))
    order by w.waiting desc
  loop
    exit when v_in_flight >= s.providers_in_flight or v_today >= s.daily_provider_cap or v_actor is null;
    select count(*) into v_tried from pipeline.layer2_auto_discovery_attempts x where x.provider_id=r.provider_id and x.status in ('failed','error');
    if v_tried >= s.candidates_per_provider then
      insert into pipeline.layer2_auto_discovery_attempts(provider_id,status,detail,resolved_at)
      values (r.provider_id,'needs_person',jsonb_build_object('reason','candidates exhausted','tried',v_tried),now());
      continue;
    end if;
    select x into c from jsonb_array_elements(security.layer2_catalogue_candidates_v1(r.provider_id, 10)) x
     where not exists(select 1 from pipeline.layer2_auto_discovery_attempts t where t.provider_id=r.provider_id
                      and t.candidate_url=regexp_replace(x->>'url','^http://','https://'))
     order by (x->>'score')::int desc limit 1;
    if c is null then
      insert into pipeline.layer2_auto_discovery_attempts(provider_id,status,detail,resolved_at)
      values (r.provider_id,'needs_person',jsonb_build_object('reason', case when v_tried=0 then 'no candidate in stored evidence' else 'no further candidates' end,'tried',v_tried),now());
      continue;
    end if;
    v_url := regexp_replace(c->>'url','^http://','https://');
    begin
      v_res := security.layer2_provider_catalogue_submit_impl(v_actor, r.provider_id, v_url,
        'Automatic discovery: ranked candidate from stored evidence (score '||(c->>'score')||')', false, 'automatic');
      insert into pipeline.layer2_auto_discovery_attempts(provider_id,run_id,candidate_url,score,evidence_id,status,detail)
      values (r.provider_id,(v_res->>'run_id')::uuid,v_url,(c->>'score')::int,(c->>'evidence_id')::uuid,'checking',
              jsonb_build_object('link_text',c->>'link_text','profile_version_id',v_res->>'profile_version_id','waiting_courses',r.waiting));
      v_in_flight := v_in_flight+1; v_today := v_today+1; v_started := v_started+1;
    exception when others then
      insert into pipeline.layer2_auto_discovery_attempts(provider_id,candidate_url,score,evidence_id,status,detail,resolved_at)
      values (r.provider_id,v_url,(c->>'score')::int,(c->>'evidence_id')::uuid,'error',jsonb_build_object('error',left(sqlerrm,300)),now());
    end;
  end loop;
  return jsonb_build_object('enabled',true,'settled',v_settled,'started',v_started,'in_flight',v_in_flight,'started_today',v_today,
    'limits',jsonb_build_object('per_day',s.daily_provider_cap,'in_flight',s.providers_in_flight,'candidates',s.candidates_per_provider));
end $function$;
revoke all on function security.layer2_auto_discovery_tick_v1() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname='layer2-auto-discovery';
select cron.schedule('layer2-auto-discovery','2-59/5 * * * *',$c$select security.layer2_auto_discovery_tick_v1();$c$);
