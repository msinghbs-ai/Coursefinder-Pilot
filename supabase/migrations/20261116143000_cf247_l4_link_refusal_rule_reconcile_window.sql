-- CF-247 Layer 4 clearance (Platform Admin 16 Nov 2026 16:47 AEDT; admin report docs/platform/layer4-clearance-and-model-benchmark-2026-11-16.md):
--   1. Rule l4-link-refusal-v1, report section 3.2 option 1 (approved): a waiting official_course_url item is closed through the Inbox's own
--      "Refuse this proposal" action (security.layer4_course_link_refuse_v1: the page is kept refused for the course and the item is rejected
--      through security.layer4_review_decide_impl), under the system automation account (as Decision 263 rules are), when the course-link finder
--      has already proved the proposed page is for something else. Scope, checked again item by item at execution time
--      (security.layer4_course_link_refusal_check_v1):
--        - the hold reason starts "The page found automatically was not linked:" and names another course's page or code or a sibling programme (A),
--          another qualification level (B), another version of the award (C), an older handbook year (D) or another campus (E);
--        - the finder's refusal of that page for this course is already recorded (pipeline.page_rejections), so closing adds no new refusal;
--        - the page is NOT the course's active official link (those 73 items stay for a person: the finder says the live page is wrong);
--        - the item is not claimed, the course is active, no manual lock on the official page, the university is not owned by the parallel reviewer;
--        - a deterministic audit sample (layer4.link_refusal_audit_pct, 5) stays waiting for a person and is marked on change_control_ref.
--      Measured 16 Nov 2026 16:55 AEDT (read only): 856 items in scope by reason; 73 propose the active official page; 32 in the 5% sample;
--      751 would be closed. Nothing is linked, no catalogue row and no consumer API object is written. The rule runs only when called
--      (security.layer4_course_link_refusal_rule_v1(limit, apply)); apply needs layer4.link_refusal_rule_on = 1. Every run and item is recorded
--      (pipeline.layer4_link_refusal_runs, pipeline.layer4_link_refusal_run_items) and in pipeline.admin_control_events.
--   2. security.layer4_reconcile_v1 no longer starves behind older items for a person (defect found 16 Nov 2026 16:22 AEDT: the 05:22 UTC run
--      settled 0 of 36 settleable items). Before, p_limit (layer4.reconcile_batch) capped the oldest items EXAMINED, so at 200 the run never got
--      past items only a person can decide. Now p_limit caps the items SETTLED (as the setting's label always said), the items examined are capped
--      by the new setting layer4.reconcile_examine_max (5000), and a run continues where the last full-queue run stopped
--      (pipeline.layer4_reconcile_cursor), wrapping to the oldest, so every waiting item is reached. p_limit 0 still examines nothing (switch off).
--      layer4.reconcile_batch returns to 200 (raised to 3000 at 16:27 AEDT as the interim fix).
-- G1: no new job (the PR 1 and PR 2 dispatcher cutovers are not touched; a standing schedule for the rule, if wanted, is an admission rule row
-- after the PR 2 cutover). G2: five settings with label, range, unit and used_by; only the system automation account id and the audit sample's
-- hash width are fixed (marked). G3: no consumer API object is read or changed (security.consumer_api_check_v1() before and after).
-- Renumbered from 20261116110000 (Pilot #1177, never applied: that version was taken by #1162 the same afternoon; deploy refused it, nothing ran).
-- Replaces: security.layer4_reconcile_v1(text,integer) (same name and signature; body md5-guarded).
-- Retires: nothing. Nothing is dropped or deleted.

set local lock_timeout = '5s';

select set_config('cf247.l4lr_api_before', (security.consumer_api_check_v1() - 'checked_at')::text, true);

-- 1. Settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer4.link_refusal_rule_on', 'Layer 4: close official-link proposals the finder already refused',
  'On: rule l4-link-refusal-v1 may close a waiting official course page item through "Refuse this proposal" when the course-link finder proved the page is for another course, level, award version, handbook year or campus, the refusal is already recorded and the page is not the course''s live official page. Nothing is linked. Off: the rule only counts.',
  'number', '1'::jsonb, 0, 1, 'on (1) or off (0)', 1240,
  'Platform Admin 16 Nov 2026 16:47 AEDT: report section 3.2 option 1 approved (close the wrong-candidate official URL items)', 'Layer 4', 'security.layer4_course_link_refusal_rule_v1'),
 ('pipeline', 'layer4.link_refusal_batch', 'Layer 4: official-link refusals closed in one call',
  'At most this many items are examined and closed in one call of rule l4-link-refusal-v1. Items not reached come first next time.',
  'number', '200'::jsonb, 1, 500, 'items', 1241,
  'Rule l4-link-refusal-v1 (Platform Admin 16 Nov 2026 16:47 AEDT)', 'Layer 4', 'security.layer4_course_link_refusal_rule_v1'),
 ('pipeline', 'layer4.link_refusal_time_budget_s', 'Layer 4: time one official-link refusal call may spend',
  'A call of rule l4-link-refusal-v1 stops taking new items after this many seconds; the rest wait for the next call.',
  'number', '7'::jsonb, 1, 7, 'seconds', 1242,
  'Rule l4-link-refusal-v1: the same ceiling as the Decision 263 rule executor', 'Layer 4', 'security.layer4_course_link_refusal_rule_v1'),
 ('pipeline', 'layer4.link_refusal_audit_pct', 'Layer 4: official-link refusals kept for a person (audit sample)',
  'This share of the items rule l4-link-refusal-v1 could close stays waiting for a person, chosen by the item''s id (the same items every time), so a person checks the finder''s refusals. 0 keeps none.',
  'number', '5'::jsonb, 0, 100, 'percent', 1243,
  'Report section 3.2 option 1: the audit sample of what the rule closes goes to a person', 'Layer 4', 'security.layer4_course_link_refusal_check_v1'),
 ('pipeline', 'layer4.reconcile_examine_max', 'Layer 4: waiting items checked a run',
  'One run of the platform settlement (layer4-readiness) checks at most this many waiting items of the platform kinds, continuing where the last run stopped and wrapping to the oldest, so no item waits behind older items for a person. Layer 4: items settled a run caps how many it settles.',
  'number', '5000'::jsonb, 100, 50000, 'items', 1212,
  'Defect 16 Nov 2026 16:22 AEDT: the run checked only the oldest 200 items and never reached 36 settleable ones', 'Layer 4', 'security.layer4_reconcile_v1')
on conflict do nothing;

with u as (
  update pipeline.platform_toolset_settings
     set value = '200'::jsonb, updated_at = now(),
         help = 'At most this many waiting items are superseded in one run. The run checks up to Layer 4: waiting items checked a run, continuing where the last run stopped.',
         reason = 'Migration 20261116143000: the setting now caps items settled (as labelled), not items examined; examined items have their own setting (layer4.reconcile_examine_max). Back to 200 from the 3000 interim of 16 Nov 2026 16:27 AEDT'
   where toolset_key = 'pipeline' and key = 'layer4.reconcile_batch'
  returning key)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'settings', 'migration', 'layer4.reconcile_batch', jsonb_build_object('migration', '20261116143000', 'after', 200,
       'why', 'p_limit of security.layer4_reconcile_v1 now caps items settled; examined items are capped by layer4.reconcile_examine_max'), null from u;

-- 2. Run records
create table if not exists pipeline.layer4_link_refusal_runs (
  id bigint generated always as identity primary key,
  rule text not null default 'l4-link-refusal-v1',
  apply boolean not null,
  invoked_by uuid,
  approval_ref text not null,
  at timestamptz not null default now(),
  examined int not null default 0,
  decided int not null default 0,
  would_decide int not null default 0,
  audit_sample int not null default 0,
  failed int not null default 0,
  result jsonb not null default '{}'::jsonb
);
comment on table pipeline.layer4_link_refusal_runs is 'CF-247 rule l4-link-refusal-v1 (Platform Admin 16 Nov 2026 16:47 AEDT, report section 3.2 option 1): one row per call of security.layer4_course_link_refusal_rule_v1, counting or closing waiting official_course_url items whose proposed page the course-link finder already refused on negative evidence. apply false only counts.';
alter table pipeline.layer4_link_refusal_runs enable row level security;
revoke all on pipeline.layer4_link_refusal_runs from anon, authenticated;

create table if not exists pipeline.layer4_link_refusal_run_items (
  run_id bigint not null references pipeline.layer4_link_refusal_runs(id),
  item_id uuid not null,
  course_id uuid,
  reason_group text,
  outcome text not null check (outcome in ('decided', 'would_decide', 'audit_sample', 'failed')),
  reasons text[],
  decision_id uuid,
  at timestamptz not null default now(),
  primary key (run_id, item_id)
);
create index if not exists layer4_link_refusal_run_items_item on pipeline.layer4_link_refusal_run_items(item_id, outcome);
comment on table pipeline.layer4_link_refusal_run_items is 'CF-247 rule l4-link-refusal-v1: one row per item a run looked at: decided (closed through Refuse this proposal, with the decision id), would_decide (count only), audit_sample (left waiting for a person) or failed (left waiting, with the reasons). reason_group is A another course, B another level, C another award version, D older handbook year, E another campus.';
alter table pipeline.layer4_link_refusal_run_items enable row level security;
revoke all on pipeline.layer4_link_refusal_run_items from anon, authenticated;

create table if not exists pipeline.layer4_reconcile_cursor (
  id int primary key default 1 check (id = 1),
  last_created_at timestamptz,
  last_item_id uuid,
  examined int,
  superseded int,
  updated_at timestamptz not null default now()
);
comment on table pipeline.layer4_reconcile_cursor is 'CF-247 (16 Nov 2026): where the last full-queue run of security.layer4_reconcile_v1 stopped (the created_at and id of the last waiting item it checked). The next run starts after it and wraps to the oldest, so every waiting item of the platform kinds is reached within layer4.reconcile_examine_max per run.';
alter table pipeline.layer4_reconcile_cursor enable row level security;
revoke all on pipeline.layer4_reconcile_cursor from anon, authenticated;

-- 3. The rule's per-item check (read only)
create or replace function security.layer4_course_link_refusal_check_v1(p_item uuid default null)
returns table(item_id uuid, course_id uuid, reason_group text, page_url text, audit_sample boolean, pass boolean, reasons text[])
language sql stable security definer set search_path = '' as $f$
  with it as (
    select i.id, i.entity_id, i.claimed_at, i.assigned_to, i.escalation_reason r,
           security.layer4_item_page_v1(i.field_code, i.proposed_value, i.layer2_state) url
      from pipeline.layer4_review_items i
     where i.status = 'pending' and i.field_code = 'official_course_url' and i.entity_type = 'course'
       and i.escalation_reason like 'The page found automatically was not linked: %'
       and (p_item is null or i.id = p_item)),
  g as (
    select it.*,
           case when it.r ilike any (array['%the page address is another course''s at this provider%', '%the page address or title shows another course''s code%',
                                           '%the page is another programme''s page%']) then 'A'
                when it.r ilike '%the page is for another qualification level%' then 'B'
                when it.r ilike '%the page is for another version of the award%' then 'C'
                when it.r ilike any (array['%the page is the % handbook entry%', '%the page is another award or an older handbook year%']) then 'D'
                when it.r ilike '%the page is for another campus%' then 'E' end grp,
           security.layer4_url_key_v1(it.url) k
      from it),
  e as (
    select g.*, c.lifecycle_status,
           exists (select 1 from pipeline.page_rejections pr where pr.course_id = g.entity_id and security.layer4_url_key_v1(pr.url) = g.k) refused,
           exists (select 1 from catalogue.course_links l where l.course_id = g.entity_id and l.link_type = 'official_course' and l.status = 'active'
                      and security.layer4_url_key_v1(l.url) = g.k) live,
           exists (select 1 from pipeline.manual_locks ml where ml.entity = 'course' and ml.entity_id = g.entity_id and ml.field in ('official_url', 'course_url')) locked,
           exists (select 1 from pipeline.layer4_review_owners o where o.provider_id = c.provider_id and o.field_code = 'official_course_url'
                      and o.owner = 'chatgpt' and o.closed_at is null) parallel
      from g join catalogue.courses c on c.id = g.entity_id
     where g.grp is not null),
  v as (
    select e.*,
           -- fixed: 28 bits of the item id's md5 choose the audit sample (stable for the item; the share itself is the setting)
           (('x' || substr(md5(e.id::text), 1, 7))::bit(28)::int % 100) < security.pipeline_num_v1('layer4.link_refusal_audit_pct', 5) aud,
           array_remove(array[
             case when e.claimed_at is not null or e.assigned_to is not null then 'claimed by a reviewer' end,
             case when e.url is null then 'no proposed page' end,
             case when e.lifecycle_status is distinct from 'active' then 'course not active' end,
             case when not e.refused then 'the finder''s refusal of this page is not recorded for the course' end,
             case when e.live then 'the proposed page is the course''s active official page (a person decides)' end,
             case when e.locked then 'manual lock on the official page' end,
             case when e.parallel then 'university owned by the parallel reviewer (ownership register)' end], null) why
      from e)
  select v.id, v.entity_id, v.grp, v.url, v.aud, coalesce(cardinality(v.why), 0) = 0, v.why from v order by v.id
$f$;
comment on function security.layer4_course_link_refusal_check_v1(uuid) is 'CF-247 rule l4-link-refusal-v1 (Platform Admin 16 Nov 2026 16:47 AEDT): for each waiting official_course_url item whose hold reason names negative evidence (another course, level, award version, handbook year or campus), whether the rule may close it, its reason group, whether it is in the audit sample, and why not. Read only.';
revoke all on function security.layer4_course_link_refusal_check_v1(uuid) from public, anon, authenticated;

-- 4. The rule
create or replace function security.layer4_course_link_refusal_rule_v1(p_limit int, p_apply boolean)
returns jsonb language plpgsql security definer set search_path = '' as $f$
-- Rule l4-link-refusal-v1. For each item security.layer4_course_link_refusal_check_v1 passes (not an audit-sample item already recorded): the item is
-- locked (one another reviewer holds is skipped), checked again on its own, and then either left waiting as the audit sample (marked on
-- change_control_ref), counted (p_apply false), or closed through security.layer4_course_link_refuse_v1 under the system automation account.
-- Apply needs layer4.link_refusal_rule_on = 1. Platform Admin or the Integration Controller (no signed-in user).
declare v record; w record; v_run bigint; v_res jsonb; v_reason text; v_prev text; v_lock int;
        v_n int := 0; v_ok int := 0; v_would int := 0; v_aud int := 0; v_fail int := 0; v_left int := 0; v_by jsonb := '{}'::jsonb; v_grp jsonb := '{}'::jsonb; v_why text;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account that records rule decisions (Decision 263)
        v_caller uuid := auth.uid(); v_t0 timestamptz := clock_timestamp();
        v_on boolean := security.pipeline_num_v1('layer4.link_refusal_rule_on', 0) >= 1;
        v_batch int := least(greatest(coalesce(p_limit, 0), 0), security.pipeline_num_v1('layer4.link_refusal_batch', 200)::int);
        v_budget numeric := security.pipeline_num_v1('layer4.link_refusal_time_budget_s', 7);
        v_ref text := 'Platform Admin 16 Nov 2026 16:47 AEDT (report docs/platform/layer4-clearance-and-model-benchmark-2026-11-16.md section 3.2 option 1)';
        v_label jsonb := '{"A": "another course''s page", "B": "another qualification level", "C": "another version of the award", "D": "an older handbook year", "E": "another campus"}'::jsonb;
begin
  if v_caller is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if coalesce(p_apply, false) and not v_on then raise exception 'layer4.link_refusal_rule_on is 0: the rule only counts' using errcode = 'P0001'; end if;
  insert into pipeline.layer4_link_refusal_runs(apply, invoked_by, approval_ref) values (coalesce(p_apply, false), v_caller, v_ref) returning id into v_run;
  for v in select c.item_id from security.layer4_course_link_refusal_check_v1(null) c
            where c.pass and not exists (select 1 from pipeline.layer4_link_refusal_run_items ri join pipeline.layer4_link_refusal_runs rr on rr.id = ri.run_id
                                          where ri.item_id = c.item_id and ri.outcome = 'audit_sample' and rr.apply)
            order by c.audit_sample desc, c.item_id limit v_batch loop
    if clock_timestamp() - v_t0 > make_interval(secs => v_budget) then v_left := v_left + 1; continue; end if;
    v_n := v_n + 1;
    begin
      begin
        select 1 into v_lock from pipeline.layer4_review_items i where i.id = v.item_id and i.status = 'pending' for update nowait;
      exception when lock_not_available then
        raise exception using errcode = 'P0001', message = 'l4lr:another reviewer is deciding this item';
      end;
      if v_lock is null then raise exception using errcode = 'P0001', message = 'l4lr:no longer waiting'; end if;
      v_lock := null;
      w := null;
      select x.item_id, x.course_id, x.reason_group, x.page_url, x.audit_sample, x.pass, x.reasons into w from security.layer4_course_link_refusal_check_v1(v.item_id) x;
      if w.item_id is null then raise exception using errcode = 'P0001', message = 'l4lr:no longer in the rule''s scope'; end if;
      if not w.pass then raise exception using errcode = 'P0001', message = 'l4lr:' || array_to_string(w.reasons, '; '); end if;
      v_grp := jsonb_set(v_grp, array[w.reason_group], to_jsonb(coalesce((v_grp->>w.reason_group)::int, 0) + 1));
      if w.audit_sample then
        insert into pipeline.layer4_link_refusal_run_items(run_id, item_id, course_id, reason_group, outcome) values (v_run, v.item_id, w.course_id, w.reason_group, 'audit_sample');
        if coalesce(p_apply, false) then
          update pipeline.layer4_review_items set change_control_ref = coalesce(change_control_ref || '; ', '') || 'audit sample of rule l4-link-refusal-v1 (a person decides)'
           where id = v.item_id and status = 'pending';
        end if;
        v_aud := v_aud + 1;
        continue;
      end if;
      if not coalesce(p_apply, false) then
        insert into pipeline.layer4_link_refusal_run_items(run_id, item_id, course_id, reason_group, outcome) values (v_run, v.item_id, w.course_id, w.reason_group, 'would_decide');
        v_would := v_would + 1;
        continue;
      end if;
      v_reason := left(format('[rule l4-link-refusal-v1] Refuse this proposal: the course-link finder showed this page is for %s, and its refusal for this course is on record. Nothing is linked; any page the course holds stays. Approved by %s',
                              v_label->>w.reason_group, v_ref), 1000);
      v_prev := current_setting('request.jwt.claim.sub', true);
      perform set_config('request.jwt.claim.sub', v_sys::text, true);
      begin
        v_res := security.layer4_course_link_refuse_v1(v.item_id, v_reason);
      exception when others then
        perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
        raise;
      end;
      perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
      insert into pipeline.layer4_link_refusal_run_items(run_id, item_id, course_id, reason_group, outcome, decision_id)
      values (v_run, v.item_id, w.course_id, w.reason_group, 'decided', nullif(v_res->>'decision_id', '')::uuid);
      v_ok := v_ok + 1;
    exception when others then
      v_why := case when sqlerrm like 'l4lr:%' then substr(sqlerrm, 6) else 'decision refused: ' || left(sqlerrm, 300) end;
      insert into pipeline.layer4_link_refusal_run_items(run_id, item_id, outcome, reasons) values (v_run, v.item_id, 'failed', string_to_array(v_why, '; '))
      on conflict (run_id, item_id) do update set outcome = 'failed', reasons = excluded.reasons, decision_id = null;
      v_by := jsonb_set(v_by, array[left(v_why, 120)], to_jsonb(coalesce((v_by->>left(v_why, 120))::int, 0) + 1));
      v_fail := v_fail + 1;
    end;
  end loop;
  update pipeline.layer4_link_refusal_runs set examined = v_n, decided = v_ok, would_decide = v_would, audit_sample = v_aud, failed = v_fail,
         result = jsonb_build_object('by_group', v_grp, 'failed_by_reason', v_by, 'not_reached', v_left, 'seconds', round(extract(epoch from clock_timestamp() - v_t0)::numeric, 1))
   where id = v_run;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', case when coalesce(p_apply, false) then 'rule_execute' else 'rule_count' end, 'l4-link-refusal-v1',
          jsonb_build_object('run_id', v_run, 'examined', v_n, 'decided', v_ok, 'would_decide', v_would, 'audit_sample', v_aud, 'failed', v_fail, 'not_reached', v_left,
                             'by_group', v_grp, 'failed_by_reason', v_by, 'approval_ref', v_ref), v_caller);
  return jsonb_build_object('run_id', v_run, 'rule', 'l4-link-refusal-v1', 'apply', coalesce(p_apply, false), 'examined', v_n, 'decided', v_ok, 'would_decide', v_would,
                            'audit_sample', v_aud, 'failed', v_fail, 'not_reached', v_left, 'by_group', v_grp, 'failed_by_reason', v_by);
