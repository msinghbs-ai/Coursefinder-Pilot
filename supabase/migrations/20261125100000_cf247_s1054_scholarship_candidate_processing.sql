-- CF-247 s1054 (S1-Build; Platform Admin 24 Nov 2026 19:48 AEDT, SCH-FU-09: "Restore reliable, authorised candidate processing through the
-- existing pipeline ... Correct the candidate picker scope and ensure fair processing across AU, NZ and CA"; no new cron, no weaker gates,
-- no higher limits).
-- Found live (rolled back, 24 Nov 2026 19:55 AEDT):
--   * scholarship-read (*/5) and scholarship-discover (*/10) are off. They were paused with scholarship-discover-refill and calendar-reread by
--     migration 20261117051700 (Pilot #1195, Platform Admin 17 Nov 2026 13:11): "Temporarily paused for bulk REQ and Roadmap ingestion ... no
--     or almost no work moved in 72 hours. Resume on Automations." (events marked temporary). That ingestion is long finished. The listing
--     reader has since filled the candidate queue, and only scholarship-discover's candidate phase reads candidates, so they wait.
--   * Unread candidates: AU 966 pickable (21 providers), 600 held by the provider's Firecrawl hold, 164 at discovery priority 2, 208 not due,
--     25 after three tries; CA 283 pickable (26), 216 held, 76 not due, 19 after three tries; NZ 92 pickable (14), 5 held, 20 not due, 2 after
--     three tries. Oldest pickable: AU 12 Nov, CA 16 Nov, NZ 20 Nov.
--   * public.svc_scholarship_candidate_next (md5 ff53456e...) puts every candidate with requested_at first, whoever asked and however long ago,
--     then tier and age. On-demand run c209b8f0 therefore read 41 other providers' candidates first (SCH-FU-03), and AU's older backlog
--     crowds out NZ and CA.
-- What changes (live on deploy):
--   1. The picker puts first only the candidates of providers in a queued or running "Find scholarships" task (scholarship_provider_scan, the
--      existing on-demand route), then takes the rest in turn across countries (AU, NZ and CA alternate), and within a country in turn across
--      providers. The holds are unchanged: hidden providers, the Firecrawl hold, search off, third-party hosts, three tries, the lease.
--   2. scholarship-discover and scholarship-read are resumed, the step the pause itself names, with a resume event giving the Platform Admin's
--      instruction. Their commands, sizes and budgets are unchanged. scholarship-discover-refill, scholarship-listing and calendar-reread are not
--      touched.
-- G1: no new job (two catalogued jobs resumed). G2: no new value (sizes stay settings). G3: no consumer object changed. Active cron stays at or
--   under 140 (checked). Manual locks checked unchanged.
-- Replaces: the requested-first, country-blind candidate order of the picker.
-- Retires: nothing. Nothing dropped or deleted.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '60s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1054_locks on commit drop as select count(*) n from pipeline.manual_locks;

CREATE OR REPLACE FUNCTION public.svc_scholarship_candidate_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb; v_ok uuid[] := '{}'; v_p record; v_task uuid[];
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  -- CF-247 s1054: only a queued or running "Find scholarships" task puts its providers' candidates first (a request left from earlier no longer does)
  v_task := array(select distinct x::uuid from pipeline.admin_jobs j, jsonb_array_elements_text(coalesce(j.args->'providers', '[]'::jsonb)) x
                   where j.kind = 'scholarship_provider_scan' and j.state in ('queued', 'running'));
  -- CF-247 scholarship recovery F1: the skip rules run when candidates are recorded and hourly (security.scholarship_candidate_skip_v1).
  -- CF-247 s1054: the holds are checked once per provider that has a due candidate, before the window, so held providers never fill it
  for v_p in select distinct c.provider_id from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
              where c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3 loop
    -- v2.15.237 unpublished; v2.15.265 eligibility and cap; v2.15.271 search off
    if not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = v_p.provider_id) and not security.fc_sch_held_v1(v_p.provider_id, true)
       and not security.provider_sch_search_off_v1(v_p.provider_id) then v_ok := v_ok || v_p.provider_id; end if;
  end loop;
  create temp table if not exists sch_cand_win_v2(id bigint, provider_id uuid, url text, requested boolean, tier int, priority int, found_at timestamptz, cc text) on commit drop;
  truncate sch_cand_win_v2;
  insert into sch_cand_win_v2
  select z.id, z.provider_id, z.url, z.requested, z.tier, z.priority, z.found_at, z.cc from (
    select c.id, c.provider_id, c.url, c.provider_id = any (v_task) requested, coalesce(d.tier, 9) tier, d.priority, c.found_at, coalesce(co.iso_alpha2::text, '--') cc,
           -- CF-247 s1054: the window takes each country in turn, so one country's older backlog never fills it
           row_number() over (partition by coalesce(co.iso_alpha2::text, '--') order by (c.provider_id = any (v_task)) desc, coalesce(d.tier, 9), (d.priority not in (0,3)), c.found_at, c.id) crk
      from pipeline.scholarship_page_candidates c join pipeline.scholarship_discovery_providers d on d.provider_id=c.provider_id and d.priority in (0,1,3,4)
      join catalogue.providers p on p.id = c.provider_id left join ref.countries co on co.id = p.country_id
     where c.provider_id = any (v_ok) and c.matched_scholarship_id is null and c.admit_status is null and c.next_read_at<=now() and coalesce(c.leased_until,'-infinity')<now() and c.attempts<3) z
   order by z.requested desc, z.crk, z.cc
   limit greatest(1, security.pipeline_num_v1('scholarship.candidate_pick_window', 600)::int);
  with ranked0 as (
    select w.id, w.requested, w.tier, w.priority, w.cc, row_number() over (partition by w.provider_id order by (w.url ~* 'international') desc, w.found_at, w.id) rn
      from sch_cand_win_v2 w where not security.third_party_host_v1(w.url)),
  ranked as (
    -- CF-247 s1054: within a country the providers take turns (rn), and the countries take turns (crk)
    select r0.*, row_number() over (partition by r0.requested, r0.cc order by r0.rn, r0.tier, (r0.priority not in (0,3)), r0.id) crk from ranked0 r0),
  pick as (
    select c.id from pipeline.scholarship_page_candidates c join ranked r on r.id=c.id
     -- re-checked on the locked row, so concurrent readers never take the same page
     where coalesce(c.leased_until,'-infinity')<now() and c.admit_status is null and c.matched_scholarship_id is null and c.next_read_at<=now()
     order by r.requested desc, r.crk, r.cc, c.id
     limit greatest(1,least(coalesce(p_limit,30), security.pipeline_num_v1('scholarship.candidates_max', 60)::int)) for update of c skip locked),
  upd as (update pipeline.scholarship_page_candidates c set leased_until=now()+interval '5 minutes', attempts=c.attempts+1 from pick where c.id=pick.id  -- fixed: claim lease
          returning c.id, c.url, c.provider_id)
  select coalesce(jsonb_agg(jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'currency',scholarship.provider_currency(u.provider_id),
           'site',(select coalesce(site_origin,website) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id),
           'hosts',(select to_jsonb(allowed_hosts) from pipeline.scholarship_discovery_providers d where d.provider_id=u.provider_id))),'[]'::jsonb)
    into v from upd u;
  return v;
