// Guards: CF-247 decision W27 (Platform Admin mandate 29 Oct 2026 16:59, Workstream 0): every writer of search.course_documents takes one transaction-scoped writer lock — the shared scoped refresh and every full rebuild wait for it, the scheduled search-refresh run only tries it and leaves its requests for the next run when it is held — and the scoped refresh locks its documents in ascending course_id; md5-guarded edits only, document values, consumer API, scholarship rules and Layer 4 unchanged, nothing dropped; the local concurrency reproduction (paste vs scheduled job, paste vs full rebuild, opposing scoped orders) is kept with a local-only guard
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261029110000_cf247_search_document_writer_lock.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const LOCK = "hashtext('cf247:search_course_documents_writer')"

test('one writer lock: scoped refresh and full rebuild wait for it, the scheduled run only tries it', () => {
  expect(code.match(new RegExp(`pg_advisory_xact_lock\\(${LOCK.replace(/[()]/g, '\\$&')}\\)`, 'g'))).toHaveLength(2)
  expect(code.match(new RegExp(`pg_try_advisory_xact_lock\\(${LOCK.replace(/[()]/g, '\\$&')}\\)`, 'g'))).toHaveLength(1)
  // the lock is a technical constant (G2), marked
  for (const line of m.split('\n').filter((l) => l.includes(LOCK))) expect(line).toContain('-- fixed:')
  // the scheduled run reports held with the result key it already uses, and leaves the requests unprocessed
  expect(code).toContain("return jsonb_build_object('pending', cardinality(v_ids), 'held', 'another search-document writer is running; the requests wait for the next run');")
})

test('the scoped refresh locks its documents in ascending course_id before updating, only when applying', () => {
  expect(code).toContain('perform 1 from search.course_documents d where d.course_id = any(p_course_ids) order by d.course_id for update;')
  const scoped = code.slice(code.indexOf("'search.refresh_course_enrichment_scoped_v1(uuid[],boolean)'"), code.indexOf("'search.refresh_course_documents_v3(boolean)'"))
  expect(scoped.indexOf('if p_apply then')).toBeLessThan(scoped.indexOf('pg_advisory_xact_lock'))
  expect(scoped.indexOf('order by d.course_id for update')).toBeLessThan(scoped.lastIndexOf('v_result := search.refresh_course_enrichment_core_scoped_v1'))
})

test('md5-guarded edits of the three live definitions; values, consumer API and rules untouched; nothing dropped', () => {
  for (const [sig, md5] of [['search.refresh_course_enrichment_scoped_v1(uuid[],boolean)', '52bff5be91bdbab2ce6d63031c5652c7'],
    ['search.refresh_course_documents_v3(boolean)', '40dc6d9707ad5a1cb019e525e3b887cb'], ['security.search_refresh_requested_v1()', 'bb78c8546a649ffb17ff0e676c7031e5']])
    expect(code).toContain(`select pg_temp.edit_n('${sig}', '${md5}', array[`)
  expect(code).toContain("if md5(v_def) <> p_md5 then raise exception")
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  expect(code).not.toMatch(/scholarship_sweep_apply_v1|course_mappings|layer4_review/)
  expect(code).not.toMatch(/\b(drop|delete from|truncate)\b/i)
  expect(m).toMatch(/^-- Replaces: search\.refresh_course_enrichment_scoped_v1/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})

test('the concurrency reproduction is kept, local-only, and models the three cases with the migration text verbatim', () => {
  const t = fs.readFileSync('tools/concurrency/w27-search-writer-lock.sh', 'utf8')
  expect(t).toContain('case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refused')
  for (const s of ['S1 paste vs scheduled job', 'S1b paste vs full rebuild', 'S2 scoped vs scoped, opposing orders']) expect(t).toContain(s)
  for (const line of ["    perform pg_advisory_xact_lock(hashtext('cf247:search_course_documents_writer'));  -- fixed: the one writer lock for search.course_documents (W27)",
    '    perform 1 from search.course_documents d where d.course_id = any(p_course_ids) order by d.course_id for update;',
    "  if not pg_try_advisory_xact_lock(hashtext('cf247:search_course_documents_writer')) then  -- fixed: the one writer lock (W27)"]) {
    expect(t).toContain(line)
    expect(m).toContain(line)
  }
})
