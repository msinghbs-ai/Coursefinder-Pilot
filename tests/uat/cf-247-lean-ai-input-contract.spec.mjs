// Guards: CF-247 Lean AI Input Phase 1 (Platform Admin 13 Nov 2026 22:51 "StudySearch — Lean AI Input and Evidence Optimisation"; admin docs/platform/LEAN-AI-INPUT-PHASE0-BASELINE-2026-11-13.md §4 and
// SHARED-SOURCE-TO-PUBLISHED-ENRICHMENT-DESIGN.md §11): observe first, change nothing that admits. The structured text keeps headings, table rows with their headers and offsets; the preflight is
// high-recall and shadow only (never used to skip a read); every enrich_ai course-page read is observed (source length, sent length, cut, preflight on sent and whole text, input hash, fingerprint)
// through public.svc_ai_input_observe_v1; a failure to observe never fails a read; retention, purge size and the switch are settings.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { LEAN_CONVERTER, OBSERVATION_CONTRACT, leanText, preflight, observation, fingerprint } from '../../supabase/functions/coverage-sweep/lean-input.ts'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261113400000_cf247_lean_ai_input_observations.sql', 'utf8')

const page = `<html><nav>Menu Courses Fees Deadline</nav><main>${'<p>About the course and its graduates.</p>'.repeat(60)}<h2>Fees</h2><table><thead><tr><th>Year</th><th>International fee</th></tr></thead>` +
  `<tbody><tr><td>2026</td><td>A$45,000</td></tr><tr><td>2027</td><td>A$46,500</td></tr></tbody></table><h2>Key dates</h2><ul><li>Applications close 30 November</li><li>Semester 1 starts February</li></ul>` +
  `<script>var applicationsClose = "never";</script><p>IELTS 6.5 overall with no band below 6.0.</p></main><footer>Apply by tomorrow</footer></html>`

test('lean-md-v1: headings, table rows with their column headers, list items, offsets back into the text and the stored page; navigation, footer and scripts left out', () => {
  const l = leanText(page)
  expect(l.converter).toBe(LEAN_CONVERTER)
  expect(LEAN_CONVERTER).toBe('lean-md-v1')
  expect(l.tables).toBe(1)
  expect(l.table_rows).toBe(2)
  expect(l.text).toContain('## Fees\nYear: 2026 | International fee: A$45,000\nYear: 2027 | International fee: A$46,500\n## Key dates\n- Applications close 30 November\n- Semester 1 starts February')
  expect(l.text).not.toContain('Menu Courses')
  expect(l.text).not.toContain('Apply by tomorrow')
  expect(l.text).not.toContain('applicationsClose')
  for (const b of l.blocks) {
    const shown = l.text.slice(b.start, b.end)
    expect(shown.endsWith(b.text)).toBe(true)
    expect(page.slice(b.source_at, b.source_at + 1)).toBe('<')
  }
  const row = l.blocks.find((b) => b.kind === 'table_row')
  expect(page.slice(row.source_at, row.source_at + 6)).toBe('<table')
  // deterministic
  expect(leanText(page)).toEqual(l)
})

test('preflight is high-recall and three-way: only "likely" is a positive claim; a weak signal is "unknown", never "no_signal"', () => {
  expect(preflight('deadline', 'Applications close 30 November')).toBe('likely')
  expect(preflight('deadline', 'Submit by 30 November')).toBe('unknown')   // a date with no deadline word stays open
  expect(preflight('deadline', 'Study engineering with us.')).toBe('no_signal')
  expect(preflight('english', 'IELTS 6.5 overall')).toBe('likely')
  expect(preflight('english', 'strong English skills')).toBe('unknown')
  expect(preflight('intakes', 'The course starts in March')).toBe('likely')
  expect(preflight('intakes', 'March')).toBe('unknown')
  expect(preflight('entry_requirements', 'Minimum ATAR 80')).toBe('likely')
  expect(preflight('duration', '3 years full-time')).toBe('likely')
  expect(preflight('description', 'short')).toBe('unknown')                 // always asked: never no_signal
  expect(preflight('description', 'x'.repeat(250))).toBe('likely')
  expect(preflight('unknown_field', 'anything')).toBe('not_measured')
})

