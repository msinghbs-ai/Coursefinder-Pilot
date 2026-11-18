-- CF-247 s710 (follow-up): the round-state refresh has one caller, rollup-scheduler (S2-Build; Platform Admin 19 Nov 2026 05:21, item 5:
-- "Wire scholarship open/closed status evaluation onto rollup-scheduler using Australia/Melbourne dates (replacing the paused UTC trigger)").
--
-- What was read live (19 Nov 2026 05:40 AEDT): since 20261119041000 the rollup-scheduler target scholarship-round-state-refresh refreshes
-- round states hourly at :23 on the Melbourne date (first run 04:23 AEDT, succeeded). The paused cron job scholarship-discover-refill
-- (active = false) still calls security.scholarship_discovery_refill_v1, which ends with its own call to the refresh: that was the only caller
-- before (it last ran 17 Nov 00:23 UTC). If the refill job were switched back on, the round states would be refreshed twice an hour.
--
-- What it changes (one existing function, md5-guarded single edit; no new table or function; G3 untouched at 75 and 48):
--   * security.scholarship_discovery_refill_v1 no longer refreshes round states; its result keeps the key round_states (null) with a note
--     naming the target. Candidate refill, cadence and skip rules are unchanged. The job stays as it is (paused); nothing is switched on or off.
-- Nothing is dropped or deleted.
-- Replaces: the round-state refresh inside security.scholarship_discovery_refill_v1 (job scholarship-discover-refill, UTC date) with the
--   rollup-scheduler target scholarship-round-state-refresh (Melbourne date, 20261119041000).
-- Retires: nothing (the function and the job stay; the job was already off).

create or replace function pg_temp.cf_edit(p_sig regprocedure, p_md5 text, p_old text, p_new text, p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_c int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(replace(v_src, p_old, p_new)) then
    raise exception '% after the edit is not the expected body', p_sig;
  end if;
end $f$;

select pg_temp.cf_edit('security.scholarship_discovery_refill_v1(integer)'::regprocedure, '23518747b890c71110556c84301e71d2',
  $o$  v_round := security.scholarship_round_state_refresh_v1(security.pipeline_num_v1('batch.scholarship_round_state', 1000)::int);$o$,
  $n$  -- 20261119052000: round states moved to the rollup-scheduler target scholarship-round-state-refresh (Melbourne date, 20261119041000)
  v_round := null;$n$,
  '20261119052000: round states moved');

-- post-checks (rolled back with the dry run if any fails)
do $chk$
declare v_drift jsonb;
begin
  if exists (select 1 from pg_proc p where p.prosrc ilike '%scholarship_round_state_refresh_v1(%' and p.proname <> 'scholarship_round_state_refresh_v1') then
    raise exception 'post-check: a function other than the target still calls the round-state refresh';
  end if;
  if not exists (select 1 from pipeline.rollup_targets where target_code = 'scholarship-round-state-refresh' and enabled and mode = 'live') then
    raise exception 'post-check: the rollup-scheduler target is not live';
  end if;
  v_drift := security.consumer_api_check_v1();
  if jsonb_typeof(v_drift) = 'array' then
    if jsonb_array_length(v_drift) > 0 then raise exception 'consumer API drift %', v_drift; end if;
  elsif jsonb_array_length(coalesce(v_drift->'drift', '[]'::jsonb)) > 0 then raise exception 'consumer API drift %', v_drift->'drift';
  end if;
end $chk$;
