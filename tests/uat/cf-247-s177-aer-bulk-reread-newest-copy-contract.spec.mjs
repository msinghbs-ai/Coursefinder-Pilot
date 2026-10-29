// Guards: CF-247 decision A5 (Platform Admin 30 Oct 2026 06:53): bulk Read again (public.admin_entry_matrix_reread) re-queues only the run on each source's newest stored copy (W28 ordering); older copies are never enqueued and keep their history, their proposed rows and pending Layer 4 item are superseded; unknown, never-read and already-waiting sources are skipped and reported; held_unparsed stays re-readable in bulk; the return is additive; the governed snapshot keeps its recorded md5s (Option A); md5-guarded; no re-read executed by the migration
// Specification: admin docs/platform/ui-audit/2026-10-30-bulk-reread-newest-copy-spec.md. G2 is guarded by s32, G3 by s57, housekeeping by s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const DIR = 'supabase/migrations'
const FILE = fs.readdirSync(DIR).find((f) => /^[0-9X]{13,14}_cf247_aer_bulk_reread_newest_copy\.sql$/.test(f))
const m = fs.readFileSync(`${DIR}/${FILE}`, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const bulk = code.slice(code.indexOf('create or replace function public.admin_entry_matrix_reread'), code.indexOf('revoke all on function public.admin_entry_matrix_reread'))
const OLD = [...m.matchAll(/\$o\$([\s\S]*?)\$o\$/g)].map((x) => x[1])
const NEW = [...m.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map((x) => x[1])
const w28 = fs.readFileSync(`${DIR}/20261029120000_cf247_aer_reread_newest_copy.sql`, 'utf8')
const before = fs.readFileSync(`${DIR}/20261026008000_cf247_entry_matrix_reread.sql`, 'utf8')

const NEWEST_ORDER = 'order by (content_hash is not distinct from v_src.content_hash) desc, created_at desc, id desc limit 1'

// The bulk rules of the migration, modelled on rows. sources: {id, content_hash}; runs as stored in pipeline.entry_matrix_runs; items: id -> status
function bulkReread(ids, sources, runs, items) {
  const out = { requeued: [], superseded_items: [], older_items: [], older_rows_runs: [], skipped: [] }
  for (const id of [...new Set(ids)].sort()) {
    const src = sources.find((s) => s.id === id)
    if (!src) { out.skipped.push({ source: id, why: 'not_found' }); continue }
    const own = runs.filter((r) => r.source_id === id)
    const newest = [...own].sort((a, b) =>
      Number(b.content_hash === src.content_hash) - Number(a.content_hash === src.content_hash) ||
      b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id))[0]
    if (!newest) { out.skipped.push({ source: id, why: 'never_read' }); continue }
    if (['queued', 'leased'].includes(newest.state)) { out.skipped.push({ source: id, why: 'already_waiting' }); continue }
    for (const r of own.filter((x) => x.id !== newest.id)) {  // older copies: closed, never re-queued, run left as it is
      const st = items[r.review_item_id]
      if (!r.review_item_id || st === 'pending') out.older_rows_runs.push(r.id)
      if (st === 'pending') { out.older_items.push(r.review_item_id); out.superseded_items.push(r.review_item_id) }
    }
    if (['done', 'failed'].includes(newest.state)) {
      out.requeued.push(newest.id)
      if (items[newest.review_item_id] === 'pending') out.superseded_items.push(newest.review_item_id)
    }
  }
  return out
}

test('md5-guarded: both live definitions are checked before anything changes; the snapshot edits apply exactly once', () => {
  expect(FILE).toBeTruthy()
  expect(code).toContain("if md5(pg_get_functiondef('public.admin_entry_matrix_reread(uuid[],text)'::regprocedure)) <> 'ca394b60216ef06dfc2ce9db265e8efe' then")
  expect(code).toContain("if md5(pg_get_functiondef('security.governed_aer_close_snapshot_v1()'::regprocedure)) <> '55910cb4111d48c54f48add915993923' then")
  expect(code.indexOf("'ca394b60216ef06dfc2ce9db265e8efe' then")).toBeLessThan(code.indexOf('create or replace function public.admin_entry_matrix_reread'))
  expect(code).toContain("select pg_temp.edit_n('security.governed_aer_close_snapshot_v1()', '55910cb4111d48c54f48add915993923', array[")
  expect(code).toContain('], array[1, 1, 1]);')
  expect(code).toContain('if md5(v_def) <> p_md5 then raise exception')
  expect(OLD).toHaveLength(3)
  expect(m).toMatch(/^-- Governed snapshot change approved: Platform Admin, 30 Oct 2026 06:53 \(A5 approved; decision paper Option A, the recommended default\)$/m)
})

test('the newest stored copy is chosen with W28’s ordering, verbatim in both Read again paths, and only that run is re-queued', () => {
  expect(w28).toContain(`select * into v_run from pipeline.entry_matrix_runs where source_id = v_src.id\n   ${NEWEST_ORDER};`)
  expect(bulk).toContain(`select * into v_run from pipeline.entry_matrix_runs where source_id = v_src.id\n     ${NEWEST_ORDER} for update;`)
  // one source at a time, ascending, locked; the old loop over every done or failed run of the sources is gone
  expect(bulk).toContain('for v_sid in select distinct u from unnest(p_source_ids) u order by 1 loop')
  expect(bulk).toContain('select * into v_src from pipeline.entry_matrix_sources where id = v_sid for update;')
  expect(bulk).not.toContain('source_id = any(p_source_ids)')
  expect(bulk.match(/update pipeline\.entry_matrix_runs/g)).toHaveLength(1)
  expect(bulk.match(/state = 'queued'/g)).toHaveLength(1)
  expect(bulk).toMatch(/state = 'queued'[\s\S]*?\n\s+where id = v_run\.id;/)
  // older copies: W28's closing statements, rows first then the pending item; decided items and their rows untouched
  expect(bulk).toContain("status_reason = 'older stored copy; read again on the newest copy: ' || v_reason")
  expect(bulk).toContain("where r.source_id = v_src.id and r.id <> v_run.id and (li.id is null or li.status = 'pending'));")
  expect(bulk).toContain("where li.status = 'pending' and li.id in (select r.review_item_id from pipeline.entry_matrix_runs r where r.source_id = v_src.id and r.id <> v_run.id);")
  expect(bulk.indexOf("'older stored copy; read again")).toBeLessThan(bulk.indexOf("update pipeline.layer4_review_items li set status = 'superseded'"))
  // D3 keys of the earlier result kept
  for (const k of ["'state', v_run.state", "'error', v_run.error", "'attempts_used', v_run.attempts", "'earlier_index', jsonb_array_length(v_run.previous_results)"]) expect(bulk).toContain(k)
})

test('skips: unknown, never read and already waiting are reported, not raised; held_unparsed stays re-readable in bulk', () => {
  expect([...bulk.matchAll(/'why', '([a-z_]+)'/g)].map((x) => x[1])).toEqual(['not_found', 'never_read', 'already_waiting'])
  expect(bulk).not.toContain("raise exception 'source not found'")
  expect(bulk).toContain("if v_run.state in ('queued', 'leased') then")
  expect(bulk).toContain("if v_run.state in ('done', 'failed') then")
  expect(bulk).not.toMatch(/held_unparsed%|entry_matrix_enabled_v1|ai_use_allowed_v1|text\/markdown/)  // no new guard; no markdown re-fetch
  // role check (A3/A5, 30 Oct 2026): the old current_user test never fired inside a security definer function (any signed-in user could call it);
  // an API request (JWT claims present) must now be a Platform Admin, a direct owner session (a migration) has no claims. Reason and non-empty array unchanged.
  expect(bulk).not.toContain("if current_user <> 'postgres'")
  expect(bulk).toContain("if (auth.uid() is not null or coalesce(auth.role(), '') <> '') and (auth.uid() is null or security.current_role_rank() < 6) then raise exception 'Platform Admin required' using errcode = '42501'; end if;")
  expect(bulk).toContain("if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'reason required'; end if;")
  expect(bulk).toContain("if coalesce(array_length(p_source_ids, 1), 0) = 0 then raise exception 'no sources given'; end if;")
})

test('row model: Otago two-copy fixture, an already-waiting source, a never-read source, a held_unparsed run, a decided older item and an unknown id', () => {
  const OTAGO = 'd74fcba4-a492-4cde-a1f0-70a398e6bfda'
  const sources = [{ id: OTAGO, content_hash: '370a12ce' }, { id: 'b', content_hash: 'b2' }, { id: 'c', content_hash: 'c1' }, { id: 'd', content_hash: 'd1' }, { id: 'e', content_hash: 'e2' }]
  const runs = [
    { id: '0d4ca5a0-e33e-427f-bc81-6fef13af5490', source_id: OTAGO, content_hash: 'fb572a9f', state: 'done', created_at: '2026-10-28T14:39:00Z', review_item_id: 'f14ae480' },
    { id: '55ace659-60b6-4657-b9c3-ced94dc7dac1', source_id: OTAGO, content_hash: '370a12ce', state: 'done', created_at: '2026-10-29T00:19:00Z', review_item_id: '81d14690' },
    { id: 'b-old', source_id: 'b', content_hash: 'b1', state: 'done', created_at: '2026-10-20T00:00:00Z', review_item_id: 'b-item' },
    { id: 'b-new', source_id: 'b', content_hash: 'b2', state: 'queued', created_at: '2026-10-21T00:00:00Z' },
    { id: 'd-run', source_id: 'd', content_hash: 'd1', state: 'failed', error: 'held_unparsed: no printed scale', created_at: '2026-10-20T00:00:00Z' },
    { id: 'e-old', source_id: 'e', content_hash: 'e1', state: 'done', created_at: '2026-10-20T00:00:00Z', review_item_id: 'e-decided' },
    { id: 'e-new', source_id: 'e', content_hash: 'e2', state: 'failed', created_at: '2026-10-19T00:00:00Z', review_item_id: 'e-item' },
  ]
  const items = { f14ae480: 'pending', '81d14690': 'pending', 'b-item': 'pending', 'e-decided': 'rejected', 'e-item': 'pending' }
  const out = bulkReread([OTAGO, 'b', 'c', 'd', 'e', 'unknown', OTAGO], sources, runs, items)
  // exactly one run per readable source; the older Otago copy is not re-queued; the stored copy, not creation order, decides (source e)
  expect(out.requeued.sort()).toEqual(['55ace659-60b6-4657-b9c3-ced94dc7dac1', 'd-run', 'e-new'])
  expect(out.older_items).toEqual(['f14ae480'])
  expect(out.older_rows_runs).toEqual(['0d4ca5a0-e33e-427f-bc81-6fef13af5490'])  // e-old's item is decided: its rows are left alone
  expect(out.superseded_items.sort()).toEqual(['81d14690', 'e-item', 'f14ae480'])
  expect(out.superseded_items).not.toContain('b-item')  // already waiting: older runs of that source not touched either
  expect(out.skipped).toEqual([{ source: 'b', why: 'already_waiting' }, { source: 'c', why: 'never_read' }, { source: 'unknown', why: 'not_found' }])
  // the replaced function re-queued every done or failed run of the sources: 6 here, the older copies and the waiting source's older run included
  expect(runs.filter((r) => ['done', 'failed'].includes(r.state))).toHaveLength(6)
})

test('the return and the event are additive: existing keys keep their meaning, new keys added', () => {
  const ret = bulk.slice(bulk.lastIndexOf('return jsonb_build_object('))
  for (const k of ["'ok', true", "'runs', v_runs", "'rows_superseded', v_rows + v_older_rows", "'items_superseded', v_items + v_older_items", "'older_items_superseded', v_older_items", "'skipped', v_skipped"]) expect(ret).toContain(k)
  for (const k of [...before.matchAll(/return jsonb_build_object\(([^;]*)\);/g)].flatMap((x) => [...x[1].matchAll(/'([a-z_]+)'/g)].map((y) => y[1]))) expect(ret).toContain(`'${k}'`)
  const ev = bulk.slice(bulk.indexOf('insert into pipeline.admin_control_events'), bulk.lastIndexOf('return jsonb_build_object('))
  expect(ev).toContain("values ('entry_matrix', 'reread', 'pipeline.entry_matrix_runs',")
  for (const k of ["'sources', to_jsonb(p_source_ids)", "'runs', v_runs", "'reason', v_reason", "'run_ids', v_ids", "'older_rows_superseded', v_older_rows", "'older_items_superseded', v_older_items", "'skipped', v_skipped"]) expect(ev).toContain(k)
  expect(m).toContain('grant execute on function public.admin_entry_matrix_reread(uuid[], text) to authenticated;')
  expect(m).toContain('revoke all on function public.admin_entry_matrix_reread(uuid[], text) from public, anon;')
})

test('governed snapshot, Option A: the recorded md5s stay; the drift check is reported completed only after the action is done', () => {
  expect(NEW.join('\n')).not.toContain('c_md5 constant')  // the record of what was approved is not rewritten
  expect(NEW.join('\n')).not.toContain('ca394b60216ef06dfc2ce9db265e8efe')
  expect(NEW[1]).toContain("select max(finished_at) into v_done_at from pipeline.admin_jobs where kind = 'governed_action' and args->>'action' = 'aer_pr_a_recovery_close' and state = 'done';")
  expect(NEW[2]).toContain("case when v_done_at is null or v_md5 = c_md5")
  expect(NEW[2]).toContain("'ok', v_md5 = c_md5)")  // strict before completion
  expect(NEW[2]).toContain("'; functions changed since by later change control') end);")
  expect(NEW.join('\n')).not.toMatch(/\b(insert|update|delete)\b/i)  // still read only
  // post-check: new md5s, the W28 ordering, the record kept, grants, the check reported completed
  expect(code).toContain("if md5(v_bulk) <> 'e2566cb6c2153d2414adb77dcfefb8c8' then")
  expect(code).toContain("if md5(v_snap) <> 'af76dcb7304db1cd6efbaf41f3f89b3a' then")
  expect(code).toContain(`if position('${NEWEST_ORDER}' in v_bulk) = 0 then`)
  expect(code).toContain(`if position('"public.admin_entry_matrix_reread(uuid[],text)":"ca394b60216ef06dfc2ce9db265e8efe"' in v_snap) = 0 then`)
})

test('the migration executes no re-read, adds no vocabulary, and names what it replaces', () => {
  const outside = code.replace(bulk, '')
  expect(outside).not.toMatch(/(admin_entry_matrix_reread|aer_reread_v1)\(\s*array/)
  expect(outside).not.toMatch(/\bupdate (pipeline|catalogue)\./)
  expect([...bulk.matchAll(/status = '([a-z_]+)'/g)].map((x) => x[1]).every((s) => ['pending', 'proposed', 'superseded'].includes(s))).toBe(true)
  expect(new Set([...bulk.matchAll(/state = '([a-z_]+)'/g)].map((x) => x[1]))).toEqual(new Set(['queued']))
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(m).toMatch(/^-- Replaces: public\.admin_entry_matrix_reread \(same name and signature, md5-guarded whole-body replacement\); security\.governed_aer_close_snapshot_v1/m)
  expect(m).toMatch(/^-- Retires: nothing$/m)
})
