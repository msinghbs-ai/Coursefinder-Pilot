-- CF-247 orchestration follow-ups (Integration Controller, 3 Nov 2026; branch cf247-orchestration-followups, builds on v2.15.424): IQ-00066 (P1)
-- plan steps proposed and tasks ended done with no eligible work; IQ-00053 residual (svc_enrich_ai_record answers cancelled by the 8 s statement
-- time-out); IQ-00063 (an onboarding row looping on a website that is an email address).
-- Why (live, read-only, 3 Nov 2026 13:52-14:10 AEDT):
--   IQ-00066. At 12:41 AEDT enrich-plan-auto (security.enrich_plan_auto_v1) created 17 automatic plans whose only step was "Find and read
--     scholarships" ("No scholarships and never searched"). The plan builder, security.enrich_plan_v1 §6, proposes that step for any provider
--     with no active scholarship and no scholarship_provider_scan task in 30 days, whatever the scan could do. All 17 providers had their sites
--     mapped for scholarships on 2-4 Oct (16 kept no candidate page, one kept one) and all 17 are refused by the scholarship reader's own gate:
--     security.fc_sch_held_v1(provider, true) is true for 17 of 17 because security.fc_sch_eligible_v1 is false (Australian, fewer than
--     scholarship_min_courses active courses). security.scholarship_task_prepare_v1 set their discovery rows pending, but the discover picker
--     (public.svc_scholarship_discover_next) holds them and moves next_discover_at on (all 17 not due before 15:00 AEDT). The task watcher
--     (security.admin_job_watch_v1) counted the pending row as "mapping the site" with 0 pages (total 0), so the IQ-00064 hold (done < total)
--     never applied; after 30 minutes the stall rule finished it ("0 of 0 done, nothing more for 30 minutes: the rest wait their turn in the
--     reader"), security.admin_jobs_tick_v1 set it done and security.enrich_plan_tick_v1 marked the step and the plan done, 16 of them with no
--     other step: 17 done plans with no data moved. The open question: a scan in the mapping or screening phase is unfinished work when the
--     work is eligible (it is held, never done), and not needed when it is not.
--   IQ-00053 residual. The six svc_enrich_ai_record answers cancelled at 13:47:02-13:47:11 and 13:48:50-13:48:58 AEDT (and 23 more at
--     13:50-13:53, outside the :47-:48 minutes) are, by the cancelled statement's context in the Postgres log: 28 in
--     security.course_description_check_v1 (the duplicate check, security.pdesc_similarity_v1 -> security.pdesc_words_v1, called from
--     security.enrich_course_text_record_v1, line 35 of svc_enrich_ai_record), 2 waiting on a key-share lock on pipeline.admin_jobs (a second
--     update of the same field_enrich_items row in one transaction re-checks its foreign key) and 1 elsewhere in the description check. The
--     worker records a whole batch (enrich.ai_items_per_call, 30) in one statement; each course description answer re-splits the new text into
--     words once for every other description of the provider (up to enrich.course_description_duplicate_window): measured 14:05-14:06 AEDT,
--     118 ms a full check on average (40 recent answers); the duplicate scan of the provider with the most descriptions (152) took 265-346 ms.
--     The same scan with the new text split once and each other text split inline (no SQL-function call per row) took 18 ms at 14:16 AEDT
--     and gave the same 152 similarities. There is no busy-window mechanism to reuse (no setting or function names one), and the failures
--     are not only in the busy minutes, so the record does less per call instead. svc_enrich_ai_record itself is not edited (Release B
--     edits it).
--   IQ-00063. pipeline.provider_onboarding d5dfc2ea (provider 2db6cb5e) has result.website and catalogue.providers.website
--     "https://info@newgen.edu.au". In course_pages, the generic course-page recipe takes the host "info@newgen.edu.au", which is not a domain,
--     so no recipe is made; starting Find course pages raises "no website is recorded"; security.provider_onboarding_tick_v1 stops the row
--     no_website; on the next run its "a missing website was entered" rule sees a non-empty website and sends it back to website, which sends it
--     to course_pages ("Website known; finding course pages."), and so on every two minutes since 12 Oct. It is the only provider whose website
--     is not a host URL (3 Nov 13:59 AEDT).
-- What (plans.step_needs_work_on and onboarding.website_check_on ship ON (1): the items state the required behaviour; each change only stops work
-- that has no eligible scope and spends nothing; 0 restores the previous behaviour):
--   1 security.scholarship_scan_work_v1(providers) (new, read-only): whether a scholarship scan has eligible work now, by the scholarship
--     reader's own gates (unpublished, no website, search switched off, directory site, security.fc_sch_held_v1: not eligible or the credit
--     cap), and whether anything is due (site mapping due: no row or next_discover_at reached; candidate pages waiting; listing pages); with
--     the reason when it has none. security.plan_step_work_v1(provider, step) (new, read-only) answers it for a plan step (scholarships; the
--     other steps keep their own rules).
--   2 security.enrich_plan_v1 (md5-guarded edit): the scholarships step is proposed only when the scan has eligible work now; otherwise it is
--     listed under not_proposed with the reason (the plan screen and the automatic planner read steps only).
--   3 security.enrich_plan_tick_v1 (md5-guarded edit): a pending step with no eligible work when it would start ends not_needed with the reason
--     (no task is started); a step whose task ended not needed is not_needed; a finished plan records actual.outcome: moved (a step done),
--     not_needed (every step that ran was not needed) or no_movement (security.plan_run_outcome_v1, new).
--   4 security.admin_job_watch_v1 (md5-guarded edit): a scholarship scan counts as mapping or screening only the eligible work (a pending
--     discovery row the reader holds is not work); one with no page in scope, no eligible work and no site mapped or tried while it ran ends
--     at once as not needed with the reason (result end_state not_needed); one whose site mapping or candidate screening is eligible and waiting is held
--     by the IQ-00064 hold (tasks.lane_hold_on), with its remaining work counted, instead of ending done by the stall rule.
--   5 security.admin_jobs_tick_v1 (md5-guarded edit): a task the watcher ended not needed is closed as cancelled (pipeline.admin_jobs.state has
--     no not_needed value, and widening its check would drop a constraint), its error the "Not needed: ..." reason; never done.
--   6 Reporting: security.plan_outcomes_v1() (new, read-only): plans finished in plans.outcome_window_hours by outcome (moved, not_needed,
--     no_movement), not-needed steps by step and tasks ended not needed; public.admin_pipeline_yield (md5-guarded edit) returns it as
--     plan_outcomes beside lane_status (Platform health › Integration queue › Pipeline yield).
--   7 security.course_description_check_v1 (md5-guarded edit): the duplicate check splits the new description into words once and each other
--     description inline (same words, same share, same threshold and window); nothing else changes.
--   8 security.website_refusal_v1(url) (new, read-only): why a website cannot be used as a site (not http or https, spaces, a user part as in an
--     email address, no domain name), or null. security.provider_onboarding_tick_v1 (md5-guarded edit): with onboarding.website_check_on, a
--     row in queued, website, course_pages or waiting_courses (or stopped no_website) whose provider website is refused stops with
--     needs_source_discovery and the reason, and is not stepped; it carries on by itself once the website is corrected; the "website entered"
--     rule no longer sends a refused website back to the website stage. needs_source_discovery is added to plans.retry_waits_for_change, so
--     the plan's adapter step waits for the change instead of retrying.
-- Budgets: no Firecrawl or AI value is raised; nothing reads a page or calls a model that did not before.
-- md5 (before = live v2.15.424, read 3 Nov 2026 13:53-14:05 AEDT; after = local replay on PostgreSQL 16, tests/fixtures/orchestration-followups/run.sh):
--   security.enrich_plan_v1(uuid)                          818ef130484e567c35a7a2cf5a99d7c8 -> a63146c23989eb64ee2248e3f32eade6
--   security.enrich_plan_tick_v1(uuid)                     cab734df6715e25014935bd22058343b -> 77705c2b34e13801f4d7ccc5773bd4c1
--   security.admin_job_watch_v1(uuid)                      34a1cfd57b367d0e60ccb4a85f56e228 -> 995f26c437f0abfb3c666271cd622fec
--   security.admin_jobs_tick_v1(integer)                   fc698f9912cffd90a7b8ae32e33dd09e -> e5f4881ca7423c8aa0df0923a5057806
--   public.admin_pipeline_yield(jsonb)                     34617ad96ea43189509c3f4dd536d50e -> a8af701f17f105b5af4db210896241eb
--   security.course_description_check_v1(uuid,jsonb)       4822f66ee262cdfa1c4cd798cfc3dd26 -> ff3d6dd7b0f88c85b1fdff6c8a8cd86b
--   security.provider_onboarding_tick_v1()                 01c5659bb4c364e80b0544fa60bca0ee -> 181fc3dd2d78930c32e70cc24fb0adbd
-- Not edited (Release B, 20261103210000, edits them): public.svc_enrich_ai_record, public.svc_enrich_ai_next, security.enrich_fields_slice_v1,
--   security.field_enrich_items_flag_v1, security.course_coverage_build_v1, security.source_proof_feed_v1.
-- Consumer API (G3): untouched (no website_*, zoho_*, api.* object, table or column is changed).
-- Data: nothing is corrected here. The onboarding row d5dfc2ea stops by itself on the first run (needs_source_discovery); the website value of
--   provider 2db6cb5e is for the Platform Admin to correct (paste file in the PR description).
-- Replaces: the scholarships step proposed without eligible work in security.enrich_plan_v1; the stall finish (done) of a scholarship scan with
--   no eligible work in security.admin_job_watch_v1 and security.admin_jobs_tick_v1; the per-row word split of the new text in
--   security.course_description_check_v1; the website-to-course-pages loop on a refused website in security.provider_onboarding_tick_v1
--   (same functions, md5-guarded edits; enrich_plan_tick_v1 and admin_pipeline_yield edited in place)
-- Retires: nothing
-- Nothing is dropped or deleted.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 0. the definitions the new code calls are the ones it was written against (not changed here) ----------------------------------------------
do $g$
declare r record;
begin
  for r in select * from (values ('security.fc_sch_held_v1(uuid,boolean)', 'f8d6fb4bf9196dfa596b8274819670a6'),
                                 ('security.provider_sch_search_off_v1(uuid)', '99185af92169668ac0437857467e4d3c'),
                                 ('security.pdesc_words_v1(text)', '1a18bd60d2978c1885a25085b688afc7'),
                                 ('security.pdesc_similarity_v1(text,text)', '357a9ebfde1c68a286ad4f685445cf9b')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then raise exception 'live % differs from the definition this change was written against', r.sig; end if;
  end loop;
end $g$;

-- 1. settings (G2) ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'plans.step_needs_work_on', 'Plans: a step runs only when it has work',
  '1: an enrichment plan proposes and starts a step only when its scope has eligible work now (scholarships: the scholarship reader''s own gates and something due); a step or scholarship scan task with none ends not needed with the reason, never done, and a scan whose site mapping or candidate screening waits is held. 0: as before.',
  'number', '1'::jsonb, '0', '1', 'on (1) or off (0)', 789, 'Platform upkeep',
  'security.enrich_plan_v1, security.enrich_plan_tick_v1, security.admin_job_watch_v1', 'CF-247 IQ-00066 (P1), 3 Nov 2026: on'),
 ('pipeline', 'plans.outcome_window_hours', 'Plans: outcome report looks back',
  'Pipeline yield › plan outcomes counts the enrichment plans finished in the last this many hours by outcome (data moved, not needed, nothing moved), the steps that were not needed and the tasks that ended not needed.',
  'number', '24'::jsonb, '1', '168', 'hours', 790, 'Platform upkeep', 'security.plan_outcomes_v1 (public.admin_pipeline_yield)', 'CF-247 IQ-00066 (P1), 3 Nov 2026'),
 ('pipeline', 'onboarding.website_check_on', 'Onboarding: refuse a website that is not a site address',
  '1: onboarding stops with needs_source_discovery, and the reason, when the provider''s recorded website is not a host URL (not http or https, spaces, a user part as in an email address, or no domain name), instead of going round between the website and course-page stages; it carries on by itself once the website is corrected. 0: as before.',
  'number', '1'::jsonb, '0', '1', 'on (1) or off (0)', 791, 'Platform upkeep', 'security.provider_onboarding_tick_v1, security.website_refusal_v1', 'CF-247 IQ-00063, 3 Nov 2026: on')
