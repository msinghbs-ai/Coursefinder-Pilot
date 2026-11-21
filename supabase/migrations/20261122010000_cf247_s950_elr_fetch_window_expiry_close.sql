-- CF-247 s950 (session S1-ELR, Platform Admin 21 Nov 2026 18:15 AEDT: "ship that small fetch-window timeout fix now as a logic-only guard"): the one-off fetch of
-- central English pages (s907, s926) closes its on-demand request when the request's window times out, not only when its queue is empty.
-- English language requirements only.
--
-- Found (read live, rolled back, 21 Nov 2026 18:20 AEDT; proof: an expired request with 2 queued pages stayed open under the old run, and the new run closed it with left_queued 2, nothing sent; a second run did nothing): step 7 of security.elr_det_sweep_tick_v1() closes an open fetch request only when none of its pages is
-- queued or in flight. security.elr_central_fetch_claim_v1 sends nothing for a request whose expires_at has passed, so a request that times out with pages still
-- queued is never closed: it stays open past its time with no report of its use, and its queued pages are never sent (the s907 request needed a migration, s926).
-- Today nothing is affected: request c48a9a42 (s926) closed at 13:02 AEDT with 52 Firecrawl units, 50 pages stored, 2 failed; no fetch request is open.
--
-- What changes (live on deploy, the next elr-det-sweep run):
--   step 7 also closes an open fetch request whose window has timed out, once none of its pages is in flight, through security.on_demand_close_v1 (report kept).
--   Pages it left queued stay queued (a person reopens them, as s926 did) and are counted in its report (closed_by window_expired, left_queued).
-- No new fetch request is opened and nothing is sent: $0 Firecrawl, $0 AI. The 52 central English pages are already fetched.
-- G1: no new job. G2: no new value (the window length is the existing ondemand.window_hours). G3 stays 75/48.
-- Parity: head 20261121235000 read live 21 Nov 2026 18:20 AEDT; no open migration; this file is numbered strictly above it.
-- Replaces: the queue-empty-only close of the s907 fetch request (same close, plus the timed-out window).
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';
set local statement_timeout = '60s';  -- fixed: the post-check reads the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s950_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s950_cron on commit drop as select count(*) n from cron.job where active;
create temp table s950_od on commit drop as select count(*) n from pipeline.on_demand_requests;

-- literal edits of the live definition, guarded by its md5 before and after
create or replace function pg_temp.edit_lit(p_sig text, p_before text, p_after text, p_edits text[][]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if p_after is not null and md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if p_after is not null and md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied ' || md5(pg_get_functiondef(p_sig::regprocedure));
end $f$;

select pg_temp.edit_lit('security.elr_det_sweep_tick_v1()', '602ee934e953fefcf467a7d06257fe79', '2a09bbdb08e77eeeb01917c854272b71', array[
  array[$o$ap record; v_ap jsonb; v_l4 int;$o$,
        $n$ap record; v_ap jsonb; v_l4 int; v_left int := 0;$n$],
  array[$o$      -- nothing left to send for an open request: close it and keep its report (actual use and the credit left)
      for v_od in select distinct f.on_demand_id from pipeline.elr_central_fetches f join pipeline.on_demand_requests r on r.id = f.on_demand_id
                   where r.state = 'open' and not exists (select 1 from pipeline.elr_central_fetches g where g.on_demand_id = f.on_demand_id and g.status in ('queued', 'sent')) loop
        insert into pipeline.elr_central_fetch_state as s (on_demand_id, closed_at, report) values (v_od, now(), security.on_demand_close_v1(v_od))
        on conflict (on_demand_id) do update set closed_at = now(), report = excluded.report;
        v_c := v_c || jsonb_build_object('central_fetch_closed', v_od);$o$,
        $n$      -- nothing left to send for an open request: close it and keep its report (actual use and the credit left)
      -- s950: a request whose window has timed out (expires_at passed) is closed too once none of its pages is in flight; the pages it left queued stay queued
      --       for a person to reopen (s926) and are counted in its report, so no fetch request stays open past its window
      for v_od in select distinct f.on_demand_id from pipeline.elr_central_fetches f join pipeline.on_demand_requests r on r.id = f.on_demand_id
                   where r.state = 'open'
                     and not exists (select 1 from pipeline.elr_central_fetches g where g.on_demand_id = f.on_demand_id and g.status = 'sent')
                     and (r.expires_at <= now() or not exists (select 1 from pipeline.elr_central_fetches g where g.on_demand_id = f.on_demand_id and g.status = 'queued')) loop
        select count(*) into v_left from pipeline.elr_central_fetches g where g.on_demand_id = v_od and g.status = 'queued';
        insert into pipeline.elr_central_fetch_state as s (on_demand_id, closed_at, report)
        values (v_od, now(), security.on_demand_close_v1(v_od) || case when v_left > 0 then jsonb_build_object('closed_by', 'window_expired', 'left_queued', v_left) else '{}'::jsonb end)
        on conflict (on_demand_id) do update set closed_at = now(), report = excluded.report;
        v_c := v_c || jsonb_build_object('central_fetch_closed', v_od) || case when v_left > 0 then jsonb_build_object('central_fetch_left_queued', v_left) else '{}'::jsonb end;$n$]
]);

comment on function security.elr_det_sweep_tick_v1() is 'CF-247 s842, s886, s896, s904 to s907, s910, s913, s950 (a fetch request whose window has timed out is closed with its report once none of its pages is in flight; pages it left queued stay queued for a person to reopen; a fetch call the worker did not run goes back to the queue; each answer is recorded on its own; one that fails is marked failed and the run goes on): one run of the job elr-det-sweep. Also keeps the values central pages give each named English band (s905), reads the band named on course pages of those universities (worker mode elr_band_read, security.elr_band_record_v1), and runs the one-off bounded fetch of known central English pages under its on-demand request (worker mode elr_central_fetch, s907). Also reads stored central English pages (security.elr_central_claim_v1, worker mode elr_central_read, security.elr_central_record_v1), applies approved elr-central policies a few a run and sends their regulated-discipline holds to Layer 4. Reads back the worker''s answers (pg_net) and records them through security.elr_det_record_v1, gives up calls with no answer in time, then sends the next indexed batch of gap course pages to the coverage-sweep worker (mode elr_det_read). $0: no model, no Firecrawl.';

do $c$
declare v_api jsonb; v_def text := pg_get_functiondef('security.elr_det_sweep_tick_v1()'::regprocedure);
begin
  if position('r.expires_at <= now() or not exists' in v_def) = 0 then raise exception 'post-check: the timed-out window close is not in the sweep'; end if;
  if (select count(*) from pipeline.on_demand_requests) <> (select n from s950_od) then raise exception 'post-check: an on-demand request was opened'; end if;
  if (select count(*) from cron.job where active) <> (select n from s950_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s950_locks) then raise exception 'post-check: the manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  raise notice 's950: fetch requests open %, fetch queue %', (select count(*) from pipeline.on_demand_requests r where r.state = 'open' and r.id in (select on_demand_id from pipeline.elr_central_fetches)),
    (select jsonb_object_agg(status, n) from (select status, count(*) n from pipeline.elr_central_fetches group by 1) x);
end $c$;
