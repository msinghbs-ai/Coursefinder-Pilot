-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 14:25 and 14:29 item 3: expedite Layer 4 › Inbox › Course link with the toolset,
-- deterministic first; admit clean single-course matches with their source and rule; leave only what a person must judge).
-- Rule l4-link-accept-v1, for the waiting "Course link" items about an official course page (field official_course_url; 1,335 of the 1,487 at
-- 14:40 AEDT; the 146 fee checks, 5 fee rows and 1 English row are not in scope). The evidence is the course-page binder's own result in
-- pipeline.coverage_course_pages (job coverage-bind and the coverage reader: the page read and its identity proved by CRICOS or NZQA code,
-- exact title, degree name, an adapter or a person; setting layer4.link_accept_identity_bases):
--   use      the binder read and proved the very page proposed: the proposal is approved (Use the new page);
--   enter    the binder read and proved another page of the course: that page is set (Enter the page), never one refused for the course before;
--   refuse   the binder read the page proposed and refused it; or the course-link finder refused it as not naming the programme, or as a
--            shared, fee, application or list page (its own escalation reason), and the binder holds no proof of it: the proposal is refused
--            (nothing is linked; any page the course holds stays);
--   hold     everything else waits for a person: two pages tied (binder ambiguous), a page not read (fetch failed, blocked, needs render), an old
--            handbook year with no current page proved, a CRICOS page on another address without proof, a manual lock.
-- A page with a year older than the current Melbourne year in its address is never used or entered by this rule.
-- Every decision goes through the existing decision path (public.layer4_review_decide or security.layer4_course_link_refuse_v1) under the
-- system automation account (Decision 263, as rule l4-link-refusal-v1), with a reason naming the rule, the binder evidence and the page; the
-- Layer 4 decision log and pipeline.page_rejections hold them. A share of the finder refusals (setting layer4.link_accept_audit_pct) is left
-- for a person as the audit sample and marked on the item. Job layer4-link-accept runs the rule every hour for new items.
-- G1: the job is catalogued. G2: switch, batch, time budget, audit share and identity bases are settings. G3: no consumer API object's shape
-- changes; official course links are data the API already reads.
-- Replaces: nothing (adds the accept side beside rule l4-link-refusal-v1)
-- Retires: nothing