on conflict (toolset_key, key) do nothing;
-- the plan's adapter step waits for a change of website instead of retrying (the step note is "onboarding stopped: needs_source_discovery")
update pipeline.platform_toolset_settings set value = value || '["needs_source_discovery"]'::jsonb
 where toolset_key = 'pipeline' and key = 'plans.retry_waits_for_change' and jsonb_typeof(value) = 'array' and not value ? 'needs_source_discovery';

-- 2. eligible work for a scholarship scan and a plan step; why a website cannot be used; plan outcomes (read-only) ---------------------------
create or replace function security.scholarship_scan_work_v1(p_providers uuid[]) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
-- CF-247 IQ-00066: whether a scholarship scan of these providers has eligible work now, by the scholarship reader's own gates, and the reason
-- when it has none. map_due: site mapping due (no discovery row, or next_discover_at reached); candidates: candidate pages waiting to be
-- screened; listings: listing pages to read again. A provider held by a gate counts for nothing.
declare r record; v_site text; v_hold text; v_map int := 0; v_cand int := 0; v_list int := 0; v_held jsonb := '{}'::jsonb; v_due text; v_first text;
begin
  for r in select pr.id, nullif(btrim(pr.website), '') website, d.provider_id is not null has_row, d.next_discover_at, d.discovered_at, d.kept_count
             from catalogue.providers pr left join pipeline.scholarship_discovery_providers d on d.provider_id = pr.id
            where pr.id = any (coalesce(p_providers, '{}'::uuid[])) order by pr.id loop
    v_site := coalesce(r.website, (select nullif(btrim(x.website), '') from pipeline.coverage_provider_discovery x where x.provider_id = r.id and x.status = 'mapped'));
    v_hold := case when exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.id) then 'unpublished'
                   when v_site is null then 'no_website'
                   when security.provider_sch_search_off_v1(r.id) then 'search_off'
                   when security.third_party_host_v1(v_site) then 'directory_site'
                   when security.fc_sch_held_v1(r.id, true) then case when not security.fc_sch_eligible_v1(r.id) then 'not_eligible' else 'credit_cap' end end;
    if v_hold is not null then
      v_held := v_held || jsonb_build_object(v_hold, coalesce((v_held->>v_hold)::int, 0) + 1);
      continue;
    end if;
    if not r.has_row or r.next_discover_at is null or r.next_discover_at <= now() then v_map := v_map + 1;
    elsif v_due is null then
      v_due := 'site mapped for scholarships ' || coalesce(to_char(r.discovered_at at time zone 'Australia/Melbourne', 'DD Mon YYYY'), 'before') || ' ('
               || coalesce(r.kept_count, 0) || ' scholarship page(s) kept); next mapping due ' || to_char(r.next_discover_at at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI');
    end if;
    v_cand := v_cand + (select count(*) from pipeline.scholarship_page_candidates c
                         where c.provider_id = r.id and c.admit_status is null and c.matched_scholarship_id is null and c.source <> 'register' and c.attempts < 3
                           and (c.read_status is null or c.read_status in ('blocked', 'fetch_failed', 'too_thin', 'not_html', 'robots_disallowed', 'scrape_failed', 'waiting_scraper', 'deferred')));
    v_list := v_list + (select count(*) from pipeline.scholarship_listing_pages l where l.provider_id = r.id and l.active and not security.third_party_host_v1(coalesce(l.url, '')));
  end loop;
  v_first := (select k from jsonb_each_text(v_held) e(k, v) order by v::int desc, k limit 1);
  return jsonb_build_object('work', v_map + v_cand + v_list > 0, 'map_due', v_map, 'candidates', v_cand, 'listings', v_list, 'held', v_held,
    'code', case when v_map + v_cand + v_list > 0 then null when v_first is not null and v_due is null then v_first else 'nothing_due' end,
    'reason', case when v_map + v_cand + v_list > 0 then null
                   when v_first is not null and v_due is null then case v_first
                     when 'unpublished' then 'the provider is unpublished or archived'
                     when 'no_website' then 'no website is known'
                     when 'search_off' then 'scholarship search is switched off for this provider'
                     when 'directory_site' then 'the recorded website is a directory site'
                     when 'not_eligible' then 'not eligible for scholarship reading (the Firecrawl scholarship rules: fewer active courses than scholarship_min_courses, or outside the scholarship pilot)'
                     else 'its scholarship credit cap for the period is used' end
                   else coalesce(v_due, 'nothing is due') || '; no candidate or listing page is waiting' end);
end $$;
revoke all on function security.scholarship_scan_work_v1(uuid[]) from public, anon, authenticated;
comment on function security.scholarship_scan_work_v1(uuid[]) is 'CF-247 IQ-00066: whether a scholarship scan of these providers has eligible work now (the scholarship reader''s gates, then site mapping due, candidate or listing pages waiting), with the reason when it has none';

create or replace function security.plan_step_work_v1(p_provider uuid, p_step text) returns jsonb
language sql stable security definer set search_path = '' as $$
  -- CF-247 IQ-00066: whether an enrichment plan step has eligible work now (plans.step_needs_work_on). Scholarships answers from the
  -- scholarship reader's gates; the other steps keep their own rules in security.enrich_plan_v1 and are always answered as having work.
  select case p_step when 'scholarships' then security.scholarship_scan_work_v1(array[p_provider]) else jsonb_build_object('work', true) end
$$;
revoke all on function security.plan_step_work_v1(uuid, text) from public, anon, authenticated;
comment on function security.plan_step_work_v1(uuid, text) is 'CF-247 IQ-00066: whether an enrichment plan step has eligible work now, with the reason when it has none (scholarships: security.scholarship_scan_work_v1)';

create or replace function security.plan_run_outcome_v1(p_steps jsonb) returns text
language sql immutable set search_path = '' as $$
  -- CF-247 IQ-00066: a finished plan moved data only when a step was done; a plan whose steps that ran were all not needed is not_needed
  select case when exists (select 1 from jsonb_array_elements(coalesce(p_steps, '[]'::jsonb)) x where x->>'status' = 'done') then 'moved'
              when exists (select 1 from jsonb_array_elements(coalesce(p_steps, '[]'::jsonb)) x where x->>'status' = 'not_needed')
               and not exists (select 1 from jsonb_array_elements(coalesce(p_steps, '[]'::jsonb)) x where x->>'status' not in ('not_needed', 'person')) then 'not_needed'
              else 'no_movement' end
$$;
revoke all on function security.plan_run_outcome_v1(jsonb) from public, anon, authenticated;
comment on function security.plan_run_outcome_v1(jsonb) is 'CF-247 IQ-00066: a finished enrichment plan''s outcome from its steps: moved (a step done), not_needed (every step that ran was not needed) or no_movement';

create or replace function security.plan_outcomes_v1() returns jsonb
language sql stable security definer set search_path = '' as $$
  -- CF-247 IQ-00066: enrichment plans finished in plans.outcome_window_hours by outcome (a done plan with no step done moved no data), the
  -- steps that were not needed, and the tasks that ended not needed
  with w as (select now() - make_interval(hours => security.pipeline_num_v1('plans.outcome_window_hours', 24)::int) since),
  r as (select x.mode, x.state, coalesce(x.actual->>'outcome', security.plan_run_outcome_v1(x.steps)) outcome, x.steps
          from pipeline.enrich_plan_runs x, w where x.finished_at >= w.since and x.state = 'done')
  select jsonb_build_object('window_since', (select since from w),
    'plans_done', (select count(*) from r),
    'moved', (select count(*) from r where outcome = 'moved'),
    'not_needed', (select count(*) from r where outcome = 'not_needed'),
    'no_movement', (select count(*) from r where outcome = 'no_movement'),
    'auto', jsonb_build_object('moved', (select count(*) from r where mode = 'auto' and outcome = 'moved'),
                               'not_needed', (select count(*) from r where mode = 'auto' and outcome = 'not_needed'),
                               'no_movement', (select count(*) from r where mode = 'auto' and outcome = 'no_movement')),
    'steps_not_needed', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select s->>'step' k, count(*) n from r, jsonb_array_elements(r.steps) s
                                                                                     where s->>'status' = 'not_needed' group by 1) z),
    'tasks_not_needed', (select count(*) from pipeline.admin_jobs j, w where j.finished_at >= w.since and j.state = 'cancelled' and j.result->>'end_state' = 'not_needed'))
