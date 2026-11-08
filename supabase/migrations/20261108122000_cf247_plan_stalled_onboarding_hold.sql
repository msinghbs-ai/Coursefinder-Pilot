-- CF-247 ENG / IQ-00072 (8 Nov 2026): the automatic enrichment planner does not pay again for a university whose adapter cannot be built and nothing has changed.
-- Why (live, read-only, 8 Nov 2026 03:40-04:50 UTC, project fxcwkweaxjtknorudmwp):
--   * Plans that finished in the last 7 days: 167. By data: 85 of them (1,295 of 5,147 credits, 25%) were plans for a university whose latest onboarding had already stopped for a
--     cause that time does not clear (609 universities are stopped 'too_few_pages', 330 'nothing_ready', 105 'no_website'; plans.retry_waits_for_change names these causes)
--     and where no course was added and no course page read since: they gained 10 field values in all (3 plans), against 505 for the other 55 plans on 3,408 credits.
--     The plan is "Find course pages" (6 credits, a search per course) and "Build the adapter" (est. 43 credits, stopped again at once: 3 to 9 courses cannot give the pages
--     an adapter needs). The plan's outcome counts the page search as movement, so it reads "succeeded with result" while no catalogue field changes: 71 of the 102
--     "succeeded_with_result" plans of the week moved 0 field values (1,659 credits). The four zero-yield plans in the mandate (52 credits) are this family.
--   * The existing guard (plans.empty_cycles_max 3) needs three empty plans in a row, 14 days apart: a university is paid for three times before it is held, and a university
--     whose onboarding cannot progress is "empty" only when its outcome says so, which the page search prevents.
-- What:
--   1 Settings (G2): plans.stalled_onboarding_hold (1 = on; this only stops repeated spend) and plans.stalled_onboarding_quiet_days (30).
--   2 security.plan_stalled_onboarding_v1(uuid): null unless the university's latest onboarding stopped for a cause named in plans.retry_waits_for_change, within the quiet
--     days, and since that stop no active course was added, no course page was read and stored, and no central search finished. Otherwise a reason.
--   3 security.enrich_plan_v1 (md5-guarded, two edits): the automatic planner (no person behind the call) is not offered the steps "Find course pages" and "Build the adapter"
--     of such a university; they are listed under not_proposed with code onboarding_stalled and the reason. The other steps (website and central pages, fill missing fields,
--     scholarships) are unchanged. A person's Run now still sees every step. It is proposed again by itself when a course is added, a page is read, a central search finishes,
--     or the quiet days pass.
-- Not done: the plan outcome still counts a page search as movement (workstream D's definition; a gain-based outcome would change every report), and the plans already run are
--   left as they are. The measure for this change is credits per plan with zero field gain, from pipeline.enrich_plan_runs.
-- Consumer API: unchanged (G3). Nothing is read from the web, nothing written but the function and the settings.
-- md5 (before = live 8 Nov 2026; after = local replay on PostgreSQL 16, tests/fixtures/eng-gap-recovery/run.sh):
--   security.enrich_plan_v1(uuid)   774c061974916b878f7762e55de07bb6 -> 15d174d703e29cb1b37d449847827cfa
-- Replaces: security.enrich_plan_v1(uuid) (md5-guarded edit of the live definition)
-- Retires: nothing.
-- Nothing is dropped or deleted by this migration.

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

-- 1 settings (G2) ---------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
('pipeline', 'plans.stalled_onboarding_hold', 'Plans: no repeated page search and adapter for a university whose onboarding is stuck',
 '1: the automatic planner does not propose "Find course pages" and "Build the adapter" for a university whose latest onboarding stopped for a cause that time does not clear (plans.retry_waits_for_change: too few pages, nothing ready, no website) while no course has been added, no course page read and no central search finished since; it is listed as not proposed with the reason, and proposed again when one of those happens or after plans.stalled_onboarding_quiet_days. A person''s Run now is not held. 0: as before.',
 'number', '1'::jsonb, 0, 1, 'on (1) or off (0)', 824, 'Platform upkeep',
 'security.plan_stalled_onboarding_v1 (security.enrich_plan_v1, job enrich-plan-auto)',
 'CF-247 ENG IQ-00072, 8 Nov 2026: on (stops repeated spend: 85 of 167 plans in 7 days, 1,295 credits, 10 field values)'),
('pipeline', 'plans.stalled_onboarding_quiet_days', 'Plans: a stuck onboarding is held for',
 'A university held for a stuck onboarding is proposed for "Find course pages" and "Build the adapter" again after this many days even if nothing has changed.',
 'number', '30'::jsonb, 1, 365, 'days', 825, 'Platform upkeep',
 'security.plan_stalled_onboarding_v1', 'CF-247 ENG IQ-00072, 8 Nov 2026: 30 days, the central-page refresh period')
on conflict (toolset_key, key) do nothing;

-- 2 the test ----------------------------------------------------------------------------------------------------------------------------------
create or replace function security.plan_stalled_onboarding_v1(p_provider uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 ENG IQ-00072 (8 Nov 2026): null when "Find course pages" and "Build the adapter" may be proposed for this university. Otherwise the reason they are not: its latest
-- onboarding stopped for a cause named in plans.retry_waits_for_change (time does not clear it), within plans.stalled_onboarding_quiet_days, and since that stop no active course
-- was added, no course page was read and stored, and no central search finished.
declare o record; v_quiet int := security.pipeline_num_v1('plans.stalled_onboarding_quiet_days', 30)::int;
begin
  if security.pipeline_num_v1('plans.stalled_onboarding_hold', 1) < 1 then return null; end if;
  select s.status, s.stop_reason, coalesce(s.finished_at, s.updated_at) at into o
    from pipeline.provider_onboarding s where s.provider_id = p_provider order by s.created_at desc limit 1;
  if o.status is distinct from 'stopped' or o.at is null or coalesce(o.stop_reason, '') = '' then return null; end if;
  if o.at < now() - make_interval(days => v_quiet) then return null; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings w cross join lateral jsonb_array_elements_text(case when jsonb_typeof(w.value) = 'array' then w.value else '[]'::jsonb end) k(t)
                  where w.toolset_key = 'pipeline' and w.key = 'plans.retry_waits_for_change' and position(lower(k.t) in lower(o.stop_reason)) > 0) then return null; end if;
  if exists (select 1 from catalogue.courses c where c.provider_id = p_provider and c.lifecycle_status = 'active' and c.created_at > o.at) then return null; end if;
  if exists (select 1 from pipeline.coverage_course_pages g where g.provider_id = p_provider and g.evidence_id is not null and g.read_status = 'read' and g.read_at > o.at) then return null; end if;
  if exists (select 1 from pipeline.provider_central_search s where s.provider_id = p_provider and s.state = 'done' and s.searched_at > o.at) then return null; end if;
  return jsonb_build_object('stop_reason', o.stop_reason, 'stopped_at', o.at,
    'reason', 'onboarding stopped (' || replace(o.stop_reason, '_', ' ') || ') on ' || to_char(o.at at time zone 'Australia/Melbourne', 'DD Mon HH24:MI')
              || ' and no course, course page or central search has changed since; proposed again when one does, or after ' || v_quiet || ' days');
end $function$;
revoke all on function security.plan_stalled_onboarding_v1(uuid) from public, anon, authenticated;
comment on function security.plan_stalled_onboarding_v1(uuid) is 'CF-247 ENG IQ-00072: reason the automatic planner does not offer Find course pages and Build the adapter (stuck onboarding, nothing changed), or null.';

-- 3 the plan -----------------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.enrich_plan_v1(uuid)', '774c061974916b878f7762e55de07bb6', '15d174d703e29cb1b37d449847827cfa',
  array[
   array[$o$v_held jsonb := '[]'::jsonb; v_empty jsonb;$o$,
         $n$v_held jsonb := '[]'::jsonb; v_empty jsonb; v_stalled jsonb;$n$],
   array[$o$  v_empty := security.plan_empty_cycles_v1(p_provider,$o$,
         $n$  -- CF-247 ENG IQ-00072 (8 Nov 2026): the automatic planner is not offered "Find course pages" and "Build the adapter" of a university whose onboarding is stuck and unchanged
  -- (security.plan_stalled_onboarding_v1); they are listed under not_proposed with the reason. The other steps and a person's Run now are unchanged.
  v_stalled := security.plan_stalled_onboarding_v1(p_provider);
  if v_stalled is not null and auth.uid() is null and exists (select 1 from jsonb_array_elements(v_steps) x where x->>'step' in ('pages', 'adapter')) then
    v_held := v_held || (select jsonb_agg(jsonb_build_object('step', x->>'step', 'label', x->>'label', 'code', 'onboarding_stalled', 'reason', v_stalled->>'reason')) from jsonb_array_elements(v_steps) x where x->>'step' in ('pages', 'adapter'));
    v_steps := coalesce((select jsonb_agg(x) from jsonb_array_elements(v_steps) x where x->>'step' not in ('pages', 'adapter')), '[]'::jsonb);
  end if;
  v_empty := security.plan_empty_cycles_v1(p_provider,$n$]
  ], array[1, 1]);