set local lock_timeout = '5s';

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer4.link_accept_rule_on', 'Course link rule: decide by the binder''s proof',
  '1: rule l4-link-accept-v1 decides waiting Course link items about an official page from the course-page binder''s own result (use a proved page, enter another proved page, refuse a page the binder or the finder refused); 0: it only counts.',
  'number', '1'::jsonb, 0, 1, 'switch', 512, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 14:29 item 3', 'Layer 4', 'security.layer4_course_link_accept_rule_v1, job layer4-link-accept'),
 ('pipeline', 'layer4.link_accept_batch', 'Course link rule: items per run',
  'How many waiting Course link items one run of rule l4-link-accept-v1 examines.',
  'number', '400'::jsonb, 1, 5000, 'items', 513, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 14:29 item 3', 'Layer 4', 'job layer4-link-accept'),
 ('pipeline', 'layer4.link_accept_time_budget_s', 'Course link rule: time budget per run',
  'Seconds one run may spend; items not reached wait for the next run.',
  'number', '240'::jsonb, 5, 600, 'seconds', 514, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 14:29 item 3', 'Layer 4', 'security.layer4_course_link_accept_rule_v1'),
 ('pipeline', 'layer4.link_accept_audit_pct', 'Course link rule: audit sample of finder refusals',
  'Per cent of the proposals the rule would refuse on the finder''s word alone that are left for a person as the audit sample.',
  'number', '5'::jsonb, 0, 100, 'per cent', 515, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 14:29 item 3', 'Layer 4', 'security.layer4_course_link_accept_check_v1'),
 ('pipeline', 'layer4.link_accept_identity_bases', 'Course link rule: identity proofs the rule accepts',
  'The binder identity bases (pipeline.coverage_course_pages.identity_basis) strong enough for the rule to use or enter a page.',
  'list', '["cricos_code", "nzqa_code", "exact_title", "manual", "degree_name", "adapter_title"]'::jsonb, 0, null, 'bases', 516, 'CF-247 S2 - BOOST, Platform Admin 18 Nov 2026 14:29 item 3', 'Layer 4', 'security.layer4_course_link_accept_check_v1')
on conflict (toolset_key, key) do nothing;

-- The classification (reads only)
create or replace function security.layer4_course_link_accept_check_v1(p_item uuid default null)
returns table(item_id uuid, course_id uuid, reason_group text, action text, page_url text, basis text, audit_sample boolean)
language sql stable security definer set search_path to '' as $function$
  with base as (
    select r.id, r.entity_id, r.escalation_reason,
           btrim(coalesce(security.layer4_item_page_v1(r.field_code, r.proposed_value, r.layer2_state), '')) purl,
           case when r.escalation_reason like 'The course page that shows%' then 'cricos_page_elsewhere'
                when r.escalation_reason like 'The page we show carries the year%' then 'old_year_address'
                when r.escalation_reason like '%do not name this programme%' then 'finder_title_mismatch'
                when r.escalation_reason like '%shared by several courses%' then 'finder_shared_or_list_page'
                else 'other' end grp
      from pipeline.layer4_review_items r
     where r.status = 'pending' and r.entity_type = 'course' and r.field_code = 'official_course_url'
       and (p_item is null or r.id = p_item)),
  x as (
    select b.*, p.status ps, p.read_status rs, p.identity_basis ib, btrim(coalesce(p.url, '')) burl,
           (p.status = 'bound' and p.read_status = 'read'
            and p.identity_basis = any (security.pipeline_list_v1('layer4.link_accept_identity_bases'))) strong,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = b.entity_id and l.field in ('official_url', 'course_url')) locked,
           extract(year from (now() at time zone 'Australia/Melbourne'))::int yr  -- fixed: the current Melbourne year
      from base b left join pipeline.coverage_course_pages p on p.course_id = b.entity_id),
  y as (
    select x.*, case
      when x.locked then 'hold'
      when x.strong and x.purl <> '' and lower(x.burl) = lower(x.purl) and coalesce(substring(x.purl from '/((?:19|20)[0-9]{2})/')::int, 9999) >= x.yr then 'use'
      when x.strong and x.burl ~* '^https://' and lower(x.burl) <> lower(x.purl) and coalesce(substring(x.burl from '/((?:19|20)[0-9]{2})/')::int, 9999) >= x.yr
           and not exists (select 1 from pipeline.page_rejections j where j.course_id = x.entity_id and lower(j.url) = lower(x.burl)) then 'enter'
      when x.ps = 'mismatch' and x.purl <> '' and lower(x.burl) = lower(x.purl) then 'refuse'
      when x.grp in ('finder_title_mismatch', 'finder_shared_or_list_page') and x.purl <> '' and not (coalesce(x.strong, false) and lower(x.burl) = lower(x.purl)) then 'refuse'
      else 'hold' end act
      from x)
  select y.id, y.entity_id, y.grp, y.act,
         case y.act when 'enter' then y.burl else y.purl end,
         case when y.act in ('use', 'enter') then 'binder proved ' || coalesce(y.ib, '?')
              when y.act = 'refuse' and y.ps = 'mismatch' and lower(y.burl) = lower(y.purl) then 'binder refused the page (' || coalesce(y.rs, y.ps) || ')'
              when y.act = 'refuse' then 'finder: ' || replace(y.grp, '_', ' ') || '; the binder holds no proof of the page'
              else coalesce(y.ps, 'no binder result') || '/' || coalesce(y.rs, '-') end,
         -- the audit sample: a fixed share of the refusals resting on the finder's word alone
         y.act = 'refuse' and not (y.ps = 'mismatch' and lower(y.burl) = lower(y.purl))
           and abs(hashtext(y.id::text)) % 100 < security.pipeline_num_v1('layer4.link_accept_audit_pct', 5)::int
    from y
$function$;
revoke all on function security.layer4_course_link_accept_check_v1(uuid) from public, anon, authenticated;
comment on function security.layer4_course_link_accept_check_v1(uuid) is 'CF-247 rule l4-link-accept-v1 (Platform Admin 18 Nov 2026 14:29): what the rule would do with each waiting Course link item about an official page (use, enter, refuse, hold), from the course-page binder''s own result and the finder''s refusal; reads only.';

-- The run (decides under the system automation account through the existing decision path)
create or replace function security.layer4_course_link_accept_rule_v1(p_limit integer, p_apply boolean)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare w record; v_res jsonb; v_reason text; v_prev text; v_lock int;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account that records rule decisions (Decision 263)
        v_caller uuid := auth.uid(); v_t0 timestamptz := clock_timestamp();
        v_on boolean := security.pipeline_num_v1('layer4.link_accept_rule_on', 0) >= 1;
        v_batch int := least(greatest(coalesce(p_limit, 0), 0), 5000);  -- fixed: upper bound of the setting's range
        v_budget numeric := security.pipeline_num_v1('layer4.link_accept_time_budget_s', 240);
        v_ref text := 'Platform Admin 18 Nov 2026 14:25 and 14:29 (expedite Course link: deterministic first)';
        v_n int := 0; v_done jsonb := '{}'::jsonb; v_would jsonb := '{}'::jsonb; v_aud int := 0; v_fail int := 0; v_left int := 0; v_hold int := 0; v_by jsonb := '{}'::jsonb; v_why text;
begin
  if v_caller is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if coalesce(p_apply, false) and not v_on then raise exception 'layer4.link_accept_rule_on is 0: the rule only counts' using errcode = 'P0001'; end if;
  for w in select * from security.layer4_course_link_accept_check_v1(null) c order by (c.action = 'hold'), c.item_id limit v_batch loop
    v_n := v_n + 1;
    if w.action = 'hold' then v_hold := v_hold + 1; continue; end if;
    if clock_timestamp() - v_t0 > make_interval(secs => v_budget) then v_left := v_left + 1; continue; end if;
    if w.audit_sample then
      if coalesce(p_apply, false) then
        update pipeline.layer4_review_items set change_control_ref = coalesce(change_control_ref || '; ', '') || 'audit sample of rule l4-link-accept-v1 (a person decides)'
         where id = w.item_id and status = 'pending' and coalesce(change_control_ref, '') not like '%audit sample of rule l4-link-accept-v1%';
      end if;
      v_aud := v_aud + 1; continue;
    end if;
    if not coalesce(p_apply, false) then v_would := jsonb_set(v_would, array[w.action], to_jsonb(coalesce((v_would->>w.action)::int, 0) + 1)); continue; end if;
    begin
      v_lock := null;
      begin
        select 1 into v_lock from pipeline.layer4_review_items i where i.id = w.item_id and i.status = 'pending' for update nowait;
      exception when lock_not_available then raise exception using errcode = 'P0001', message = 'l4la:another reviewer is deciding this item';
      end;
      if v_lock is null then raise exception using errcode = 'P0001', message = 'l4la:no longer waiting'; end if;
      v_reason := left(format('[rule l4-link-accept-v1] %s: %s; page %s. Approved by %s',
        case w.action when 'use' then 'Use the proposed page' when 'enter' then 'Set the proved page' else 'Refuse this proposal (nothing is linked; any page the course holds stays)' end,
        w.basis, w.page_url, v_ref), 1000);
      v_prev := current_setting('request.jwt.claim.sub', true);
      perform set_config('request.jwt.claim.sub', v_sys::text, true);
      begin
        v_res := case w.action
          when 'use' then public.layer4_review_decide(w.item_id, 'approve', v_reason, null)
          when 'enter' then public.layer4_review_decide(w.item_id, 'edit_and_approve', v_reason, to_jsonb(w.page_url))
          else security.layer4_course_link_refuse_v1(w.item_id, v_reason) end;
      exception when others then perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true); raise;
      end;
      perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
      v_done := jsonb_set(v_done, array[w.action], to_jsonb(coalesce((v_done->>w.action)::int, 0) + 1));
    exception when others then
      v_why := case when sqlerrm like 'l4la:%' then substr(sqlerrm, 6) else 'decision refused: ' || left(sqlerrm, 200) end;
      v_by := jsonb_set(v_by, array[left(v_why, 120)], to_jsonb(coalesce((v_by->>left(v_why, 120))::int, 0) + 1));
      v_fail := v_fail + 1;
    end;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', case when coalesce(p_apply, false) then 'rule_execute' else 'rule_count' end, 'l4-link-accept-v1',
          jsonb_build_object('examined', v_n, 'decided', v_done, 'would_decide', v_would, 'held', v_hold, 'audit_sample', v_aud, 'failed', v_fail, 'failed_by_reason', v_by,
                             'not_reached', v_left, 'seconds', round(extract(epoch from clock_timestamp() - v_t0)::numeric, 1), 'approval_ref', v_ref), coalesce(v_caller, v_sys));
  return jsonb_build_object('rule', 'l4-link-accept-v1', 'apply', coalesce(p_apply, false), 'examined', v_n, 'decided', v_done, 'would_decide', v_would, 'held', v_hold,
                            'audit_sample', v_aud, 'failed', v_fail, 'failed_by_reason', v_by, 'not_reached', v_left);