$$;
revoke all on function security.plan_outcomes_v1() from public, anon, authenticated;
comment on function security.plan_outcomes_v1() is 'CF-247 IQ-00066: enrichment plans finished in plans.outcome_window_hours by outcome (moved, not_needed, no_movement), steps not needed and tasks ended not needed; returned by public.admin_pipeline_yield as plan_outcomes';

create or replace function security.website_refusal_v1(p_url text) returns text
language sql immutable set search_path = '' as $$
  -- CF-247 IQ-00063: why a recorded website cannot be used as a site address, or null (an empty website is the no_website path, not this)
  select case
    when nullif(btrim(coalesce(p_url, '')), '') is null then null
    when btrim(p_url) ~ '\s' then 'it contains spaces'
    when btrim(p_url) !~* '^https?://' then 'it is not an http or https address'
    when substring(btrim(p_url) from '^[A-Za-z]+://([^/?#]*)') like '%@%' then 'it has a user part ("' || split_part(substring(btrim(p_url) from '^[A-Za-z]+://([^/?#]*)'), '@', 1) || '@"), as an email address does'
    when lower(substring(btrim(p_url) from '^[A-Za-z]+://([^/?#:]+)')) !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}\.?$' then 'its host is not a domain name'
  end
$$;
revoke all on function security.website_refusal_v1(text) from public, anon, authenticated;
comment on function security.website_refusal_v1(text) is 'CF-247 IQ-00063: why a recorded website cannot be used as a site address (not http or https, spaces, a user part as in an email address, no domain name), or null';

