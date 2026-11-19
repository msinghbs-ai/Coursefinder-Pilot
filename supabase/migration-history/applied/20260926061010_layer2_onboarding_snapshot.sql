create table if not exists pipeline.layer2_onboarding_snapshot(
  provider_id uuid primary key references catalogue.providers(id) on delete cascade,
  country_code text not null,
  courses_waiting int not null,
  rank_no int not null,
  candidates jsonb not null default '[]'::jsonb,
  computed_at timestamptz not null default now()
);
create index if not exists layer2_onboarding_snapshot_rank_idx on pipeline.layer2_onboarding_snapshot(country_code, rank_no);
alter table pipeline.layer2_onboarding_snapshot enable row level security;
revoke all on pipeline.layer2_onboarding_snapshot from public, anon, authenticated;

create or replace function security.layer2_onboarding_snapshot_refresh_v1(p_with_candidates int default 150)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','security','pipeline','catalogue'
as $$
declare t0 timestamptz := clock_timestamp(); v_n int;
begin
  create temp table _w on commit drop as
    select b.country_code, c.provider_id, count(*)::int waiting
    from pipeline.au_nz_enrichment_backlog_v1 b join catalogue.courses c on c.id=b.course_id
    where b.field_key='official_course_url' and b.backlog_state='awaiting_source_profile_qualification'
    group by 1,2;
  delete from pipeline.layer2_onboarding_snapshot s where not exists (select 1 from _w where _w.provider_id=s.provider_id);
  insert into pipeline.layer2_onboarding_snapshot(provider_id,country_code,courses_waiting,rank_no,candidates,computed_at)
  select provider_id, country_code, waiting, rn,
         case when rn <= p_with_candidates then security.layer2_catalogue_candidates_v1(provider_id, 5) else '[]'::jsonb end, now()
  from (select _w.*, row_number() over (partition by country_code order by waiting desc, provider_id) rn from _w) x
  on conflict (provider_id) do update set country_code=excluded.country_code, courses_waiting=excluded.courses_waiting,
    rank_no=excluded.rank_no, candidates=excluded.candidates, computed_at=excluded.computed_at;
  get diagnostics v_n = row_count;
  return jsonb_build_object('providers',v_n,'ms',round(extract(epoch from clock_timestamp()-t0)*1000));
end $$;
revoke all on function security.layer2_onboarding_snapshot_refresh_v1(int) from public, anon, authenticated;

create or replace function public.layer2_provider_onboarding_queue_v1(p_country text default 'AU', p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','security','pipeline','catalogue','public'
as $$
declare v jsonb; v_cc text := upper(coalesce(p_country,'AU'));
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'Curator role is required' using errcode='42501'; end if;
  with t as (
    select s.*, p.canonical_name, p.website from pipeline.layer2_onboarding_snapshot s join catalogue.providers p on p.id=s.provider_id
    where s.country_code=v_cc order by s.rank_no limit greatest(1,least(coalesce(p_limit,50),200))),
  e as (
    select t.*,
      exists(select 1 from pipeline.layer2_source_profiles sp join pipeline.sources so on so.id=sp.source_id where so.provider_id=t.provider_id and sp.authority_class='qualification_candidate' and sp.domain='course_facts' and sp.enabled and not sp.paused) has_candidate_profile,
      (select jsonb_object_agg(st,n) from (select qi.status st, count(*) n from pipeline.layer2_scale_qualification_items qi where qi.provider_id=t.provider_id group by 1) z) item_states,
      (select jsonb_build_object('status',a.status,'url',a.candidate_url,'score',a.score,'evidence_id',a.evidence_id,'at',a.created_at,'resolved_at',a.resolved_at,'reason',a.detail->>'reason','error',a.detail->>'error')
         from pipeline.layer2_auto_discovery_attempts a where a.provider_id=t.provider_id order by a.created_at desc limit 1) auto_latest,
      (select count(*) from pipeline.layer2_auto_discovery_attempts a where a.provider_id=t.provider_id and a.status in ('failed','error')) auto_failed,
      (select jsonb_build_object('url',x.catalogue_url,'at',x.created_at,'dry_run',x.dry_run,'origin',x.origin) from pipeline.layer2_provider_catalogue_submissions x where x.provider_id=t.provider_id order by x.created_at desc limit 1) last_submission
    from t)
  select jsonb_build_object('country',v_cc,
    'providers_waiting',(select count(*) from pipeline.layer2_onboarding_snapshot where country_code=v_cc),
    'courses_waiting',(select coalesce(sum(courses_waiting),0) from pipeline.layer2_onboarding_snapshot where country_code=v_cc),
    'computed_at',(select max(computed_at) from pipeline.layer2_onboarding_snapshot where country_code=v_cc),
    'items',coalesce((select jsonb_agg(jsonb_build_object('provider_id',provider_id,'provider',canonical_name,'website',website,'courses_waiting',courses_waiting,
        'state',case when (item_states ? 'profile_qualified') or auto_latest->>'status'='passed' then 'qualified'
                     when (item_states ? 'source_pattern_candidate') then 'identity_check_running'
                     when auto_latest->>'status'='needs_person' then 'needs_person'
                     when (item_states ? 'layer3_required') or (item_states ? 'layer4_required') then 'needs_catalogue_page'
                     when (item_states ? 'source_limited') then 'site_limited'
                     when item_states is null then 'not_yet_assessed' else 'in_progress' end,
        'ready_for_submission',has_candidate_profile and ((item_states ? 'layer3_required') or (item_states ? 'layer4_required')),
        'suggested_start',coalesce(regexp_replace(candidates->0->>'url','^http://','https://'),website),
        'candidates',(select coalesce(jsonb_agg(c),'[]'::jsonb) from (select c from jsonb_array_elements(candidates) c limit 3) cc),
        'auto_latest',auto_latest,'auto_failed',auto_failed,'last_submission',last_submission) order by rank_no) from e),'[]'::jsonb))
  into v;
  return v;
end $$;
revoke all on function public.layer2_provider_onboarding_queue_v1(text,integer) from public, anon;
grant execute on function public.layer2_provider_onboarding_queue_v1(text,integer) to authenticated, service_role;

select cron.unschedule(jobid) from cron.job where jobname='layer2-onboarding-snapshot';
select cron.schedule('layer2-onboarding-snapshot','*/10 * * * *',$c$select security.layer2_onboarding_snapshot_refresh_v1(150);$c$);
