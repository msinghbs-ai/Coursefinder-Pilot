CREATE OR REPLACE FUNCTION security.admin_a15_acceptance_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue', 'ref', 'search', 'publishing', 'public', 'auth'
AS $function$
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
    'sydney',(
      select count(*)=4
      from pipeline.provider_contact_observations o
      join catalogue.providers p on p.id=o.provider_id
      where lower(p.canonical_name)='the university of sydney'
        and o.is_current and o.verification_state='current'
        and o.team_name='International Recruitment'
        and o.source_url='https://www.sydney.edu.au/study/applying/how-to-apply/international-students/contact-our-regional-experts.html'
        and o.metadata->>'a15_quality_reconciliation'='sydney_first_party_regional_experts'
        and (o.full_name,o.job_title,o.territory_text,o.work_email) in (
          ('Chris Lawrance','Regional Manager','Americas and Europe','chris.lawrance@sydney.edu.au'),
          ('Nishant Jadhav','Senior Regional Manager','Central Asia, South Asia, Middle East and Africa','nishant.jadhav@sydney.edu.au'),
          ('Sean Lee','Senior Regional Manager','Asia (excluding China, Hong Kong and Macau)','sean.lee@sydney.edu.au'),
          ('Sherrie Huan','Senior Regional Manager','China, Hong Kong and Macau','sherrie.huan@sydney.edu.au')
        )
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
    and coalesce((v_key_contacts->>'sydney')::boolean,false)
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
end $function$