end $f$;
comment on function security.layer4_course_link_refusal_rule_v1(int, boolean) is 'CF-247 rule l4-link-refusal-v1 (Platform Admin 16 Nov 2026 16:47 AEDT, report section 3.2 option 1): closes waiting official_course_url items the course-link finder already refused on negative evidence, through Refuse this proposal under the system automation account; the audit sample stays for a person. p_apply false counts only; apply needs layer4.link_refusal_rule_on.';
revoke all on function security.layer4_course_link_refusal_rule_v1(int, boolean) from public, anon, authenticated;

-- 5. layer4_reconcile_v1: settle cap, examine cap and a cursor (md5-guarded on the live body)
do $g$
declare v_md5 text := (select md5(p.prosrc) from pg_proc p where p.oid = 'security.layer4_reconcile_v1(text,integer)'::regprocedure);
begin
  if v_md5 not in ('5ec45998c27babfb92d024b0c60d1265', '641ff18954c6c5006b3f7dacca6cdf1e') then
    raise exception 'live security.layer4_reconcile_v1 differs from the definition this change replaces (body md5 %)', v_md5;
  end if;
end $g$;

create or replace function security.layer4_reconcile_v1(p_kind text, p_limit integer)
returns jsonb language plpgsql security definer set search_path = '' as $function$
-- While layer4.reconcile_supersede_on is 1: waiting items of p_kind (or of every kind in layer4.platform_kinds when null) that the platform can
-- settle are superseded (status superseded, decided_at, the reason on change_control_ref; pipeline.layer4_supersessions holds the reason, the
-- covering item and the evidence). Never approves or rejects; never touches a lock. Off: counts only. {on, examined, superseded, by_reason}.
-- 16 Nov 2026 (migration 20261116143000): p_limit caps the items superseded; at most layer4.reconcile_examine_max items are checked, and a run over
-- every kind starts after the item the last such run stopped at (pipeline.layer4_reconcile_cursor), wrapping to the oldest, so no settleable item
-- waits behind older items for a person. p_limit 0 checks nothing.
declare r record; v_res jsonb; v_on boolean := security.pipeline_num_v1('layer4.reconcile_supersede_on', 0) >= 1; v_n int := 0; v_ex int := 0;
        v_by jsonb := '{}'::jsonb; v_kinds text[] := security.pipeline_list_v1('layer4.platform_kinds', '[]'::jsonb);
        v_cap int := greatest(coalesce(p_limit, 0), 0);
        v_max int := greatest(security.pipeline_num_v1('layer4.reconcile_examine_max', 5000)::int, 1);
        v_cur pipeline.layer4_reconcile_cursor; v_last_at timestamptz; v_last_id uuid;
