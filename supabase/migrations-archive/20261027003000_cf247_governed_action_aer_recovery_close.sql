-- CF-247 Decision 268 (Platform Admin 27 Oct 2026 21:57 and 22:00): routine operations become governed actions in the admin UI; SQL is
-- break-glass only. First and only action of this slice: adopt and close the AER PR A recovery that is already open (opened by paste at
-- 21:50:00, events 22140 and 22141; the six runs settled by 22:05:20). Record: admin docs/coursefinder-design-reference-v1.4.md Decision 268;
-- change control CF-CHG-20260915-247 (27 Oct 22:2x and the PR entry); docs/platform/aer-v1.1-build-log.md.
--
-- What it adds (no new table, reader, status or consumer field):
--   security.governed_aer_close_snapshot_v1()  read only: the live state the action closes (the six outcomes, proposed / active / quarantined
--                                               counts, the cost since the recovery opened, RMIT's scope) and every precondition with its
--                                               expected and actual value
--   public.admin_governed_action(text, jsonb)  Platform Admin only (auth.uid() and rank 6, checked here): 'read', 'preview' (live checks, a
--                                               rolled-back dry run, an action hash and an approval that expires; logged) and 'approve'
--                                               (idempotency key, revalidation, run once, post-checks, linked audit event)
--   one task kind 'governed_action' in pipeline.admin_job_kinds: each approval is one pipeline.admin_jobs row written only as 'done', 'failed'
--                                               or 'cancelled' (refused), existing states; it is never queued, so the task runner never takes it
--   a unique index on the idempotency key of governed-action tasks (a repeated click or retry cannot run twice)
--   settings governed.approval_minutes and governed.max_attempts (G2)
-- The action (allowlisted, fixed parameters, never arbitrary SQL): on approval remove RMIT from entry.providers, restoring UTS and WSU, the
-- scope before the recovery opened; verify it; nothing else. It admits nothing (the 37 proposed rows stay with Layer 4 review), touches no run,
-- row or item, leaves Vietnam, Nigeria, the three D2 pages and the 20 quarantined rows as they are, and refuses if any precondition changed.
-- Replaces: the manual close step of the AER PR A recovery (PASTE-20261027-aer-pr-a-recovery-close.sql, never applied; retired from the operating
--   procedure by Decision 268)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. Consumer API not touched (Decision 266).

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'governed.approval_minutes', 'Governed actions: approval valid for', 'How long a governed action''s preview may be approved. After that the Platform Admin previews again, so an approval always rests on a recent live check (Decision 268).', 'number', to_jsonb(15), 5, 60, 'minutes', 960, 'Governed actions', 'public.admin_governed_action', 'CF-247 Decision 268 (27 Oct 2026)'),
 ('pipeline', 'governed.max_attempts', 'Governed actions: failed attempts before pause', 'After this many failed runs of one governed action it pauses: further approvals are refused until the cause is fixed (Decision 268).', 'number', to_jsonb(3), 1, 5, 'attempts', 961, 'Governed actions', 'public.admin_governed_action', 'CF-247 Decision 268 (27 Oct 2026)')
on conflict (toolset_key, key) do nothing;

insert into pipeline.admin_job_kinds(kind, label, what, can_pause, added_in)
values ('governed_action', 'Governed action', 'One allowlisted Platform Admin action approved in the admin UI: checked live, dry-run, run once under an idempotency key, post-checked and audited (Decision 268). Written when it has run or been refused; never queued.', false, 'Decision 268')
on conflict (kind) do nothing;

create unique index if not exists admin_jobs_governed_idempotency_uq on pipeline.admin_jobs ((args->>'idempotency_key')) where kind = 'governed_action';

