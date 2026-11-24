// Guards: Layer 1 Register fixes (Platform Admin 18 Nov 2026 10:51): overdue next ingestion dates are moved on by the unified dispatcher (rollup-scheduler target, no new cron job), only readers proven superseded by coverage-sweep are retired (kept, paused; checked at apply), readers with no other path stay under Needs attention, QS verification is reconciled only from an applied publisher file, and register headings never slide over the filter bar or + Add source.
// CF-247 S624. supabase/migrations-archive/20261118125000_cf247_layer1_register_due_roll_and_reconcile.sql; src/mature.css.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118125000_cf247_layer1_register_due_roll_and_reconcile.sql', 'utf8')
const CSS = fs.readFileSync('src/mature.css', 'utf8')

test('overdue next ingestion dates move on through a live rollup-scheduler target', () => {
  expect(M).toContain("values ('layer1-next-due-roll', null, 'select security.layer1_next_due_roll_v1()', md5('select security.layer1_next_due_roll_v1()'), '23 * * * *', 'A', 60, true, 'live', 1000,")
  expect(M).toContain("where o.active and not o.paused and s.status <> 'retired' and o.next_ingestion_at < now()")
  expect(M).toContain("and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id = o.source_id and q.status in ('queued', 'running'))")
  expect(M).toContain("raise exception 'post-check: an overdue next ingestion date was not moved on'")
  expect(M).not.toMatch(/cron\.schedule\(/)
})

test('only superseded readers are retired, checked at apply, and kept', () => {
  expect(M).toContain("raise exception 'source % is not superseded by coverage-sweep as read (course pages %, active courses %); not retired'")
  for (const l of ['Aurora College academic programmes', 'College of the North Atlantic programme guide', 'Confederation College full-time programme API', 'Loyalist College programme directory']) expect(M).toContain(`'${l}'`)
  expect(M).toContain("update pipeline.layer1_source_operations set paused = true, auto_ingest = false, updated_at = now(),")
  expect(M).toContain("raise exception 'post-check: a reader with no other path was retired'")
  expect(M).toContain("where kind = 'edge_function' and name in ('layer1-ca-cna-programs', 'layer1-ca-confederation-programs', 'layer1-ca-loyalist-programs') and status = 'active';")
  expect(M).not.toContain("'layer1-ca-firstparty-catalogues')")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(M).toMatch(/-- Replaces: nothing/)
  expect(M).toMatch(/-- Retires: the Layer 1 sources/)
})

test('QS verification is reconciled only from an applied publisher-file import', () => {
  expect(M).toContain("where m.system_id = sy.id and m.edition_year = (s.metadata->>'edition_year')::int and m.status = 'applied' order by m.uploaded_at desc limit 1) mi on true")
  expect(M).toContain("'); the automatic publisher read is not used for this edition.'")
})

test('register headings scroll with their rows and the toolbar stays above the list', () => {
  expect(CSS).toContain('[data-l1-sources] .xl-toolbar{position:relative;z-index:3}')
  expect(CSS).toContain('[data-l1-sources] .xl-row th{position:static}')
  expect(CSS).toContain('[data-l1-sources] .xl-head{position:static}')
  expect(fs.readFileSync('src/ui-v1/Layer1RegisterView.jsx', 'utf8')).toContain('<section className="ui-xl-page" data-l1-sources>')
})
