-- CF-247 G2 promotion wave B (Phase 2 of the UI/UX and settings simplification; Platform Admin 16 Nov 2026 05:23; audit
-- claude/ui-ux-settings-audit-2026-11-15.md §2.4 and §8). The eleven stage timers written into security.provider_onboarding_step_v1 (job
-- provider-onboarding) become nine settings with today's values (section Onboarding), so nothing behaves differently until a person changes one
-- with a reason. The one technical value left (a one-minute clock tolerance) is marked "-- fixed: <why>".
--   applying the adapter:      90 minutes at most -> onboarding.apply_max_minutes; may end after 10 minutes -> onboarding.apply_quiet_minutes
--                              when no result within 5 minutes -> onboarding.apply_activity_minutes
--   a step whose task ended:   90 minutes -> onboarding.job_done_wait_minutes
--   course page search:        pages read within 60 minutes -> onboarding.read_quiet_minutes
--   adapter proposal or apply: 30 minutes (x3) -> onboarding.proposal_wait_minutes
--   writing admitted values:   20 minutes -> onboarding.enrich_wait_minutes; written within 10 minutes -> onboarding.enrich_quiet_minutes
--   scholarships settle:       15 minutes -> onboarding.scholarship_settle_minutes
-- How: the live definition is md5-guarded, every edit must match exactly the expected number of times (all 12 intervals of the function are
--   accounted for), and the edited definition is executed in place (same name, signature, owner and grants). Applying it twice changes nothing.
-- G1: no job. G2: 9 settings with label, range, unit, section and used_by. G3: no consumer API object; security.consumer_api_check_v1() before and after.
-- Replaces: security.provider_onboarding_step_v1(uuid) (same name and signature; md5-guarded edit in place).
-- Retires: nothing. Nothing is dropped or deleted.

set local lock_timeout = '5s';

-- 1. Settings (G2): today's values ---------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by, control_class) values
 ('pipeline', 'onboarding.job_done_wait_minutes', 'Onboarding: a step whose task has ended moves on after',
  'A step waiting on a task that is done, failed or cancelled moves on once the step is this many minutes old.',
  'number', to_jsonb(90), 10, 1440, 'minutes', 1911, 'G2 promotion wave B (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Onboarding', 'security.provider_onboarding_step_v1 (job provider-onboarding)', 'automatic'),
 ('pipeline', 'onboarding.read_quiet_minutes', 'Onboarding: course page search waits while pages were read within',
  'The course page search step keeps waiting only while some page of the provider was read within this many minutes.',
  'number', to_jsonb(60), 10, 1440, 'minutes', 1912, 'G2 promotion wave B (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Onboarding', 'security.provider_onboarding_step_v1 (job provider-onboarding)', 'automatic'),
 ('pipeline', 'onboarding.proposal_wait_minutes', 'Onboarding: an adapter proposal not finished is retried after',
  'An adapter proposal or apply step that has not finished in this many minutes is treated as failed and retried (up to the attempts setting).',
  'number', to_jsonb(30), 5, 1440, 'minutes', 1913, 'G2 promotion wave B (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Onboarding', 'security.provider_onboarding_step_v1 (job provider-onboarding)', 'automatic'),
 ('pipeline', 'onboarding.apply_max_minutes', 'Onboarding: applying the adapter moves on after at most',
  'Applying the adapter to the stored pages moves on after this many minutes, finished or not.',
  'number', to_jsonb(90), 10, 1440, 'minutes', 1914, 'G2 promotion wave B (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Onboarding', 'security.provider_onboarding_step_v1 (job provider-onboarding)', 'automatic'),
 ('pipeline', 'onboarding.apply_quiet_minutes', 'Onboarding: applying may end early after',
  'After this many minutes, applying ends early when no adapter result arrived in the last minutes of Onboarding: applying counts as active while results arrived within.',
  'number', to_jsonb(10), 2, 240, 'minutes', 1915, 'G2 promotion wave B (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Onboarding', 'security.provider_onboarding_step_v1 (job provider-onboarding)', 'automatic'),
 ('pipeline', 'onboarding.apply_activity_minutes', 'Onboarding: applying counts as active while results arrived within',
  'Applying the adapter counts as still active while an adapter result arrived within this many minutes.',
  'number', to_jsonb(5), 1, 60, 'minutes', 1916, 'G2 promotion wave B (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Onboarding', 'security.provider_onboarding_step_v1 (job provider-onboarding)', 'automatic'),
 ('pipeline', 'onboarding.enrich_wait_minutes', 'Onboarding: writing admitted values may end after',
  'After this many minutes, writing the admitted values ends when nothing was written in the last minutes of Onboarding: writing counts as active while values were written within.',
  'number', to_jsonb(20), 5, 240, 'minutes', 1917, 'G2 promotion wave B (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Onboarding', 'security.provider_onboarding_step_v1 (job provider-onboarding)', 'automatic'),
 ('pipeline', 'onboarding.enrich_quiet_minutes', 'Onboarding: writing counts as active while values were written within',
  'Writing the admitted values counts as still active while a value was written within this many minutes.',
  'number', to_jsonb(10), 1, 120, 'minutes', 1918, 'G2 promotion wave B (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Onboarding', 'security.provider_onboarding_step_v1 (job provider-onboarding)', 'automatic'),
 ('pipeline', 'onboarding.scholarship_settle_minutes', 'Onboarding: scholarships settle after',
  'The scholarship step ends after this many minutes once nothing waits for AI reading or review.',
  'number', to_jsonb(15), 5, 1440, 'minutes', 1919, 'G2 promotion wave B (Platform Admin 16 Nov 2026 05:23): was written into the function', 'Onboarding', 'security.provider_onboarding_step_v1 (job provider-onboarding)', 'automatic')