-- the live state the AER PR A recovery closure rests on, with each precondition's expected and actual value (read only)
create or replace function security.governed_aer_close_snapshot_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare
  c_rmit constant uuid := '8e1adb6c-e069-43db-9584-bd054255e702';
  c_scope_open constant jsonb := '["9d22a19e-c3f7-4012-b738-17bc0b481e7f", "1719c3ba-1ddf-483e-935e-c750124ba99c", "8e1adb6c-e069-43db-9584-bd054255e702"]';
  c_scope_closed constant jsonb := '["9d22a19e-c3f7-4012-b738-17bc0b481e7f", "1719c3ba-1ddf-483e-935e-c750124ba99c"]';
  -- the six runs of the recovery, their settled outcome, and each run's cumulative cost when the recovery opened (verified 27 Oct 21:51)
  c_runs constant jsonb := '[
    {"slug":"norway","run":"88e17723-1d6e-4b68-8678-ecef98d66e21","state":"failed","error":"held_unparsed: no printed scale%","cost_at_open":0.0077756},
    {"slug":"qatar","run":"e07eeaf5-f805-42d4-9976-d6a5ed9ff398","state":"done","item":"9adbeada-af55-40e8-95dc-4f4fe97cb5fe","cost_at_open":0},
    {"slug":"singapore","run":"b4aecc1c-47a5-495d-9a9b-5d19c6854209","state":"done","item":"bcd9f55b-43fd-4c5b-9e6a-ae85c68ed8bf","cost_at_open":0.0060744},
    {"slug":"sri-lanka","run":"10995ef9-c95e-4cf1-9d83-a1deb2857344","state":"done","item":"8a803c95-8d0a-4743-b79b-155085a1f0d1","cost_at_open":0.0037492},
    {"slug":"thailand","run":"494bcd84-9914-43f1-8c0e-8f59c6baafc3","state":"done","item":"f56bd767-9a19-44ba-855a-748f47aec009","cost_at_open":0.0034708},
    {"slug":"united-kingdom","run":"04349c2b-2192-4a9f-9865-0611870d8c3d","state":"failed","error":"held_incomplete:%","cost_at_open":0.0081736}]';
  -- left as they are: Vietnam held for PR B, Nigeria, the three non-country (D2) pages
  c_untouched constant jsonb := '[
    {"slug":"vietnam","run":"33eba77e-ba83-4ffa-bd1b-267ffe6aa14c","error":"held: AER PR B%"},
    {"slug":"nigeria","run":"0bcdf776-7107-4ab1-9f28-858a54f90b90","error":"held_incomplete:%"},
    {"slug":"foundation-equivalencies","run":"e47e8cdb-9432-416a-bd61-eaba26951dde","error":"held_unparsed:%"},
    {"slug":"global-assessment-certificate","run":"a3a8b518-1aa2-42e0-8ef9-457336109c1d","error":"held_unparsed:%"},
    {"slug":"international-baccalaureate","run":"5004850f-b526-474d-9cd7-374f5fc99588","error":"held_unparsed:%"}]';
  -- the lane's functions as they were when the recovery ran (a changed function means the state may differ from what was approved)
  c_md5 constant jsonb := '{"public.svc_entry_matrix_next(integer)":"f992b7fc20bfce4d27c0e7bbee4256a3",
    "public.svc_entry_matrix_record(uuid,jsonb,numeric,text)":"e1a130e278ff535e33eade3c2e0b9aa2",
    "public.admin_entry_matrix_reread(uuid[],text)":"ca394b60216ef06dfc2ce9db265e8efe",
    "security.entry_matrix_enabled_v1(uuid)":"15fc1b28e855be2d4234057527a1a086",
    "security.entry_matrix_fire_v1()":"dd985f9ab6b51bddbf5e97d1f7d83143",
    "security.entry_matrix_enqueue_v1()":"d3b562ff4bcace32bf24d308473739ed"}';
  c_active constant int := 343; c_quarantined constant int := 20; c_proposed constant int := 37;  -- fixed: preconditions of this one action
  v_scope jsonb; v_runs jsonb := '[]'; v_unt jsonb := '[]'; v_md5 jsonb := '{}'; v_checks jsonb := '[]'; x jsonb; r record; k text;
  v_ok boolean := true; v_cost numeric := 0; v_n int; v_active int; v_q int; v_prop int; v_sup int; v_items int; v_open_at timestamptz; v_due timestamptz;
