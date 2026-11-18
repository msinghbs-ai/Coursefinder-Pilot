-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 14:29, items 1 and 2: promote Boost learnings into the worker and reader; settle the refused
-- study loads; wire the scholarship scope rule into the live pipeline).
-- What it does:
--   1. Worker coverage-sweep v1.0.17 reads study loads with prompt boost-study-load-v5 and selector study-load-windows-v4 (boost.ts FEE_NOTE):
--      a fee note (EFTSL, Commonwealth supported places, a fee "calculated based on a standard full-time study load") is never sent, never
--      counts as a sentence about international students and is refused as a quote. 27 of the 400 refused readings in Layer 4 quoted one.
--      The route qualification rows of boost_extract and its benchmark move to that prompt version, as for v2 to v4 (pipeline.ai_route_qualifications;
--      the admission qualification in pipeline.boost_model_qualifications is per model and lane and is unchanged).
--   2. The stored pages behind the 400 open Boost study load readings are released to be read again by v1.0.17 (state released; the claim
--      takes them in matrix order). A verified reading is admitted by the unchanged promotion; the feed then closes the open reading as
--      superseded. What is still open after the re-read is settled by the follow-up rule (next migration).
--   3. Job scholarship-scope-auto (every hour at minute 19, setting scholarship.scope_auto_on): every scholarship that newly waits for a
--      course scope gets the deterministic decision of security.scholarship_scope_auto_decide_v1 (migrations 20261118153000 and 163000),
--      applied with its reason and audit row, so Layer 4 › Scholarship course links stays at 0 for rule-decidable scholarships.
-- G1: the new job is catalogued. G2: batch and switch are settings. G3: no consumer API object is changed.
-- Replaces: prompt boost-study-load-v4 and selector study-load-windows-v3 (worker v1.0.16) with v5 and v4 (worker v1.0.17)
-- Retires: nothing

set local lock_timeout = '5s';

-- 1. Route qualification rows follow the prompt version (as for v2, v3 and v4)
update pipeline.ai_route_qualifications
   set prompt_version = 'boost-study-load-v5',
       note = coalesce(note, '') || ' | 18 Nov 2026: prompt boost-study-load-v5 (worker v1.0.17, Platform Admin 14:29: a fee note, EFTSL or CSP is never the study load)',
       changed_at = now()
 where service_code in ('boost_extract', 'boost_extract_benchmark') and prompt_version = 'boost-study-load-v4';

-- 2. Read the pages behind the open readings again with v5
create temp table cf_requeue on commit drop as
  select x.item_key from pipeline.boost_extract_items x
   join pipeline.boost_study_load_reviews r on r.course_id = x.entity_id and r.evidence_id = x.evidence_id
  where r.status = 'open' and x.lane = 'study_load' and x.state = 'rejected';
update pipeline.boost_extract_items x
   set state = 'released', note = 'read again by worker v1.0.17 (prompt boost-study-load-v5: fee notes never the study load; Platform Admin 18 Nov 2026 14:29)'
 where x.item_key in (select item_key from cf_requeue);

