-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 14:29 item 2: settle the 400 refused Boost study load readings with full audit entries).
-- Rule l4-boost-sl-settle-v1. The pages behind the open readings were released for a re-read by worker v1.0.17 with prompt
-- boost-study-load-v5 (migration 20261118171000: fee notes are never the study load). For each open reading whose page has been read again
-- since it was released:
--   - a verified reading with a study load is admitted by the unchanged promotion; the review feed then closes the open reading as superseded
--     (nothing for this rule to do);
--   - a verified reading of "not stated" (the page states no study load under the v5 rules, or every study word was in a fee note) is
--     settled as Not stated;
--   - a reading refused again by the page check is settled as Not stated: twice the page did not support any study load the reader gave.
-- Each settlement goes through the Layer 4 Inbox decision of kind boost_study_load (security.layer4_boost_study_load_inbox_decide_v1, which
-- writes the review row and an admin_control_events audit row) under the system automation account, with the reason naming the rule, the
-- re-read and the page check's findings. A reading whose page has not been read again yet waits. Job layer4-boost-sl-settle runs the rule
-- every 30 minutes until none is left, then has nothing to do.
-- G1: the job is catalogued. G2: switch and batch are settings. G3: no consumer API object is changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'boost.sl_settle_on', 'Boost study load: settle refused readings after the re-read',
  '1: an open Boost study load reading in Layer 4 whose page was read again with the current prompt and still gives no admissible study load is settled as Not stated, with its reason and audit row. 0: such readings wait for a person.',
  'number', '1'::jsonb, 0, 1, 'switch', 248, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 14:29 item 2', 'Boost', 'security.boost_study_load_settle_rule_v1, job layer4-boost-sl-settle'),
 ('pipeline', 'batch.boost_sl_settle', 'Boost study load: readings settled per run',
  'How many open readings one run of the settlement rule examines.',
  'number', '400'::jsonb, 1, 1000, 'readings', 249, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 14:29 item 2', 'Boost', 'job layer4-boost-sl-settle')
on conflict (toolset_key, key) do nothing;

create or replace function security.boost_study_load_settle_rule_v1(p_limit integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare w record; v_prev text; v_res jsonb; v_reason text;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account that records rule decisions (Decision 263)
        v_lim int := least(greatest(coalesce(p_limit, 0), 0), 1000);  -- fixed: upper bound of the setting's range
        v_prompt text := (select q.prompt_version from pipeline.ai_route_qualifications q where q.service_code = 'boost_extract' and q.status = 'qualified' order by q.prompt_version desc limit 1);
        v_ok int := 0; v_fail int := 0; v_wait int := 0; v_by jsonb := '{}'::jsonb;
begin
  if security.pipeline_num_v1('boost.sl_settle_on', 0) < 1 or v_lim = 0 then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_sl_settle'));  -- fixed: one run at a time
  perform security.boost_study_load_review_feed_v1();  -- readings whose course gained a study load are closed as superseded first
  select count(*) into v_wait from pipeline.boost_study_load_reviews r
   where r.status = 'open' and not exists (select 1 from pipeline.boost_inbound_staging s where s.lane = 'study_load' and s.entity_id = r.course_id
     and s.evidence_id is not distinct from r.evidence_id and s.prompt_version = v_prompt and s.id > r.staging_id);
  for w in
    select r.id, r.course_id, n.worker_status, n.answer, n.verdict, n.id staging_id
      from pipeline.boost_study_load_reviews r
      join lateral (select s.* from pipeline.boost_inbound_staging s where s.lane = 'study_load' and s.entity_id = r.course_id
                     and s.evidence_id is not distinct from r.evidence_id and s.prompt_version = v_prompt and s.id > r.staging_id order by s.id desc limit 1) n on true
     where r.status = 'open'
       and (n.worker_status = 'rejected' or (n.worker_status = 'verified' and n.answer->>'study_load' is null))
     order by r.opened_at limit v_lim
  loop
    v_reason := left(format('[rule l4-boost-sl-settle-v1] Not stated: the page was read again with %s (fee notes, EFTSL and CSP never count) and %s. Approved by Platform Admin 18 Nov 2026 14:29 item 2',
      v_prompt, case when w.worker_status = 'verified' then 'the page states no study load' else 'the page check refused the reading again (' || coalesce((select string_agg(x, '; ') from jsonb_array_elements_text(coalesce(w.verdict->'problems', '[]'::jsonb)) x), 'no finding') || ')' end), 1000);
    v_prev := current_setting('request.jwt.claim.sub', true);
    perform set_config('request.jwt.claim.sub', v_sys::text, true);
    begin
      v_res := security.layer4_boost_study_load_inbox_decide_v1(w.id::text, 'not_stated', null, v_reason);
      perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
      if coalesce((v_res->>'ok')::boolean, false) then v_ok := v_ok + 1; v_by := jsonb_set(v_by, array[w.worker_status], to_jsonb(coalesce((v_by->>w.worker_status)::int, 0) + 1)); else v_fail := v_fail + 1; end if;
    exception when others then perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true); v_fail := v_fail + 1;
    end;
  end loop;
  if v_ok + v_fail > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'rule_execute', 'l4-boost-sl-settle-v1', jsonb_build_object('settled_not_stated', v_ok, 'by_reread', v_by, 'failed', v_fail, 'waiting_for_reread', v_wait, 'prompt', v_prompt), v_sys);
  end if;
  return jsonb_build_object('ok', true, 'settled', v_ok, 'by_reread', v_by, 'failed', v_fail, 'waiting_for_reread', v_wait,
                            'open', (select count(*) from pipeline.boost_study_load_reviews where status = 'open'), 'prompt', v_prompt);