begin
  if v_cap = 0 then
    return jsonb_build_object('on', v_on, 'kind', p_kind, 'examined', 0, 'resolvable', v_by, 'superseded', 0);
  end if;
  if p_kind is null then select * into v_cur from pipeline.layer4_reconcile_cursor where id = 1; end if;
  for r in select i.id, i.field_code, i.entity_type, i.entity_id, i.created_at from pipeline.layer4_review_items i
            where i.status = 'pending' and i.field_code = any (v_kinds) and (p_kind is null or i.field_code = p_kind)
            order by (v_cur.last_created_at is not null and (i.created_at, i.id) <= (v_cur.last_created_at, v_cur.last_item_id)), i.created_at, i.id
            limit v_max loop
    v_ex := v_ex + 1;
    v_last_at := r.created_at; v_last_id := r.id;
    v_res := security.layer4_resolution_v1(r.id);
    continue when v_res is null;
    v_by := jsonb_set(v_by, array[v_res->>'reason'], to_jsonb(coalesce((v_by->>(v_res->>'reason'))::int, 0) + 1));
    continue when not v_on;
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           change_control_ref = coalesce(change_control_ref || '; ', '') || 'CF-247 L4 readiness: settled by the platform (' || (v_res->>'reason') || ')'
     where id = r.id and status = 'pending';
    continue when not found;
    insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
    values (r.id, r.field_code, r.entity_type, r.entity_id, v_res->>'reason', nullif(v_res->>'covered_by_item', '')::uuid, coalesce(v_res->'evidence', '{}'::jsonb), 'reconcile');
    update pipeline.layer4_item_readiness set item_status = 'superseded', readiness = 'closed', classified_at = now() where item_id = r.id;
    v_n := v_n + 1;
    exit when v_n >= v_cap;
  end loop;
  if p_kind is null and v_ex > 0 then
    insert into pipeline.layer4_reconcile_cursor(id, last_created_at, last_item_id, examined, superseded, updated_at)
    values (1, v_last_at, v_last_id, v_ex, v_n, now())
    on conflict (id) do update set last_created_at = excluded.last_created_at, last_item_id = excluded.last_item_id,
                                   examined = excluded.examined, superseded = excluded.superseded, updated_at = excluded.updated_at;
  end if;
  return jsonb_build_object('on', v_on, 'kind', p_kind, 'examined', v_ex, 'resolvable', v_by, 'superseded', v_n);