-- 3. the plan builder proposes a scholarships step only when the scan has eligible work now -------------------------------------------------
select pg_temp.edit_once('security.enrich_plan_v1(uuid)', '818ef130484e567c35a7a2cf5a99d7c8', 'a63146c23989eb64ee2248e3f32eade6', array[
 [$o$        v_sch int; v_sch_scan timestamptz;
begin$o$,
  $n$        v_sch int; v_sch_scan timestamptz; v_work jsonb; v_held jsonb := '[]'::jsonb;
begin$n$],
 [$o$  if v_sch = 0 and (v_sch_scan is null or v_sch_scan < now() - interval '30 days') then  -- fixed: the scholarship cap period is 30 days
    v_steps := v_steps || jsonb_build_object('step', 'scholarships',$o$,
  $n$  if v_sch = 0 and (v_sch_scan is null or v_sch_scan < now() - interval '30 days') then  -- fixed: the scholarship cap period is 30 days
    -- CF-247 IQ-00066 (plans.step_needs_work_on): proposed only when the scan has eligible work now; otherwise listed as not proposed, with why
    v_work := case when security.pipeline_num_v1('plans.step_needs_work_on', 0) >= 1 then security.plan_step_work_v1(p_provider, 'scholarships') end;
    if not coalesce((v_work->>'work')::boolean, true) then
      v_held := v_held || jsonb_build_object('step', 'scholarships', 'label', 'Find and read scholarships', 'code', v_work->>'code', 'reason', v_work->>'reason');
    else
    v_steps := v_steps || jsonb_build_object('step', 'scholarships',$n$],
 [$o$'group', 'scholarships',
      'blocked', case when p.website is null then 'Needs a website first (step 1)' end);
  end if;$o$,
  $n$'group', 'scholarships',
      'blocked', case when p.website is null then 'Needs a website first (step 1)' end);
    end if;
  end if;$n$],
 [$o$    'steps', v_steps,$o$,
  $n$    'steps', v_steps, 'not_proposed', v_held,$n$]
]::text[][], array[1, 1, 1, 1]);

