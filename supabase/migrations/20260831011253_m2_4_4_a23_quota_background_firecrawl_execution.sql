
create table if not exists pipeline.layer2_execution_policy(
  policy_key text primary key,
  enabled boolean not null default true,
  qualification_provider_wave_size integer not null default 50 check(qualification_provider_wave_size between 1 and 200),
  qualification_provider_wave_max integer not null default 100 check(qualification_provider_wave_max between 1 and 500),
  qualification_sample_size integer not null default 10 check(qualification_sample_size between 1 and 50),
  qualification_retry_hours integer not null default 168 check(qualification_retry_hours between 1 and 2160),
  production_target_wave_size integer not null default 500 check(production_target_wave_size between 1 and 5000),
  production_max_wave_size integer not null default 1000 check(production_max_wave_size between 1 and 5000),
  schedule_remaining boolean not null default true,
  route_mode text not null default 'scraper_first' check(route_mode in('scraper_first','managed')),
  updated_by uuid,
  updated_at timestamptz not null default now(),
  change_control_ref text not null default 'CF-CHG-20260830-048'
);
alter table pipeline.layer2_execution_policy enable row level security;
revoke all on pipeline.layer2_execution_policy from public,anon,authenticated;
insert into pipeline.layer2_execution_policy(
 policy_key,enabled,qualification_provider_wave_size,qualification_provider_wave_max,
 qualification_sample_size,qualification_retry_hours,production_target_wave_size,
 production_max_wave_size,schedule_remaining,route_mode
) values('default',true,50,100,10,168,500,1000,true,'scraper_first')
on conflict(policy_key) do nothing;