end $function$;
revoke all on function security.layer4_course_link_accept_rule_v1(integer, boolean) from public, anon, authenticated;
comment on function security.layer4_course_link_accept_rule_v1(integer, boolean) is 'CF-247 rule l4-link-accept-v1 (Platform Admin 18 Nov 2026 14:29): decides waiting Course link items about an official page from the binder''s proof (use, enter, refuse) under the system automation account through the existing decision path; holds the rest for a person; leaves an audit sample.';

insert into pipeline.automation_catalogue (jobname, area, sort, label, description, control_rank, batch_editable) values
 ('layer4-link-accept', 'Layer 4', 31, 'Course link rule (binder proof)',
  'Every hour at minute 41, when setting layer4.link_accept_rule_on is 1 (Settings > Pipeline settings > Layer 4): rule l4-link-accept-v1 decides waiting Course link items about an official page from the course-page binder''s own result: uses a proposed page the binder read and proved, sets another page the binder proved, refuses a page the binder or the finder refused (an audit share is left for a person). Two tied pages, unread pages, old handbook years and manual locks wait for a person.',
  6, true)
on conflict (jobname) do nothing;

select cron.schedule('layer4-link-accept', '41 * * * *',
  'select security.layer4_course_link_accept_rule_v1(security.pipeline_num_v1(''layer4.link_accept_batch'', 400)::int, true)')
