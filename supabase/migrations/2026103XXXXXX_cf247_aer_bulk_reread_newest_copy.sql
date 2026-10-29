-- CF-247 AER decision A5 (Platform Admin 30 Oct 2026 06:53): bulk Read again targets the newest stored copy only. APPROVED.
-- "Never enqueue older stored copies. Preserve history. Prevent duplicate current Layer 4 items and handle superseded items through the governed
-- model. Require exact counts and dry-run evidence before execution. No paid re-read is authorised merely by approving this mechanism."
-- Specification: admin docs/platform/ui-audit/2026-10-30-bulk-reread-newest-copy-spec.md (Lane I, Workstream 5). Follows W28
-- (20261029120000), which made the single-source Read again (security.aer_reread_v1) re-queue only the run on the source's current stored copy
-- and left public.admin_entry_matrix_reread unchanged because security.governed_aer_close_snapshot_v1 pins its md5.
--
-- 1 public.admin_entry_matrix_reread(uuid[], text), whole-body replacement guarded on live md5 ca394b60216ef06dfc2ce9db265e8efe. It looped over
--   every done or failed run of each source, so a source with two stored copies was read twice and could keep two current Layer 4 items. Now,
--   for each distinct source in ascending id order (locks always taken in the same order):
--     * the source row is locked; an unknown id is skipped as 'not_found' (no exception, so one bad id does not stop the batch);
--     * the run on the newest stored copy is chosen with W28's ordering, copied verbatim; no run: skipped as 'never_read'; newest run queued
--       or leased: skipped as 'already_waiting' and its older runs are not touched either;
--     * runs on older copies are never re-queued and keep their history (state, result, previous_results, review_item_id untouched); their
--       proposed rows (only where the run's item is null or pending), then their pending Layer 4 item, are closed as 'superseded', as W28 does;
--     * the newest run only, when done or failed, is read again with today's steps: its proposed rows, then its pending item superseded; the
--       earlier result appended to previous_results with the same keys (D3: state, error, attempts_used, earlier_index); re-queued. Failed runs,
--       held_unparsed included, stay re-readable here on purpose (the bulk function is the route after a reader change; aer_reread_v1 refuses them).
--   Role check corrected (A3, tightening only): the earlier test `current_user <> 'postgres'` never fired inside this security definer function
--   (current_user is always the owner there), so any signed-in user could call it over the API. Now a request carrying JWT claims must be a
--   Platform Admin (rank 6); a direct owner session (a migration) has no claims and is allowed as before.
--   Unchanged: the reason of 5 characters or more, the non-empty array check; no scope or AI
--   limit check is added; no markdown re-fetch (that stays a single-source action). One event (entry_matrix, reread) as today; its existing keys
--   keep their meaning ('runs' stays the count, as in every earlier reread event and in aer_reread_v1's), and it adds 'run_ids' (the runs
--   re-queued), 'older_rows_superseded', 'older_items_superseded' and 'skipped' ([{source, why}]). The return value is additive: ok, runs,
--   rows_superseded and items_superseded keep their meaning (all rows, all items); older_items_superseded and skipped are added.
--   No caller changes: no frontend code or edge function calls it, and since W28 no database function does (verified live 30 Oct 2026).
-- 2 security.governed_aer_close_snapshot_v1(), md5-guarded edit (55910cb4111d48c54f48add915993923), each edit applied exactly once. Option A of the
--   specification: the recorded c_md5 (the evidence of what was approved) is kept as it is; only the check "The entry-reading functions are
--   unchanged since the recovery ran" changes: once a done governed_action task exists for aer_pr_a_recovery_close it reports ok with a note
--   (action completed <finished_at>; functions changed since by later change control). Before completion the check stays strict.
-- Governed snapshot change approved: Platform Admin, 30 Oct 2026 06:53 (A5 approved; decision paper Option A, the recommended default)
--
-- This migration executes no re-read: it replaces two function definitions and checks them. No run, row, item or setting is changed.
-- Replaces: public.admin_entry_matrix_reread (same name and signature, md5-guarded whole-body replacement); security.governed_aer_close_snapshot_v1
--   (same name and signature, md5-guarded edit of its function-drift check only)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. No new job, table, setting, status or event action. Consumer API not touched (G3, Decision 266).

-- both live definitions must be the ones this change was written against (checked before anything changes)
do $$ begin
  if md5(pg_get_functiondef('public.admin_entry_matrix_reread(uuid[],text)'::regprocedure)) <> 'ca394b60216ef06dfc2ce9db265e8efe' then
    raise exception 'live public.admin_entry_matrix_reread differs from the definition this change replaces';
  end if;
  if md5(pg_get_functiondef('security.governed_aer_close_snapshot_v1()'::regprocedure)) <> '55910cb4111d48c54f48add915993923' then
    raise exception 'live security.governed_aer_close_snapshot_v1 differs from the definition this change edits';
  end if;
end $$;

create or replace function public.admin_entry_matrix_reread(p_source_ids uuid[], p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v_src pipeline.entry_matrix_sources%rowtype; v_run pipeline.entry_matrix_runs%rowtype; v_sid uuid;
        v_reason text := trim(coalesce(p_reason, '')); v_runs int := 0; v_rows int := 0; v_items int := 0; v_n int;
        v_older_rows int := 0; v_older_items int := 0; v_ids jsonb := '[]'; v_skipped jsonb := '[]';
begin
  -- a request through the API (JWT claims present) must be a Platform Admin; a direct database session (the owner, a migration) has no claims. (current_user is always the owner inside a security definer function, so it cannot tell them apart)
  if (auth.uid() is not null or coalesce(auth.role(), '') <> '') and (auth.uid() is null or security.current_role_rank() < 6) then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'reason required'; end if;
  if coalesce(array_length(p_source_ids, 1), 0) = 0 then raise exception 'no sources given'; end if;
  -- A5 (30 Oct 2026): one source at a time, in ascending id order, so locks are always taken in the same order
  for v_sid in select distinct u from unnest(p_source_ids) u order by 1 loop
    select * into v_src from pipeline.entry_matrix_sources where id = v_sid for update;
    if v_src.id is null then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('source', v_sid, 'why', 'not_found')); continue;
    end if;
    -- W28: the run on the newest stored copy (the source's current content_hash), else the latest run; older copies keep their history
    select * into v_run from pipeline.entry_matrix_runs where source_id = v_src.id
     order by (content_hash is not distinct from v_src.content_hash) desc, created_at desc, id desc limit 1 for update;
    if v_run.id is null then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('source', v_src.id, 'why', 'never_read')); continue;
    end if;
    if v_run.state in ('queued', 'leased') then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('source', v_src.id, 'why', 'already_waiting')); continue;
    end if;

    -- W28: runs on older stored copies are not read again. Their proposed rows, then their still-pending item, are superseded; decided items stay
    update catalogue.provider_entry_matrix m set status = 'superseded', status_reason = 'older stored copy; read again on the newest copy: ' || v_reason, updated_at = now()
     where m.status = 'proposed' and m.run_id in (select r.id from pipeline.entry_matrix_runs r left join pipeline.layer4_review_items li on li.id = r.review_item_id
                                                   where r.source_id = v_src.id and r.id <> v_run.id and (li.id is null or li.status = 'pending'));
    get diagnostics v_n = row_count; v_older_rows := v_older_rows + v_n;
    update pipeline.layer4_review_items li set status = 'superseded'
     where li.status = 'pending' and li.id in (select r.review_item_id from pipeline.entry_matrix_runs r where r.source_id = v_src.id and r.id <> v_run.id);
    get diagnostics v_n = row_count; v_older_items := v_older_items + v_n;

    -- the newest copy's run only (done or failed; D3: a failed run, held_unparsed included, can be read again here after a reader change):
    -- rows first, then the item (its trigger, entry_matrix_review_apply_v1, then finds no proposed rows left), earlier result kept, re-queued
    if v_run.state in ('done', 'failed') then
      update catalogue.provider_entry_matrix set status = 'superseded', status_reason = 'read again: ' || v_reason, updated_at = now()
       where run_id = v_run.id and status = 'proposed';
      get diagnostics v_n = row_count; v_rows := v_rows + v_n;
      if v_run.review_item_id is not null then
        update pipeline.layer4_review_items set status = 'superseded' where id = v_run.review_item_id and status = 'pending';
        get diagnostics v_n = row_count; v_items := v_items + v_n;
      end if;
      update pipeline.entry_matrix_runs
         set previous_results = previous_results || jsonb_build_array(jsonb_build_object('result', v_run.result, 'rows_admitted', v_run.rows_admitted,
               'rows_dropped', v_run.rows_dropped, 'cost_usd', v_run.cost_usd, 'model', v_run.model_code, 'review_item_id', v_run.review_item_id, 'done_at', v_run.done_at,
               'reread_at', now(), 'reason', v_reason,
               -- D3: the earlier result's state, error and the attempts it used stay with it; earlier_index links it to what came before
               'state', v_run.state, 'error', v_run.error, 'attempts_used', v_run.attempts, 'earlier_index', jsonb_array_length(v_run.previous_results))),
             state = 'queued', attempts = 0, leased_until = null, result = null, rows_admitted = 0, rows_dropped = 0, review_item_id = null,
             error = null, done_at = null, updated_at = now()
       where id = v_run.id;
      v_runs := v_runs + 1; v_ids := v_ids || jsonb_build_array(v_run.id);
    end if;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'reread', 'pipeline.entry_matrix_runs',
          jsonb_build_object('sources', to_jsonb(p_source_ids), 'runs', v_runs, 'rows_superseded', v_rows + v_older_rows, 'items_superseded', v_items + v_older_items, 'reason', v_reason,
                             'run_ids', v_ids, 'older_rows_superseded', v_older_rows, 'older_items_superseded', v_older_items, 'skipped', v_skipped), auth.uid());
  return jsonb_build_object('ok', true, 'runs', v_runs, 'rows_superseded', v_rows + v_older_rows, 'items_superseded', v_items + v_older_items,
                            'older_items_superseded', v_older_items, 'skipped', v_skipped);