CREATE OR REPLACE FUNCTION public.layer2_background_scope_service(p_actor uuid, p_action text, p_country_code text, p_scope_type text DEFAULT 'country'::text, p_scope_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security'
AS $function$
declare
 v_rank integer:=0;
 v_policy pipeline.layer2_execution_policy%rowtype;
 v_firecrawl pipeline.layer2_acquisition_providers%rowtype;
 v_budget jsonb:='{}'::jsonb;
 v_preview jsonb;
 v_qual jsonb;
 v_wave jsonb;
 v_remaining integer:=0;
 v_reserve integer:=0;
 v_usable integer:=0;
 v_accepted integer:=0;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select coalesce(max(r.rank),0) into v_rank from security.user_roles ur join security.roles r on r.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 select * into v_policy from pipeline.layer2_execution_policy where policy_key='default' and enabled;
 if not found then raise exception 'Layer 2 execution policy missing' using errcode='55000'; end if;
 select * into v_firecrawl from pipeline.layer2_acquisition_providers where provider_key='firecrawl' limit 1;
 if v_firecrawl.id is null or not v_firecrawl.enabled or v_firecrawl.vault_secret_id is null then
   raise exception 'Firecrawl is not ready for Layer 2 execution' using errcode='55000';
 end if;
 v_budget:=security.layer2_provider_budget_status(v_firecrawl.id,coalesce(nullif(v_firecrawl.request_template->>'fixed_credit_units','')::numeric,1));
 v_remaining:=greatest(coalesce((v_budget->>'remaining_units')::integer,0),0);
 v_reserve:=greatest(coalesce((v_budget->>'stop_at_remaining_units')::integer,0),0);
 v_usable:=greatest(v_remaining-v_reserve,0);
 v_accepted:=least(v_policy.production_target_wave_size,v_policy.production_max_wave_size,v_usable);

 v_preview:=public.layer2_scale_scope_service(p_actor,'preview',p_country_code,p_scope_type,p_scope_id,0,0);
 v_preview:=v_preview||jsonb_build_object(
   'execution_policy',to_jsonb(v_policy)-'updated_by',
   'firecrawl_budget',v_budget,
   'firecrawl',jsonb_build_object(
      'display_name',v_firecrawl.display_name,'provider_key',v_firecrawl.provider_key,
      'rate_limit_per_minute',v_firecrawl.rate_limit_per_minute,'concurrency',v_firecrawl.concurrency,
      'monthly_limit',v_firecrawl.billing_config->'monthly_vendor_units_limit',
      'reserve_units',v_reserve,'usable_remaining_units',v_usable
   ),
   'production_accepted_wave_size',v_accepted,
   'qualification_sample_note','The per-Provider Course sample is an identity check against one acquired Provider seed page, not one scrape per sampled Course.'
 );

 if p_action='preview' then return v_preview; end if;
 if p_action<>'start' then raise exception 'unsupported action' using errcode='22023'; end if;

 if coalesce((v_preview->>'qualification_required_count')::integer,0)>0 then
   v_qual:=public.layer2_scale_scope_service(p_actor,'qualify_wave',p_country_code,p_scope_type,p_scope_id,0,0);
   return v_preview||jsonb_build_object(
     'ok',true,'status','background_qualification_scheduled',
     'qualification',v_qual,
     'next_step','Qualification runs in background; production Course waves auto-start after the current scope is exhausted or deferred.'
   );
 end if;

 if upper(p_country_code)='NZ' then
   return v_preview||jsonb_build_object('ok',true,'status','production_deferred','reason','NZ Layer 2 Course enrichment remains deferred');
 end if;
 if v_accepted<1 then
   return v_preview||jsonb_build_object('ok',false,'status','budget_blocked','reason','Firecrawl monthly safety reserve reached');
 end if;
 if coalesce((v_preview->>'queueable_count')::integer,0)<1 then
   return v_preview||jsonb_build_object('ok',true,'status','nothing_queueable');
 end if;

 v_wave:=public.layer2_wave_scope_service(
   p_actor,'start',p_country_code,p_scope_type,p_scope_id,v_accepted,v_policy.schedule_remaining,v_policy.route_mode,null
 );
 return v_preview||jsonb_build_object(
   'ok',true,'status','background_enrichment_started','production',v_wave,
   'next_step','Production Course waves are scheduled in the background.'
 );
end $function$
;

CREATE OR REPLACE FUNCTION public.layer2_execution_policy_service(p_actor uuid, p_action text, p_patch jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'security'
AS $function$
declare
 v_rank integer:=0;
 v_policy pipeline.layer2_execution_policy%rowtype;
 v_firecrawl pipeline.layer2_acquisition_providers%rowtype;
 v_budget jsonb:='{}'::jsonb;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select coalesce(max(r.rank),0) into v_rank
 from security.user_roles ur join security.roles r on r.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and r.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

 if p_action='update' then
   if v_rank<5 then raise exception 'pim_admin role required' using errcode='42501'; end if;
   update pipeline.layer2_execution_policy p set
     qualification_provider_wave_size=least(greatest(coalesce(nullif(p_patch->>'qualification_provider_wave_size','')::integer,p.qualification_provider_wave_size),1),500),
     qualification_provider_wave_max=least(greatest(coalesce(nullif(p_patch->>'qualification_provider_wave_max','')::integer,p.qualification_provider_wave_max),1),500),
     qualification_sample_size=least(greatest(coalesce(nullif(p_patch->>'qualification_sample_size','')::integer,p.qualification_sample_size),1),50),
     qualification_retry_hours=least(greatest(coalesce(nullif(p_patch->>'qualification_retry_hours','')::integer,p.qualification_retry_hours),1),2160),
     production_target_wave_size=least(greatest(coalesce(nullif(p_patch->>'production_target_wave_size','')::integer,p.production_target_wave_size),1),5000),
     production_max_wave_size=least(greatest(coalesce(nullif(p_patch->>'production_max_wave_size','')::integer,p.production_max_wave_size),1),5000),
     schedule_remaining=coalesce((p_patch->>'schedule_remaining')::boolean,p.schedule_remaining),
     route_mode=case when p_patch->>'route_mode' in('scraper_first','managed') then p_patch->>'route_mode' else p.route_mode end,
     updated_by=p_actor,updated_at=now(),change_control_ref='CF-CHG-20260830-048'
   where p.policy_key='default';
 end if;

 select * into v_policy from pipeline.layer2_execution_policy where policy_key='default';
 select * into v_firecrawl from pipeline.layer2_acquisition_providers where provider_key='firecrawl' limit 1;
 if v_firecrawl.id is not null then
   v_budget:=security.layer2_provider_budget_status(
     v_firecrawl.id,
     coalesce(nullif(v_firecrawl.request_template->>'fixed_credit_units','')::numeric,1)
   );
 end if;

 return jsonb_build_object(
  'policy',to_jsonb(v_policy)-'updated_by',
  'firecrawl',jsonb_build_object(
    'provider_id',v_firecrawl.id,'provider_key',v_firecrawl.provider_key,'display_name',v_firecrawl.display_name,
    'enabled',v_firecrawl.enabled,'credential_configured',v_firecrawl.vault_secret_id is not null,
    'rate_limit_per_minute',v_firecrawl.rate_limit_per_minute,'concurrency',v_firecrawl.concurrency,
    'timeout_seconds',v_firecrawl.timeout_seconds,'billing_config',v_firecrawl.billing_config,
    'budget_status',v_budget
  ),
  'qualification_note','Course samples are identity checks against one acquired Provider seed page; they are not separate production scrapes.',
  'production_note','Production Course waves are queued in the background and clamped by the Firecrawl entitlement/reserve.'
 );
end $function$
;

CREATE OR REPLACE FUNCTION public.layer2_scale_qualification_prepare(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'catalogue', 'ref', 'security'
AS $function$
declare
  v_run pipeline.layer2_scale_qualification_runs%rowtype;
  r record;
  v_source uuid;
  v_profile uuid;
  v_version uuid;
  v_cfg jsonb;
  v_hash text;
  v_validation jsonb;
  v_country text;
  v_profiles jsonb:='[]'::jsonb;
  v_ready integer:=0;
  v_limited integer:=0;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select * into v_run from pipeline.layer2_scale_qualification_runs where id=p_run_id for update;
  if not found then raise exception 'qualification run not found' using errcode='22023'; end if;
  if v_run.status in ('completed','cancelled') then
    return jsonb_build_object('ok',true,'status',v_run.status,'run_id',p_run_id);
  end if;

  select iso_alpha2::text into v_country from ref.countries where id=v_run.country_id;

  for r in
    select distinct qi.provider_id,p.canonical_name,p.website,p.country_id
    from pipeline.layer2_scale_qualification_items qi
    join catalogue.providers p on p.id=qi.provider_id
    where qi.run_id=p_run_id
      and qi.status in ('selected','qualifying')
    order by p.canonical_name
  loop
    if r.website is null
       or btrim(r.website)=''
       or r.website !~* '^https?://[^[:space:]]+$'
       or lower(r.website) like 'https://https://%'
       or lower(r.website) like 'http://http://%'
    then
      update pipeline.layer2_scale_qualification_items
      set status='source_limited',
          outcome=coalesce(outcome,'{}'::jsonb)||jsonb_build_object(
            'stage','source_seed_qualification',
            'outcome','source_limited',
            'reason','missing_or_invalid_layer1_provider_website',
            'layer1_provider_website',r.website,
            'handoff','layer4_source_resolution',
            'canonical_mutation_authorised',false,
            'search_mutation_authorised',false,
            'publication_mutation_authorised',false
          )
      where run_id=p_run_id and provider_id=r.provider_id;
      v_limited:=v_limited+1;
      continue;
    end if;

    select lp.id,s.id into v_profile,v_source
    from pipeline.layer2_source_profiles lp
    join pipeline.sources s on s.id=lp.source_id
    where s.provider_id=r.provider_id
      and lp.authority_class='qualification_candidate'
      and lp.domain='course_facts'
    order by lp.created_at desc
    limit 1;

    if v_profile is null then
      insert into pipeline.sources(
        source_type,provider_id,country_id,url,label,trust_rank,status,metadata
      ) values(
        'web_catalogue',r.provider_id,r.country_id,btrim(r.website),
        'A11 qualification — '||r.canonical_name,60,'active',
        jsonb_build_object(
          'layer',2,
          'qualification_candidate',true,
          'qualification_run_id',p_run_id,
          'change_control_ref','CF-CHG-20260830-048',
          'canonical_mutation_authorised',false
        )
      ) returning id into v_source;

      insert into pipeline.layer2_source_profiles(
        source_id,profile_key,domain,acquisition_method,target_entity_type,
        authority_class,enabled,paused,operational_owner,freshness_sla_hours,schedule_text
      ) values(
        v_source,
        'qualification-'||lower(v_country)||'-'||left(replace(r.provider_id::text,'-',''),16),
        'course_facts','website','course_fact','qualification_candidate',
        true,false,'PIM/Data Operations',168,'qualification_only'
      ) returning id into v_profile;

      v_cfg:=jsonb_build_object(
        'acquisition_method','website',
        'base_domain',btrim(r.website),
        'discovery_url',btrim(r.website),
        'url_patterns',jsonb_build_array(btrim(r.website)),
        'inclusion_rules',jsonb_build_array(),
        'exclusion_rules',jsonb_build_array(),
        'headers',jsonb_build_object('user_agent','CourseFinder Layer2 Qualification/1.0'),
        'authentication',jsonb_build_object('mechanism','none'),
        'rate_limit_per_minute',30,
        'concurrency',1,
        'timeout_seconds',30,
        'retry',jsonb_build_object('max_attempts',2,'backoff','exponential'),
        'robots_policy','respect',
        'allowed_mime_types',jsonb_build_array('text/html','application/json'),
        'max_payload_mb',10,
        'parser_profile','generic-first-party-source-qualification-v1',
        'target_entity_type','course_fact',
        'mapping_strategy','qualification_only_no_canonical_mutation',
        'stable_identifier_strategy','layer1_provider_id_plus_first_party_host',
        'regulatory_code_extraction',jsonb_build_object('cricos',null,'nzqa',null),
        'evidence_required',true,
        'freshness_sla_hours',168,
        'schedule','qualification_only',
        'content_change_policy','evidence_only_never_direct_canonical_mutation',
        'source_authority','first_party_candidate_unqualified',
        'operational_owner','PIM/Data Operations',
        'change_control_ref','CF-CHG-20260830-048'
      );
      v_hash:=encode(extensions.digest(v_cfg::text,'sha256'),'hex');
      v_validation:=security.layer2_validate_profile_config(v_cfg);

      insert into pipeline.layer2_source_profile_versions(
        profile_id,version_no,configuration,configuration_hash,
        validation_status,validation_result,change_control_ref,uat_ref
      ) values(
        v_profile,1,v_cfg,v_hash,
        case when (v_validation->>'valid')::boolean then 'valid' else 'invalid' end,
        v_validation,'CF-CHG-20260830-048','M2.4.2-A11-source-qualification'
      ) returning id into v_version;

      update pipeline.layer2_source_profiles set current_version_id=v_version where id=v_profile;

      insert into pipeline.layer2_profile_provider_routes(
        profile_id,acquisition_provider_id,priority,enabled,
        required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref
      )
      select
        v_profile,ap.id,
        case ap.provider_key
          when 'firecrawl' then 5
          when 'direct-http' then 20
          when 'scrape-do' then 80
          when 'scraperapi' then 90
          when 'zenrows' then 100
          else 120
        end,
        case when ap.provider_key in ('firecrawl','direct-http') then true else false end,'{}'::jsonb,'{}'::jsonb,
        '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":false}'::jsonb,
        '["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,
        'CF-CHG-20260830-048'
      from pipeline.layer2_acquisition_providers ap
      where ap.enabled
      on conflict do nothing;
    end if;

    update pipeline.layer2_scale_qualification_items
    set status='qualifying',
        outcome=coalesce(outcome,'{}'::jsonb)||jsonb_build_object(
          'stage','source_seed_qualification',
          'qualification_profile_id',v_profile,
          'qualification_source_id',v_source,
          'layer1_provider_website',r.website,
          'canonical_mutation_authorised',false,
          'search_mutation_authorised',false,
          'publication_mutation_authorised',false
        )
    where run_id=p_run_id and provider_id=r.provider_id and status in ('selected','qualifying');

    v_profiles:=v_profiles||jsonb_build_array(jsonb_build_object(
      'provider_id',r.provider_id,'provider_name',r.canonical_name,
      'website',r.website,'profile_id',v_profile,'source_id',v_source
    ));
    v_ready:=v_ready+1;
  end loop;

  update pipeline.layer2_scale_qualification_runs
  set status=case when v_ready>0 then 'running' else 'completed' end,
      result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
        'stage','source_seed_qualification',
        'providers_ready_for_acquisition',v_ready,
        'providers_source_limited',v_limited,
        'identity_safety_required',true,
        'canonical_mutation_authorised',false,
        'search_mutation_authorised',false,
        'publication_mutation_authorised',false
      ),
      completed_at=case when v_ready=0 then now() else null end
  where id=p_run_id;

  return jsonb_build_object(
    'ok',true,'run_id',p_run_id,
    'providers_ready_for_acquisition',v_ready,
    'providers_source_limited',v_limited,
    'profiles',v_profiles,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.layer2_scale_scope_service(p_actor uuid, p_action text, p_country_code text, p_scope_type text DEFAULT 'country'::text, p_scope_id uuid DEFAULT NULL::uuid, p_wave_size integer DEFAULT 0, p_sample_size integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline', 'catalogue', 'ref', 'security'
AS $function$
declare
  v_rank integer:=0;
  v_country_id uuid;
  v_scope text:=lower(coalesce(nullif(trim(p_scope_type),''),'country'));
  v_policy pipeline.layer2_execution_policy%rowtype;
  v_wave integer;
  v_sample integer;
  v_retry_hours integer;
  v_run uuid;
  v_provider_count integer:=0;
  v_course_count integer:=0;
  v_payload jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 if p_actor is null then raise exception 'actor required' using errcode='42501'; end if;
 select coalesce(max(role.rank),0) into v_rank
 from security.user_roles ur join security.roles role on role.code=ur.role_code
 where ur.user_id=p_actor and (ur.expires_at is null or ur.expires_at>now()) and role.status='active';
 if v_rank<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;
 if v_scope not in ('country','state','university') then raise exception 'invalid scope type' using errcode='22023'; end if;
 if v_scope in ('state','university') and p_scope_id is null then raise exception 'scope id required' using errcode='22023'; end if;

 select * into v_policy from pipeline.layer2_execution_policy where policy_key='default' and enabled;
 if not found then raise exception 'Layer 2 execution policy missing' using errcode='55000'; end if;
 v_wave:=least(greatest(coalesce(nullif(p_wave_size,0),v_policy.qualification_provider_wave_size),1),v_policy.qualification_provider_wave_max);
 v_sample:=least(greatest(coalesce(nullif(p_sample_size,0),v_policy.qualification_sample_size),1),50);
 v_retry_hours:=v_policy.qualification_retry_hours;

 select id into v_country_id from ref.countries where upper(iso_alpha2::text)=upper(trim(p_country_code)) limit 1;
 if v_country_id is null then raise exception 'country not found' using errcode='22023'; end if;

 if p_action='preview' then
   with providers as (
     select p.id
     from catalogue.providers p
     where p.country_id=v_country_id
       and exists(select 1 from catalogue.courses c where c.provider_id=p.id)
       and (
         v_scope='country'
         or (v_scope='university' and p.id=p_scope_id)
         or (v_scope='state' and (
           p.subdivision_id=p_scope_id
           or exists(
             select 1 from catalogue.courses c
             join catalogue.course_campuses cc on cc.course_id=c.id
             join catalogue.campuses cam on cam.id=cc.campus_id
             where c.provider_id=p.id and cam.subdivision_id=p_scope_id
           )
         ))
       )
   ), status as (
     select p.id,
       exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=p.id and lp.domain='course_facts'
           and lp.authority_class<>'qualification_candidate'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       ) qualified,
       (select count(*) from catalogue.courses c where c.provider_id=p.id)::integer courses
     from providers p
   )
   select jsonb_build_object(
     'ok',true,'scope_source','layer1_catalogue','country_code',upper(trim(p_country_code)),
     'scope_type',v_scope,'scope_id',p_scope_id,
     'university_count',count(*)::integer,
     'catalogue_count',coalesce(sum(courses),0)::integer,
     'qualified_provider_count',count(*) filter(where qualified)::integer,
     'qualification_required_count',count(*) filter(where not qualified)::integer,
     'executable_course_count',coalesce(sum(courses) filter(where qualified),0)::integer,
     'qualification_course_count',coalesce(sum(courses) filter(where not qualified),0)::integer,
     'queueable_count',(
       select count(distinct c.id)::integer
       from providers pp join catalogue.courses c on c.provider_id=pp.id
       where exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=pp.id and lp.domain='course_facts'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       )
       and (
         nullif(c.course_url,'') is not null
         or exists(
           select 1 from pipeline.layer2_course_discovery_candidates dc
           join pipeline.layer2_source_profiles lp2 on lp2.current_version_id=dc.source_profile_version_id
           join pipeline.sources s2 on s2.id=lp2.source_id
           where dc.course_id=c.id and dc.selected and nullif(dc.discovered_url,'') is not null and s2.provider_id=pp.id
         )
       )
     ),
     'needs_discovery_count',(
       select count(distinct c.id)::integer
       from providers pp join catalogue.courses c on c.provider_id=pp.id
       where exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=pp.id and lp.domain='course_facts'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       )
       and nullif(c.course_url,'') is null
       and not exists(
         select 1 from pipeline.layer2_course_discovery_candidates dc
         join pipeline.layer2_source_profiles lp2 on lp2.current_version_id=dc.source_profile_version_id
         join pipeline.sources s2 on s2.id=lp2.source_id
         where dc.course_id=c.id and dc.selected and nullif(dc.discovered_url,'') is not null and s2.provider_id=pp.id
       )
     ),
     'active_run_count',(
       select count(*)::integer from pipeline.layer2_run_batches b
       join pipeline.layer2_source_profiles lp on lp.id=b.profile_id
       join pipeline.sources s on s.id=lp.source_id
       where b.status in ('queued','running')
         and s.provider_id in (select id from providers)
     ),
     'recommended_action',case when count(*) filter(where not qualified)>0 then 'qualify_wave' else 'sync' end,
     'wave_size',v_wave,'sample_size',v_sample
   ) into v_payload
   from status;
   return v_payload;
 end if;

 if p_action='qualify_wave' then
   insert into pipeline.layer2_scale_qualification_runs(
     country_id,scope_type,scope_id,requested_by,wave_size,sample_size,status,change_control_ref
   ) values(v_country_id,v_scope,p_scope_id,p_actor,v_wave,v_sample,'planned','CF-CHG-20260830-048')
   returning id into v_run;

   with eligible as (
     select p.id,p.canonical_name,(select count(*) from catalogue.courses c where c.provider_id=p.id) course_count
     from catalogue.providers p
     where p.country_id=v_country_id
       and exists(select 1 from catalogue.courses c where c.provider_id=p.id)
       and (
         v_scope='country'
         or (v_scope='university' and p.id=p_scope_id)
         or (v_scope='state' and (
           p.subdivision_id=p_scope_id
           or exists(
             select 1 from catalogue.courses c
             join catalogue.course_campuses cc on cc.course_id=c.id
             join catalogue.campuses cam on cam.id=cc.campus_id
             where c.provider_id=p.id and cam.subdivision_id=p_scope_id
           )
         ))
       )
       and not exists(
         select 1 from pipeline.layer2_source_profiles lp
         join pipeline.sources s on s.id=lp.source_id
         join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
         where s.provider_id=p.id and lp.domain='course_facts'
           and lp.authority_class<>'qualification_candidate'
           and lp.enabled and not lp.paused and pv.validation_status='valid'
       )
       and not exists(
         select 1
         from pipeline.layer2_scale_qualification_items qi
         join pipeline.layer2_scale_qualification_runs qr on qr.id=qi.run_id
         where qi.provider_id=p.id
           and qr.status in ('planned','running')
       )
       and not exists(
         select 1
         from pipeline.layer2_scale_qualification_items qi2
         join pipeline.layer2_scale_qualification_runs qr2 on qr2.id=qi2.run_id
         where qi2.provider_id=p.id
           and qi2.status in ('source_pattern_candidate','source_limited','blocked','layer3_required','layer4_required')
           and qr2.created_at > now()-make_interval(hours=>v_retry_hours)
       )
     order by course_count desc,p.canonical_name,p.id
     limit v_wave
   ), samples as (
     select e.id provider_id,c.id course_id,
            row_number() over(partition by e.id order by
              case when nullif(c.course_url,'') is null then 0 else 1 end,
              c.stable_key,c.id
            )::integer sample_rank
     from eligible e
     join catalogue.courses c on c.provider_id=e.id
   )
   insert into pipeline.layer2_scale_qualification_items(run_id,provider_id,course_id,sample_rank,selection_reason)
   select v_run,provider_id,course_id,sample_rank,
          case when sample_rank<=greatest(1,least(2,v_sample)) then 'gap_first_control_mix' else 'layer1_gap_sample' end
   from samples where sample_rank<=v_sample
   order by provider_id,sample_rank;

   select count(distinct provider_id),count(*) into v_provider_count,v_course_count
   from pipeline.layer2_scale_qualification_items where run_id=v_run;

   if v_provider_count=0 then
     update pipeline.layer2_scale_qualification_runs
     set status='completed',completed_at=now(),result_summary=jsonb_build_object('outcome','nothing_to_qualify','background_scheduler_authorized',true,'auto_progress_scope',true,'qualification_identity_sample_only',true,'route_mode',v_policy.route_mode,'production_target_wave_size',v_policy.production_target_wave_size)
     where id=v_run;
   else
     update pipeline.layer2_scale_qualification_runs
     set provider_count=v_provider_count,course_sample_count=v_course_count,
         result_summary=jsonb_build_object(
           'outcome','sample_selected',
           'next_step','deterministic_source_qualification',
           'identity_safety_required',true,
           'background_scheduler_authorized',true,
           'auto_progress_scope',true,
           'qualification_identity_sample_only',true,
           'route_mode',v_policy.route_mode,
           'production_target_wave_size',v_policy.production_target_wave_size,
           'canonical_mutation_authorised',false,
           'search_mutation_authorised',false,
           'publication_mutation_authorised',false
         )
     where id=v_run;
   end if;

   return jsonb_build_object(
     'ok',true,'status',case when v_provider_count=0 then 'nothing_to_qualify' else 'qualification_wave_planned' end,
     'qualification_run_id',v_run,'provider_count',v_provider_count,'course_sample_count',v_course_count,
     'wave_size',v_wave,'sample_size',v_sample,'background_scheduled',true,'identity_sample_only',true,
     'canonical_mutation_authorised',false,'search_mutation_authorised',false,'publication_mutation_authorised',false
   );
 end if;

 raise exception 'unsupported action' using errcode='22023';
end $function$
;

CREATE OR REPLACE FUNCTION security.layer2_qualification_scheduler_tick_impl(p_limit integer DEFAULT 2)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'public', 'pipeline', 'ref'
AS $function$
declare
 r record;
 v_result jsonb;
 v_next jsonb;
 v_preview jsonb;
 v_policy pipeline.layer2_execution_policy%rowtype;
 v_country text;
 v_firecrawl uuid;
 v_budget jsonb;
 v_remaining integer;
 v_reserve integer;
 v_accepted integer;
 v_prod jsonb;
 v_dispatched integer:=0;
 v_progressed integer:=0;
 v_results jsonb:='[]'::jsonb;
begin
 if current_user not in('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into v_policy from pipeline.layer2_execution_policy where policy_key='default' and enabled;
 if not found then return jsonb_build_object('ok',false,'reason','execution_policy_missing'); end if;

 for r in
   select q.id
   from pipeline.layer2_scale_qualification_runs q
   where q.status='planned'
     and coalesce((q.result_summary->>'background_scheduler_authorized')::boolean,false)
   order by q.created_at
   limit greatest(1,least(coalesce(p_limit,2),10))
   for update skip locked
 loop
   begin
     v_result:=security.layer2_scale_qualification_dispatch(r.id);
     v_results:=v_results||jsonb_build_array(jsonb_build_object('run_id',r.id,'dispatch',v_result));
     v_dispatched:=v_dispatched+1;
   exception when others then
     v_results:=v_results||jsonb_build_array(jsonb_build_object('run_id',r.id,'dispatch_error',sqlerrm));
   end;
 end loop;

 for r in
   select q.*
   from pipeline.layer2_scale_qualification_runs q
   where q.status in('completed','partial')
     and coalesce((q.result_summary->>'auto_progress_scope')::boolean,false)
     and not coalesce((q.result_summary->>'auto_progress_processed')::boolean,false)
   order by q.completed_at nulls last,q.created_at
   limit greatest(1,least(coalesce(p_limit,2),10))
   for update skip locked
 loop
   select iso_alpha2::text into v_country from ref.countries where id=r.country_id;
   begin
     v_next:=public.layer2_scale_scope_service(r.requested_by,'qualify_wave',v_country,r.scope_type,r.scope_id,0,0);
     if coalesce((v_next->>'provider_count')::integer,0)>0 then
       update pipeline.layer2_scale_qualification_runs
       set result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
          'auto_progress_processed',true,'next_qualification_run_id',v_next->>'qualification_run_id','auto_progressed_at',now()
       ) where id=r.id;
       v_results:=v_results||jsonb_build_array(jsonb_build_object('run_id',r.id,'next_qualification_run_id',v_next->>'qualification_run_id'));
       v_progressed:=v_progressed+1;
     else
       if nullif(v_next->>'qualification_run_id','') is not null then
         update pipeline.layer2_scale_qualification_runs
         set result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object('auto_progress_processed',true,'empty_terminal_probe',true)
         where id=(v_next->>'qualification_run_id')::uuid;
       end if;
       v_preview:=public.layer2_scale_scope_service(r.requested_by,'preview',v_country,r.scope_type,r.scope_id,0,0);
       v_prod:=null;
       if upper(v_country)<>'NZ' and coalesce((v_preview->>'queueable_count')::integer,0)>0 then
         select id into v_firecrawl from pipeline.layer2_acquisition_providers where provider_key='firecrawl' and enabled limit 1;
         v_budget:=security.layer2_provider_budget_status(v_firecrawl,1);
         v_remaining:=greatest(coalesce((v_budget->>'remaining_units')::integer,0),0);
         v_reserve:=greatest(coalesce((v_budget->>'stop_at_remaining_units')::integer,0),0);
         v_accepted:=least(v_policy.production_target_wave_size,v_policy.production_max_wave_size,greatest(v_remaining-v_reserve,0));
         if v_accepted>0 then
           v_prod:=public.layer2_wave_scope_service(
             r.requested_by,'start',v_country,r.scope_type,r.scope_id,v_accepted,v_policy.schedule_remaining,v_policy.route_mode,null
           );
         end if;
       end if;
       update pipeline.layer2_scale_qualification_runs
       set result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
          'auto_progress_processed',true,'auto_progressed_at',now(),'production_result',coalesce(v_prod,'{}'::jsonb),
          'remaining_unqualified_or_deferred',coalesce((v_preview->>'qualification_required_count')::integer,0)
       ) where id=r.id;
       v_results:=v_results||jsonb_build_array(jsonb_build_object('run_id',r.id,'production',v_prod));
       v_progressed:=v_progressed+1;
     end if;
   exception when others then
     v_results:=v_results||jsonb_build_array(jsonb_build_object('run_id',r.id,'progress_error',sqlerrm));
   end;
 end loop;

 return jsonb_build_object('ok',true,'dispatched_runs',v_dispatched,'progressed_runs',v_progressed,'results',v_results);