on conflict (toolset_key, key) do nothing;

-- 2. The edit helper (this transaction only) ------------------------------------------------------------------------------------------------
-- p_edits: one row per edit {kind, old, new, n}: kind 'swap' replaces old with new; kind 'mark' appends " -- fixed: <new>" to each line that
-- contains old. Each edit must match exactly n times, or nothing is changed.
create or replace function pg_temp.cf_g2_edit(p_fn text, p_md5 text, p_done text, p_edits jsonb) returns text language plpgsql as $edit$
declare v_def text := pg_get_functiondef(p_fn::regprocedure); v_new text; e jsonb; v_n int; v_pat text;
begin
  if position(p_done in v_def) > 0 then return 'already'; end if;
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_fn, md5(v_def); end if;
  v_new := v_def;
  for e in select * from jsonb_array_elements(p_edits) loop
    v_n := (length(v_new) - length(replace(v_new, e->>'old', ''))) / length(e->>'old');
    if v_n <> (e->>'n')::int then raise exception '%: "%" found % time(s), expected %', p_fn, e->>'old', v_n, e->>'n'; end if;
    if e->>'kind' = 'swap' then
      v_new := replace(v_new, e->>'old', e->>'new');
    else
      v_pat := regexp_replace(e->>'old', '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '[^\n]*';
      v_new := regexp_replace(v_new, v_pat, '\& -- fixed: ' || (e->>'new'), 'g');
    end if;
  end loop;
  if position(p_done in v_new) = 0 then raise exception '%: the edited definition does not carry %', p_fn, p_done; end if;
  execute v_new;
  return md5(pg_get_functiondef(p_fn::regprocedure));
end $edit$;

-- 3. The edit -------------------------------------------------------------------------------------------------------------------------------
do $$
declare v_out text;
begin
  v_out := pg_temp.cf_g2_edit('security.provider_onboarding_step_v1(uuid)', '8597740642ce2470f793be575793e680', 'onboarding.apply_max_minutes', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'if v_age > interval ''90 minutes'' or (v_age > interval ''10 minutes''', 'new', 'if v_age > make_interval(mins => security.pipeline_num_v1(''onboarding.apply_max_minutes'', 90)::int) or (v_age > make_interval(mins => security.pipeline_num_v1(''onboarding.apply_quiet_minutes'', 10)::int)', 'n', 1),
       jsonb_build_object('kind', 'swap', 'old', 'r.at > now() - interval ''5 minutes''', 'new', 'r.at > now() - make_interval(mins => security.pipeline_num_v1(''onboarding.apply_activity_minutes'', 5)::int)', 'n', 1),
       jsonb_build_object('kind', 'swap', 'old', 'and v_age > interval ''90 minutes''', 'new', 'and v_age > make_interval(mins => security.pipeline_num_v1(''onboarding.job_done_wait_minutes'', 90)::int)', 'n', 1),
       jsonb_build_object('kind', 'swap', 'old', 'pg.read_at > now() - interval ''60 minutes''', 'new', 'pg.read_at > now() - make_interval(mins => security.pipeline_num_v1(''onboarding.read_quiet_minutes'', 60)::int)', 'n', 1),
       jsonb_build_object('kind', 'swap', 'old', 'v_age > interval ''30 minutes''', 'new', 'v_age > make_interval(mins => security.pipeline_num_v1(''onboarding.proposal_wait_minutes'', 30)::int)', 'n', 3),
       jsonb_build_object('kind', 'swap', 'old', 'v_age > interval ''20 minutes''', 'new', 'v_age > make_interval(mins => security.pipeline_num_v1(''onboarding.enrich_wait_minutes'', 20)::int)', 'n', 1),
       jsonb_build_object('kind', 'swap', 'old', 'c.at > now() - interval ''10 minutes''', 'new', 'c.at > now() - make_interval(mins => security.pipeline_num_v1(''onboarding.enrich_quiet_minutes'', 10)::int)', 'n', 1),
       jsonb_build_object('kind', 'swap', 'old', 'v_age > interval ''15 minutes''', 'new', 'v_age > make_interval(mins => security.pipeline_num_v1(''onboarding.scholarship_settle_minutes'', 15)::int)', 'n', 1),
       jsonb_build_object('kind', 'mark', 'old', '- interval ''1 minute''', 'new', 'clock tolerance: scholarships created just before the step started', 'n', 1)));
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('settings', 'migration', 'G2 promotion wave B', jsonb_build_object('migration', '20261116030000', 'functions', jsonb_build_object('security.provider_onboarding_step_v1(uuid)', v_out)), null);
end $$;

-- 4. Post-checks ----------------------------------------------------------------------------------------------------------------------------
do $$
declare v_def text := pg_get_functiondef('security.provider_onboarding_step_v1(uuid)'::regprocedure);
begin
  if (length(v_def) - length(replace(v_def, 'interval ''', ''))) / length('interval ''') <> 1 then
    raise exception 'post-check: an interval other than the marked clock tolerance is still written into security.provider_onboarding_step_v1';
  end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('onboarding.job_done_wait_minutes', 'onboarding.read_quiet_minutes', 'onboarding.proposal_wait_minutes', 'onboarding.apply_max_minutes', 'onboarding.apply_quiet_minutes', 'onboarding.apply_activity_minutes', 'onboarding.enrich_wait_minutes', 'onboarding.enrich_quiet_minutes', 'onboarding.scholarship_settle_minutes')) <> 9 then
    raise exception 'post-check: the 9 settings are not all present';
  end if;
end $$;