-- 4. the plan tick: a step with no eligible work is not needed; a task ended not needed is a not-needed step; a finished plan's outcome ------
select pg_temp.edit_once('security.enrich_plan_tick_v1(uuid)', 'cab734df6715e25014935bd22058343b', '77705c2b34e13801f4d7ccc5773bd4c1', array[
 [$o$v_note text; v_track text;$o$,
  $n$v_note text; v_track text; v_work jsonb;$n$],
 [$o$             actual = jsonb_build_object(
               'credits',$o$,
  $n$             actual = jsonb_build_object(
               'outcome', security.plan_run_outcome_v1(r.steps),  -- CF-247 IQ-00066: moved, not_needed or no_movement
               'credits',$n$],
 [$o$      v_note := null;
$o$,
  $n$      v_note := null;
      -- CF-247 IQ-00066 (plans.step_needs_work_on): whether the step's scope has eligible work now
      v_work := case when security.pipeline_num_v1('plans.step_needs_work_on', 0) >= 1 and not coalesce((s->>'person')::boolean, false)
                     then security.plan_step_work_v1(r.provider_id, s->>'step') end;
$n$],
 [$o$      elsif r.mode = 'auto' and s->>'group' not in ('none')$o$,
  $n$      elsif not coalesce((v_work->>'work')::boolean, true) then
        -- CF-247 IQ-00066: no eligible work now: the step is not needed (no task is started), with the reason
        v_state := 'not_needed'; v_note := left('Not needed: ' || coalesce(v_work->>'reason', 'no eligible work'), 300);
      elsif r.mode = 'auto' and s->>'group' not in ('none')$n$],
 [$o$                       || case when v_state in ('person', 'skipped', 'failed') then jsonb_build_object('finished_at', now()) else '{}'::jsonb end)$o$,
  $n$                       || case when v_state in ('person', 'skipped', 'failed', 'not_needed') then jsonb_build_object('finished_at', now()) else '{}'::jsonb end
                       || case when v_state = 'not_needed' then jsonb_build_object('not_needed', v_work) else '{}'::jsonb end)$n$],
 [$o$when j.state in ('done') then 'done' when j.state in ('failed', 'cancelled') then j.state end$o$,
  $n$when j.state in ('done') then 'done'
                                                    when j.state = 'cancelled' and j.result->>'end_state' = 'not_needed' then 'not_needed'  -- CF-247 IQ-00066
                                                    when j.state in ('failed', 'cancelled') then j.state end$n$],
 [$o$                                              when 'timed_out' then 'still running after '$o$,
  $n$                                              -- CF-247 IQ-00066: a task ended not needed gives the step its reason
                                              when 'not_needed' then (select left(coalesce(j.result->>'note', 'Not needed'), 300) from pipeline.admin_jobs j where j.id = (s->'ref'->>'id')::uuid)
                                              when 'timed_out' then 'still running after '$n$]
]::text[][], array[1, 1, 1, 1, 1, 1, 1]);

