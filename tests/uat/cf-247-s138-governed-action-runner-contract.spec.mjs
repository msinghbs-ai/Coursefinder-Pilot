// Guards: CF-247 Decision 268 (Platform Admin 27 Oct 2026 21:57 and 22:00): routine operations are governed actions in the admin UI, approved by a Platform Admin; one allowlisted action with fixed parameters (close the AER PR A recovery), previewed live with a rolled-back dry run, approved once under an idempotency key after revalidation, post-checked and audited; never queued; SQL break-glass only in the SOP
// Record: admin docs/coursefinder-design-reference-v1.4.md Decision 268; change control CF-CHG-20260915-247 (27 Oct). G2 (settings) is guarded by s32 and G3 (consumer API) by s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261027003000_cf247_governed_action_aer_recovery_close.sql', 'utf8')
const code = m.split('\n').filter(l => !/^\s*--/.test(l)).join('\n')
const fn = code.slice(code.indexOf('create or replace function public.admin_governed_action'), code.indexOf('revoke all on function public.admin_governed_action'))
const snap = code.slice(code.indexOf('create or replace function security.governed_aer_close_snapshot_v1'), code.indexOf('revoke all on function security.governed_aer_close_snapshot_v1'))
const ui = fs.readFileSync('src/GovernedActions.jsx', 'utf8')
const ops = fs.readFileSync('src/Layer23Operations.jsx', 'utf8')
const sops = fs.readFileSync('src/guide/sops.js', 'utf8')

test('Platform Admin only, checked on the server; one allowlisted action; no SQL is taken from the request', () => {
  expect(fn).toContain("if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;")
  expect(fn).toContain("c_code constant text := 'aer_pr_a_recovery_close';")
  expect(fn).toContain("if p_action <> 'read' and coalesce(p_args->>'action', '') <> c_code then raise exception 'not an allowed action'; end if;")
  expect(fn).not.toMatch(/\bexecute\b/i)  // no dynamic SQL at all
  expect(fn).not.toMatch(/p_args->>'(sql|query|statement)'/i)
  expect(m).toContain('grant execute on function public.admin_governed_action(text, jsonb) to authenticated;')
  expect(m).toContain('revoke all on function public.admin_governed_action(text, jsonb) from public, anon;')
})

test('preview: live preconditions, a dry run that is rolled back, an action hash and an approval that expires, logged', () => {
  expect(fn).toContain("raise exception using errcode = 'P0001', message = 'governed dry run', detail = v_dry::text;")
  expect(fn).toContain("v_dry := v_key::jsonb || jsonb_build_object('ok', true, 'rolled_back', true);")
  expect(fn).toContain("v_hash := md5(v_snap::text);")
  expect(fn).toContain("'expires_at', now() + make_interval(mins => v_mins)")
  expect(fn).toContain("values ('governed_actions', 'preview', c_code,")
  expect(fn).toContain("security.pipeline_num_v1('governed.approval_minutes', 15)")
  // the preconditions: the open event, RMIT's scope, the six settled runs, nothing claimable, the counts, the held pages, the lane's functions
  for (const s of ["id = 22141 and action = 'recovery_open_paste'", "'RMIT is in the reading scope (UTS, WSU and RMIT)'", "'The six runs have settled as recorded'",
    "'No RMIT run is queued or being read'", "c_active constant int := 343; c_quarantined constant int := 20; c_proposed constant int := 37;",
    "'Their four Layer 4 items are pending'", "'Vietnam, Nigeria and the three D2 pages are held as they were'", "'The entry-reading functions are unchanged since the recovery ran'"])
    expect(snap).toContain(s)
  expect(snap).toMatch(/language plpgsql stable security definer/)
  expect(snap).not.toMatch(/\b(insert|update|delete)\b/i)  // read only
})