end $$;
revoke all on function public.admin_entry_matrix_reread(uuid[], text) from public, anon;
grant execute on function public.admin_entry_matrix_reread(uuid[], text) to authenticated;
comment on function public.admin_entry_matrix_reread(uuid[], text) is 'CF-247 AER v1.1: read stored entry-requirements pages again after a reader change; proposed rows and pending items superseded, earlier result kept. Platform Admin, logged. A5 (30 Oct 2026): per source only the run on the newest stored copy (W28 ordering) is re-queued; runs on older copies keep their history and their proposed rows and pending Layer 4 item are superseded; unknown, never-read and already-waiting sources are skipped and reported.';

-- 2 the governed snapshot (Option A): the recorded c_md5 stays; the drift check is reported as completed once the governed action has run
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

select pg_temp.edit_n('security.governed_aer_close_snapshot_v1()', '55910cb4111d48c54f48add915993923', array[
  array[$o$v_open_at timestamptz; v_due timestamptz;$o$,
        $n$v_open_at timestamptz; v_due timestamptz; v_done_at timestamptz;$n$],
  array[$o$  for k in select jsonb_object_keys(c_md5) loop$o$,
        $n$  -- A5 (30 Oct 2026), Option A: once the action has run, later change control may change these functions; c_md5 stays as the record
  select max(finished_at) into v_done_at from pipeline.admin_jobs where kind = 'governed_action' and args->>'action' = 'aer_pr_a_recovery_close' and state = 'done';
  for k in select jsonb_object_keys(c_md5) loop$n$],
  array[$o$    jsonb_build_object('check', 'The entry-reading functions are unchanged since the recovery ran', 'expected', c_md5, 'actual', v_md5, 'ok', v_md5 = c_md5));$o$,
        $n$    case when v_done_at is null or v_md5 = c_md5
      then jsonb_build_object('check', 'The entry-reading functions are unchanged since the recovery ran', 'expected', c_md5, 'actual', v_md5, 'ok', v_md5 = c_md5)
      else jsonb_build_object('check', 'The entry-reading functions are unchanged since the recovery ran', 'expected', c_md5, 'actual', v_md5, 'ok', true,
             'note', 'action completed ' || to_char(v_done_at at time zone 'Australia/Sydney', 'DD Mon YYYY HH24:MI') || '; functions changed since by later change control') end);$n$]
], array[1, 1, 1]);