end $function$;

do $g$
declare v_md5 text := (select md5(p.prosrc) from pg_proc p where p.oid = 'security.layer4_reconcile_v1(text,integer)'::regprocedure);
begin
  if v_md5 <> '641ff18954c6c5006b3f7dacca6cdf1e' then raise exception 'security.layer4_reconcile_v1 body md5 after the change is %, expected 641ff18954c6c5006b3f7dacca6cdf1e', v_md5; end if;
end $g$;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'security.layer4_course_link_refusal_check_v1', 'Layer 4', 'Layer 4', 'Rule l4-link-refusal-v1: which waiting official-link items the finder already refused on negative evidence may be closed, the audit sample, and why not', 'active', '{}', '20261116143000'),
  ('function', 'security.layer4_course_link_refusal_rule_v1', 'Layer 4', 'Layer 4', 'Rule l4-link-refusal-v1: closes those items through Refuse this proposal under the system automation account (Platform Admin 16 Nov 2026 16:47)', 'active', '{}', '20261116143000'),
  ('table', 'pipeline.layer4_link_refusal_runs', 'Layer 4', 'Layer 4', 'One row per call of rule l4-link-refusal-v1', 'active', '{}', '20261116143000'),
  ('table', 'pipeline.layer4_link_refusal_run_items', 'Layer 4', 'Layer 4', 'One row per item a call of rule l4-link-refusal-v1 looked at', 'active', '{}', '20261116143000'),
  ('table', 'pipeline.layer4_reconcile_cursor', 'Layer 4', 'Layer 4', 'Where the last full-queue platform settlement run stopped, so every waiting item is reached', 'active', '{}', '20261116143000')
