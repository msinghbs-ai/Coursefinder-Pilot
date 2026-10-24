-- CF-247 HOTFIX (24 Oct 2026). Three production defects (Platform Admin 24 Oct 2026 13:17; record: admin repo
-- docs/platform/ui-audit/2026-10-24-hotfix-manual-task-and-layer4-entry.md). Evidence first, then the fixes.
--
-- D2 MANUAL TASK NEVER REACHES FIRECRAWL. "Find course pages: University of Otago (50 courses)" queued its 50 rows in
--   pipeline.course_link_search with requested_at set; the one worker lane (course-link-search-worker, every minute, mode link_search)
--   asks public.svc_course_link_search_next for work — the same picker serves scheduled backlog and a person's task, so there is ONE path.
--   The picker drops a university on the search-stop list (security.fc_search_stopped_v1) before it looks at requested_at: Otago was
--   stopped on 21 Oct by "20 title-search pages in a row were the wrong page" and never resumed, so the task waited for ever. The same
--   gate swallowed 1,549 of the 2,866 person-requested rows waiting (87 stopped universities). The bulk-onboarding check voided the
--   person-asked bypass a second time. Gates, budgets and caps are NOT changed (constraint): a row of a person's running
--   "Find course pages" task passes the stop and bulk checks only, behind setting search.person_task_bypass (on). Budget (day share,
--   month cap), the target-only rule, hidden providers, directory sites and the skip list still apply to it.
--   D-target_only (Platform Admin 24 Oct 2026 13:55): a Find course pages task at a university the target-only rule holds is refused at
--   start with the gate named; no task passes target-only (its release is R2's audit decision).
-- D3 THE STALL WAS INVISIBLE. The task watcher closed a blocked find task after 45 minutes as "the rest wait their turn"; the gap-cause
--   taxonomy filed the same rows as "no page: web search queued" (automatic). Now: security.link_search_block_v1 walks the picker's
--   gates in its order and names the first one that holds (the stall cause); security.admin_job_status_v1 gives every task its last
--   progress, last forwarded, next attempt and — once nothing has moved for tasks.stall_seconds (60) — its blocking reason; the Task
--   manager shows them; the watcher's closing note names the gate; gap causes gain "no page: web search stopped for this university"
--   (not automatic). The same function names the cause for the hourly taxonomy and for the task (one pattern, both surfaces).
-- D1 LAYER 4 "ENTER ANOTHER ADDRESS" ON A QUARANTINED ITEM. The Inbox labels every pending review row "Course link", including fee items
--   (provider_current_tuition: the identity re-verification quarantine and the fee floor). Their "Enter another address" went to
--   layer4_review_decide, which has no branch for a fee and fell through to the scalar resolver ("field is not enabled for scalar Layer 4
--   editing"). It now goes through the standard bind path a person's page entry uses (admin_course_edit set_official_url: manual binding,
--   manual locks, read first in line, then the fee reader and the AI fill): the page is read again under the current identity rule and the
--   fee re-admits through coverage_apply_course_v1 (a manual binding is exempt from the identity quarantine). https:// only, on the
--   provider's own site. "Use the new page" has no page on a fee item and says so; "Keep the page we hold" closes the item as before.
-- Replaces: nothing (svc_course_link_search_next, worker_mode_waiting_v1, admin_job_watch_v1, admin_jobs, admin_layer4_inbox and
--   gap_causes_snapshot_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 0 settings ---------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'search.person_task_bypass', 'Course search: a person''s task passes the stop', '1: a course page search a person asked for (Find course pages) runs even when the university''s automatic search has stopped (wrong pages in a row, too many searches with no page) or it came in with bulk onboarding. Budgets, the target-only rule and the skip list still apply. 0: a person''s task waits like the automatic search.', 'number', '1'::jsonb, '0', '1', 'on/off', 781, 'Course page search', 'public.svc_course_link_search_next', 'hotfix D2 (Platform Admin 24 Oct 2026 13:17)'),
 ('pipeline', 'tasks.stall_seconds', 'Tasks: blocked after', 'A running task that has moved nothing for this many seconds shows why it is blocked (Scheduled jobs › Task manager).', 'number', '60'::jsonb, '30', '3600', 'seconds', 782, 'Platform upkeep', 'security.admin_job_status_v1', 'hotfix D3')
on conflict (toolset_key, key) do nothing;

-- 1 who asked: a row of a person's running Find course pages task ---------------------------------------------------------------------------
create or replace function security.link_search_person_task_v1(p_provider uuid, p_course uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from pipeline.admin_jobs j
                  where j.kind = 'course_page_find' and j.state in ('queued', 'running')
                    and j.args->>'provider_id' = p_provider::text and j.args->'course_ids' ? p_course::text)
$$;
comment on function security.link_search_person_task_v1(uuid, uuid) is 'hotfix D2: true when the course is in a person''s queued or running Find course pages task for the provider';

-- 2 the stall cause: the picker's gates, in its order, the first that holds ----------------------------------------------------------------
create or replace function security.link_search_block_v1(p_provider uuid, p_course_ids uuid[] default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_job record; v_flag record; v_on boolean; v_cap numeric; v_used numeric; v_left numeric; v_stop record; v_rc record; v_person boolean;
        v_bypass boolean := security.pipeline_num_v1('search.person_task_bypass', 1) >= 1;
begin
  v_person := p_course_ids is not null and exists (select 1 from unnest(p_course_ids) c where security.link_search_person_task_v1(p_provider, c));
  select j.active into v_job from cron.job j where j.jobname = 'course-link-search-worker';
  select f.flagged_at, f.next_check_at into v_flag from pipeline.enrichment_flags f
   where f.entity = 'job' and f.entity_key = 'course-link-search-worker' and f.reason_code = 'idle_paused' and f.state = 'raised' order by f.flagged_at desc limit 1;
  if v_job.active is distinct from true and v_flag.flagged_at is null then
    return jsonb_build_object('code', 'lane_paused', 'words', 'The course page search lane is switched off', 'fix', 'Scheduled jobs › Automations › Find course pages (search): Resume');
  end if;
  if v_flag.flagged_at is not null then
    return jsonb_build_object('code', 'lane_idle_paused', 'words', 'The course page search lane is paused by the idle guard until ' || to_char(v_flag.next_check_at at time zone 'Australia/Melbourne', 'HH24:MI'), 'fix', 'It wakes by itself when work waits; nothing to do');
  end if;
  select s.enabled, s.monthly_credit_cap into v_on, v_cap from pipeline.course_link_search_settings s where s.id = 1;
  if not coalesce(v_on, false) then return jsonb_build_object('code', 'search_off', 'words', 'Course page search is switched off', 'fix', 'Models & services › Toolsets & limits › Firecrawl › course search'); end if;
  select coalesce(sum(u.units), 0) into v_used from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now());
  if v_used + 2 > v_cap then return jsonb_build_object('code', 'month_cap', 'words', 'This month''s course search credits are used (' || v_used::int || ' of ' || v_cap::int || ')', 'fix', 'Waits for next month, or raise the monthly cap'); end if;
  v_left := security.fc_budget_left_v1('course_link_search');
  if v_left < 2 then return jsonb_build_object('code', 'day_budget', 'words', 'Today''s Firecrawl share for course search is used', 'fix', 'Waits for tomorrow''s share'); end if;
  if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_provider) then
    return jsonb_build_object('code', 'provider_hidden', 'words', 'The university is unpublished or archived; its searches wait', 'fix', 'Publish the university');
  end if;
  select x.searches, x.since into v_stop from security.fc_search_stopped_v1() x where x.provider_id = p_provider;
  if v_stop.since is not null and not (v_bypass and v_person) then
    return jsonb_build_object('code', 'search_stopped', 'words', 'The automatic search stopped for this university on ' || to_char(v_stop.since at time zone 'Australia/Melbourne', 'DD Mon') || ' (wrong pages in a row, or too many searches with no page)' || case when not v_bypass then '; a person''s task waits too (search.person_task_bypass is off)' else '' end, 'fix', 'Adapter builder › Find course pages › Search again, or a person''s Find course pages task');
  end if;
  if coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
     and not exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = p_provider and tc.included) then
    return jsonb_build_object('code', 'not_target', 'words', 'Firecrawl is for target universities only and this one is not a target', 'fix', 'Models & services › Toolsets & limits › Firecrawl targets');
  end if;
  select rc.search_domain into v_rc from pipeline.course_link_recipes rc where rc.provider_id = p_provider and rc.active limit 1;
  if v_rc.search_domain is null then return jsonb_build_object('code', 'no_site', 'words', 'No website is recorded to search', 'fix', 'Adapter builder step 1: the website'); end if;
  if security.third_party_host_v1('https://' || v_rc.search_domain) then return jsonb_build_object('code', 'directory_site', 'words', 'The recorded website is a course directory, not the university''s own', 'fix', 'Adapter builder step 1: change the website'); end if;
  if exists (select 1 from catalogue.providers px, pipeline.platform_toolset_settings sk
              where px.id = p_provider and sk.toolset_key = 'pipeline' and sk.key = 'search.skip_providers' and sk.value ? px.stable_key) then
    return jsonb_build_object('code', 'skipped_provider', 'words', 'This university is on the search skip list', 'fix', 'Settings › Pipeline settings › search.skip_providers');
  end if;
  return null;