-- 5. the task watcher: a scholarship scan with no eligible work is not needed; an eligible mapping or screening is held, not done ------------
select pg_temp.edit_once('security.admin_job_watch_v1(uuid)', '34a1cfd57b367d0e60ccb4a85f56e228', '995f26c437f0abfb3c666271cd622fec', array[
 [$o$v_hold_h int; v_why text; v_unit text;$o$,
  $n$v_hold_h int; v_why text; v_unit text; v_work jsonb; v_left int;$n$],
 [$o$    v_phase := case when v_n_map > 0 then 'mapping the site' when v_n_cand > 0 then 'screening candidate pages' when v_done < v_total then 'reading scholarship pages' else 'finishing' end;
$o$,
  $n$    v_phase := case when v_n_map > 0 then 'mapping the site' when v_n_cand > 0 then 'screening candidate pages' when v_done < v_total then 'reading scholarship pages' else 'finishing' end;
    -- CF-247 IQ-00066 (plans.step_needs_work_on): only eligible work counts as mapping or screening: a site mapping that is due and not held
    -- by the scholarship reader's gates, candidate pages of a provider that is not held. With no scholarship page in scope, no eligible work
    -- and no site mapped or tried while it ran (prepare set the tries to 0), the scan is not needed (ended below).
    if v_j.kind = 'scholarship_provider_scan' and security.pipeline_num_v1('plans.step_needs_work_on', 0) >= 1 then
      v_work := security.scholarship_scan_work_v1(v_ids);
      v_n_map := least(v_n_map, coalesce((v_work->>'map_due')::int, v_n_map));
      v_n_cand := least(v_n_cand, coalesce((v_work->>'candidates')::int, v_n_cand));
      v_phase := case when v_total = 0 and not coalesce((v_work->>'work')::boolean, true)
                       and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = any (v_ids) and (d.attempts > 0 or d.discovered_at >= v_since))
                      then 'not needed'
                      when v_n_map > 0 then 'mapping the site' when v_n_cand > 0 then 'screening candidate pages' when v_done < v_total then 'reading scholarship pages' else 'finishing' end;
    end if;
$n$],
 [$o$|| (v_extra->>'too_thin') || ' too thin, ' || (v_extra->>'skipped') || ' skipped); ', 'no new pages found; ') || v_note;
    end if;$o$,
  $n$|| (v_extra->>'too_thin') || ' too thin, ' || (v_extra->>'skipped') || ' skipped); ', 'no new pages found; ') || v_note;
    end if;
    -- CF-247 IQ-00066: ended with nothing in scope and no eligible work: not needed (closed as such by security.admin_jobs_tick_v1), never done
    if v_fin and v_phase = 'not needed' and v_total = 0 then
      v_note := left('Not needed: ' || coalesce(v_work->>'reason', 'no eligible work') || '. No scholarship page, site mapping or candidate page was due for this task', 500);
      v_extra := v_extra || jsonb_build_object('end_state', 'not_needed', 'not_needed', v_work);
    end if;$n$],
 [$o$  if not v_fin and v_done < v_total and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1$o$,
  $n$  -- CF-247 IQ-00066: a scholarship scan whose eligible site mapping or candidate screening waits is unfinished work too (held, not done)
  if not v_fin and (v_done < v_total or (v_j.kind = 'scholarship_provider_scan' and v_n_map + v_n_cand > 0 and security.pipeline_num_v1('plans.step_needs_work_on', 0) >= 1))
     and security.pipeline_num_v1('tasks.lane_hold_on', 0) >= 1$n$],
 [$o$    v_stall := null;
$o$,
  $n$    v_stall := null;
    v_left := greatest(v_total - v_done, v_n_map + v_n_cand);  -- CF-247 IQ-00066: the items left, or the mappings and screenings waiting
$n$],
 [$o$(v_total - v_done)$o$, $n$v_left$n$],
 [$o$'unprocessed', v_total - v_done$o$, $n$'unprocessed', v_left$n$],
 [$o$' of ' || v_total || ' ' || v_unit$o$, $n$' of ' || greatest(v_total, v_left) || ' ' || v_unit$n$]
]::text[][], array[1, 1, 1, 1, 1, 4, 2, 2]);

