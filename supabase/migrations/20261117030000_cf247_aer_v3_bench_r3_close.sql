-- CF-247 AER v3 benchmark, round 3 closed: the run switches back to 0 and the on-demand window closed (follows migration 20261117020000).
-- Replaces: nothing
-- Retires: nothing
--
-- Round 3 (ai_eval_runs 24 Gemini 2.5 Flash, 25 MiMo v2.6 Flash, 26 Mistral Small 3.2) has answered. This change restores reading.aer_v2_long_page_sections_on,
-- ai_eval.offline_runs_on and ai_eval.aer_v3_runs_on to 0, each with its reason and a control event, and closes on-demand window 349feb5b (its actual use
-- and the credit left are recorded by security.on_demand_close_v1). It refuses, changing nothing, while any round-3 run is still queued or answering.
-- Scoring and the qualification evidence (pending at most) are written by the ai-eval job; nothing is qualified or switched on here. Unchanged: every
-- route, cascade, qualification and production reader; aer.v2_shadow_on stays 0. G1: no job. G2: existing settings only. G3: untouched.

set local lock_timeout = '5s'; -- fixed: lock wait guard for the updates below

do $g$
begin
  if exists (select 1 from pipeline.ai_eval_runs x join pipeline.ai_improvement_proposals p on p.id = x.proposal_id
              where p.code like 'aer-v2-course-v3-%-r3' and x.state in ('queued', 'running', 'answering')) then
    raise exception 'refused: a round-3 run is still answering; nothing was changed';
  end if;
end $g$;

with u as (
  update pipeline.platform_toolset_settings
     set value = '0'::jsonb, updated_at = now(),
         reason = 'Migration 20261117030000: AER v3 benchmark round 3 recorded (runs 24 to 26); restored to 0 after the run (Platform Admin 16 Nov 2026 16:52 step 3)'
   where toolset_key = 'pipeline' and key in ('reading.aer_v2_long_page_sections_on', 'ai_eval.offline_runs_on', 'ai_eval.aer_v3_runs_on')
  returning key)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'settings', 'migration', u.key, jsonb_build_object('migration', '20261117030000', 'after', 0, 'why', 'AER v3 benchmark round 3 recorded'), null from u;

select security.on_demand_close_v1(id) from pipeline.on_demand_requests
 where id = '349feb5b-61ef-4e4d-82c2-77a08d11aafc' and closed_at is null;

do $k$
begin
  if security.pipeline_num_v1('reading.aer_v2_long_page_sections_on', 1) <> 0 or security.pipeline_num_v1('ai_eval.offline_runs_on', 1) <> 0
     or security.pipeline_num_v1('ai_eval.aer_v3_runs_on', 1) <> 0 then
    raise exception 'post-check: the three run switches are back to 0';
  end if;
  if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 then raise exception 'post-check: the AER v2 shadow reader stays off'; end if;
  if exists (select 1 from pipeline.ai_service_routes where service_code in ('entry_requirements_v2_shadow', 'course_entry_requirements', 'entry_matrices') and enabled) then
    raise exception 'post-check: the entry reading routes stay off';
  end if;
end $k$;