end $$;
comment on function security.link_search_block_v1(uuid, uuid[]) is 'hotfix D3: the first course-search gate that holds for a provider (and a person''s task rows), as {code, words, fix}; null when nothing blocks. The stall taxonomy for the Task manager and the gap causes';

-- 3 every task: last progress, last forwarded, next attempt, and the blocking reason once stalled ---------------------------------------------
create or replace function security.admin_job_status_v1(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare j pipeline.admin_jobs%rowtype; v_last timestamptz; v_fwd timestamptz; v_ids uuid[]; v_pid uuid; v_block jsonb; v_runner record;
        v_stall int := security.pipeline_num_v1('tasks.stall_seconds', 60)::int; v_sent int; v_waiting int;
begin
  select * into j from pipeline.admin_jobs where id = p_id;
  if j.id is null or j.state not in ('queued', 'running', 'paused') then return null; end if;
  v_last := coalesce(nullif(j.cursor->>'last_change_at', '')::timestamptz, j.started_at, j.created_at);
  select c.active, (select max(d.start_time) from cron.job_run_details d where d.jobid = c.jobid) last_run into v_runner from cron.job c where c.jobname = 'admin-jobs';
  if j.kind = 'course_page_find' then
    v_ids := array(select x::uuid from jsonb_array_elements_text(coalesce(j.args->'course_ids', '[]'::jsonb)) x);
    v_pid := nullif(j.args->>'provider_id', '')::uuid;
    select max(s.sent_at), count(*) filter (where s.sent_at >= j.created_at), count(*) filter (where s.state = 'queued')
      into v_fwd, v_sent, v_waiting from pipeline.course_link_search s where s.course_id = any (v_ids);
    if v_fwd < j.created_at then v_fwd := null; end if;
  elsif j.kind = 'enrich_fields' then
    select max(i.updated_at) into v_fwd from pipeline.field_enrich_items i where i.job_id = j.id and i.state <> 'queued';
  end if;
  if j.state = 'running' and now() - greatest(coalesce(v_fwd, '-infinity'), v_last) > make_interval(secs => v_stall) then
    if v_runner.active is distinct from true then
      v_block := jsonb_build_object('code', 'runner_off', 'words', 'The task runner is switched off', 'fix', 'Scheduled jobs › Automations › Tasks: Resume');
    elsif j.kind = 'course_page_find' then
      v_block := coalesce(security.link_search_block_v1(v_pid, v_ids),
                          case when v_waiting > 0 then jsonb_build_object('code', 'waiting_turn', 'words', v_waiting || ' search(es) waiting their turn behind earlier requests', 'fix', 'Nothing to do') end);
    elsif j.pause_requested then
      v_block := jsonb_build_object('code', 'pausing', 'words', 'Pausing at the next provider', 'fix', 'Resume the task');
    else
      v_block := jsonb_build_object('code', 'no_progress', 'words', 'Nothing has moved for ' || greatest(1, extract(epoch from now() - v_last)::int / 60) || ' minute(s)', 'fix', 'Platform health › Work queues says why the lane is idle');
    end if;
  end if;
  return jsonb_build_object('last_progress_at', v_last, 'last_forwarded_at', v_fwd, 'forwarded', v_sent,
                            'next_attempt_at', date_trunc('minute', now()) + interval '1 minute',  -- fixed: the task runner and the search lane run every minute
                            'runner_last_run', v_runner.last_run, 'blocked', v_block);
end $$;
comment on function security.admin_job_status_v1(uuid) is 'hotfix D3: a running task''s last progress, last forwarded to its tool, next attempt and, once stalled tasks.stall_seconds, its blocking reason ({code, words, fix})';

-- 4 the picker: a person's task passes the stop and bulk checks (gates, budgets and caps unchanged) ------------------------------------------
select pg_temp.edit_n('public.svc_course_link_search_next(integer)', '63012f8a950da8b89e56c6150107eafc', array[
  array[$o$declare v_on boolean; v_cap numeric;$o$,
        $n$declare v_person boolean := security.pipeline_num_v1('search.person_task_bypass', 1) >= 1; v_on boolean; v_cap numeric;$n$],
  array[$o$           security.fc_provider_tier_v1(q.provider_id) tier, rc.search_domain
$o$, $n$           security.fc_provider_tier_v1(q.provider_id) tier, rc.search_domain,
           (q.provider_id = any (v_stopped)) stopped  -- 24 Oct 2026 (hotfix D2): kept as a flag; the row check below decides
$n$],
  array[$o$       and q.provider_id <> all (v_stopped)
$o$, $n$$n$],
  array[$o$       and (pv.focus or s.requested_at is not null)$o$,
        $n$       and (not pv.stopped or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id)))  -- hotfix D2: a person's task passes the stop
       and (pv.focus or s.requested_at is not null)$n$],
  array[$o$       and case when s.requested_at is not null and not pv.bulk then true$o$,
        $n$       and case when s.requested_at is not null and (not pv.bulk or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id))) then true$n$]],
  array[1, 1, 1, 1, 1]);