test('an observation names the cut and the field signalled only beyond it; the fingerprint follows input, field, prompt, model and schema', async () => {
  const l = leanText(page)
  const src = 'Course overview. '.repeat(1600) + 'Applications close 30 November.'
  const o = await observation({ read: 'course_deadline', field: 'deadline', item_id: 7, source_text: src, sent_text: src.slice(0, 24000), limit_chars: 24000, lean: l,
    prompt_key: 'course-text-v2', model: 'qwen/qwen3-30b-a3b-instruct-2507', schema_key: 'course_text:deadline', worker: 'w' }, 'abc')
  expect(o.contract).toBe(OBSERVATION_CONTRACT)
  expect(o.cut).toBe(true)
  expect(o.cut_at).toBe(24000)
  expect(o.source_chars).toBe(src.length)
  expect(o.preflight_sent).toBe('no_signal')
  expect(o.preflight_full).toBe('likely')
  expect(o.input_sha256).toMatch(/^[0-9a-f]{64}$/)
  const base = { input_sha256: o.input_sha256, field: 'deadline', prompt_key: 'course-text-v2', model: 'qwen/qwen3-30b-a3b-instruct-2507', schema_key: 'course_text:deadline' }
  expect(await fingerprint(base)).toBe(o.fingerprint)
  for (const k of ['input_sha256', 'field', 'prompt_key', 'model', 'schema_key']) expect(await fingerprint({ ...base, [k]: base[k] + 'x' })).not.toBe(o.fingerprint)
  const whole = await observation({ read: 'course_fields', field: 'english', item_id: 8, source_text: 'IELTS 6.5', sent_text: 'IELTS 6.5', limit_chars: 24000, lean: l, prompt_key: 'p', model: 'm', schema_key: 's', worker: 'w' }, 'abc')
  expect(whole.cut).toBe(false)
  expect(whole.cut_at).toBe(null)
})

test('the worker observes in shadow: every read observed, nothing skipped or changed, a failure never fails the read, off by setting', () => {
  expect(IX).toMatch(/const WORKER = "coverage-sweep-worker-v0\.87\.0";|\/\/ was v0\.87\.0 \/\/ v0\.87\.0 \(13 Nov 2026, numbered after #1128/)  // current, or kept as "was" by a later worker (v0.88.0 merges #1128)
  expect(IX).toContain('import { leanText, observation, sha256Hex } from "./lean-input.ts";')
  expect(IX).toContain('const OBSERVE = wsNum("reading.input_observe_on", 1) > 0, observed: any[] = [];')
  expect(IX).toContain('if (OBSERVE) await observeReads(pg, raw, data).catch(() => {});  // shadow only: never fails or changes the read')
  expect(IX).toContain('rpc("svc_ai_input_observe_v1", { p_rows: noNul(observed) }).catch(')
  // the observer mirrors each read's own text and limit
  expect(IX).toContain('sent: courseTextPage(raw, PAGE_CHARS), limit: PAGE_CHARS, prompt: CDESC_PROMPT_VERSION')
  expect(IX).toContain('sent: courseTextPage(raw, PAGE_CHARS), limit: PAGE_CHARS, prompt: COURSE_TEXT_PROMPT_VERSION')
  expect(IX).toContain('sent: fieldsSrc.slice(0, PAGE_CHARS), limit: PAGE_CHARS')
  expect(IX).toContain('const page = ((data ? `Page data fields:\\n${data}\\n\\n` : "") + mainText(raw)).slice(0, PAGE_CHARS);')
  // the preflight decides nothing in the worker
  const enrich = IX.slice(IX.indexOf('if (mode === "enrich_ai")'), IX.indexOf('if (mode === "scholarship_inspect")'))
  expect(enrich).not.toMatch(/preflight\(/)
  expect(enrich).not.toMatch(/preflight_(sent|full)\s*===/)
})

test('the migration: table with purpose, service-role insert that never raises on a bad row, bounded purge from settings, read-only report; nothing dropped', () => {
  expect(MIG).toMatch(/^-- Replaces: nothing\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\.$/m)
  expect(MIG).toContain("comment on table pipeline.ai_input_observations is 'CF-247 Lean AI Input Phase 1")
  expect(MIG).toContain("if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;")
  expect(MIG).toContain("grant execute on function public.svc_ai_input_observe_v1(jsonb) to service_role;")
  expect(MIG).toContain("revoke all on function public.svc_ai_input_observe_v1(jsonb) from public, anon, authenticated;")
  expect(MIG).toContain("make_interval(days => security.pipeline_num_v1('reading.input_observation_retention_days', 30)::int)")
  expect(MIG).toContain("limit security.pipeline_num_v1('reading.input_observation_purge_batch', 2000)::int")
  for (const k of ['reading.input_observe_on', 'reading.input_observation_retention_days', 'reading.input_observation_purge_batch']) expect(MIG).toContain(`('pipeline', '${k}',`)
  expect(MIG).toContain("count(*) filter (where j.preflight_full = 'no_signal' and j.state in ('filled', 'review'))")
  expect(MIG).not.toMatch(/^\s*(drop|truncate)\b/im)
  // G3: no consumer API object
  expect(MIG).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
})
