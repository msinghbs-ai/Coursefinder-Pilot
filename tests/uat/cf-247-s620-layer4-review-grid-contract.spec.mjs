// Guards: UI/UX audit Phase 5 first slice (Platform Admin 18 Nov 2026 10:09 "Start & Merge Phase 5 First Slice Immediately"; admin docs/platform/ui-audit/ui-ux-settings-audit-2026-11-15.md §4.2, §5, §7.3): Layer 4 › Inbox › Grid with saved views (three shared views, changed by a Platform Admin only, checked on the server), server paging, a bounded CSV export (layer4.grid_export_max_rows) and the Source Quote vs Extracted Value drawer; decisions still go only through admin_layer4_inbox, and no view changes the AER audit sample or the course-address rules.
// CF-247 S620. supabase/migrations-archive/20261118120000_cf247_phase5_review_grid_saved_views.sql, src/Layer4Grid.jsx, src/lib/layer4-grid.js, src/Layer4Inbox.jsx.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { GRID_COLUMNS, DEFAULT_COLS, toCsv, quoteValuePairs, urlOf } from '../../src/lib/layer4-grid.js'

const M = fs.readFileSync('supabase/migrations-archive/20261118120000_cf247_phase5_review_grid_saved_views.sql', 'utf8')
const G = fs.readFileSync('src/Layer4Grid.jsx', 'utf8')
const I = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')

test('the migration adds saved views with the three shared views and checks who changes them on the server', () => {
  expect(M).toContain('create table if not exists pipeline.saved_views (')
  expect(M).toMatch(/comment on table pipeline\.saved_views is/)
  expect(M).toContain("check ((scope = 'shared' and owner_id is null and code is not null) or (scope = 'personal' and owner_id is not null))")
  for (const code of ['aer_audit_samples', 'official_urls', 'provider_blockers']) expect(M).toContain(`'${code}'`)
  expect(M).toContain("'why_contains', 'audit_sample'")
  expect(M).toContain("raise exception 'a shared view is changed by a Platform Admin only'")
  expect(M).toContain("'saved_view_archive'")
  expect(M).toMatch(/-- Replaces: /)
  expect(M).toMatch(/-- Retires: nothing\./)
})

test('the grid read is paged by settings, bounded, read only and limited to the built-in kinds', () => {
  expect(M).toContain("security.pipeline_num_v1('layer4.grid_export_max_rows', 5000)")
  expect(M).toContain("security.pipeline_num_v1('layer4.inbox_page_size', 200)")
  expect(M).toContain("'layer4.grid_export_max_rows', 'Layer 4 grid: rows a CSV export holds'")
  expect(M).toContain("not (security.layer4_inbox_kinds_v1() ? v_kind)")
  expect(M).toContain("'grid_kinds', coalesce((select jsonb_agg(k order by k) from jsonb_object_keys(security.layer4_inbox_kinds_v1()) k), '[]'::jsonb)")
  const read = M.slice(M.indexOf('create or replace function public.admin_layer4_grid_read_v1'), M.indexOf('create or replace function public.admin_layer4_item_trace_v1'))
  expect(read).toContain(' stable\n')
  expect(read).not.toMatch(/\b(insert|update|delete)\s+(into\s+)?(pipeline|catalogue)\./i)
})

test('the drawer reads the item, its evidence and its decision history without deciding anything', () => {
  const trace = M.slice(M.indexOf('create or replace function public.admin_layer4_item_trace_v1'))
  expect(trace).toContain("security.layer4_inbox_items_v2(null, p_kind, array[p_kind || ':' || p_ref], true)")
  expect(trace).toContain("c.area = 'layer4' and c.target = p_ref")
  expect(trace).not.toMatch(/\b(insert|update|delete)\s+(into\s+)?(pipeline|catalogue)\./i)
  expect(M).not.toMatch(/(select|perform)\s+(public\.)?admin_layer4_inbox\s*\(/i)
  expect(M).toContain("security.pipeline_num_v1('aer.machine_audit_pct', -1) < 0")
})

test('the Inbox has a Grid view and decisions in the drawer use the Inbox card', () => {
  expect(fs.readFileSync('src/Layer4AdvancedFilters.jsx', 'utf8')).toContain("['university','By university'],['kind','By kind'],['grid','Grid'],['decided','Decided']") // s931: the views are under Advanced filters
  expect(I).toContain("view==='grid'?<Layer4Grid kinds={kinds}")
  expect(I).toContain('renderItem={(it,done)=><Item it={it}')
  expect(G).toContain("call('admin_layer4_grid_read_v1'")
  expect(G).toContain("call('admin_layer4_item_trace_v1'")
  expect(G).toContain("call('admin_saved_view_save_v1'")
  expect(G).not.toMatch(/(call|rpc)\('admin_layer4_inbox'/)
  expect(G).toContain('<h3>Source quote and extracted value</h3>')
  expect(G).toContain('A view chooses the kind, the reason filter, the order and the columns; it never changes a rule')
  expect(G).toContain('Shared views are changed by a Platform Admin.')
})

test('the pure helpers: columns, CSV quoting and quote/value pairs per kind', () => {
  expect(Object.keys(GRID_COLUMNS)).toEqual(['kind', 'subject', 'provider', 'country', 'why', 'suggestion', 'created_at', 'age_days'])
  for (const c of DEFAULT_COLS) expect(GRID_COLUMNS[c]).toBeTruthy()
  expect(toCsv([{ subject: 'Bachelor, "Arts"', age_days: 3 }], ['subject', 'age_days'])).toBe('Item,Days waiting\r\n"Bachelor, ""Arts""",3')
  expect(urlOf('javascript:alert(1)')).toBeNull()
  expect(urlOf('https://example.edu/a')).toBe('https://example.edu/a')
  const link = quoteValuePairs({ detail: { before: ['https://old.example.edu'], proposed: { course_url: 'https://new.example.edu' } } })
  expect(link).toEqual([{ quote: '', value: 'https://new.example.edu', before: 'https://old.example.edu', link: true }])
  const aer = quoteValuePairs({ detail: { proposed: { url: 'https://u.example.edu/entry', sample: [{ kind: 'atar', description: 'ATAR 80', quote: 'Selection rank 80' }] } } })
  expect(aer[0]).toEqual({ quote: 'Selection rank 80', value: 'atar · ATAR 80' })
  expect(quoteValuePairs({ detail: { evidence: { page_url: 'https://down.example.edu' } } })).toEqual([{ quote: '', value: 'https://down.example.edu', link: true }])
  expect(quoteValuePairs({ detail: {} })).toEqual([])
})
