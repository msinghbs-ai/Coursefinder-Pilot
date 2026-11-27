// Guards: Platform Admin 25 Nov 2026 15:40 AEDT (retain the v6 selector and correct the three demonstrated missed lines; no new reader, engine or pipeline)
// s1152: the existing recall check records where a labelled line on the page but outside the selection sits (lean-miss.ts), diagnostic only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

async function load(file, name) {
  const out = path.join(os.tmpdir(), `${name}-${process.pid}.mjs`)
  execFileSync('node_modules/.bin/esbuild', [file, '--bundle', '--format=esm', '--platform=node', `--outfile=${out}`, '--log-level=error'])
  return import(out)
}
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261127010000_cf247_s1152_selection_miss_detail.sql', 'utf8')

test('s1152: a missed line is located by its lean block, heading, signal and the stored markup around it', async () => {
  const lean = await load('supabase/functions/coverage-sweep/lean-input.ts', 'li1152')
  const aer = await load('supabase/functions/coverage-sweep/aer-v2.ts', 'av1152')
  const sec = await load('supabase/functions/coverage-sweep/lean-sections.ts', 'ls1152')
  const m = await load('supabase/functions/coverage-sweep/lean-miss.ts', 'lm1152')
  const raw = '<html><body><main><h1>MBA</h1><h2>Who is it for</h2><p>Graduate with an <strong>AUSTRALIAN DEGREE</strong> (AQF Level 9)</p><h2>Careers</h2><p>Manager.</p></main></body></html>'
  const ab = aer.aerV3Blocks(lean.leanText(raw), null), plain = sec.blockPlain(ab)
  const [d] = m.missDetail(raw, ab.blocks, plain, [], ['Graduate with an AUSTRALIAN DEGREE (AQF Level 9)'], 'entry_requirements')
  expect(d.lean_words).toBe(d.of_words)
  expect(d.block).toMatchObject({ selected: false, heading: 'Who is it for', signal: 'likely' })
  expect(d.raw).toContain('<strong>AUSTRALIAN DEGREE</strong>')
  const [e] = m.missDetail(raw, ab.blocks, plain, [], ['A line that is not in the lean text at all'], 'entry_requirements')
  expect(e).toMatchObject({ block: null, raw: null })
  expect(e.lean_words).toBeLessThan(e.of_words)
})

test('s1152: only the recall check records it; the record function keeps every column and adds miss_detail; six cases wait for the new worker', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.60"')
  expect(IX).toContain('if (row.gold_in_page && !row.gold_in_selection) row.miss_detail = missDetail(raw, ab.blocks, whole, sel.block_ids, gold, f);')
  expect(IX.split('missDetail(').length - 1).toBe(1)  // one call site: diagnostic only
  expect(MIG).toContain("md5(pg_get_functiondef('public.svc_lean_sections_eval_record_v1(jsonb)'::regprocedure)) <> '4c152f2eb34861faaf537117c167996a'")
  expect(MIG).toContain("miss_detail = case when jsonb_typeof(x->'miss_detail') = 'array' then x->'miss_detail' end")
  expect(MIG).toContain("now() + interval '10 minutes'")
  expect(MIG.replace(/--.*$/gm, '')).not.toMatch(/ai_service_routes|ai_route_qualifications|lean_qualify_cases|cron\.schedule|cron\.alter_job|\bdelete from\b|truncate /i)
  expect(MIG.split('\n').filter((l) => /^(drop|delete|truncate)\b/i.test(l) || /^alter table .* drop /i.test(l))).toEqual([])
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