-- the lane wakes for a person's task at a stopped university (R1 wake-up test)
select pg_temp.edit_n('security.worker_mode_waiting_v1(text)', '781c1f7da4ebd4c34e38be824a4226a7', array[
  array[$o$                                and s.provider_id <> all (array(select x.provider_id from security.fc_search_stopped_v1() x)))$o$,
        $n$                                and (s.provider_id <> all (array(select x.provider_id from security.fc_search_stopped_v1() x))
                                     or (security.pipeline_num_v1('search.person_task_bypass', 1) >= 1 and security.link_search_person_task_v1(s.provider_id, s.course_id))))$n$]],
  array[1]);

-- 4b accept → toolset at once: the task asks the same worker with the same body the minute job sends (one path), straight after commit,
--    instead of waiting up to a minute for the next tick. A lane an operator paused stays paused; the idle guard's own pause does not hold it.
select pg_temp.edit_n('security.provider_task_fire_v1(text)', 'a972d06b948cf0db6986c90614fc09b3', array[
  array[$o$                         when 'central_find' then '{"mode":"central_find","limit":4}'::jsonb end;
  if v_body is null then return 0; end if;$o$,
        $n$                         when 'central_find' then '{"mode":"central_find","limit":4}'::jsonb
                         -- hotfix D2 (24 Oct 2026): the body of job course-link-search-worker, word for word
                         when 'link_search' then jsonb_build_object('mode', 'link_search', 'limit', security.pipeline_num_v1('batch.link_search_worker', 120)::int) end;
  if v_body is null then return 0; end if;
  if p_mode = 'link_search'
     and not exists (select 1 from cron.job j where j.jobname = 'course-link-search-worker' and j.active)
     and not exists (select 1 from pipeline.enrichment_flags f where f.entity = 'job' and f.entity_key = 'course-link-search-worker' and f.reason_code = 'idle_paused' and f.state = 'raised') then
    return 0;
  end if;$n$]],
  array[1]);