-- 6. the task runner closes a task the watcher ended not needed as cancelled with the reason (admin_jobs.state has no not_needed) ------------
select pg_temp.edit_once('security.admin_jobs_tick_v1(integer)', 'fc698f9912cffd90a7b8ae32e33dd09e', 'e5f4881ca7423c8aa0df0923a5057806', array[
 [$o$      update pipeline.admin_jobs set state = case when result->>'end_state' = 'failed' then 'failed' else 'done' end,
             error = case when result->>'end_state' = 'failed' then left(result->>'note', 500) else error end,$o$,
  $n$      -- CF-247 IQ-00066: a task the watcher ended not needed (no eligible work) is never done: it is closed cancelled, its error the reason
      update pipeline.admin_jobs set state = case when result->>'end_state' = 'failed' then 'failed' when result->>'end_state' = 'not_needed' then 'cancelled' else 'done' end,
             error = case when result->>'end_state' in ('failed', 'not_needed') then left(result->>'note', 500) else error end,$n$]
]::text[][], array[1]);

-- 7. Pipeline yield shows the plan outcomes ------------------------------------------------------------------------------------------------
select pg_temp.edit_once('public.admin_pipeline_yield(jsonb)', '34617ad96ea43189509c3f4dd536d50e', 'a8af701f17f105b5af4db210896241eb', array[
 [$o$security.field_backlog_v1(nullif(p_args->>'country', '')));$o$,
  $n$security.field_backlog_v1(nullif(p_args->>'country', '')))
         -- CF-247 IQ-00066: plans finished by outcome (a done plan with no step done moved no data), steps and tasks not needed
         || jsonb_build_object('plan_outcomes', security.plan_outcomes_v1());$n$]
]::text[][], array[1]);

-- 8. the course description duplicate check splits the new text once (IQ-00053 residual) ---------------------------------------------------
select pg_temp.edit_once('security.course_description_check_v1(uuid,jsonb)', '4822f66ee262cdfa1c4cd798cfc3dd26', 'ff3d6dd7b0f88c85b1fdff6c8a8cd86b', array[
 [$o$        v_checks jsonb;
begin$o$,
  $n$        v_checks jsonb; v_words text[];
begin$n$],
 [$o$  -- boilerplate: the same words as another course of the provider (held, or waiting in Layer 4)
  select z.course_id, z.sim into v_other from (
    select x.course_id, security.pdesc_similarity_v1(v_text, x.d) sim from ($o$,
  $n$  -- boilerplate: the same words as another course of the provider (held, or waiting in Layer 4)
  -- CF-247 IQ-00053 residual: the new text is split into words once, and each other text inline, by the rule of security.pdesc_words_v1 and
  -- security.pdesc_similarity_v1 (distinct lower-case words of 3 or more letters or digits; shared words over all words of both)
  v_words := security.pdesc_words_v1(v_text);
  select z.course_id, z.sim into v_other from (
    select x.course_id, case when cardinality(v_words) = 0 or cardinality(x.wb) = 0 then 0
                             else round(k.n::numeric / (cardinality(v_words) + cardinality(x.wb) - k.n), 4) end sim
      from (select x0.course_id, array(select distinct w from regexp_split_to_table(lower(coalesce(x0.d, '')), '[^a-z0-9]+') w where length(w) >= 3) wb from ($n$],
 [$o$500)::int) x) z$o$,
  $n$500)::int) x0) x
      cross join lateral (select count(*) n from unnest(v_words) w where w = any (x.wb)) k) z$n$]
]::text[][], array[1, 1, 1]);

