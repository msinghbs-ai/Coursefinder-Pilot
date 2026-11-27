// Guards: SS-Programme-Control 27 Nov 2026 13:39 and 13:43 AEDT (P0 reader plugin implementation) and Platform Admin direction 27 Nov 2026 (coursefinder-admin #1293: reader configuration is data, no per-institute CI); CLAUDE.md "A passing qualification never switches anything on by itself"
// CF-247 s1310. supabase/migrations/20261130171000_cf247_s1310_reader_config_operations.sql, src/ReaderConfigs.jsx, scripts/reader-config-ops.mjs, .github/workflows/reader-config-ops.yml
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261130171000_cf247_s1310_reader_config_operations.sql', 'utf8')
const ui = fs.readFileSync('src/ReaderConfigs.jsx', 'utf8')
const tab = fs.readFileSync('src/AdapterBuilderTab.jsx', 'utf8')
const ops = fs.readFileSync('scripts/reader-config-ops.mjs', 'utf8')
const wf = fs.readFileSync('.github/workflows/reader-config-ops.yml', 'utf8')

test('a configuration is a closed list: registered reading.entry_ settings within their ranges, an address pattern, country from the address, hosts of the provider', () => {
  expect(sql).toContain("if v_t not in ('country_page_generic_heading', 'provider_settings') then raise exception 'INVALID_INPUT: template")
  expect(sql).toContain("if k !~ '^reading\\.entry_[a-z0-9_]+$' or s.key is null then raise exception")
  expect(sql).toContain('x::text::numeric < s.min_value')
  expect(sql).toContain("not (h = v_base or h like '%.' || v_base)")
  expect(sql).toContain("raise exception 'INVALID_INPUT: no entry-matrix source of this provider matches url_like'")
  expect(sql).not.toMatch(/execute\s+p_|execute\s+v_cfg|format\(.*p_args/i)
})

test('a draft is never leased; qualify queues stored-copy samples for the existing worker lease; a pass switches nothing on', () => {
  expect(sql).toContain("security.reader_config_samples_v1(v_dom, v_pid, v_cfg->>'url_like', p_args->'samples', 'draft')")
  expect(sql).toContain("(x.configuration->>'provider_id')::uuid, x.configuration->>'url_like',")
  expect(sql).toContain("'queued');")
  expect(sql).not.toMatch(/insert into pipeline\.layer2_source_profiles[\s\S]{0,400}values \([^)]*true, false/)
  expect(sql).toContain("'pending', jsonb_build_object('draft', true")
})

test('activation is the existing step and authority; scholarships stay held; the operations path never grants authority', () => {
  expect(sql).toContain("security.reader_activate_sch_v1(x.id) else security.reader_activate_v1(x.id) end")
  expect(sql).toContain("if p_action in ('activate', 'pause', 'resume', 'rollback') and p_rank < 6 then raise exception 'Platform Admin role required'")
  expect(sql).not.toContain('ops_learning_eligibility_set_v1(')
  expect(sql).toContain("('reader_config:aer_matrix:provider_settings', 'aer'")
})

test('negatives by class, the maintenance step, version history and annual requalification', () => {
  expect(sql).toContain("then e.value->>''outcome'' in (''deterministic_read'', ''guard_passed'') else e.value->>''outcome'' <> ''guard_held'' end)")
  expect(sql).toContain("v_neg_bad = 0;")
  expect(sql).toContain("perform security.reader_config_maintain_v1();  -- s1310")
  expect(sql).toContain("'reader.requalify_days'")
  expect(sql).toContain("make_interval(days => v_days)")
  expect(sql).toContain("'paused_requalification_failed'")
  for (const m of ['39a7b937df4feae498a3bee1793a3d7b', '0e0ea7b891eb4688f998ba991dce7e94', 'b42617c90c58499582670c4240bc075b']) expect(sql).toContain(m)
})

test('every write has a reason and a log line; nothing is dropped or deleted; the consumer API, cron and locks are checked', () => {
  expect(sql).toContain("if p_action <> 'list' and v_reason = '' then raise exception 'INVALID_INPUT: a reason is required'")
  for (const a of ['draft_saved', 'qualify_requested', 'activation_requested', 'rolled_back', 'draft_discarded']) expect(sql).toContain(`'${a}'`)
  expect(sql).not.toMatch(/\bdrop\s+(table|function|view|column|index|schema|policy)\b|\bdelete\s+from\b|\btruncate\s+/i)
  expect(sql).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect(sql).toMatch(/-- Replaces: .*\n/)
  expect(sql).toMatch(/-- Retires: nothing\./)
})

test('the screen: step 5 of the Adapter builder reads and writes through admin_reader_configs_v1 only, with no list written into the code', () => {
  expect(tab).toContain("<span className=\"ab-num\">5</span> Reader configurations (academic entry and scholarships)")
  expect(tab).toContain('<ReaderConfigs providerId={b.provider_id}')
  expect(ui.match(/supabase\.rpc\('([a-z_0-9]+)'/g).every((m) => m.includes('admin_reader_configs_v1'))).toBe(true)
  expect(ui).toContain("(d.settings||[]).map(s=><option key={s.key}")
  expect(ui).toContain('data-reader-activate')
  expect(ui).toContain('data-reader-rollback')
  expect(ui).toContain('data-reader-requalify')
})

test('the operations workflow calls only the governed writer (one call per operation) and needs a reason', () => {
  expect(ops).toContain("select public.svc_reader_configs_v1(${lit(o.action)}, ${lit(JSON.stringify(o.args || {}))}::jsonb, ${lit(by)}) as r")
  expect(ops).toContain('const rows = await op(q)')
  expect(sql).toContain("if p_action = 'list' then")
  expect(ops).toContain("needs a reason")
  expect(wf).toContain('workflow_dispatch:')
  expect(wf).not.toMatch(/\bpush:|\bschedule:|pull_request/)
})
