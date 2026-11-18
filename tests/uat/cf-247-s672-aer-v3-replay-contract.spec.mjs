// Guards: S672 AER v2 offline model qualification replay (Platform Admin standing mandate 18 Nov 2026 19:28 AEDT, session S1-AER step 3): only the three pinned candidate versions (Qwen3 30B, Mistral Small 3.2, MiMo v2.6 Flash; no fallback across models) on the frozen set 5 and prompt aer-v2-course-v3; the gate unchanged (source integrity 100%, error at most 10 points, no false positives); run switches on for the run only and always restored, on-demand window opened and closed; nothing qualified or switched on by a result.
// CF-247 S672. Migration 20261118239000_cf247_s672_aer_v3_replay_r4; workflow aer-v3-replay.yml; script scripts/aer-v3-replay.mjs.
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261118239000_cf247_s672_aer_v3_replay_r4.sql', 'utf8')
const S = fs.readFileSync('scripts/aer-v3-replay.mjs', 'utf8')
const W = fs.readFileSync('.github/workflows/aer-v3-replay.yml', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')

test('the migration opens three round-4 runs on the exact pinned models, the same prompt text and set, and changes no switch or threshold', () => {
  for (const [v, m] of [['aer-v2-course-v3-qwen3-30b', 'qwen/qwen3-30b-a3b-instruct-2507'], ['aer-v2-course-v3-mistral-small-3.2', 'mistralai/mistral-small-3.2-24b-instruct'],
    ['aer-v2-course-v3-mimo-v2.6-flash', 'xiaomi/mimo-v2.6-flash']]) expect(M).toContain(`('${v}', '${m}')`)
  expect(M).toContain("coalesce((a.routing->>'allow_fallbacks')::boolean, true) = false")
  expect(M).toContain("v.version || '-r4'")
  expect(M).toContain('v.id, 5,')
  expect(M).toContain("'min_source_integrity_pct', 100, 'max_error_rate_pts', 10")
  expect(M).toContain("'false_positives', 0")
  const c = code(M)
  expect(c).not.toMatch(/update pipeline\.platform_toolset_settings|on_demand_open_v1|status\s*=\s*'qualified'\s*,|set\s+status\s*=\s*'qualified'/i)
  expect(c).not.toMatch(/create\s+(or\s+replace\s+)?(function|table|view|trigger)/i)
  expect(c).toContain("security.pipeline_num_v1('ai_eval.offline_runs_on', 1) <> 0")
  expect(c).toContain("security.pipeline_num_v1('ai_eval.min_source_integrity_pct', 0) <> 100")
  expect(M).toContain('-- Replaces: nothing. Retires: nothing.')
})

test('the workflow runs only on dispatch for the Pilot, with no admission, and the script answers only the opened round', () => {
  expect(W).toContain('workflow_dispatch:')
  expect(W).not.toMatch(/^\s*(schedule|push|pull_request):/m)
  expect(W).toContain('Refused: the typed project ref does not match the Pilot')
  expect(W).toContain('node scripts/aer-v3-replay.mjs "$ROUND" "$MAXMIN"')
  expect(S).toContain("start.length !== 3 || start.some((r) => r.state !== 'queued')")
  expect(S).toContain("jsonb_build_object('mode', 'aer_v3_eval')")
  expect(S).not.toMatch(/'qualified'|ai_service_routes|aer\.v2_shadow_on|route_activate|ai_route_qualify/)
})

test('switches on for the run only and always restored; window opened OpenRouter-only and always closed; scoring is the framework\'s own', () => {
  expect(S).toContain("const SW = ['reading.aer_v2_long_page_sections_on', 'ai_eval.offline_runs_on', 'ai_eval.aer_v3_runs_on']")
  expect(S.indexOf('} finally {')).toBeGreaterThan(S.indexOf('await switches(1,'))
  expect(S.split('} finally {')[1]).toContain('await switches(0,')
  expect(S.split('} finally {')[1]).toContain('security.on_demand_close_v1(')
  expect(S).toContain("null, array['openrouter']) as r")
  expect(S).toContain("'firecrawl_credits', 0")
  expect(S).toContain('select security.ai_eval_score_v1(')
  expect(S).toContain("if (sw.some((s) => Number(s.value) !== 0))")
})