comment on function security.governed_aer_close_snapshot_v1() is 'CF-247 Decision 268: live state and preconditions of the governed closure of the AER PR A recovery (read only). A5 (30 Oct 2026, Option A): the recorded function md5s are kept; once the action is done, a later change to those functions is reported as completed, not as a failed precondition.';

-- post-check: both definitions are the new ones, the bulk function selects with W28's ordering, the record is kept, grants unchanged
do $$
declare v_bulk text := pg_get_functiondef('public.admin_entry_matrix_reread(uuid[],text)'::regprocedure);
        v_snap text := pg_get_functiondef('security.governed_aer_close_snapshot_v1()'::regprocedure); v_chk jsonb;
begin
  if md5(v_bulk) <> 'e2566cb6c2153d2414adb77dcfefb8c8' then raise exception 'A5 post-check: admin_entry_matrix_reread md5 is % (expected e2566cb6c2153d2414adb77dcfefb8c8)', md5(v_bulk); end if;
  if md5(v_snap) <> 'af76dcb7304db1cd6efbaf41f3f89b3a' then raise exception 'A5 post-check: governed_aer_close_snapshot_v1 md5 is % (expected af76dcb7304db1cd6efbaf41f3f89b3a)', md5(v_snap); end if;
  if position('order by (content_hash is not distinct from v_src.content_hash) desc, created_at desc, id desc limit 1' in v_bulk) = 0 then
    raise exception 'A5 post-check: the bulk function does not select the newest stored copy with the W28 ordering'; end if;
  if position('"public.admin_entry_matrix_reread(uuid[],text)":"ca394b60216ef06dfc2ce9db265e8efe"' in v_snap) = 0 then
    raise exception 'A5 post-check: the recorded c_md5 of the governed snapshot was changed'; end if;
  if not has_function_privilege('authenticated', 'public.admin_entry_matrix_reread(uuid[],text)', 'execute')
     or has_function_privilege('anon', 'public.admin_entry_matrix_reread(uuid[],text)', 'execute') then
    raise exception 'A5 post-check: grants on admin_entry_matrix_reread changed'; end if;
  select e into v_chk from jsonb_array_elements(security.governed_aer_close_snapshot_v1()->'checks') e
   where e->>'check' = 'The entry-reading functions are unchanged since the recovery ran';
  if exists (select 1 from pipeline.admin_jobs where kind = 'governed_action' and args->>'action' = 'aer_pr_a_recovery_close' and state = 'done')
     and not (coalesce((v_chk->>'ok')::boolean, false) and v_chk ? 'note') then
    raise exception 'A5 post-check: the completed governed action still reports function drift as a failed check: %', v_chk; end if;
end $$;
