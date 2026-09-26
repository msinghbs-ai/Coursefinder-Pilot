-- Package 7 (Decision 141): per-provider Layer 2 onboarding by a person while Layer 3 AI is paused.
-- An operator supplies the provider's course catalogue page; the same deterministic path as the
-- Layer 3 source-pattern hand-back then runs: new profile version (catalogue link scan), three
-- control courses, and the existing three-course identity check (3 of 3). Nothing reaches the
-- catalogue, search or publication unless that check passes. Audited per submission.
create table if not exists pipeline.layer2_provider_catalogue_submissions(
  id uuid primary key default extensions.gen_random_uuid(),
  provider_id uuid not null references catalogue.providers(id),
  catalogue_url text not null,
  reason text not null,
  actor_id uuid not null,
  dry_run boolean not null,
  outcome jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists layer2_provider_catalogue_submissions_provider_idx on pipeline.layer2_provider_catalogue_submissions(provider_id, created_at desc);
alter table pipeline.layer2_provider_catalogue_submissions enable row level security;
revoke all on pipeline.layer2_provider_catalogue_submissions from public, anon, authenticated;

create or replace function security.site_host(p_url text) returns text language sql immutable
as $$ select regexp_replace(lower(substring(coalesce(p_url,'') from '^https?://([^/:?#]+)')), '^www\.', '') $$;

create or replace function security.layer2_provider_catalogue_submit_impl(p_actor uuid, p_provider_id uuid, p_catalogue_url text, p_reason text, p_dry_run boolean)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','extensions'
as $function$
declare v_url text := btrim(coalesce(p_catalogue_url,'')); v_host text; v_site_hosts text[]; lp pipeline.layer2_source_profiles%rowtype;
  v_run uuid; v_ids uuid[]; v_cfg jsonb; v_hash text; v_validation jsonb; v_ver uuid; v_no int; v_dispatch jsonb; v_out jsonb;
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
  v_cfg := jsonb_set(v_cfg,'{source_authority}',to_jsonb('first_party_candidate_under_person_supplied_pattern'::text),true);
  v_cfg := jsonb_set(v_cfg,'{change_control_ref}',to_jsonb('CF-CHG-20260915-247'::text),true);
  v_validation := security.layer2_validate_profile_config(v_cfg);
  if not coalesce((v_validation->>'valid')::boolean,false) then raise exception 'the resulting Layer 2 profile is invalid: %', v_validation using errcode='22023'; end if;
  v_out := jsonb_build_object('provider_id',p_provider_id,'catalogue_url',v_url,'run_id',v_run,'profile_id',lp.id,'control_course_ids',to_jsonb(v_ids),'identity_control_required','3_of_3','dry_run',p_dry_run);
  if not p_dry_run then
    v_hash := encode(extensions.digest(v_cfg::text,'sha256'),'hex');
    select coalesce(max(version_no),0)+1 into v_no from pipeline.layer2_source_profile_versions where profile_id=lp.id;
    insert into pipeline.layer2_source_profile_versions(profile_id,version_no,configuration,configuration_hash,validation_status,validation_result,change_control_ref,uat_ref,created_by)
    values (lp.id,v_no,v_cfg,v_hash,'valid',v_validation,'CF-CHG-20260915-247','Decision-141-person-supplied-pattern',p_actor) returning id into v_ver;
    update pipeline.layer2_source_profiles set current_version_id=v_ver, updated_at=now() where id=lp.id;
    update pipeline.layer2_scale_qualification_items qi set status='source_pattern_candidate',
      outcome=coalesce(qi.outcome,'{}'::jsonb)||jsonb_build_object('stage','course_page_source_pattern_validation','source_pattern_origin','person_supplied',
        'catalogue_candidate_url',v_url,'pattern_dispatch_version_id',v_ver,'control_course_ids',to_jsonb(v_ids),'identity_control_required','3_of_3','submitted_by',p_actor,
        'canonical_mutation_authorised',false,'search_mutation_authorised',false,'publication_mutation_authorised',false)
     where qi.run_id=v_run and qi.provider_id=p_provider_id and qi.status in ('layer3_required','layer4_required');
    v_dispatch := security.layer2_discovery_scope_dispatch_v2(lp.id, v_ids, 3, null, v_ids);
    v_out := v_out || jsonb_build_object('profile_version_id',v_ver,'dispatch',v_dispatch,'provider_qualified',false,'next','three-course identity check running');
  end if;
  insert into pipeline.layer2_provider_catalogue_submissions(provider_id,catalogue_url,reason,actor_id,dry_run,outcome) values (p_provider_id,v_url,btrim(p_reason),p_actor,p_dry_run,v_out);
  return v_out;
end $function$;
revoke all on function security.layer2_provider_catalogue_submit_impl(uuid,uuid,text,text,boolean) from public, anon, authenticated;

create or replace function public.layer2_provider_catalogue_submit_v1(p_provider_id uuid, p_catalogue_url text, p_reason text, p_dry_run boolean default false)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','security','public'
as $$
declare v_actor uuid := auth.uid();
begin
  if v_actor is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 4 then raise exception 'Pipeline Operator role is required to onboard a provider' using errcode='42501'; end if;
  return security.layer2_provider_catalogue_submit_impl(v_actor, p_provider_id, p_catalogue_url, p_reason, coalesce(p_dry_run,false));
end $$;
revoke all on function public.layer2_provider_catalogue_submit_v1(uuid,text,text,boolean) from public, anon;
grant execute on function public.layer2_provider_catalogue_submit_v1(uuid,text,text,boolean) to authenticated, service_role;

create or replace function public.layer2_provider_onboarding_queue_v1(p_country text default 'AU', p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','security','pipeline','catalogue','public'
as $$
declare v jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'Curator role is required' using errcode='42501'; end if;
  with w as (
    select c.provider_id, count(*) waiting from pipeline.au_nz_enrichment_backlog_v1 b join catalogue.courses c on c.id=b.course_id
    where b.field_key='official_course_url' and b.backlog_state='awaiting_source_profile_qualification' and b.country_code=upper(coalesce(p_country,'AU'))
    group by 1),
  q as (
    select w.provider_id, w.waiting, p.canonical_name, p.website,
      exists(select 1 from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id where s.provider_id=w.provider_id and sp.authority_class='qualification_candidate' and sp.domain='course_facts' and sp.enabled and not sp.paused) has_candidate_profile,
      (select jsonb_object_agg(st,n) from (select qi.status st, count(*) n from pipeline.layer2_scale_qualification_items qi where qi.provider_id=w.provider_id group by 1) z) item_states,
      (select jsonb_build_object('url',x.catalogue_url,'at',x.created_at,'dry_run',x.dry_run) from pipeline.layer2_provider_catalogue_submissions x where x.provider_id=w.provider_id order by x.created_at desc limit 1) last_submission
    from w join catalogue.providers p on p.id=w.provider_id)
  select jsonb_build_object('country',upper(coalesce(p_country,'AU')),'providers_waiting',(select count(*) from q),'courses_waiting',(select coalesce(sum(waiting),0) from q),
    'items',coalesce((select jsonb_agg(jsonb_build_object('provider_id',provider_id,'provider',canonical_name,'website',website,'courses_waiting',waiting,
        'state',case when (item_states ? 'source_pattern_candidate') then 'identity_check_running'
                     when (item_states ? 'layer3_required') or (item_states ? 'layer4_required') then 'needs_catalogue_page'
                     when (item_states ? 'source_limited') then 'site_limited'
                     when item_states is null then 'not_yet_assessed' else 'in_progress' end,
        'ready_for_submission',has_candidate_profile and ((item_states ? 'layer3_required') or (item_states ? 'layer4_required')),
        'suggested_start',website,'last_submission',last_submission) order by waiting desc)
      from (select * from q order by waiting desc limit greatest(1,least(coalesce(p_limit,50),200))) t),'[]'::jsonb))
  into v;
  return v;
end $$;
revoke all on function public.layer2_provider_onboarding_queue_v1(text,integer) from public, anon;
grant execute on function public.layer2_provider_onboarding_queue_v1(text,integer) to authenticated, service_role;
