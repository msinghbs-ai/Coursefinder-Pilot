-- CF-247 StudySearch SS-014 D14 and monitoring accuracy (Platform Admin direction 2 Nov 2026 07:41, "Continuous Multi-Agent Engineering and
-- Production Closure" §4 and Agent A; admin docs/platform/nz-enrichment-brief/2026-11-02-continuous-multi-agent-delivery-direction.md).
-- Why (verified live, read-only, 2 Nov 2026; admin 2026-11-02-ss014-followup-0730.md §3 and 2026-11-02-ss015-gate-c-jobs.md §3 and the
-- integrator follow-up at 06:30):
--   1. D14. security.flag_jobs_v1 pauses a worker job whose last flag.empty_calls_to_pause (30) calls all found nothing. It takes the last 30
--      calls logged, then keeps only those with an answer. flag-recheck runs at :x0, the same second as coverage-ai-match (every minute,
--      answer in about 4.2 s), so the newest of the 30 never has an answer yet: the guard sees 29 and never pauses (56 empty calls in a row,
--      05:36 to 06:32, and no pause; about 1,440 avoidable calls a day).
--   2. Monitoring accuracy (P2). The 03:00 critical "Coverage page reading has stopped: 12 waiting" counted pages of hidden providers that
--      the reader never takes (10 of 12): the health check's read-queue rule and the watchdog's course_page_read count lack the reader's
--      hidden-provider and lease filters. The watchdog also called course_page_search "stuck" while the configured day's cap
--      (search.daily_picked_cap) held it.
-- What:
--   * security.flag_jobs_v1 (md5-guarded edit): only calls logged at least flag.answer_wait_seconds ago are counted (new setting, 120 s by
--     default: the time-out of a worker call, so every counted call has answered or timed out). The last 30 such calls must all have
--     answered and found nothing. Nothing else in the guard changes: the re-arm (a capped trial, or sooner when work waits) is as before.
--   * security.coverage_read_eligible_v1(): the pages public.svc_coverage_read_next would take now (its own conditions, without its per-call
--     size). The health check's read rule (count and stall age) and the watchdog's course_page_read count both read it.
--   * security.course_link_search_eligible_v1(): the queued searches public.svc_course_link_search_next would pick, without its per-call
--     size, its Firecrawl budget checks (shown as the tool's state) and the day's cap. The watchdog's course_page_search count reads it.
--   * security.course_link_search_cap_reason_v1() and pipeline.queue_watch.cap_sql (new column): a queue held by a configured cap is reported
--     as state 'capped' ("Paused: daily cap", with the figures and when picking resumes), not "stuck". No alert and no health issue.
--   * security.queue_watch_run_v1 (md5-guarded edit): reads cap_sql; the capped state; the health detail counts capped queues.
--   * security.platform_health_check_v1 (md5-guarded edit): the coverage page reading rule counts and ages only what the reader takes.
-- The two readers are not changed; their live md5s are checked so the counts are known to mirror the definitions they were written from.
-- Replaces: security.flag_jobs_v1, security.queue_watch_run_v1, security.platform_health_check_v1 (same names; md5-guarded edits); pipeline.queue_watch rows course_page_read and course_page_search (pending_sql, md5-guarded)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No job, schedule or batch size changes. Consumer API untouched (G3).

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

-- 0. the readers the counts mirror are the definitions they were written from (not changed here)
do $g$
begin
  if md5(pg_get_functiondef('public.svc_coverage_read_next(integer)'::regprocedure)) <> '2ac1114dd4a5da99d8ddb742f7d0c1be' then
    raise exception 'live public.svc_coverage_read_next differs from the reader security.coverage_read_eligible_v1 mirrors'; end if;
  if md5(pg_get_functiondef('public.svc_course_link_search_next(integer)'::regprocedure)) <> '00f7add9839d659f7dfc7efe6bd82216' then
    raise exception 'live public.svc_course_link_search_next differs from the picker security.course_link_search_eligible_v1 mirrors'; end if;
end $g$;

-- 1. setting (G2) ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'flag.answer_wait_seconds', 'Idle guard: a run counts once it is this old',
  'The idle guard pauses a worker job after its last runs all found nothing. It counts only runs started at least this long ago, so every counted run has answered (or timed out). A run still under way is never counted as empty. Keep it at or above the worker call time-out (120 seconds).',
  'number', to_jsonb(120), 10, 600, 'seconds', 786, 'Flags', 'security.flag_jobs_v1',
  'SS-014 D14 (Platform Admin 2 Nov 2026 07:41): the guard counted the run still under way and never reached 30')
on conflict (toolset_key, key) do nothing;

-- 2. D14: count only calls old enough to have answered ----------------------------------------------------------------------------------
select pg_temp.edit_once('security.flag_jobs_v1()', 'a7a7427b4caeea2fa62d017695c3b54e', '2421dd1c132bd6460aa12c8dbdce3fa6', array[
 array[$o$        v_need int := security.pipeline_num_v1('flag.empty_calls_to_pause', 30)::int;$o$,
       $n$        v_need int := security.pipeline_num_v1('flag.empty_calls_to_pause', 30)::int;
        -- SS-014 D14 (2 Nov 2026): only calls old enough to have answered are counted; the call still under way is never one of the last runs
        v_answered timestamptz := now() - make_interval(secs => security.pipeline_num_v1('flag.answer_wait_seconds', 120));$n$],
 array[$o$and l2.created_at > coalesce(f.released_at, '-infinity')$o$,
       $n$and l2.created_at > coalesce(f.released_at, '-infinity') and l2.created_at <= v_answered$n$]],
 array[1, 1]);

-- 3. what the readers take ----------------------------------------------------------------------------------------------------------------
create or replace function security.coverage_read_eligible_v1()
returns table(course_id uuid, provider_id uuid, due_at timestamptz)
language sql stable security definer set search_path to '' as $$
  -- SS-014 P2 (2 Nov 2026): the pages public.svc_coverage_read_next takes now, by its own conditions (hidden providers and leased pages left
  -- out), without its per-call size. due_at: when the page became due (for the stall age).
  select p.course_id, p.provider_id, coalesce(p.next_read_at, p.bound_at)
    from pipeline.coverage_course_pages p
   where p.status in ('bound','ambiguous') and coalesce(p.next_read_at,now())<=now() and coalesce(p.leased_until,'-infinity')<now() and p.read_attempts<3
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)
$$;
revoke all on function security.coverage_read_eligible_v1() from public, anon, authenticated;
comment on function security.coverage_read_eligible_v1() is 'SS-014 P2 (2 Nov 2026): the course pages the reader (svc_coverage_read_next) would take now; read by the health check''s coverage page reading rule and the watchdog''s course_page_read count';