-- D-target_only (Platform Admin 24 Oct 2026 13:55): a task at a university the target-only rule holds is refused at start, the gate
-- named at once; no task passes target-only (its release is R2's audit decision, not this hotfix). The check is the picker's own.
select pg_temp.edit_n('security.provider_task_prepare_v1(text,jsonb)', '77d029207a8737f9e17adcc6670f1c6a', array[
  array[$o$      raise exception 'no website is recorded for this provider yet, so there is nowhere to search; use Fill in from website first';
    end if;$o$,
        $n$      raise exception 'no website is recorded for this provider yet, so there is nowhere to search; use Fill in from website first';
    end if;
    if coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
       and not exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = v_pid and tc.included) then
      raise exception 'Not started: this university is not a search target, and course page search is for target universities only (Toolsets & limits › targets).';
    end if;$n$],
  array[$o$    get diagnostics v_n = row_count;
    return jsonb_build_object('provider_id', v_pid, 'course_ids', to_jsonb(v_ids), 'queued', v_n,$o$,
        $n$    get diagnostics v_n = row_count;
    perform security.provider_task_fire_v1('link_search');  -- hotfix D2: forwarded on accept, not at the next minute
    return jsonb_build_object('provider_id', v_pid, 'course_ids', to_jsonb(v_ids), 'queued', v_n,$n$]],
  array[1, 1]);

-- 5 the watcher names the gate when it closes a stalled find task; the Task manager reads every task's status --------------------------------
select pg_temp.edit_n('security.admin_job_watch_v1(uuid)', '58a4ec23ee992b70a4cd8dd312cec2ef', array[
  array[$o$      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = v_pid and u.purpose = 'course_link_search' and u.at >= v_since));$o$,
        $n$      'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.provider_id = v_pid and u.purpose = 'course_link_search' and u.at >= v_since),
      'blocked', security.link_search_block_v1(v_pid, v_ids));  -- hotfix D3
    if v_extra->'blocked' is not null and v_extra->'blocked' <> 'null'::jsonb then v_note := 'Blocked: ' || (v_extra->'blocked'->>'words') || '. ' || (v_extra->'blocked'->>'fix'); end if;$n$]],
  array[1]);

