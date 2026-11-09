-- Guards: F-INT D3 forward fix (Platform Admin decision 9 Nov 2026): after migration 20261109170000 was applied a SECOND time (no change, no new batch), forward recovery of batch 1:
-- rows still holding exactly the value the backfill set are restored to the value before; a row that changed since is left as it is and recorded; running the undo again changes nothing.
\set ON_ERROR_STOP on
\set QUIET on
do $$
declare b1 uuid := (select batch_id from pipeline.intake_revisit_backfill_batches); r jsonb; ea uuid := (select intake_id from public.rb_cases where name = 'edited_since_a'); eb uuid := (select intake_id from public.rb_cases where name = 'edited_since_b');
        n_log int; n_bad int; va timestamptz; st text;
begin
  if (select count(*) from pipeline.intake_revisit_backfill_batches) <> 1 then raise exception 'the second application made a batch'; end if;
  if exists (select 1 from public.rb_diff('after_first')) then raise exception 'the second application changed % rows', (select count(*) from public.rb_diff('after_first')); end if;
  raise notice 'PASS idempotent: the migration applied a second time changed no row, made no batch and no log row (the original rows now have a time, so no row is a candidate)';
  select count(*) into n_log from pipeline.intake_revisit_backfill_log where batch_id = b1;
  -- two rows are decided again after the backfill: one gets another time, one loses its time
  update pipeline.course_intake_dates set next_revisit_at = next_revisit_at + interval '1 day' where intake_id = ea;
  update pipeline.course_intake_dates set next_revisit_at = null where intake_id = eb;
  select next_revisit_at into va from pipeline.course_intake_dates where intake_id = ea;
  insert into public.rb_snap select 'before_undo', d.intake_id, to_jsonb(d)::text from pipeline.course_intake_dates d;
  r := security.intake_revisit_backfill_undo_v1(b1);
  if (r->>'restored')::int <> n_log - 2 or (r->>'skipped_changed_since')::int <> 2 or r->>'status' <> 'partly_undone' then raise exception 'undo result %', r; end if;
  -- restored rows are exactly the rows before the backfill (whole-row equality with the seeded snapshot); the two changed rows keep what they hold
  select count(*) into n_bad from pipeline.intake_revisit_backfill_log g join public.rb_snap s on s.label = 'seeded' and s.intake_id = g.intake_id join pipeline.course_intake_dates d on d.intake_id = g.intake_id
   where g.batch_id = b1 and g.undo_outcome = 'restored' and s.row_text <> to_jsonb(d)::text;
  if n_bad <> 0 then raise exception '% restored rows differ from their state before the backfill', n_bad; end if;
  if (select next_revisit_at from pipeline.course_intake_dates where intake_id = ea) is distinct from va or (select next_revisit_at from pipeline.course_intake_dates where intake_id = eb) is not null then raise exception 'a changed row was overwritten'; end if;
  if (select undo_outcome from pipeline.intake_revisit_backfill_log where batch_id = b1 and intake_id = ea) <> 'skipped_changed' or (select undo_outcome from pipeline.intake_revisit_backfill_log where batch_id = b1 and intake_id = eb) <> 'skipped_changed' then raise exception 'outcome'; end if;
  if exists (select 1 from pipeline.intake_revisit_backfill_log where batch_id = b1 and undone_at is null) then raise exception 'a log row has no undo record'; end if;
  select status into st from pipeline.intake_revisit_backfill_batches where batch_id = b1;
  if st <> 'partly_undone' or (select rows_restored from pipeline.intake_revisit_backfill_batches where batch_id = b1) <> n_log - 2 or (select rows_skipped from pipeline.intake_revisit_backfill_batches where batch_id = b1) <> 2 then raise exception 'batch undo record'; end if;
  raise notice 'PASS undo: % rows are back to exactly their state before the backfill (whole-row equality); 2 rows that changed after the backfill (one with another time, one without) are left as they are and recorded as skipped_changed; the batch is partly_undone', n_log - 2;
  insert into public.rb_snap select 'after_undo', d.intake_id, to_jsonb(d)::text from pipeline.course_intake_dates d;
  r := security.intake_revisit_backfill_undo_v1(b1);
  if exists (select 1 from public.rb_diff('after_undo')) then raise exception 'a second undo changed rows'; end if;
  begin perform security.intake_revisit_backfill_undo_v1(gen_random_uuid()); raise exception 'unknown batch accepted'; exception when sqlstate '22023' then null; end;
  raise notice 'PASS undo again: a second undo changes nothing; a batch that is not recorded is refused';
end $$;
