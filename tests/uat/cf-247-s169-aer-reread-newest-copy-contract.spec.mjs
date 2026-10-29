// Guards: CF-247 decision W28 (29 Oct 2026): Read again re-queues only the run on the newest stored copy of a source; runs on older copies keep their history and their still-pending Layer 4 item is superseded with existing statuses; md5-guarded edit of security.aer_reread_v1; no new status; nothing dropped or deleted
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const FILE = fs.readdirSync('supabase/migrations').find((f) => /^20261029(\d{6}|XXXXXX)_cf247_aer_reread_newest_copy\.sql$/.test(f))
const m = fs.readFileSync(`supabase/migrations/${FILE}`, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
// the replacement texts ($n$ ... $n$) are the new function body; the originals ($o$ ... $o$) are what live must contain
const NEW = [...m.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map((x) => x[1]).join('\n')
const OLD = [...m.matchAll(/\$o\$([\s\S]*?)\$o\$/g)].map((x) => x[1])

const NEWEST_ORDER = 'order by (content_hash is not distinct from v_src.content_hash) desc, created_at desc, id desc limit 1'

// The selection and closing rules of the migration, modelled on rows (one source; runs as stored in pipeline.entry_matrix_runs)
function reread(source, runs, items) {
  const newest = [...runs].sort((a, b) =>
    Number(b.content_hash === source.content_hash) - Number(a.content_hash === source.content_hash) ||
    b.created_at.localeCompare(a.created_at) || b.id.localeCompare(a.id))[0]
  const out = { requeued: [], superseded_items: [], untouched_runs: [] }
  for (const r of runs) {
    const item = items[r.review_item_id]
    if (r.id === newest.id) {
      out.requeued.push(r.id)
      if (item === 'pending') out.superseded_items.push(r.review_item_id)
    } else {
      out.untouched_runs.push(r.id) // state, result, previous_results and review_item_id kept
      if (item === 'pending') out.superseded_items.push(r.review_item_id)
    }
  }
  return out
}

test('the edit is md5-guarded against the live definition and applies each change exactly once', () => {
  expect(code).toContain("create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[])")
  expect(code).toContain("if md5(v_def) <> p_md5 then raise exception")
  expect(code).toContain("select pg_temp.edit_n('security.aer_reread_v1(uuid,text,uuid)', '7da109835cf52fb9790778eec6882664', array[")
  expect(code).toContain('], array[1, 1, 1, 1]);')
  expect(OLD).toHaveLength(4)
  expect(OLD[0]).toBe('  select * into v_run from pipeline.entry_matrix_runs where source_id = v_src.id order by created_at desc limit 1;')
  expect(OLD[1]).toContain('return public.admin_entry_matrix_reread(array[v_src.id], v_reason);')
})

test('Read again selects the run on the newest stored copy and re-queues only that run', () => {
  expect(NEW).toContain(`select * into v_run from pipeline.entry_matrix_runs where source_id = v_src.id\n   ${NEWEST_ORDER};`)
  // the whole-source hand-off that re-queued every copy is gone; only v_run is set back to queued
  expect(NEW).not.toContain('admin_entry_matrix_reread(')
  expect(NEW.match(/state = 'queued'/g)).toHaveLength(1)
  expect(NEW).toMatch(/state = 'queued'[\s\S]*?\n\s+where id = v_run\.id;/)
  // older copies: proposed rows then the pending item superseded; runs of decided items untouched
  expect(NEW).toContain("where m.status = 'proposed' and m.run_id in (select r.id from pipeline.entry_matrix_runs r left join pipeline.layer4_review_items li on li.id = r.review_item_id")
  expect(NEW).toContain("where r.source_id = v_src.id and r.id <> v_run.id and (li.id is null or li.status = 'pending'));")
  expect(NEW).toContain("where li.status = 'pending' and li.id in (select r.review_item_id from pipeline.entry_matrix_runs r where r.source_id = v_src.id and r.id <> v_run.id);")
  expect(NEW).toContain("update pipeline.layer4_review_items set status = 'superseded' where id = v_run.review_item_id and status = 'pending';")
  // no update of an older run's row: the only update of entry_matrix_runs targets v_run
  expect(NEW.match(/update pipeline\.entry_matrix_runs/g)).toHaveLength(1)
})

test('Otago Polytechnic two-copy fixture: only the 370a12ce copy is read again, the stale item is closed', () => {
  const source = { id: 'd74fcba4-a492-4cde-a1f0-70a398e6bfda', content_hash: '370a12ce' }
  const runs = [
    { id: '0d4ca5a0-e33e-427f-bc81-6fef13af5490', content_hash: 'fb572a9f', created_at: '2026-10-28T14:39:00Z', review_item_id: 'f14ae480' },
    { id: '55ace659-60b6-4657-b9c3-ced94dc7dac1', content_hash: '370a12ce', created_at: '2026-10-29T00:19:00Z', review_item_id: '81d14690' },
  ]
  expect(reread(source, runs, { f14ae480: 'pending', '81d14690': 'pending' })).toEqual({
    requeued: ['55ace659-60b6-4657-b9c3-ced94dc7dac1'],
    superseded_items: ['f14ae480', '81d14690'],
    untouched_runs: ['0d4ca5a0-e33e-427f-bc81-6fef13af5490'],
  })
  // newest is decided by the stored copy, not by creation order
  const swapped = runs.map((r) => ({ ...r, created_at: r.id.startsWith('0d4c') ? '2026-10-30T00:00:00Z' : r.created_at }))
  expect(reread(source, swapped, {}).requeued).toEqual(['55ace659-60b6-4657-b9c3-ced94dc7dac1'])
  // an item already decided is not touched
  expect(reread(source, runs, { f14ae480: 'rejected', '81d14690': 'pending' }).superseded_items).toEqual(['81d14690'])
})

test('no new vocabulary, gates untouched, nothing dropped or deleted, housekeeping lines', () => {
  const statuses = new Set([...NEW.matchAll(/status = '([a-z_]+)'/g)].map((x) => x[1]))
  for (const s of statuses) expect(['pending', 'proposed', 'superseded']).toContain(s)
  const states = new Set([...NEW.matchAll(/state = '([a-z_]+)'/g)].map((x) => x[1]))
  for (const s of states) expect(['queued', 'done']).toContain(s)
  expect([...NEW.matchAll(/values \('entry_matrix', '([a-z_]+)'/g)].map((x) => x[1])).toEqual(['reread'])
  // the guards are not among the edited texts
  for (const g of ["'give a reason", 'entry_matrix_enabled_v1', "ai_use_allowed_v1('entry_matrix')", "'held_unparsed%'", "('queued', 'leased')"]) {
    expect(OLD.join('\n')).not.toContain(g)
  }
  expect(code).not.toMatch(/svc_entry_matrix_record|entry_matrix_identity|completeness|status = 'active'|'approved'/)
  expect(code).not.toMatch(/website_|zoho_|\bapi\./)
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(m).toMatch(/^-- Replaces: security\.aer_reread_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})