begin
  select value into v_scope from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.providers';
  select created_at into v_open_at from pipeline.admin_control_events where id = 22141 and action = 'recovery_open_paste';
  for x in select * from jsonb_array_elements(c_runs) loop
    select er.*, i.status item_status into r from pipeline.entry_matrix_runs er left join pipeline.layer4_review_items i on i.id = er.review_item_id where er.id = (x->>'run')::uuid;
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('slug', x->>'slug', 'run', x->>'run', 'state', r.state, 'attempts', r.attempts, 'error', r.error,
      'completeness', r.result->'completeness'->>'status', 'matched', (r.result->'completeness'->>'matched')::int, 'expected', (r.result->'completeness'->>'expected')::int,
      'review_item', r.review_item_id, 'item_status', r.item_status, 'cost_usd', r.cost_usd,
      'cost_since_open', round(coalesce(r.cost_usd, 0) - (x->>'cost_at_open')::numeric, 7),
      'ok', r.state = x->>'state' and (x->>'error' is null or coalesce(r.error, '') like x->>'error') and (x->>'item' is null or (r.review_item_id::text = x->>'item' and r.item_status = 'pending'))));
    v_cost := v_cost + coalesce(r.cost_usd, 0) - (x->>'cost_at_open')::numeric;
  end loop;
  for x in select * from jsonb_array_elements(c_untouched) loop
    select * into r from pipeline.entry_matrix_runs where id = (x->>'run')::uuid;
    v_unt := v_unt || jsonb_build_array(jsonb_build_object('slug', x->>'slug', 'state', r.state, 'error', left(r.error, 120), 'ok', r.state = 'failed' and coalesce(r.error, '') like x->>'error'));
  end loop;
  for k in select jsonb_object_keys(c_md5) loop
    v_md5 := v_md5 || jsonb_build_object(k, md5(pg_get_functiondef(k::regprocedure)));
  end loop;
  select count(*) filter (where status = 'active'), count(*) filter (where status = 'unverified' and provenance->>'aer_flag' = 'quarantined'),
         count(*) filter (where status = 'proposed'), count(*) filter (where status = 'superseded')
    into v_active, v_q, v_prop, v_sup from catalogue.provider_entry_matrix where provider_id = c_rmit;
  select count(*) into v_items from pipeline.layer4_review_items i where i.id in (select (e->>'item')::uuid from jsonb_array_elements(c_runs) e where e ? 'item') and i.status = 'pending';
  select count(*) into v_n from pipeline.entry_matrix_runs where provider_id = c_rmit and state in ('queued', 'leased');
  select min(read_at) + make_interval(days => security.pipeline_num_v1('entry.matrix_refresh_days', 30)::int) into v_due
    from pipeline.entry_matrix_sources where provider_id = c_rmit and read_via <> 'stored';
  v_checks := jsonb_build_array(
    jsonb_build_object('check', 'The recovery being closed was opened (event 22141)', 'expected', 'opened 27 Oct 2026 21:50', 'actual', coalesce(to_char(v_open_at at time zone 'Australia/Sydney', 'DD Mon YYYY HH24:MI'), 'not found'), 'ok', v_open_at is not null),
    jsonb_build_object('check', 'RMIT is in the reading scope (UTS, WSU and RMIT)', 'expected', c_scope_open, 'actual', v_scope, 'ok', v_scope = c_scope_open),
    jsonb_build_object('check', 'The six runs have settled as recorded', 'expected', 6, 'actual', (select count(*) from jsonb_array_elements(v_runs) e where (e->>'ok')::boolean), 'ok', (select bool_and((e->>'ok')::boolean) from jsonb_array_elements(v_runs) e)),
    jsonb_build_object('check', 'No RMIT run is queued or being read', 'expected', 0, 'actual', v_n, 'ok', v_n = 0),
    jsonb_build_object('check', 'RMIT active rows', 'expected', c_active, 'actual', v_active, 'ok', v_active = c_active),
    jsonb_build_object('check', 'RMIT quarantined rows', 'expected', c_quarantined, 'actual', v_q, 'ok', v_q = c_quarantined),
    jsonb_build_object('check', 'RMIT proposed rows (in Layer 4 review)', 'expected', c_proposed, 'actual', v_prop, 'ok', v_prop = c_proposed),
    jsonb_build_object('check', 'Their four Layer 4 items are pending', 'expected', 4, 'actual', v_items, 'ok', v_items = 4),
    jsonb_build_object('check', 'Vietnam, Nigeria and the three D2 pages are held as they were', 'expected', 5, 'actual', (select count(*) from jsonb_array_elements(v_unt) e where (e->>'ok')::boolean), 'ok', (select bool_and((e->>'ok')::boolean) from jsonb_array_elements(v_unt) e)),
    jsonb_build_object('check', 'The entry-reading functions are unchanged since the recovery ran', 'expected', c_md5, 'actual', v_md5, 'ok', v_md5 = c_md5));
  select bool_and((e->>'ok')::boolean) into v_ok from jsonb_array_elements(v_checks) e;
  return jsonb_build_object('action', 'aer_pr_a_recovery_close', 'ok', coalesce(v_ok, false), 'checks', v_checks, 'runs', v_runs, 'untouched', v_unt,
    'counts', jsonb_build_object('active', v_active, 'proposed', v_prop, 'quarantined', v_q, 'superseded', v_sup, 'items_pending', v_items),
    'cost_usd_since_open', round(v_cost, 4), 'cost_basis', 'each run''s cost now, less its cost when the recovery opened (verified 27 Oct 2026 21:51)',
    'scope', jsonb_build_object('now', v_scope, 'after', c_scope_closed, 'open', c_scope_open), 'refresh_due', v_due, 'opened_at', v_open_at);