end $function$;
comment on function public.svc_scholarship_candidate_next(integer) is 'CF-247 s1054: the next due scholarship candidate pages for the candidate reader. Candidates of providers in a queued or running "Find scholarships" task come first; the rest are taken in turn across countries and, within a country, across providers. Holds: hidden provider, Firecrawl hold, search off, third-party host, three tries, lease.';

-- resume the two readers the 17 Nov pause names (the step it gives: "Resume on Automations"), recorded like the pause
do $resume$
declare
  v_jobs constant text[] := array['scholarship-discover', 'scholarship-read'];
  v_reason constant text := 'Resumed: the 17 Nov 2026 13:11 pause was temporary for the bulk REQ and Roadmap ingestion, which is finished; Platform Admin 24 Nov 2026 19:48 AEDT (SCH-FU-09): restore the existing scheduled candidate processing. Commands, sizes and budgets unchanged.';
  r record; v_n int := 0;
begin
  if exists (select 1 from unnest(v_jobs) x where x in (select legacy_job from pipeline.rollup_targets)
                                              or x in (select legacy_job from pipeline.admission_rules)
                                              or x in (select lane_code from pipeline.coverage_lane_runs where tick_at > now() - interval '1 day')) then
    raise exception 'a job to resume is run by a dispatcher; it is not resumed here';
  end if;
  if exists (select 1 from unnest(v_jobs) x where not exists (select 1 from pipeline.admin_control_events e where e.area = 'automations' and e.action = 'pause' and e.target = x
                                                                and e.detail->>'by' = 'migration 20261117051700' and (e.detail->>'temporary')::boolean)) then
    raise exception 'a job to resume was not paused by the temporary 17 Nov pause';
  end if;
  for r in select j.jobid, j.jobname from cron.job j where j.jobname = any (v_jobs) and not j.active loop
    perform cron.alter_job(r.jobid, active => true);
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('automations', 'resume', r.jobname, jsonb_build_object('reason', v_reason, 'by', 'migration 20261125100000 (CF-247 s1054)', 'paused_by', 'migration 20261117051700'), null);
    v_n := v_n + 1;
  end loop;
  raise notice 's1054: resumed % job(s)', v_n;
end $resume$;

do $c$
declare v_api jsonb;
begin
  if (select count(*) from cron.job where jobname in ('scholarship-discover', 'scholarship-read') and active) <> 2 then raise exception 'post-check: the two readers are not running'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1054_locks) then raise exception 'post-check: manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