create or replace function security.course_link_search_eligible_v1()
returns table(course_id uuid, provider_id uuid, requested boolean)
language sql stable security definer set search_path to '' as $$
  -- SS-014 P2 (2 Nov 2026): the queued searches public.svc_course_link_search_next would pick, by its own conditions in its own order, without
  -- its per-call size, its Firecrawl budget checks (the watchdog shows those as the tool's state) and the day's picked-courses cap
  -- (security.course_link_search_cap_reason_v1).
  with prov as materialized (
    select q.provider_id,
           security.enrich_focus_v1(q.provider_id) focus,
           security.site_few_course_pages_v1(q.provider_id) few,
           security.site_not_checked_v1(q.provider_id) unchecked,
           exists (select 1 from pipeline.provider_onboarding o
                    where o.provider_id = q.provider_id and o.source in ('backfill', 'new_provider')
                      and not exists (select 1 from pipeline.firecrawl_search_resumes r where r.provider_id = q.provider_id and r.resumed_at > o.created_at)) bulk,
           (q.provider_id = any (array(select x.provider_id from security.fc_search_stopped_v1() x))) stopped
      from (select distinct s0.provider_id from pipeline.course_link_search s0 where s0.state = 'queued') q
      join pipeline.course_link_recipes rc on rc.provider_id = q.provider_id and rc.active
     where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)
       and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)
            or exists (select 1 from pipeline.firecrawl_target_cache tc where tc.provider_id = q.provider_id and tc.included))
       and not security.third_party_host_v1('https://' || rc.search_domain)
       and not exists (select 1 from catalogue.providers px, pipeline.platform_toolset_settings sk
                        where px.id = q.provider_id and sk.toolset_key = 'pipeline' and sk.key = 'search.skip_providers' and sk.value ? px.stable_key)),
  v as (select security.pipeline_num_v1('search.person_task_bypass', 1) >= 1 person)
  select s.course_id, s.provider_id, s.requested_at is not null
    from pipeline.course_link_search s join prov pv on pv.provider_id = s.provider_id
    join catalogue.courses c on c.id = s.course_id
    cross join v
   where s.state = 'queued'
     and security.search_stop_gate_v1(s.provider_id, s.course_id, pv.stopped) is null
     and (pv.focus or s.requested_at is not null)
     and case when s.requested_at is not null and (not pv.bulk or (v.person and security.link_search_person_task_v1(s.provider_id, s.course_id))) then true
              when pv.few or pv.unchecked then false
              else security.site_list_match_done_v1(s.course_id, s.provider_id) end