test('approve: one at a time, an idempotency key that returns the first result, revalidation, and a refusal that changes nothing', () => {
  expect(fn).toContain("perform pg_advisory_xact_lock(hashtext('governed_action:' || c_code));")
  expect(fn).toContain("if v_key !~ '^[0-9a-f-]{36}$' then raise exception 'an idempotency key is required'; end if;")
  expect(fn).toContain("if v_job.id is not null then return jsonb_build_object('repeated', true, 'id', v_job.id, 'state', v_job.state, 'result', v_job.result); end if;")
  expect(m).toContain("create unique index if not exists admin_jobs_governed_idempotency_uq on pipeline.admin_jobs ((args->>'idempotency_key')) where kind = 'governed_action';")
  for (const why of ["'already done (task '", "'paused after '", "'no preview of yours to approve'", "'the preview has expired; preview again'",
    "'the approval does not match the preview'", "'the live state changed since the preview; preview again'", "'a precondition failed'"]) expect(fn).toContain(why)
  expect(fn).toContain("security.pipeline_num_v1('governed.max_attempts', 3)")
  expect(fn).toContain("if length(v_reason) < 5 then raise exception 'give a reason (kept in the log)'; end if;")
})

test('the action: only RMIT out of the reading scope, post-checked, audited; a failure leaves nothing changed; rows written done, failed or cancelled, never queued', () => {
  const run = fn.slice(fn.lastIndexOf('update pipeline.platform_toolset_settings set value = c_scope_closed'))  // the approved run (after the refusals)
  expect(run).toContain("update pipeline.platform_toolset_settings set value = c_scope_closed")
  expect((run.match(/\bupdate pipeline\./g) || []).length).toBe(1)  // the scope is the only thing it changes
  expect(fn).not.toMatch(/catalogue\.provider_entry_matrix|layer4_review_decide|entry_matrix_runs set|admin_entry_matrix_reread/)  // admits, re-reads and touches no run
  for (const p of ["'scope_restored'", "'rmit_out_of_scope'", "'uts_wsu_in_scope'", "'counts_unchanged'", "'runs_unchanged'"]) expect(run).toContain(p)
  expect(run).toContain("raise exception 'post-check failed: %', v_post;")
  expect(run).toContain("values ('governed_actions', 'executed', c_code,")
  expect(run).toContain("'failed', 'Close the AER PR A recovery (failed; nothing changed)'")
  const states = [...fn.matchAll(/'governed_action', 'governed', '([a-z]+)'/g)].map(x => x[1]).sort()
  expect(states).toEqual(['cancelled', 'done', 'failed'])
  expect(m).toContain("values ('governed_action', 'Governed action',")
  expect(m).toContain('-- Replaces:')
  expect(m).toContain('-- Retires: nothing')
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('UI: Platform Admin only, on Layer 2/3 › Operations; preview first; approval needs a reason and carries the key made with the preview', () => {
  expect(ops).toContain("{rank>=6&&<GovernedActions onError={onError}/>}")
  expect(ui).toContain("supabase.rpc('admin_governed_action',{p_action:'preview',p_args:{action:ACTION}})")
  expect(ui).toContain("setP(data||null);setKey(newKey())")
  expect(ui).toContain("p_args:{action:ACTION,preview_id:p.preview_id,action_hash:p.action_hash,idempotency_key:key,reason}")
  expect(ui).toContain('<ReasonAction label="Approve and run" confirm="Run once"')
  expect(ui).toContain("{p.ok&&!expired?<ReasonAction")
  for (const a of ['data-governed-outcomes', 'data-governed-counts', 'data-governed-scope', 'data-governed-checks', 'data-governed-dry-run', 'data-governed-result']) expect(ui).toContain(a)
  expect(ui).not.toMatch(/supabase\.from\(/)  // no direct table access from the page
})

test('SOP: the paste duty is replaced by governed actions; SQL is break-glass only', () => {
  expect(sops).toContain("trigger: 'A governed action ready to review (Decision 268)'")
  expect(sops).toContain("trigger: 'Break-glass only: a change that drops or deletes, or an operation no governed action covers (Decision 268)'")
  expect(sops).not.toContain("trigger: 'A paste file from a change (anything that drops or deletes)'")
})