on conflict do nothing;

-- 6. Post-checks
do $c$
declare v_c jsonb := (select jsonb_build_object('n', count(*), 'pass', count(*) filter (where pass), 'live', count(*) filter (where 'the proposed page is the course''s active official page (a person decides)' = any (reasons)))
                        from security.layer4_course_link_refusal_check_v1(null));
begin
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in
      ('layer4.link_refusal_rule_on', 'layer4.link_refusal_batch', 'layer4.link_refusal_time_budget_s', 'layer4.link_refusal_audit_pct', 'layer4.reconcile_examine_max')
      and label is not null and unit is not null and used_by is not null and min_value is not null and max_value is not null) <> 5 then
    raise exception 'post-check (G2): the five settings carry label, range, unit and used_by';
  end if;
  if security.pipeline_num_v1('layer4.reconcile_batch', 0) <> 200 or security.pipeline_num_v1('layer4.reconcile_supersede_on', 0) <> 1 then
    raise exception 'post-check: layer4.reconcile_batch is 200 and the reconcile switch stays on';
  end if;
  if (v_c->>'n')::int = 0 or (v_c->>'pass')::int > (v_c->>'n')::int - (v_c->>'live')::int then
    raise exception 'post-check: the rule''s scope is not as measured (%): items proposing the active official page never pass', v_c;
  end if;
  if exists (select 1 from pipeline.layer4_link_refusal_run_items) then raise exception 'post-check: the migration decides nothing (no run recorded)'; end if;
  if (security.consumer_api_check_v1() - 'checked_at')::text is distinct from current_setting('cf247.l4lr_api_before', true) then
    raise exception 'post-check (G3): the consumer API check result changed';
  end if;
  if coalesce(current_setting('cf247.l4lr_api_before', true)::jsonb->'drift', '[]'::jsonb) not in ('[]'::jsonb, '{}'::jsonb, 'null'::jsonb) then
    raise exception 'post-check (G3): the consumer API differs from its baseline';
  end if;
  raise notice 'l4-link-refusal-v1 scope at migration: %', v_c;
end $c$;