$$;
revoke all on function security.course_link_search_eligible_v1() from public, anon, authenticated;
comment on function security.course_link_search_eligible_v1() is 'SS-014 P2 (2 Nov 2026): the queued course page searches the picker (svc_course_link_search_next) would pick, cap and budget aside; read by the watchdog''s course_page_search count';

create or replace function security.course_link_search_cap_reason_v1() returns text
language plpgsql stable security definer set search_path to '' as $$
declare v_cap int := security.pipeline_num_v1('search.daily_picked_cap', 100)::int; v_n int;
        v_day timestamptz := date_trunc('day', now() at time zone 'UTC') at time zone 'UTC';  -- fixed: the UTC day the picker counts
begin
  -- SS-014 P2 (2 Nov 2026): the picker's own day count; null while there is room
  select count(*) into v_n from pipeline.course_link_search where sent_at >= v_day;
  if v_cap - v_n > 0 then return null; end if;
  -- over the cap the picker still takes a person's running Find course pages task: that is not a pause
  if security.pipeline_num_v1('search.person_task_bypass', 1) >= 1
     and exists (select 1 from security.course_link_search_eligible_v1() e where security.link_search_person_task_v1(e.provider_id, e.course_id)) then return null; end if;
  return format('Paused: daily cap. %s of %s courses picked today (setting search.daily_picked_cap, counted per UTC day); picking resumes at %s', v_n, v_cap,
                to_char((v_day + interval '1 day') at time zone 'Australia/Melbourne', 'DD Mon HH24:MI'));  -- fixed: the next UTC day
end $$;
revoke all on function security.course_link_search_cap_reason_v1() from public, anon, authenticated;
comment on function security.course_link_search_cap_reason_v1() is 'SS-014 P2 (2 Nov 2026): why course page search is paused by its configured day''s cap (search.daily_picked_cap), or null; the watchdog''s course_page_search cap_sql';

-- 4. the watchdog: a configured cap is a pause, not "stuck" -------------------------------------------------------------------------------
alter table pipeline.queue_watch add column if not exists cap_sql text;
comment on column pipeline.queue_watch.cap_sql is 'SS-014 P2 (2 Nov 2026): returns a reason when a configured cap holds the queue (state capped, "Paused: daily cap"), else null; null for queues without a cap';
comment on table pipeline.queue_watch_state is 'CF-247 22 Oct 2026 (progress watchdog): the latest state of each watched queue (moving, waiting, stuck, failing, out_of_toolset, nothing_left, done, paused, capped) with the figures behind it. capped (SS-014 P2, 2 Nov 2026): held by a configured cap such as search.daily_picked_cap.';

select pg_temp.edit_once('security.queue_watch_run_v1(boolean)', '59c67cf1b496ab43c11c82491962b418', '5735193b0d93f4764502504617c55687', array[
 array[$o$v_tool text; v_ts text; v_fixed int; v_err text;$o$, $n$v_tool text; v_ts text; v_fixed int; v_err text; v_cap text;$n$],
 array[$o$v_last := null; v_state := null; v_reason := null;$o$, $n$v_last := null; v_state := null; v_reason := null; v_cap := null;$n$],
 array[$o$      execute q.exhausted_sql into v_exh;$o$, $n$      execute q.exhausted_sql into v_exh;
      if q.cap_sql is not null then execute q.cap_sql into v_cap; end if;  -- SS-014 P2 (2 Nov 2026): a configured cap holding the queue$n$],
 array[$o$        v_state := 'paused'; v_reason := 'Switched off by a person: ' || array_to_string(v_paused, ', ');$o$,
       $n$        v_state := 'paused'; v_reason := 'Switched off by a person: ' || array_to_string(v_paused, ', ');
      elsif v_pending > 0 and v_cap is not null then
        v_state := 'capped'; v_reason := v_cap;  -- SS-014 P2 (2 Nov 2026): "Paused: daily cap", not stuck; no alert, no health issue$n$],
 array[$o$'paused', count(*) filter (where s.state = 'paused'))$o$, $n$'paused', count(*) filter (where s.state = 'paused'), 'paused_daily_cap', count(*) filter (where s.state = 'capped'))$n$]],
 array[1, 1, 1, 1, 1]);

