\set ON_ERROR_STOP on
create or replace function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $$;
do $$ declare t jsonb; begin
  perform pg_temp.ok((select outcome from security.aer_schedule_held_v1(10) where item_id = '5a000000-0000-0000-0000-00000000000a') = 'cut at the row limit: for a person',
    'before: a cut read the recovery rule makes eligible is sent to a person (the live defect)');
  t := security.aer_schedule_tick_v1(true);
  perform pg_temp.ok(t->>'refusal' = 'the daily cap is reached' and (t->>'corrections')::int = 0, 'before: 200 new reads used the shared cap, so no corrected read runs (the live defect)');
end $$;