where not exists (select 1 from cron.job where jobname = 'layer4-link-accept');

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('job', 'layer4-link-accept', 'Layer 4', 'Course links', 'Course link rule l4-link-accept-v1 every hour', 'active', '{}', '20261118173000'),
  ('function', 'security.layer4_course_link_accept_check_v1', 'Layer 4', 'Course links', 'What rule l4-link-accept-v1 would do with each waiting Course link item', 'active', '{}', '20261118173000'),
  ('function', 'security.layer4_course_link_accept_rule_v1', 'Layer 4', 'Course links', 'One run of rule l4-link-accept-v1', 'active', '{}', '20261118173000')
on conflict do nothing;

-- The first run, over every waiting item
create temp table cf_run on commit drop as select security.layer4_course_link_accept_rule_v1(5000, true) r;

do $c$
declare v jsonb := (select r from cf_run); v_dec int;
begin
  v_dec := coalesce((v->'decided'->>'use')::int, 0) + coalesce((v->'decided'->>'enter')::int, 0) + coalesce((v->'decided'->>'refuse')::int, 0);
  if v_dec = 0 then raise exception 'post-check: the rule decided nothing: %', v; end if;
  if (v->>'failed')::int > v_dec / 10 then raise exception 'post-check: too many refused decisions: %', v; end if;  -- fixed: a run where more than one in ten decisions fails is stopped and rolled back
  if exists (select 1 from pipeline.layer4_decisions d join pipeline.layer4_review_items i on i.id = d.review_item_id
              where d.reason like '[rule l4-link-accept-v1]%' and d.actor_id is distinct from 'c0ffee00-0000-4000-8000-000000000150'::uuid) then
    raise exception 'post-check: a rule decision is not recorded under the system automation account';
  end if;
  if not exists (select 1 from cron.job where jobname = 'layer4-link-accept' and active) then raise exception 'post-check: job layer4-link-accept is not scheduled'; end if;
  raise notice 'Rule l4-link-accept-v1 first run: %', v;
end $c$;
