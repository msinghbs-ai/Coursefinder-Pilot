-- A15 post-freeze hardening and final acceptance contract.
-- Reviewed contact semantics take precedence over later scraper observations;
-- successful complete scans emit removal/restoration events without deleting history;
-- one bounded authenticated read exposes final acceptance invariants only.

create index if not exists provider_contact_observations_profile_current_first_party_idx
  on pipeline.provider_contact_observations(profile_id, identity_hash)
  where source_class='first_party' and is_current=true and verification_state<>'rejected';

create or replace function public.provider_contact_observation_upsert_service(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $$
declare
  v_prior pipeline.provider_contact_observations%rowtype;
  v_id uuid;
  v_event text;
  v_before jsonb;
  v_after jsonb;
  v_last_candidate jsonb;
  v_metadata jsonb;
  v_reviewed boolean:=false;
  v_review_rejected boolean:=false;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select * into v_prior
  from pipeline.provider_contact_observations
  where identity_hash=p_payload->>'identity_hash'
  limit 1
  for update;

  v_after:=jsonb_build_object(
    'job_title',nullif(p_payload->>'job_title',''),
    'territory_text',nullif(p_payload->>'territory_text',''),
    'work_email',nullif(p_payload->>'work_email',''),
    'work_phone',nullif(p_payload->>'work_phone',''),
    'professional_profile_url',nullif(p_payload->>'professional_profile_url','')
  );
  v_metadata:=coalesce(p_payload->'metadata','{}'::jsonb)
    || case when p_payload->>'source_class'='first_party'
      then jsonb_build_object('a15_last_scraper_candidate',v_after,'a15_last_scraper_seen_at',now())
      else '{}'::jsonb end;

  if v_prior.id is null then
    insert into pipeline.provider_contact_observations(
      provider_id,profile_id,source_class,source_provider,source_url,external_person_id,
      full_name,job_title,team_name,territory_text,territory_codes,work_email,work_phone,
      professional_profile_url,evidence_id,identity_hash,verification_state,observed_at,last_verified_at,
      is_current,confidence,metadata
    ) values(
      (p_payload->>'provider_id')::uuid,nullif(p_payload->>'profile_id','')::uuid,
      p_payload->>'source_class',nullif(p_payload->>'source_provider',''),nullif(p_payload->>'source_url',''),
      nullif(p_payload->>'external_person_id',''),nullif(p_payload->>'full_name',''),nullif(p_payload->>'job_title',''),
      nullif(p_payload->>'team_name',''),nullif(p_payload->>'territory_text',''),
      coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'territory_codes','[]'::jsonb))),'{}'::text[]),
      nullif(p_payload->>'work_email',''),nullif(p_payload->>'work_phone',''),nullif(p_payload->>'professional_profile_url',''),
      nullif(p_payload->>'evidence_id','')::uuid,p_payload->>'identity_hash',
      coalesce(nullif(p_payload->>'verification_state',''),'unverified'),
      coalesce(nullif(p_payload->>'observed_at','')::timestamptz,now()),
      coalesce(nullif(p_payload->>'last_verified_at','')::timestamptz,now()),
      coalesce(nullif(p_payload->>'is_current','')::boolean,true),
      nullif(p_payload->>'confidence','')::numeric,
      v_metadata
    ) returning id into v_id;

    insert into pipeline.provider_contact_watch_events(
      provider_id,observation_id,event_type,source_class,after_state,metadata
    ) values(
      (p_payload->>'provider_id')::uuid,v_id,'new_contact',p_payload->>'source_class',v_after,
      jsonb_build_object('worker_version',p_payload#>>'{metadata,worker_version}','source_provider',p_payload->>'source_provider')
    );
    return jsonb_build_object('id',v_id,'created',true,'event_type','new_contact','review_precedence',false);
  end if;

  v_before:=jsonb_build_object(
    'job_title',v_prior.job_title,
    'territory_text',v_prior.territory_text,
    'work_email',v_prior.work_email,
    'work_phone',v_prior.work_phone,
    'professional_profile_url',v_prior.professional_profile_url
  );
  v_reviewed:=v_prior.metadata ? 'a15_quality_review_at';
  v_review_rejected:=v_reviewed
    and v_prior.metadata ? 'a15_quality_disposition'
    and not (v_prior.metadata ? 'a15_quality_reconciliation')
    and v_prior.verification_state='rejected';
  v_last_candidate:=v_prior.metadata->'a15_last_scraper_candidate';

  if v_reviewed then
    if not v_review_rejected and not v_prior.is_current then
      v_event:='contact_restored';
    elsif v_last_candidate is not null and v_last_candidate is distinct from v_after then
      if v_last_candidate->>'job_title' is distinct from v_after->>'job_title' then
        v_event:='title_changed';
      elsif v_last_candidate->>'territory_text' is distinct from v_after->>'territory_text' then
        v_event:='territory_changed';
      elsif v_last_candidate->>'work_email' is distinct from v_after->>'work_email'
         or v_last_candidate->>'work_phone' is distinct from v_after->>'work_phone'
         or v_last_candidate->>'professional_profile_url' is distinct from v_after->>'professional_profile_url' then
        v_event:='contact_changed';
      end if;
    end if;

    update pipeline.provider_contact_observations set
      profile_id=coalesce(nullif(p_payload->>'profile_id','')::uuid,profile_id),
      source_provider=coalesce(nullif(p_payload->>'source_provider',''),source_provider),
      source_url=coalesce(nullif(p_payload->>'source_url',''),source_url),
      external_person_id=coalesce(nullif(p_payload->>'external_person_id',''),external_person_id),
      evidence_id=coalesce(nullif(p_payload->>'evidence_id','')::uuid,evidence_id),
      observed_at=coalesce(nullif(p_payload->>'observed_at','')::timestamptz,observed_at),
      last_verified_at=coalesce(nullif(p_payload->>'last_verified_at','')::timestamptz,now()),
      verification_state=case when v_review_rejected then verification_state else 'current' end,
      is_current=case when v_review_rejected then is_current else true end,
      valid_to=case when v_review_rejected then valid_to else null end,
      confidence=greatest(coalesce(confidence,0),coalesce(nullif(p_payload->>'confidence','')::numeric,0)),
      metadata=metadata||v_metadata||jsonb_build_object('a15_review_precedence_applied_at',now()),
      updated_at=now()
    where id=v_prior.id;

    if v_event is not null then
      insert into pipeline.provider_contact_watch_events(
        provider_id,observation_id,event_type,source_class,before_state,after_state,metadata
      ) values(
        v_prior.provider_id,v_prior.id,v_event,v_prior.source_class,v_before,
        case when v_event='contact_restored' then v_before else v_after end,
        jsonb_build_object(
          'worker_version',p_payload#>>'{metadata,worker_version}',
          'source_provider',p_payload->>'source_provider',
          'review_precedence',true,
          'pending_review',v_event<>'contact_restored'
        )
      );
    end if;
    return jsonb_build_object(
      'id',v_prior.id,'created',false,'event_type',v_event,
      'review_precedence',true,'review_rejected',v_review_rejected
    );
  end if;

  if not v_prior.is_current and v_prior.verification_state<>'rejected' then
    v_event:='contact_restored';
  elsif v_prior.job_title is distinct from nullif(p_payload->>'job_title','') then
    v_event:='title_changed';
  elsif v_prior.territory_text is distinct from nullif(p_payload->>'territory_text','') then
    v_event:='territory_changed';
  elsif v_prior.work_email is distinct from nullif(p_payload->>'work_email','')
     or v_prior.work_phone is distinct from nullif(p_payload->>'work_phone','')
     or v_prior.professional_profile_url is distinct from nullif(p_payload->>'professional_profile_url','') then
    v_event:='contact_changed';
  end if;

  update pipeline.provider_contact_observations set
    profile_id=coalesce(nullif(p_payload->>'profile_id','')::uuid,profile_id),
    source_provider=coalesce(nullif(p_payload->>'source_provider',''),source_provider),
    source_url=coalesce(nullif(p_payload->>'source_url',''),source_url),
    external_person_id=coalesce(nullif(p_payload->>'external_person_id',''),external_person_id),
    full_name=coalesce(nullif(p_payload->>'full_name',''),full_name),
    job_title=nullif(p_payload->>'job_title',''),
    team_name=nullif(p_payload->>'team_name',''),
    territory_text=nullif(p_payload->>'territory_text',''),
    territory_codes=coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'territory_codes','[]'::jsonb))),territory_codes),
    work_email=nullif(p_payload->>'work_email',''),
    work_phone=nullif(p_payload->>'work_phone',''),
    professional_profile_url=nullif(p_payload->>'professional_profile_url',''),
    evidence_id=coalesce(nullif(p_payload->>'evidence_id','')::uuid,evidence_id),
    verification_state=case when v_event='contact_restored' then 'current' else coalesce(nullif(p_payload->>'verification_state',''),verification_state) end,
    observed_at=coalesce(nullif(p_payload->>'observed_at','')::timestamptz,observed_at),
    last_verified_at=coalesce(nullif(p_payload->>'last_verified_at','')::timestamptz,now()),
    is_current=case when v_event='contact_restored' then true else coalesce(nullif(p_payload->>'is_current','')::boolean,true) end,
    valid_to=case when v_event='contact_restored' then null else valid_to end,
    confidence=coalesce(nullif(p_payload->>'confidence','')::numeric,confidence),
    metadata=metadata||v_metadata,
    updated_at=now()
  where id=v_prior.id;

  if v_event is not null then
    insert into pipeline.provider_contact_watch_events(
      provider_id,observation_id,event_type,source_class,before_state,after_state,metadata
    ) values(
      v_prior.provider_id,v_prior.id,v_event,v_prior.source_class,v_before,v_after,
      jsonb_build_object('worker_version',p_payload#>>'{metadata,worker_version}','source_provider',p_payload->>'source_provider')
    );
  end if;
  return jsonb_build_object('id',v_prior.id,'created',false,'event_type',v_event,'review_precedence',false);
end $$;

create or replace function public.provider_contact_profile_reconcile_service(
  p_profile_id uuid,
  p_seen_identity_hashes text[],
  p_pages_fetched integer
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pipeline'
as $$
declare
  v_provider_id uuid;
  v_removed integer:=0;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if coalesce(p_pages_fetched,0)<=0 then
    raise exception 'complete scan with at least one fetched page required' using errcode='22023';
  end if;

  select provider_id into v_provider_id
  from pipeline.provider_contact_profiles
  where id=p_profile_id;
  if v_provider_id is null then raise exception 'contact profile not found'; end if;

  with removed as (
    update pipeline.provider_contact_observations o set
      verification_state='stale',
      is_current=false,
      valid_to=coalesce(valid_to,now()),
      metadata=o.metadata||jsonb_build_object(
        'a15_last_scraper_absent_at',now(),
        'a15_removal_scan_pages',p_pages_fetched
      ),
      updated_at=now()
    where o.profile_id=p_profile_id
      and o.provider_id=v_provider_id
      and o.source_class='first_party'
      and o.is_current=true
      and o.verification_state<>'rejected'
      and not (o.identity_hash=any(coalesce(p_seen_identity_hashes,'{}'::text[])))
    returning o.*
  )
  insert into pipeline.provider_contact_watch_events(
    provider_id,observation_id,event_type,source_class,before_state,after_state,metadata
  )
  select
    r.provider_id,r.id,'contact_removed',r.source_class,
    jsonb_build_object(
      'job_title',r.job_title,'territory_text',r.territory_text,
      'work_email',r.work_email,'work_phone',r.work_phone,
      'professional_profile_url',r.professional_profile_url
    ),
    null,
    jsonb_build_object('scan_complete',true,'pages_fetched',p_pages_fetched,'reviewed',r.metadata ? 'a15_quality_review_at')
  from removed r;
  get diagnostics v_removed=row_count;

  return jsonb_build_object(
    'ok',true,'profile_id',p_profile_id,'provider_id',v_provider_id,
    'seen',coalesce(cardinality(p_seen_identity_hashes),0),
    'removed',v_removed,'pages_fetched',p_pages_fetched,'scan_complete',true
  );
end $$;

revoke all on function public.provider_contact_observation_upsert_service(jsonb) from public,anon,authenticated;
revoke all on function public.provider_contact_profile_reconcile_service(uuid,text[],integer) from public,anon,authenticated;
grant execute on function public.provider_contact_observation_upsert_service(jsonb) to service_role,postgres;
grant execute on function public.provider_contact_profile_reconcile_service(uuid,text[],integer) to service_role,postgres;

create or replace function security.admin_a15_acceptance_status()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','pipeline','catalogue','ref','search','publishing','public','auth'
as $$
declare
  v_rank integer:=0;
  v_metrics jsonb;
  v_key_contacts jsonb;
  v_watch jsonb;
  v_security jsonb;
  v_authority jsonb;
  v_ok boolean;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if v_rank<1 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;

  v_metrics:=jsonb_build_object(
    'profile_total',(select count(*) from pipeline.provider_contact_profiles),
    'profile_au',(select count(*) from pipeline.provider_contact_profiles p join ref.countries c on c.id=p.country_id where c.iso_alpha2='AU'),
    'profile_nz',(select count(*) from pipeline.provider_contact_profiles p join ref.countries c on c.id=p.country_id where c.iso_alpha2='NZ'),
    'profile_success',(select count(*) from pipeline.provider_contact_profiles where last_success_at is not null and last_error is null),
    'profile_errors',(select count(*) from pipeline.provider_contact_profiles where last_error is not null),
    'current_contacts',(select count(*) from pipeline.provider_contact_observations where is_current and verification_state<>'rejected'),
    'contact_providers',(select count(distinct provider_id) from pipeline.provider_contact_observations where is_current and verification_state<>'rejected'),
    'territory_contacts',(select count(*) from pipeline.provider_contact_observations where is_current and verification_state<>'rejected' and nullif(trim(territory_text),'') is not null),
    'rejected_contacts',(select count(*) from pipeline.provider_contact_observations where verification_state='rejected'),
    'email_contacts',(select count(*) from pipeline.provider_contact_observations where is_current and verification_state<>'rejected' and nullif(trim(work_email),'') is not null),
    'phone_contacts',(select count(*) from pipeline.provider_contact_observations where is_current and verification_state<>'rejected' and nullif(trim(work_phone),'') is not null),
    'reviewed_rejection_violations',(
      select count(*) from pipeline.provider_contact_observations
      where metadata ? 'a15_quality_review_at'
        and metadata ? 'a15_quality_disposition'
        and not (metadata ? 'a15_quality_reconciliation')
        and (verification_state<>'rejected' or is_current)
    )
  );

  v_key_contacts:=jsonb_build_object(
    'uow',(
      select count(*)=5
      from pipeline.provider_contact_observations o
      join catalogue.providers p on p.id=o.provider_id
      where lower(p.canonical_name)='university of wollongong'
        and o.is_current and o.verification_state='current'
        and o.metadata->>'a15_quality_reconciliation'='uow_first_party_regional_experts'
    ),
    'vu',(
      select count(*)=2
      from pipeline.provider_contact_observations o
      join catalogue.providers p on p.id=o.provider_id
      where lower(p.canonical_name)='victoria university'
        and o.is_current and o.verification_state='current'
        and o.full_name is null and o.job_title='International Student Enquiries'
        and o.team_name='VU International' and o.work_email='international@vu.edu.au'
        and o.work_phone='+61 3 9919 1164'
        and o.metadata->>'a15_quality_reconciliation'='vu_final_preferred_contact'
    ),
    'wellington',exists(
      select 1
      from pipeline.provider_contact_observations o
      join catalogue.providers p on p.id=o.provider_id
      where lower(p.canonical_name)='victoria university of wellington'
        and o.is_current and o.verification_state='current' and o.full_name is null
        and o.job_title='International Student Experience' and o.team_name='International Student Experience'
        and o.work_email='international-support@vuw.ac.nz' and o.work_phone='+64 4 463 5350'
        and o.metadata->>'a15_quality_reconciliation'='wellington_international_student_experience'
    ),
    'otago',exists(
      select 1 from pipeline.provider_contact_observations o join catalogue.providers p on p.id=o.provider_id
      where lower(p.canonical_name)='university of otago'
        and o.is_current and o.verification_state='current' and o.full_name is null
        and o.job_title='International Marketing and Recruitment'
        and o.team_name='International Marketing and Recruitment'
        and o.metadata->>'a15_quality_reconciliation'='otago_team_contact'
    )
  );

  v_watch:=jsonb_build_object(
    'contact_removed_count',(select count(*) from pipeline.provider_contact_watch_events where event_type='contact_removed'),
    'contact_restored_count',(select count(*) from pipeline.provider_contact_watch_events where event_type='contact_restored'),
    'removal_supported',position('contact_removed' in pg_get_functiondef('public.provider_contact_profile_reconcile_service(uuid,text[],integer)'::regprocedure))>0,
    'restoration_supported',position('contact_restored' in pg_get_functiondef('public.provider_contact_observation_upsert_service(jsonb)'::regprocedure))>0
  );

  v_security:=jsonb_build_object(
    'rls_enabled',(
      select bool_and(c.relrowsecurity)
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='pipeline' and c.relname in (
        'provider_contact_profiles','provider_contact_observations',
        'provider_contact_watch_events','provider_contact_enrichment_attempts'
      )
    ),
    'no_direct_table_grants',not exists(
      select 1 from information_schema.role_table_grants
      where table_schema='pipeline'
        and table_name in (
          'provider_contact_profiles','provider_contact_observations',
          'provider_contact_watch_events','provider_contact_enrichment_attempts'
        )
        and grantee in ('anon','authenticated','PUBLIC')
    ),
    'service_upsert_private',
      not has_function_privilege('anon','public.provider_contact_observation_upsert_service(jsonb)','execute')
      and not has_function_privilege('authenticated','public.provider_contact_observation_upsert_service(jsonb)','execute'),
    'service_reconcile_private',
      not has_function_privilege('anon','public.provider_contact_profile_reconcile_service(uuid,text[],integer)','execute')
      and not has_function_privilege('authenticated','public.provider_contact_profile_reconcile_service(uuid,text[],integer)','execute')
  );

  v_authority:=jsonb_build_object(
    'providers',(select count(*) from catalogue.providers),
    'courses',(select count(*) from catalogue.courses),
    'search_documents',(select count(*) from search.course_documents),
    'publication_entity_states',(select count(*) from publishing.entity_states),
    'publication_events',(select count(*) from publishing.publication_events),
    'publication_approvals',(select count(*) from publishing.publication_approvals),
    'expected',jsonb_build_object(
      'providers',3085,'courses',43461,'search_documents',33105,
      'publication_entity_states',0,'publication_events',9,'publication_approvals',2
    )
  );

  v_ok:=v_metrics @> jsonb_build_object(
      'profile_total',60,'profile_au',52,'profile_nz',8,'profile_success',60,'profile_errors',0,
      'current_contacts',31,'contact_providers',11,'territory_contacts',17,'rejected_contacts',45,
      'email_contacts',30,'phone_contacts',18,'reviewed_rejection_violations',0
    )
    and coalesce((v_key_contacts->>'uow')::boolean,false)
    and coalesce((v_key_contacts->>'vu')::boolean,false)
    and coalesce((v_key_contacts->>'wellington')::boolean,false)
    and coalesce((v_key_contacts->>'otago')::boolean,false)
    and coalesce((v_watch->>'removal_supported')::boolean,false)
    and coalesce((v_watch->>'restoration_supported')::boolean,false)
    and coalesce((v_watch->>'contact_removed_count')::integer,0)>0
    and coalesce((v_security->>'rls_enabled')::boolean,false)
    and coalesce((v_security->>'no_direct_table_grants')::boolean,false)
    and coalesce((v_security->>'service_upsert_private')::boolean,false)
    and coalesce((v_security->>'service_reconcile_private')::boolean,false)
    and (v_authority-'expected')=(v_authority->'expected');

  return jsonb_build_object(
    'ok',v_ok,
    'change_control','CF-CHG-20260829-046',
    'frozen_baseline','A15-60-profile-first-party-v1',
    'metrics',v_metrics,
    'key_contacts',v_key_contacts,
    'watch_events',v_watch,
    'security',v_security,
    'authority',v_authority,
    'canonical_mutation_authorised',false,
    'search_mutation_authorised',false,
    'publication_mutation_authorised',false
  );
end $$;

revoke all on function security.admin_a15_acceptance_status() from public,anon;
grant execute on function security.admin_a15_acceptance_status() to authenticated,service_role;

create or replace function public.admin_read(p_operation text,p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog','public','security'
as $$
declare v_result jsonb;v_id uuid;begin
 if p_operation='admin_filter_option_page' then return security.admin_filter_option_page(p_args); end if;
 if p_operation='dashboard' then return security.admin_dashboard_maturity(); end if;
 if p_operation='catalogue_filter_page' then return security.admin_catalogue_filter_page(p_args); end if;
 if p_operation in ('provider_filters','course_filters') then return security.admin_catalogue_filter_options(p_operation,p_args); end if;
 if p_operation in ('evidence_page','evidence_filters','evidence_detail','evidence_observations','evidence_entities') then return security.admin_evidence_read(p_operation,p_args); end if;
 if p_operation='courses_page' then return security.admin_course_page_fast(p_args); end if;
 if p_operation in ('providers_page','campuses_page','scholarships_page') then return security.admin_catalogue_page(p_operation,p_args); end if;
 if p_operation in ('qilt_outcomes','qilt_filters','prisms_student_flow','prisms_filters') then return security.admin_insights_read(p_operation,p_args); end if;
 if p_operation='reviews_page' then return security.admin_operational_page(p_operation,p_args); end if;
 if p_operation in ('reviews','jobs','sources') then return security.admin_operations_read(p_operation,p_args); end if;
 if p_operation='layer1_operations' then return security.admin_layer1_operations_read(p_args); end if;
 if p_operation='layer2_ops_alerts' then return security.layer2_operational_alerts_read(); end if;
 if p_operation in ('layer2_ops_overview','layer2_ops_run_detail') then return security.admin_layer2_ops_read(p_operation,p_args); end if;
 if p_operation in ('layer2_profiles','layer2_profile_detail') then return security.admin_layer2_config_read(p_operation,p_args); end if;
 if p_operation in ('layer2_acquisition_providers','layer2_provider_routes','layer2_provider_attempts') then return security.admin_layer2_provider_read(p_operation,p_args); end if;
 if p_operation='attributes' then return security.admin_pim_governance_read(p_args); end if;
 if p_operation in ('pipeline_overview','pipeline_jobs_page','pipeline_job_detail','pipeline_sources_page','pipeline_filters') then v_result:=security.admin_pipeline_ops_read(p_operation,p_args);return security.admin_pipeline_ops_sanitise_result(p_operation,v_result);end if;
 if p_operation in ('data_quality_overview','data_quality_exceptions') then return security.admin_data_quality_read(p_operation,p_args); end if;
 if p_operation='publication_overview' then return security.admin_publication_overview(); end if;
 if p_operation='a15_acceptance_status' then return security.admin_a15_acceptance_status(); end if;
 if p_operation='provider_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_provider_detail(v_id)||jsonb_build_object('contextual_insights',security.admin_contextual_insights('provider',v_id));end if;
 if p_operation='campus_detail' then v_id:=nullif(p_args->>'id','')::uuid;return security.admin_campus_detail(v_id);end if;
 v_result:=security.admin_read_impl(p_operation,p_args);
 if p_operation='course_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('fee_summary',security.admin_course_fee_summary(v_id))||jsonb_build_object('entry_summary',security.admin_course_entry_summary(v_id))||jsonb_build_object('taxonomy_summary',security.admin_course_taxonomy_summary(v_id))||jsonb_build_object('state_summary',security.admin_course_state_summary(v_id))||jsonb_build_object('contextual_insights',security.admin_contextual_insights('course',v_id));end if;
 if p_operation='scholarship_detail' then v_id:=nullif(p_args->>'id','')::uuid;return v_result||jsonb_build_object('semantic_summary',security.admin_scholarship_semantic_summary(v_id));end if;
 return v_result;
end $$;

revoke all on function public.admin_read(text,jsonb) from public,anon;
grant execute on function public.admin_read(text,jsonb) to authenticated,service_role;