-- 9. onboarding refuses a website that is not a site address (IQ-00063) ------------------------------------------------------------------
select pg_temp.edit_once('security.provider_onboarding_tick_v1()', '01c5659bb4c364e80b0544fa60bca0ee', '181fc3dd2d78930c32e70cc24fb0adbd', array[
 [$o$  -- a missing website was entered: carry on
  update pipeline.provider_onboarding ob set status = 'website', stop_reason = null, step_started_at = now(), job_id = null, note = 'Website entered; carrying on.', updated_at = now()
    from catalogue.providers pv where pv.id = ob.provider_id and ob.status = 'stopped' and ob.stop_reason = 'no_website' and nullif(pv.website, '') is not null;$o$,
  $n$  -- CF-247 IQ-00063 (onboarding.website_check_on): a recorded website that is not a site address (a user part as in an email address, no
  -- domain name, not http or https) is refused: onboarding stops with needs_source_discovery and the reason, instead of going round between
  -- the website and course-page stages, and is not stepped until the website is corrected
  if security.pipeline_num_v1('onboarding.website_check_on', 0) >= 1 then
    update pipeline.provider_onboarding ob set status = 'stopped', stop_reason = 'needs_source_discovery', job_id = null, updated_at = now(),
           note = left('The recorded website (' || pv.website || ') cannot be used: ' || security.website_refusal_v1(pv.website)
                       || '. Its website has to be found again: correct it in Layer 4 › Websites to find or the Adapter builder (1.1), and onboarding carries on by itself.', 500)
      from catalogue.providers pv
     where pv.id = ob.provider_id and security.website_refusal_v1(pv.website) is not null
       and (ob.status in ('queued', 'website', 'course_pages', 'waiting_courses') or (ob.status = 'stopped' and ob.stop_reason = 'no_website'));
  end if;
  -- a missing website was entered: carry on (CF-247 IQ-00063: also a refused one corrected; never a refused one)
  update pipeline.provider_onboarding ob set status = 'website', stop_reason = null, step_started_at = now(), job_id = null, note = 'Website entered; carrying on.', updated_at = now()
    from catalogue.providers pv where pv.id = ob.provider_id and ob.status = 'stopped' and ob.stop_reason in ('no_website', 'needs_source_discovery') and nullif(pv.website, '') is not null
     and (security.pipeline_num_v1('onboarding.website_check_on', 0) < 1 or security.website_refusal_v1(pv.website) is null);$n$]
]::text[][], array[1]);

-- 10. catalogue and component register --------------------------------------------------------------------------------------------------------
update pipeline.automation_catalogue set description = description || ' With plans.step_needs_work_on, a scholarships step is proposed only when the scan has eligible work now (security.plan_step_work_v1).'
 where jobname = 'enrich-plan-auto' and description not like '%plans.step_needs_work_on%';
update pipeline.automation_catalogue set description = description || ' With plans.step_needs_work_on, a step with no eligible work when it would start ends not needed with the reason; a finished plan records its outcome (moved, not_needed, no_movement).'
 where jobname = 'enrich-plan-run' and description not like '%plans.step_needs_work_on%';
update pipeline.automation_catalogue set description = description || ' With plans.step_needs_work_on, a scholarship scan with no eligible work ends not needed (closed cancelled with the reason), never done, and an eligible site mapping or screening is held.'
 where jobname = 'admin-jobs' and description not like '%plans.step_needs_work_on%';
update pipeline.automation_catalogue set description = description || ' With onboarding.website_check_on, a website that is not a site address stops onboarding with needs_source_discovery until it is corrected.'
 where jobname = 'provider-onboarding' and description not like '%onboarding.website_check_on%';
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.scholarship_scan_work_v1', 'Platform', 'Platform upkeep', 'Whether a scholarship scan has eligible work now, with the reason', 'active', '{}', '20261103230000'),
 ('function', 'security.plan_step_work_v1', 'Platform', 'Platform upkeep', 'Whether an enrichment plan step has eligible work now', 'active', '{}', '20261103230000'),
 ('function', 'security.plan_run_outcome_v1', 'Platform', 'Platform upkeep', 'A finished enrichment plan''s outcome (moved, not_needed, no_movement)', 'active', '{}', '20261103230000'),
 ('function', 'security.plan_outcomes_v1', 'Platform', 'Platform upkeep', 'Plans by outcome, steps and tasks not needed (Pipeline yield)', 'active', '{}', '20261103230000'),
 ('function', 'security.website_refusal_v1', 'Platform', 'Platform upkeep', 'Why a recorded website cannot be used as a site address', 'active', '{}', '20261103230000')
on conflict do nothing;

-- 11. post-check ------------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline'
        and key in ('plans.step_needs_work_on', 'plans.outcome_window_hours', 'onboarding.website_check_on')) <> 3 then
    raise exception 'orchestration follow-ups post-check: a setting is missing'; end if;
  if security.website_refusal_v1('https://info@newgen.edu.au') is null or security.website_refusal_v1('https://www.example.edu.au/courses') is not null then
    raise exception 'orchestration follow-ups post-check: the website check does not refuse a user part or refuses a site address'; end if;
  if security.plan_run_outcome_v1('[{"status": "not_needed"}]'::jsonb) <> 'not_needed' or security.plan_run_outcome_v1('[{"status": "done"}, {"status": "not_needed"}]'::jsonb) <> 'moved' then
    raise exception 'orchestration follow-ups post-check: plan outcome'; end if;
end $$;
