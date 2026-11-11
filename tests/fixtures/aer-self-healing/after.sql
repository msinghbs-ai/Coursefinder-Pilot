\set ON_ERROR_STOP on
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
do $$ declare t jsonb; n int; begin
  perform pg_temp.ok((select eligible and outcome = 'held: read again (D-R2)' from security.aer_schedule_held_v1(10) where item_id = '5a000000-0000-0000-0000-00000000000a'),
    'after: A (cut, limit raised, rule eligible, check passes) is read again');
  perform pg_temp.ok((select not eligible and outcome like 'held, not read again: row_limit (read the entry matrix)%' from security.aer_schedule_held_v1(10) where item_id = '5a000000-0000-0000-0000-00000000000b'),
    'after: B (cut under the same limit) is not read again and carries the rule''s class and next action');
  perform pg_temp.ok((select not eligible and outcome = 'held only for rows a person leaves out' from security.aer_schedule_held_v1(10) where item_id = '5a000000-0000-0000-0000-00000000000c'),
    'after: C (nothing cut, nothing dropped) is unchanged');
  update fx.item_state set check_ok = false where item_id = '5a000000-0000-0000-0000-00000000000a';
  perform pg_temp.ok((select not eligible and outcome like 'held, not correctable: fixture%' from security.aer_schedule_held_v1(10) where item_id = '5a000000-0000-0000-0000-00000000000a'),
    'after: an eligible cut read is still refused when the correction check fails');
  update fx.item_state set check_ok = true where item_id = '5a000000-0000-0000-0000-00000000000a';
  t := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok(t->>'refusal' is null and (t->>'corrections')::int = 1 and (t->>'course_reads')::int = 0 and (t->>'corrections_room')::int = 10,
    'after: with the new-read cap used, the corrected read still runs on its own allowance; no new read starts');
  perform pg_temp.ok((t->>'used_24h')::int = 200 and (t->>'corrections_used_24h')::int = 0 and (t->>'corrections_daily_max')::int = 100, 'after: the two allowances are counted apart (default 100)');
  update pipeline.platform_toolset_settings set value = '0' where key = 'aer.schedule_correction_daily_max';
  t := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok(t->>'refusal' = 'the daily cap is reached' and (t->>'corrections')::int = 0, 'after: allowance 0 stops corrected reads (reversal without code)');
  update pipeline.platform_toolset_settings set value = '100' where key = 'aer.schedule_correction_daily_max';
  insert into pipeline.aer_schedule_runs(ran_at, course_reads, corrections) values (now() - interval '1 hour', 0, 95);
  t := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok((t->>'corrections_room')::int = 5, 'after: a run reads again at most what is left of the 24-hour allowance');
  delete from pipeline.aer_schedule_runs where corrections = 95;
  -- back-pressure still stops new reads, and corrected reads still run under it (they replace a waiting item)
  update pipeline.platform_toolset_settings set value = '1' where key = 'aer.schedule_layer4_max';
  delete from pipeline.aer_schedule_runs;
  t := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok((t->>'back_pressure')::boolean and (t->>'course_reads')::int = 0 and (t->>'corrections')::int = 1, 'after: under back-pressure no new read, the corrected read runs');
  -- a real run: one corrected read asked, recorded on the run row
  t := security.aer_schedule_tick_v1(false);
  perform pg_temp.ok((select corrections from pipeline.aer_schedule_runs order by id desc limit 1) = 1 and (select detail->>'corrections_daily_max' from pipeline.aer_schedule_runs order by id desc limit 1) = '100',
    'after: the run row records the corrected read and the allowance');
end $$;
