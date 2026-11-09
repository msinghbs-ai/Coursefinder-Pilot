-- Guards: F-INT D3 forward fix (Platform Admin decision 9 Nov 2026): after the undo, migration 20261109170000 is applied again (a new batch for the rows that have no time again, never for the row that has one),
-- and the Platform Admin call recovers that batch: refused without a Platform Admin and without a reason, recorded in the admin control log, restores exactly.
\set ON_ERROR_STOP on
\set QUIET on
do $$
declare b1 uuid; b2 record; r jsonb; v_uid uuid := gen_random_uuid(); ea uuid := (select intake_id from public.rb_cases where name = 'edited_since_a'); st text; n_log int; n_bad int;
begin
  select * into b2 from pipeline.intake_revisit_backfill_batches order by created_at desc limit 1;
  select batch_id into b1 from pipeline.intake_revisit_backfill_batches order by created_at limit 1;
  if (select count(*) from pipeline.intake_revisit_backfill_batches) <> 2 or b2.batch_id = b1 or b2.status <> 'applied' then raise exception 'second batch'; end if;
  select count(*) into n_log from pipeline.intake_revisit_backfill_log where batch_id = b2.batch_id;
  if n_log <> (select candidate_count from pipeline.intake_revisit_backfill_batches where batch_id = b1) - 1 or b2.rows_changed <> n_log then raise exception 'second batch rows % (the row that already has a time is not a candidate)', n_log; end if;
  if exists (select 1 from pipeline.intake_revisit_backfill_log where batch_id = b2.batch_id and intake_id = ea) then raise exception 'a row with a time was changed again'; end if;
  if b2.checksum_expected = (select checksum_expected from pipeline.intake_revisit_backfill_batches where batch_id = b1) then raise exception 'checksums equal'; end if;
  raise notice 'PASS re-run after recovery: a new version of the same file gives a new batch of % rows (those with no time again), never the row that already has one; checksum differs from batch 1', n_log;

  -- the Platform Admin call: no sign-in, a user without the role, no reason
  begin perform public.admin_intake_revisit_backfill_undo_v1(b2.batch_id, 'fixture'); raise exception 'no sign-in accepted'; exception when sqlstate '42501' then null; end;
  perform set_config('request.jwt.claim.sub', v_uid::text, false);
  begin perform public.admin_intake_revisit_backfill_undo_v1(b2.batch_id, 'fixture'); raise exception 'user without role accepted'; exception when sqlstate '42501' then null; end;
  insert into security.user_roles(user_id, role_code) values (v_uid, 'operator');
  begin perform public.admin_intake_revisit_backfill_undo_v1(b2.batch_id, 'fixture'); raise exception 'operator accepted'; exception when sqlstate '42501' then null; end;
  insert into security.user_roles(user_id, role_code) values (v_uid, 'platform_admin');
  begin perform public.admin_intake_revisit_backfill_undo_v1(b2.batch_id, '  '); raise exception 'empty reason accepted'; exception when sqlstate '22023' then null; end;
  if (select status from pipeline.intake_revisit_backfill_batches where batch_id = b2.batch_id) <> 'applied' then raise exception 'a refused call changed the batch'; end if;
  r := public.admin_intake_revisit_backfill_undo_v1(b2.batch_id, 'fixture: forward recovery of the second batch');
  perform set_config('request.jwt.claim.sub', '', false);
  if (r->>'restored')::int <> n_log or (r->>'skipped_changed_since')::int <> 0 or r->>'status' <> 'undone' then raise exception 'admin undo result %', r; end if;
  select count(*) into n_bad from pipeline.intake_revisit_backfill_log g join public.rb_snap s on s.label = 'after_undo' and s.intake_id = g.intake_id join pipeline.course_intake_dates d on d.intake_id = g.intake_id where g.batch_id = b2.batch_id and s.row_text <> to_jsonb(d)::text;
  if n_bad <> 0 or exists (select 1 from public.rb_diff('after_undo')) then raise exception 'admin undo did not restore exactly'; end if;
  if not exists (select 1 from pipeline.admin_control_events e where e.area = 'intake_dates' and e.action = 'revisit_backfill_undo' and e.actor = v_uid and e.detail->>'reason' like 'fixture:%') then raise exception 'no control log row'; end if;
  raise notice 'PASS Platform Admin call: refused without sign-in, for a user without the role, for an operator and without a reason (the batch is untouched); with the role and a reason it restores % rows exactly, writes the admin control log and the batch is undone', n_log;
end $$;