end $function$;
revoke all on function security.boost_study_load_settle_rule_v1(integer) from public, anon, authenticated;
comment on function security.boost_study_load_settle_rule_v1(integer) is 'CF-247 rule l4-boost-sl-settle-v1 (Platform Admin 18 Nov 2026 14:29 item 2): settles as Not stated each open Boost study load reading whose page, read again with the current prompt, still gives no admissible study load; through the Layer 4 Inbox decision under the system automation account.';

insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('layer4-boost-sl-settle', 'Boost', 24, 'Boost study load: settle after the re-read',
  'Every 30 minutes, when setting boost.sl_settle_on is 1 (Settings > Pipeline settings > Boost): each open Boost study load reading in Layer 4 whose page was read again with the current prompt and still gives no admissible study load (stated as none, or refused again by the page check) is settled as Not stated through the Layer 4 Inbox decision, with the rule and the findings as its reason. A reading whose course gained a study load is closed as superseded by the review feed.',
  6, true)
on conflict (jobname) do nothing;

select cron.schedule('layer4-boost-sl-settle', '7,37 * * * *',
  'select security.boost_study_load_settle_rule_v1(security.pipeline_num_v1(''batch.boost_sl_settle'', 400)::int)')
where not exists (select 1 from cron.job where jobname = 'layer4-boost-sl-settle');

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'layer4-boost-sl-settle', 'Layer 4', 'Boost', 'Settles refused Boost study load readings after the re-read', 'active', '{}', '20261118175000'),
  ('function', 'security.boost_study_load_settle_rule_v1', 'Layer 4', 'Boost', 'One run of rule l4-boost-sl-settle-v1', 'active', '{}', '20261118175000')
on conflict do nothing;

create temp table cf_run on commit drop as select security.boost_study_load_settle_rule_v1(1000) r;

do $c$
declare v jsonb := (select r from cf_run);
begin
  if (v->>'failed')::int > 0 then raise exception 'post-check: % settlements failed: %', v->>'failed', v; end if;
  if exists (select 1 from pipeline.boost_study_load_reviews r where r.reason like '[rule l4-boost-sl-settle-v1]%' and (r.decided_by is distinct from 'c0ffee00-0000-4000-8000-000000000150'::uuid or r.status <> 'not_stated')) then
    raise exception 'post-check: a rule settlement is not recorded as Not stated under the system automation account';
  end if;
  if not exists (select 1 from cron.job where jobname = 'layer4-boost-sl-settle' and active) then raise exception 'post-check: the job is not scheduled'; end if;
  raise notice 'Rule l4-boost-sl-settle-v1 first run: %', v;
end $c$;