-- 3. Settings and the scholarship scope job
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'scholarship.scope_auto_on', 'Scholarship course links: decide by rule every hour',
  '1: every hour, each scholarship that newly waits for a course scope gets the deterministic decision (its own name and description; All courses only for explicit university-wide wording; No courses when not course-specific), applied with its reason and an audit row. 0: they wait in Layer 4 › Inbox for a person.',
  'number', '1'::jsonb, 0, 1, 'switch', 344, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 14:29 item 1 (scholarship scope rules wired into the live pipeline)', 'Scholarships', 'security.scholarship_scope_auto_tick_v1, job scholarship-scope-auto'),
 ('pipeline', 'batch.scholarship_scope_auto', 'Scholarship course links: scholarships decided per run',
  'How many waiting scholarships one hourly run decides.',
  'number', '50'::jsonb, 1, 500, 'scholarships', 345, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 14:29 item 1', 'Scholarships', 'job scholarship-scope-auto')
on conflict (toolset_key, key) do nothing;

create or replace function security.scholarship_scope_auto_tick_v1(p_limit integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_n int := 0; v_by jsonb := '{}'::jsonb; r record; v_res jsonb; v_lim int := least(greatest(coalesce(p_limit, 0), 0), 500);  -- fixed: upper bound of the setting's range
begin
  if security.pipeline_num_v1('scholarship.scope_auto_on', 0) < 1 or v_lim = 0 then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:scholarship_scope_auto'));  -- fixed: one run at a time
  for r in select w.scholarship_id from security.scholarship_links_waiting_v1() w order by w.oldest limit v_lim loop
    v_res := security.scholarship_scope_auto_decide_v1(r.scholarship_id, true);
    v_n := v_n + 1;
    v_by := jsonb_set(v_by, array[v_res->>'decision'], to_jsonb(coalesce((v_by->>(v_res->>'decision'))::int, 0) + 1));
  end loop;
  if v_n > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'rule_execute', 'scholarship-scope-auto', jsonb_build_object('decided', v_n, 'by_decision', v_by), security.system_actor_id());
  end if;
  return jsonb_build_object('ok', true, 'decided', v_n, 'by_decision', v_by);
end $function$;
revoke all on function security.scholarship_scope_auto_tick_v1(integer) from public, anon, authenticated;
comment on function security.scholarship_scope_auto_tick_v1(integer) is 'CF-247 (Platform Admin 18 Nov 2026 14:29): decides by rule the scholarships that newly wait for a course scope (security.scholarship_scope_auto_decide_v1), when scholarship.scope_auto_on is 1.';

insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('scholarship-scope-auto', 'Scholarships', 46, 'Scholarship course links by rule',
  'Every hour at minute 19, when setting scholarship.scope_auto_on is 1 (Settings > Pipeline settings > Scholarships): each scholarship that newly waits for a course scope gets the deterministic decision from its own name and description (only matching courses; All courses only for explicit university-wide wording; No courses when not course-specific), applied as the Course links decision applies it, with its reason and a Layer 4 audit row. A person can change any decision on the Course links screen.',
  6, true)
on conflict (jobname) do nothing;

select cron.schedule('scholarship-scope-auto', '19 * * * *',
  'select security.scholarship_scope_auto_tick_v1(security.pipeline_num_v1(''batch.scholarship_scope_auto'', 50)::int)')
where not exists (select 1 from cron.job where jobname = 'scholarship-scope-auto');

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'scholarship-scope-auto', 'Layer 4', 'Scholarships', 'Scholarship course links decided by rule every hour', 'active', '{}', '20261118171000'),
  ('function', 'security.scholarship_scope_auto_tick_v1', 'Layer 4', 'Scholarships', 'One run of the scholarship scope rule over waiting scholarships', 'active', '{}', '20261118171000')
on conflict do nothing;

-- 4. Post-checks
do $c$
declare v_n int; v_q int;
begin
  select count(*) into v_n from pipeline.boost_extract_items x join pipeline.boost_study_load_reviews r on r.course_id = x.entity_id and r.evidence_id = x.evidence_id
   where r.status = 'open' and x.lane = 'study_load' and x.state = 'rejected';
  if v_n > 0 then raise exception 'post-check: % pages behind open readings were not released', v_n; end if;
  select count(*) into v_q from pipeline.ai_route_qualifications where service_code = 'boost_extract' and prompt_version = 'boost-study-load-v5' and status = 'qualified';
  if v_q <> 1 then raise exception 'post-check: the boost_extract route is not qualified on prompt v5 (% rows)', v_q; end if;
  if not exists (select 1 from cron.job where jobname = 'scholarship-scope-auto' and active) then raise exception 'post-check: job scholarship-scope-auto is not scheduled'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'scholarship-scope-auto') then raise exception 'post-check: the job is not catalogued'; end if;
  raise notice 'Released % pages for the v5 re-read', (select count(*) from cf_requeue);
end $c$;