end $function$
;

revoke all on function public.layer2_execution_policy_service(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.layer2_execution_policy_service(uuid,text,jsonb) to service_role;
revoke all on function public.layer2_scale_scope_service(uuid,text,text,text,uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.layer2_scale_scope_service(uuid,text,text,text,uuid,integer,integer) to service_role;
revoke all on function public.layer2_scale_qualification_prepare(uuid) from public,anon,authenticated;
grant execute on function public.layer2_scale_qualification_prepare(uuid) to service_role;
revoke all on function public.layer2_background_scope_service(uuid,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.layer2_background_scope_service(uuid,text,text,text,uuid) to service_role;
revoke all on function security.layer2_qualification_scheduler_tick_impl(integer) from public,anon,authenticated;
grant execute on function security.layer2_qualification_scheduler_tick_impl(integer) to service_role;

update pipeline.layer2_scale_qualification_runs
set status='cancelled',
    completed_at=coalesce(completed_at,now()),
    result_summary=coalesce(result_summary,'{}'::jsonb)||jsonb_build_object(
      'superseded_by','A23_background_qualification',
      'superseded_at',now(),
      'dispatch_skipped',true,
      'reason','legacy manual planned run had no background scheduler authority'
    ),
    change_control_ref='CF-CHG-20260830-048'
where status='planned'
  and not coalesce((result_summary->>'background_scheduler_authorized')::boolean,false);

update pipeline.layer2_profile_provider_routes pr
set priority=priority+1000,updated_at=now()
from pipeline.layer2_source_profiles lp
where pr.profile_id=lp.id
  and lp.domain='course_facts' and lp.authority_class='qualification_candidate';

update pipeline.layer2_profile_provider_routes pr
set priority=case ap.provider_key when 'firecrawl' then 5 when 'direct-http' then 20 when 'scrape-do' then 80 when 'scraperapi' then 90 when 'zenrows' then 100 else 120 end,
    enabled=case when ap.provider_key in('firecrawl','direct-http') then true else false end,
    change_control_ref='CF-CHG-20260830-048',
    updated_at=now()
from pipeline.layer2_source_profiles lp,pipeline.layer2_acquisition_providers ap
where pr.profile_id=lp.id and pr.acquisition_provider_id=ap.id
  and lp.domain='course_facts' and lp.authority_class='qualification_candidate';

do $$
begin
 if exists(select 1 from cron.job where jobname='coursefinder-layer2-qualification-scheduler') then
   perform cron.unschedule((select jobid from cron.job where jobname='coursefinder-layer2-qualification-scheduler' limit 1));
 end if;
 perform cron.schedule(
   'coursefinder-layer2-qualification-scheduler',
   '*/5 * * * *',
   'select security.layer2_qualification_scheduler_tick_impl(2);'
 );
end $$;