-- the two queues count what their readers take (md5-guarded on the text they replace)
do $q$
declare v_read text := 'select count(*) from security.coverage_read_eligible_v1()';
        v_search text := 'select count(*) from security.course_link_search_eligible_v1()';
        v_cap text := 'select security.course_link_search_cap_reason_v1()';
begin
  if (select md5(pending_sql) from pipeline.queue_watch where key = 'course_page_read') not in ('faa7842a12313124d61630df63e645b5', md5(v_read)) then
    raise exception 'live queue_watch course_page_read pending_sql differs from the text this change replaces'; end if;
  if (select md5(pending_sql) from pipeline.queue_watch where key = 'course_page_search') not in ('78fb16558e148e54c6ff7537d72e1692', md5(v_search)) then
    raise exception 'live queue_watch course_page_search pending_sql differs from the text this change replaces'; end if;
  update pipeline.queue_watch set pending_sql = v_read where key = 'course_page_read';
  update pipeline.queue_watch set pending_sql = v_search, cap_sql = v_cap where key = 'course_page_search';
end $q$;

-- 5. the health check's coverage page reading rule counts and ages only what the reader takes ---------------------------------------------
select pg_temp.edit_once('security.platform_health_check_v1(boolean)', '964db44f6fbcf2cf4c6e6463f4860b40', '25ff04344e2a940a3132e7ba709f98aa', array[
 array[$o$      select greatest(max(read_at), (select min(coalesce(q.next_read_at, q.bound_at)) from pipeline.coverage_course_pages q
                                      where q.status in ('bound','ambiguous') and coalesce(q.next_read_at,now())<=now() and q.read_attempts<3)) into v_ts from pipeline.coverage_course_pages;$o$,
       $n$      -- SS-014 P2 (2 Nov 2026): waiting means what the reader takes (security.coverage_read_eligible_v1: hidden providers and leased pages left out)
      select greatest(max(read_at), (select min(e.due_at) from security.coverage_read_eligible_v1() e)) into v_ts from pipeline.coverage_course_pages;$n$],
 array[$o$        $q$select count(*) from pipeline.coverage_course_pages p where p.status in ('bound','ambiguous') and coalesce(p.next_read_at,now())<=now() and p.read_attempts<3$q$);$o$,
       $n$        $q$select count(*) from security.coverage_read_eligible_v1()$q$);  -- SS-014 P2 (2 Nov 2026): the same pages the reader takes$n$]],
 array[1, 1]);

-- 6. register --------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.coverage_read_eligible_v1', 'Platform', 'Platform upkeep', 'SS-014 P2: the course pages the reader takes now; the health check and watchdog count them', 'active', '{}', '20261102040000'),
 ('function', 'security.course_link_search_eligible_v1', 'Platform', 'Platform upkeep', 'SS-014 P2: the course page searches the picker would pick; the watchdog counts them', 'active', '{}', '20261102040000'),
 ('function', 'security.course_link_search_cap_reason_v1', 'Platform', 'Platform upkeep', 'SS-014 P2: course page search paused by its configured day''s cap', 'active', '{}', '20261102040000')
on conflict do nothing;

-- 7. post-check ------------------------------------------------------------------------------------------------------------------------
do $post$
declare v_reader text := pg_get_functiondef('public.svc_coverage_read_next(integer)'::regprocedure);
begin
  -- the read count's conditions are the reader's, word for word
  if position($p$where p.status in ('bound','ambiguous') and coalesce(p.next_read_at,now())<=now() and coalesce(p.leased_until,'-infinity')<now() and p.read_attempts<3$p$ in v_reader) = 0
     or position($p$and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)$p$ in v_reader) = 0 then
    raise exception 'SS-014 post-check: the reader''s conditions are not the ones the read count uses'; end if;
  if (select pending_sql from pipeline.queue_watch where key = 'course_page_read') <> 'select count(*) from security.coverage_read_eligible_v1()'
     or (select cap_sql from pipeline.queue_watch where key = 'course_page_search') <> 'select security.course_link_search_cap_reason_v1()' then
    raise exception 'SS-014 post-check: watchdog queues'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'flag.answer_wait_seconds' and label is not null and unit = 'seconds' and used_by is not null) then
    raise exception 'SS-014 post-check: setting flag.answer_wait_seconds'; end if;
end $post$;