select pg_temp.edit_n('public.admin_jobs(text,jsonb)', 'e5c8f8447e33aacc176abc3a72a38e8a', array[
  array[$o$'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by)) order by j.created_at desc)$o$,
        $n$'requested_by_name', (select coalesce(u.email, j.requested_by::text) from auth.users u where u.id = j.requested_by), 'status', security.admin_job_status_v1(j.id)) order by j.created_at desc)$n$]],
  array[1]);

-- 6 Layer 4: a fee item's "Enter another address" goes through the standard bind path ----------------------------------------------------------
create or replace function security.layer4_fee_item_rebind_v1(p_item uuid, p_url text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_item pipeline.layer4_review_items%rowtype; v_url text := btrim(coalesce(p_url, '')); v_host text; v_dom text; v_pid uuid;
begin
  if auth.uid() is null then raise exception 'sign in required' using errcode = '42501'; end if;
  select * into v_item from pipeline.layer4_review_items where id = p_item for update;
  if v_item.id is null or v_item.status <> 'pending' then raise exception 'this item is no longer waiting (someone may have decided it)'; end if;
  if v_item.entity_type <> 'course' or v_item.field_code <> 'provider_current_tuition' then raise exception 'this choice is for a held fee only'; end if;
  if v_url !~* '^https://[^\s/]+\.[^\s]+$' then raise exception 'enter the full web address (https://…)'; end if;
  select c.provider_id into v_pid from catalogue.courses c where c.id = v_item.entity_id;
  v_host := lower(regexp_replace(substring(v_url from '^https://([^/:?#]+)'), '^www\.', ''));
  select lower(regexp_replace(substring(coalesce(p.website, '') from '^(?:https?://)?([^/:?#]+)'), '^www\.', '')) into v_dom from catalogue.providers p where p.id = v_pid;
  if coalesce(v_dom, '') <> '' and not (v_host = v_dom or v_host like '%.' || v_dom) then raise exception 'this page is not on the provider''s own website (%)', v_dom; end if;
  -- the standard path a person's page entry takes: manual binding and locks, read first in line, then the fee reader and the AI fill
  perform public.admin_course_edit(v_item.entity_id, 'set_official_url', jsonb_build_object('url', v_url, 'reason', left('Layer 4: ' || btrim(p_reason), 480)));
  update pipeline.layer4_review_items set status = 'edited_approved', decided_at = now() where id = v_item.id;
  insert into pipeline.layer4_decisions(review_item_id, action, actor_id, reason, before_value, proposed_value, final_value, evidence_id, layer2_state, layer3_state, change_control_ref)
  values (v_item.id, 'edit_and_approve', auth.uid(), btrim(p_reason), v_item.before_value, v_item.proposed_value, jsonb_build_object('course_url', v_url),
          v_item.evidence_id, v_item.layer2_state, v_item.layer3_state, coalesce(v_item.change_control_ref, 'CF-CHG-20260915-247') || '; hotfix D1 24 Oct 2026');
  return jsonb_build_object('ok', true, 'course_id', v_item.entity_id, 'url', v_url,
    'returns', 'The page is the course''s official page (a person''s value). It is read again first in line under the current page rule; the fee reader then reads it and the fee is admitted if the page states it.');
end $$;
comment on function security.layer4_fee_item_rebind_v1(uuid, text, text) is 'hotfix D1: a held-fee Layer 4 item takes a person''s course page address through admin_course_edit set_official_url (bind, lock, read, fee reader) and is closed as edited and approved';

select pg_temp.edit_n('public.admin_layer4_inbox(text,jsonb)', 'e78152ef7808c64ed99611fb4810843a', array[
  array[$o$  if v_kind = 'course_link' then
    v_r := public.layer4_review_decide($o$,
        $n$  -- 24 Oct 2026 (hotfix D1): a course-link row that holds a fee (identity re-verification quarantine, fee floor) is not a link decision
  if v_kind = 'course_link' and v_det->>'field_code' = 'provider_current_tuition' and v_choice in ('use', 'enter') then
    if v_choice = 'use' then raise exception 'this item holds a fee, not a new page: enter the course page''s address, or keep the page we hold'; end if;
    v_r := security.layer4_fee_item_rebind_v1(v_ref::uuid, v_value, v_reason);
  elsif v_kind = 'course_link' then
    v_r := public.layer4_review_decide($n$]],
  array[1]);

-- 7 the hourly taxonomy names the stall ------------------------------------------------------------------------------------------------------------
select pg_temp.edit_n('security.gap_causes_snapshot_v1()', 'e1fa25d8a5073bdf5b9dbf18174b7039', array[
  array[$o$declare v_at timestamptz := date_trunc('hour', now()); v int;$o$,
        $n$declare v_at timestamptz := date_trunc('hour', now()); v int; v_stopped uuid[] := array(select x.provider_id from security.fc_search_stopped_v1() x);$n$],
  array[$o$           g.status gs, g.read_status rs, g.identity_basis ib, s.state ls$o$,
        $n$           g.status gs, g.read_status rs, g.identity_basis ib, case when s.state = 'queued' and s.provider_id = any (v_stopped) then 'stopped' else s.state end ls$n$],
  array[$o$case when e.ls = 'queued' then 'no page: web search queued'$o$,
        $n$case when e.ls = 'stopped' then 'no page: web search stopped for this university' when e.ls = 'queued' then 'no page: web search queued'$n$],
  array[$o$           when z.cause like 'no page: web search queued' then 'web search for the course page (job link-search)'$o$,
        $n$           when z.cause = 'no page: web search stopped for this university' then 'none: the automatic search stopped (wrong pages in a row); Search again or a person''s Find course pages task'
           when z.cause like 'no page: web search queued' then 'web search for the course page (job link-search)'$n$],
  array[$o$'campus has no city', 'fee waiting in review')$o$,
        $n$'campus has no city', 'fee waiting in review', 'no page: web search stopped for this university')$n$]],
  array[1, 1, 1, 1, 1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.link_search_person_task_v1', 'Layer 2', 'a person''s Find course pages task row', 'active', '{}', '20261024009000'),
 ('function', 'security.link_search_block_v1', 'Layer 2', 'course-search stall cause (gate order)', 'active', '{}', '20261024009000'),
 ('function', 'security.admin_job_status_v1', 'Layer 2', 'task last progress, forwarded, next attempt, blocking reason', 'active', '{}', '20261024009000'),
 ('function', 'security.layer4_fee_item_rebind_v1', 'Layer 4', 'held-fee item: a person''s page address through the bind path', 'active', '{}', '20261024009000')
on conflict (kind, name) do nothing;

-- PASTE FILE — CF-247 HOTFIX v2.15.342, decision D-stopped (Platform Admin 24 Oct 2026 13:55)
-- Applied by: the Platform Admin, in the Supabase SQL editor of project fxcwkweaxjtknorudmwp, AFTER v2.15.342 (PR #686) is merged and live.
-- Record: docs/platform/ui-audit/2026-10-24-hotfix-manual-task-and-layer4-entry.md (section 11).
--
-- What it does: re-opens the person-requested course page searches that the search-stop list held (1,549 rows at 24 universities on
-- 24 Oct 13:40) by starting ONE "Find course pages" task per university for exactly those courses, as the Platform Admin. A person's
-- task passes the stop (search.person_task_bypass), so the rows go to the search; each task shows Last forwarded / Blocked in the Task
-- manager. Budgets, the month cap and the day share still apply (about 2 credits a search; today's share is far above 3,100).
-- It does NOT resume the universities' automatic search, change any gate, or delete anything.
-- Interim handling until S1 (per-course stop + negative evidence) lands; S1 is the permanent fix.
--
-- Count guards: the hotfix must be live; the rows to re-open must be no more than 1,549 at no more than these 24 universities (fewer is
-- fine: some may have been searched since, e.g. by the Otago E2E task); a university that already has a waiting or running Find course
-- pages task is skipped and counted. An unpublished or archived university is skipped and named (a task cannot start there): on 24 Oct
-- that is Nova Institute of Technology (16 rows), so 1,533 rows at 23 universities are re-opened.

do $p$
declare
  v_admin constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- Platform Admin
  v_list constant uuid[] := array[
    '570ddbbd-f07e-4060-b52d-c5322dcdaa00','1b8f2f2f-d3d2-455e-a9fd-5a65744352ec','22657140-1cb0-4fa7-91df-90518ea8b35b','188103a5-1aba-4f99-bd3e-0416659086d3',
    'bac82321-ded7-4e10-a71d-b18f3ae4d1c7','27349414-019b-4c0b-a38d-db92aaaf5e68','014118a6-54ea-4f36-ba05-a363b73b7979','0e1532b8-de30-4761-87fe-460684608633',
    'ab12c7f8-e368-453d-9dfe-4ab8bd744829','2a97c91d-9340-49fa-a437-6c76ea01edd9','3f48840c-8038-42a0-805e-8f7974301b23','5d21e4d4-73b4-4ad6-b100-199264540e72',
    '9e46baf2-694b-4d79-889e-b956d144c930','131ef262-b6e4-40a3-b8bf-7e4d6098eba8','8e1adb6c-e069-43db-9584-bd054255e702','d3f9ed02-2cca-4370-8070-7e52f381d1ba',
    '72a15f12-f3ee-40d7-8edf-af648ee10e14','ef420a23-6e62-47d3-9ab0-fdc35ebe97a0','dce6f5a7-c912-4a07-b9c6-7cf230a0e13b','47c734fe-9c1d-403f-b7cc-c4c77ad742fd',
    'a886a995-0315-4c92-9a74-697a2d0e014f','719403bc-6957-4d21-af69-2b3b102df578','cffa9cab-0a3b-458b-8383-483ce622c9c3','fac03540-a412-4c76-a5ab-cd338d7760db']::uuid[];
  v_rows int; v_provs int; r record; v jsonb; v_started int := 0; v_courses int := 0; v_skipped int := 0; v_hidden text := ''; v_failed text := '';
begin
  if to_regprocedure('security.link_search_person_task_v1(uuid,uuid)') is null
     or coalesce((select (value #>> '{}')::numeric from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'search.person_task_bypass'), 0) < 1 then
    raise exception 'v2.15.342 is not live (or search.person_task_bypass is off): merge PR #686 first';
  end if;
  select count(*), count(distinct s.provider_id) into v_rows, v_provs
    from pipeline.course_link_search s
   where s.state = 'queued' and s.requested_at is not null and s.provider_id = any (v_list)
     and s.provider_id in (select x.provider_id from security.fc_search_stopped_v1() x);
  if v_rows > 1549 or v_provs > 24 then raise exception 'count guard: expected at most 1,549 rows at 24 universities, found % at %', v_rows, v_provs; end if;
  if v_rows = 0 then raise exception 'count guard: nothing left to re-open (0 rows)'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  for r in select s.provider_id, array_agg(s.course_id) ids
             from pipeline.course_link_search s
            where s.state = 'queued' and s.requested_at is not null and s.provider_id = any (v_list)
              and s.provider_id in (select x.provider_id from security.fc_search_stopped_v1() x)
            group by s.provider_id loop
    if exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.provider_id) then
      v_hidden := v_hidden || (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = r.provider_id) || ' (' || cardinality(r.ids) || '); '; continue;
    end if;
    if exists (select 1 from pipeline.admin_jobs j where j.kind = 'course_page_find' and j.state in ('queued', 'running') and j.args->>'provider_id' = r.provider_id::text) then
      v_skipped := v_skipped + 1; continue;
    end if;
    begin
      v := public.admin_jobs('start', jsonb_build_object('kind', 'course_page_find',
             'args', jsonb_build_object('provider_id', r.provider_id, 'course_ids', to_jsonb(r.ids)),
             'reason', 'Hotfix D-stopped (24 Oct 2026): re-open the searches the stop list held'));
      v_started := v_started + 1; v_courses := v_courses + cardinality(r.ids);
    exception when others then v_failed := v_failed || r.provider_id || ': ' || sqlerrm || '; ';
    end;
  end loop;
  if v_failed <> '' then raise exception 'not applied (rolled back): %', v_failed; end if;
  raise exception 'DRYRUN OK Re-opened: % task(s), % course(s) (guard: % rows at % universities); % skipped (task already waiting or running); not started, unpublished: %', v_started, v_courses, v_rows, v_provs, v_skipped, coalesce(nullif(v_hidden, ''), 'none') || ' | picked now ' || jsonb_array_length(public.svc_course_link_search_next(200)) || ', tasks ' || (select count(*) from pipeline.admin_jobs where reason like '%Hotfix D-stopped%');
end $p$;

-- Check afterwards (expect the tasks running, rows moving from queued to sent within a few minutes):
