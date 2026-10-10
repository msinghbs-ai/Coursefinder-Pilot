-- Package 7 (Decisions 141, 146, 147): onboarding queue shows each provider's ranked candidates
-- (from stored evidence, with the capture each came from) and its latest automatic attempt.
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
      (select jsonb_object_agg(st,n) from (select qi.status st, count(*) n from pipeline.layer2_scale_qualification_items qi where qi.provider_id=w.provider_id group by 1) z) item_states
    from w join catalogue.providers p on p.id=w.provider_id),
  t as (select * from q order by waiting desc limit greatest(1,least(coalesce(p_limit,50),200))),
  e as (
    select t.*,
      (select jsonb_build_object('status',a.status,'url',a.candidate_url,'score',a.score,'evidence_id',a.evidence_id,'at',a.created_at,'resolved_at',a.resolved_at,'reason',a.detail->>'reason','error',a.detail->>'error')
         from pipeline.layer2_auto_discovery_attempts a where a.provider_id=t.provider_id order by a.created_at desc limit 1) auto_latest,
      (select count(*) from pipeline.layer2_auto_discovery_attempts a where a.provider_id=t.provider_id and a.status in ('failed','error')) auto_failed,
      (select jsonb_build_object('url',x.catalogue_url,'at',x.created_at,'dry_run',x.dry_run,'origin',x.origin) from pipeline.layer2_provider_catalogue_submissions x where x.provider_id=t.provider_id order by x.created_at desc limit 1) last_submission,
      security.layer2_catalogue_candidates_v1(t.provider_id, 3) candidates
    from t)
  select jsonb_build_object('country',upper(coalesce(p_country,'AU')),'providers_waiting',(select count(*) from q),'courses_waiting',(select coalesce(sum(waiting),0) from q),
    'items',coalesce((select jsonb_agg(jsonb_build_object('provider_id',provider_id,'provider',canonical_name,'website',website,'courses_waiting',waiting,
        'state',case when (item_states ? 'profile_qualified') or auto_latest->>'status'='passed' then 'qualified'
                     when (item_states ? 'source_pattern_candidate') then 'identity_check_running'
                     when auto_latest->>'status'='needs_person' then 'needs_person'
                     when (item_states ? 'layer3_required') or (item_states ? 'layer4_required') then 'needs_catalogue_page'
                     when (item_states ? 'source_limited') then 'site_limited'
                     when item_states is null then 'not_yet_assessed' else 'in_progress' end,
        'ready_for_submission',has_candidate_profile and ((item_states ? 'layer3_required') or (item_states ? 'layer4_required')),
        'suggested_start',coalesce(regexp_replace(candidates->0->>'url','^http://','https://'),website),
        'candidates',candidates,'auto_latest',auto_latest,'auto_failed',auto_failed,'last_submission',last_submission) order by waiting desc) from e),'[]'::jsonb))
  into v;
  return v;
end $$;
revoke all on function public.layer2_provider_onboarding_queue_v1(text,integer) from public, anon;
grant execute on function public.layer2_provider_onboarding_queue_v1(text,integer) to authenticated, service_role;
