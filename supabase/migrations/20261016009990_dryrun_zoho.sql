-- CF-247 HOTFIX 2 (24 Oct 2026, v2.15.343). Found in the v2.15.342 post-merge check (Platform Admin 13:55 step 2, record: admin repo
-- docs/platform/ui-audit/2026-10-24-hotfix-manual-task-and-layer4-entry.md section 12): the Otago task was forwarded at accept
-- (worker picked 58 at 03:19:29 UTC) but searched 0 every minute. The worker asks the database for each credit (public.svc_fc_spend),
-- and that check carries a third copy of the search-stop gate: it refused every course-search credit for a stopped university
-- (406 refusals for Otago on 24 Oct, reason search_stopped), and the worker gave each row back to the queue as "credit budget".
-- The v2.15.342 dry run proved accept → picker but did not run the worker's spend step.
-- Fix: the same on-demand bypass as the picker (search.person_task_bypass): while a person's Find course pages task for the university
-- is waiting or running, the stop does not refuse its course-search credit. The day share, the day total, the month cap, the account
-- reserve and the target-only rule still apply (unchanged). The other functions that read the stop only report it.
-- Replaces: nothing (public.svc_fc_spend and security.admin_job_status_v1 edited in place, md5-guarded)
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

select pg_temp.edit_n('public.svc_fc_spend(numeric,text,uuid,text)', '22dda25276ec8b6c25889404f7e2802e', array[
  array[$o$    elsif p_provider_id is not null and v_grp = 'course_search' and security.fc_search_stopped_for_v1(p_provider_id) then$o$,
        $n$    elsif p_provider_id is not null and v_grp = 'course_search' and security.fc_search_stopped_for_v1(p_provider_id)
          -- 24 Oct 2026 (hotfix 2): a person's waiting or running Find course pages task passes the stop here too, as in the picker
          and not (security.pipeline_num_v1('search.person_task_bypass', 1) >= 1
                   and exists (select 1 from pipeline.admin_jobs j where j.kind = 'course_page_find' and j.state in ('queued', 'running')
                                  and j.args->>'provider_id' = p_provider_id::text)) then$n$]],
  array[1]);

-- D3 follow-up: "forwarded" alone hid this stall (the Task manager showed Last forwarded each minute and no block while every credit was
-- refused). For Find course pages the stall clock now follows credits actually spent, and a credit refusal since the task started is its
-- blocking reason, ahead of the gate walk.
select pg_temp.edit_n('security.admin_job_status_v1(uuid)', 'f75ed9089f125deb7c5c038a2194b41e', array[
  array[$o$v_sent int; v_waiting int;$o$, $n$v_sent int; v_waiting int; v_spent timestamptz; v_refused record;$n$],
  array[$o$    if v_fwd < j.created_at then v_fwd := null; end if;$o$,
        $n$    if v_fwd < j.created_at then v_fwd := null; end if;
    select max(u.at) into v_spent from pipeline.coverage_vendor_usage u where u.provider_id = v_pid and u.purpose = 'course_link_search' and u.at >= j.created_at;
    select r.reason, r.n, r.last_at into v_refused from pipeline.firecrawl_refusals_by_provider r
     where r.provider_id = v_pid and r.grp = 'course_search' and r.last_at >= j.created_at and r.last_at > coalesce(v_spent, '-infinity')
     order by r.last_at desc limit 1;$n$],
  array[$o$  if j.state = 'running' and now() - greatest(coalesce(v_fwd, '-infinity'), v_last) > make_interval(secs => v_stall) then$o$,
        $n$  if j.state = 'running' and now() - greatest(coalesce(case when j.kind = 'course_page_find' then v_spent else v_fwd end, '-infinity'), v_last) > make_interval(secs => v_stall) then$n$],
  array[$o$      v_block := coalesce(security.link_search_block_v1(v_pid, v_ids),$o$,
        $n$      v_block := coalesce(case when v_refused.reason is not null then jsonb_build_object('code', 'credit_refused',
                            'words', 'Sent to the search, but its credits were refused (' || replace(v_refused.reason, '_', ' ') || ', ' || v_refused.n || ' time(s) today)',
                            'fix', 'Models & services › Toolsets & limits › Firecrawl') end,
                          security.link_search_block_v1(v_pid, v_ids),$n$],
  array[$o$'forwarded', v_sent,$o$, $n$'forwarded', v_sent, 'last_spent_at', v_spent,$n$]],
  array[1, 1, 1, 1, 1]);

update pipeline.platform_toolset_settings set used_by = 'public.svc_course_link_search_next, public.svc_fc_spend'
 where toolset_key = 'pipeline' and key = 'search.person_task_bypass' and used_by = 'public.svc_course_link_search_next';

do $t$ declare v_before jsonb := security.admin_job_status_v1('a4ec5237-d663-48d7-8d1e-f68ba15c105f'); begin raise exception 'DRYRUN OK %', jsonb_build_object(
  'otago_spend', public.svc_fc_spend(2, 'course_link_search', 'ab12c7f8-e368-453d-9dfe-4ab8bd744829'::uuid, '"x" site:otago.ac.nz'),
  'humber_spend_no_task', public.svc_fc_spend(2, 'course_link_search', '570ddbbd-f07e-4060-b52d-c5322dcdaa00'::uuid, '"x" site:humber.ca'),
  'otago_status_now', v_before - 'runner_last_run' - 'next_attempt_at'); end $t$;