end $$;
revoke all on function security.governed_aer_close_snapshot_v1() from public, anon, authenticated;
comment on function security.governed_aer_close_snapshot_v1() is 'CF-247 Decision 268: live state and preconditions of the governed closure of the AER PR A recovery (read only).';

-- the governed action runner: one allowlisted action, Platform Admin only
create or replace function public.admin_governed_action(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  c_code constant text := 'aer_pr_a_recovery_close';
  c_rmit constant text := '8e1adb6c-e069-43db-9584-bd054255e702';
  c_scope_closed constant jsonb := '["9d22a19e-c3f7-4012-b738-17bc0b481e7f", "1719c3ba-1ddf-483e-935e-c750124ba99c"]';
  v_snap jsonb; v_hash text; v_mins int := security.pipeline_num_v1('governed.approval_minutes', 15)::int; v_max int := security.pipeline_num_v1('governed.max_attempts', 3)::int;
  v_key text; v_prev pipeline.admin_control_events%rowtype; v_job pipeline.admin_jobs%rowtype; v_id uuid := gen_random_uuid(); v_ev bigint;
  v_dry jsonb; v_post jsonb; v_failed int; v_reason text := btrim(coalesce(p_args->>'reason', ''));
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_action not in ('read', 'preview', 'approve') then raise exception 'unknown request %', p_action; end if;
  -- allowlist: one action, fixed parameters; no SQL text is ever taken from the request
  if p_action <> 'read' and coalesce(p_args->>'action', '') <> c_code then raise exception 'not an allowed action'; end if;

  select count(*) into v_failed from pipeline.admin_jobs where kind = 'governed_action' and args->>'action' = c_code and state = 'failed';
  if p_action = 'read' then
    select * into v_job from pipeline.admin_jobs where kind = 'governed_action' and args->>'action' = c_code and state = 'done' order by finished_at desc limit 1;
    return jsonb_build_object('actions', jsonb_build_array(jsonb_build_object('action', c_code, 'label', 'Close the AER PR A recovery',
      'what', 'Removes RMIT from the entry-requirements reading scope, restoring UTS and WSU, after the six recovery runs settled. Admits nothing; the proposed rows stay in Layer 4 review.',
      'decision', 'Decision 268', 'done', v_job.id is not null, 'paused', v_failed >= v_max, 'failed_attempts', v_failed, 'max_attempts', v_max)),
      'snapshot', security.governed_aer_close_snapshot_v1(), 'last', case when v_job.id is null then null else to_jsonb(v_job) end,
      'history', (select coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'state', j.state, 'at', j.finished_at, 'reason', j.reason, 'result', j.result) order by j.created_at desc), '[]'::jsonb)
                    from pipeline.admin_jobs j where j.kind = 'governed_action' and j.args->>'action' = c_code));
  end if;

  if p_action = 'preview' then
    v_snap := security.governed_aer_close_snapshot_v1();
    v_hash := md5(v_snap::text);
    -- the live dry run: the action's own steps, then rolled back
    begin
      update pipeline.platform_toolset_settings set value = c_scope_closed where toolset_key = 'pipeline' and key = 'entry.providers';
      v_dry := jsonb_build_object('scope_after', (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.providers'),
                                  'rmit_in_scope_after', security.entry_matrix_enabled_v1(c_rmit::uuid));
      raise exception using errcode = 'P0001', message = 'governed dry run', detail = v_dry::text;
    exception when others then
      if sqlerrm = 'governed dry run' then
        get stacked diagnostics v_key = pg_exception_detail; v_dry := v_key::jsonb || jsonb_build_object('ok', true, 'rolled_back', true);
      else v_dry := jsonb_build_object('ok', false, 'error', left(sqlerrm, 300)); end if;
    end;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('governed_actions', 'preview', c_code, jsonb_build_object('action_hash', v_hash, 'ok', (v_snap->>'ok')::boolean and coalesce((v_dry->>'ok')::boolean, false),
              'expires_at', now() + make_interval(mins => v_mins), 'dry_run', v_dry), auth.uid())
    returning id into v_ev;
    return jsonb_build_object('action', c_code, 'preview_id', v_ev, 'action_hash', v_hash, 'expires_at', now() + make_interval(mins => v_mins),
      'ok', (v_snap->>'ok')::boolean and coalesce((v_dry->>'ok')::boolean, false) and v_failed < v_max, 'paused', v_failed >= v_max,
      'snapshot', v_snap, 'dry_run', v_dry,
      'already_done', exists (select 1 from pipeline.admin_jobs where kind = 'governed_action' and args->>'action' = c_code and state = 'done'));
  end if;

  -- approve: one at a time per action; a repeated click or retry with the same key returns the first result and runs nothing
  perform pg_advisory_xact_lock(hashtext('governed_action:' || c_code));
  v_key := btrim(coalesce(p_args->>'idempotency_key', ''));
  if v_key !~ '^[0-9a-f-]{36}$' then raise exception 'an idempotency key is required'; end if;
  select * into v_job from pipeline.admin_jobs where kind = 'governed_action' and args->>'idempotency_key' = v_key;
  if v_job.id is not null then return jsonb_build_object('repeated', true, 'id', v_job.id, 'state', v_job.state, 'result', v_job.result); end if;
  if length(v_reason) < 5 then raise exception 'give a reason (kept in the log)'; end if;

  select * into v_job from pipeline.admin_jobs where kind = 'governed_action' and args->>'action' = c_code and state = 'done' limit 1;
  select * into v_prev from pipeline.admin_control_events where id = nullif(p_args->>'preview_id', '')::bigint and area = 'governed_actions' and action = 'preview' and target = c_code;
  v_snap := security.governed_aer_close_snapshot_v1();
  v_hash := md5(v_snap::text);
  -- refusals: recorded, nothing changed
  if v_job.id is not null or v_failed >= v_max or v_prev.id is null or v_prev.actor is distinct from auth.uid()
     or now() > (v_prev.detail->>'expires_at')::timestamptz or v_prev.detail->>'action_hash' is distinct from p_args->>'action_hash'
     or v_hash is distinct from p_args->>'action_hash' or not (v_snap->>'ok')::boolean then
    v_post := jsonb_build_object('refused', true, 'why', case
      when v_job.id is not null then 'already done (task ' || v_job.id || ')'
      when v_failed >= v_max then 'paused after ' || v_failed || ' failed attempts'
      when v_prev.id is null or v_prev.actor is distinct from auth.uid() then 'no preview of yours to approve'
      when now() > (v_prev.detail->>'expires_at')::timestamptz then 'the preview has expired; preview again'
      when v_prev.detail->>'action_hash' is distinct from p_args->>'action_hash' then 'the approval does not match the preview'
      when v_hash is distinct from p_args->>'action_hash' then 'the live state changed since the preview; preview again'
      else 'a precondition failed' end, 'snapshot', v_snap);
    insert into pipeline.admin_jobs(id, kind, lane, state, title, args, result, requested_by, reason, created_at, started_at, updated_at, finished_at)
    values (v_id, 'governed_action', 'governed', 'cancelled', 'Close the AER PR A recovery (refused)', jsonb_build_object('action', c_code, 'idempotency_key', v_key, 'action_hash', p_args->>'action_hash', 'preview_id', v_prev.id),
            v_post, auth.uid(), v_reason, now(), now(), now(), now());
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('governed_actions', 'refused', c_code, jsonb_build_object('task', v_id, 'why', v_post->>'why'), auth.uid());
    return jsonb_build_object('id', v_id, 'state', 'cancelled') || v_post;
  end if;

  -- run once: the action's steps and its post-checks together; any failure leaves nothing changed and is recorded
  begin
    update pipeline.platform_toolset_settings set value = c_scope_closed, updated_by = auth.uid(), updated_at = now(),
           reason = 'Governed action ' || c_code || ' (Decision 268): ' || left(v_reason, 300)
     where toolset_key = 'pipeline' and key = 'entry.providers';
    v_post := jsonb_build_object(
      'scope_restored', (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.providers') = c_scope_closed,
      'rmit_out_of_scope', not security.entry_matrix_enabled_v1(c_rmit::uuid),
      'uts_wsu_in_scope', security.entry_matrix_enabled_v1('9d22a19e-c3f7-4012-b738-17bc0b481e7f') and security.entry_matrix_enabled_v1('1719c3ba-1ddf-483e-935e-c750124ba99c'),
      'counts_unchanged', (security.governed_aer_close_snapshot_v1()->'counts') = (v_snap->'counts'),
      'runs_unchanged', (security.governed_aer_close_snapshot_v1()->'runs') = (v_snap->'runs'));
    if not ((v_post->>'scope_restored')::boolean and (v_post->>'rmit_out_of_scope')::boolean and (v_post->>'uts_wsu_in_scope')::boolean
            and (v_post->>'counts_unchanged')::boolean and (v_post->>'runs_unchanged')::boolean) then
      raise exception 'post-check failed: %', v_post;
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('governed_actions', 'executed', c_code, jsonb_build_object('task', v_id, 'action_hash', v_hash, 'preview_id', v_prev.id, 'post_checks', v_post,
              'scope_before', v_snap->'scope'->'now', 'scope_after', c_scope_closed, 'counts', v_snap->'counts', 'cost_usd_since_open', v_snap->'cost_usd_since_open'), auth.uid())
    returning id into v_ev;
    insert into pipeline.admin_jobs(id, kind, lane, state, title, args, result, requested_by, reason, created_at, started_at, updated_at, finished_at)
    values (v_id, 'governed_action', 'governed', 'done', 'Close the AER PR A recovery', jsonb_build_object('action', c_code, 'idempotency_key', v_key, 'action_hash', v_hash, 'preview_id', v_prev.id),
            jsonb_build_object('post_checks', v_post, 'audit_event', v_ev, 'before', v_snap, 'scope_after', c_scope_closed), auth.uid(), v_reason, now(), now(), now(), now());
    return jsonb_build_object('id', v_id, 'state', 'done', 'audit_event', v_ev, 'post_checks', v_post, 'scope_after', c_scope_closed);
  exception when others then
    insert into pipeline.admin_jobs(id, kind, lane, state, title, args, result, error, requested_by, reason, created_at, started_at, updated_at, finished_at)
    values (v_id, 'governed_action', 'governed', 'failed', 'Close the AER PR A recovery (failed; nothing changed)', jsonb_build_object('action', c_code, 'idempotency_key', v_key, 'action_hash', v_hash, 'preview_id', v_prev.id),
            jsonb_build_object('nothing_changed', true, 'attempt', v_failed + 1, 'paused_after', v_max), left(sqlerrm, 500), auth.uid(), v_reason, now(), now(), now(), now());
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('governed_actions', 'failed', c_code, jsonb_build_object('task', v_id, 'error', left(sqlerrm, 300), 'attempt', v_failed + 1), auth.uid());
    return jsonb_build_object('id', v_id, 'state', 'failed', 'error', left(sqlerrm, 300), 'nothing_changed', true, 'paused', v_failed + 1 >= v_max);
  end;
end $$;
revoke all on function public.admin_governed_action(text, jsonb) from public, anon;
grant execute on function public.admin_governed_action(text, jsonb) to authenticated;
comment on function public.admin_governed_action(text, jsonb) is 'CF-247 Decision 268: governed actions run from the admin UI (Platform Admin only). One allowlisted action: close the AER PR A recovery.';

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'public.admin_governed_action', 'Platform', 'Decision 268: governed action runner (preview with a rolled-back dry run, approve once under an idempotency key, post-checks, audit); one allowlisted action', 'active', '{}', '20261027003000'),
 ('function', 'security.governed_aer_close_snapshot_v1', 'Platform', 'Decision 268: live state and preconditions of the AER PR A recovery closure', 'active', '{}', '20261027003000')
on conflict do nothing;
