// Guards: Decision 5 E-6/E-7/E-8/E-9 (Platform Admin 2 Nov 2026 10:56)
// Consolidated decision pack, Decision 5: E-7 "enforce the existing US$14/day ceiling ... every paid AI lane, aggregate daily ceiling, credit
// floor of US$10, in-flight work, retry and restart safety, accurate spend accounting"; E-8 "a single hard monthly ceiling across all
// acquisition paths, including on-demand requests"; E-9 W1 "an external hourly GitHub Actions watchdog using existing CI credentials and
// read-only checks"; E-6 U1 "accurate UI labelling of the existing settings-only backup". The behaviour, with a refusal case for each rule,
// runs on isolated fixtures by tests/fixtures/budget-enforcement/run.sh (scratch PostgreSQL; the edited functions are loaded from their live
// text and checked against the live md5s; each defect is reproduced first). This spec holds the contract, the workflow and the Backup screen.
// G2, G3 and housekeeping are guarded centrally (s32, s57, s42).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { mockAdmin } from './support/admin-mock.mjs'
import { openCard } from './support/cards.mjs'

const MIG = 'supabase/migrations/20261102070000_cf247_budget_enforcement_and_watchdog.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/budget-enforcement'
const fx = (f) => fs.readFileSync(`${FX}/${f}`, 'utf8')
const fixtures = fx('fixtures.sql'), before = fx('fixtures-before.sql'), run = fx('run.sh')
const live = JSON.parse(fx('live-defs.json'))
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); return m.slice(a, m.indexOf('\nend $$;', a)) }
const wf = fs.readFileSync('.github/workflows/platform-watchdog.yml', 'utf8')
const ui = fs.readFileSync('src/SettingsBackup.jsx', 'utf8')

const EDITS = [
  ['public.svc_coverage_ai_match_next(integer)', 'e40e9847068ccf4b7e6e1244a31c2cee', '5a8176270c18994ef3564a5f59a9ff60'],
  ['public.admin_adapter_builder(text,jsonb)', '23c611e79c25ab1663f65fcea709b202', '62e93d40ff0616e87a8960d2d29a2b21'],
  ['security.fc_budget_left_v1(text)', '187ad8c1c8b085f61ce3fba7cd0fe247', 'e979d2e3d7319d845a5149e40abe6987'],
  ['public.svc_fc_spend(numeric,text,uuid,text)', '7a9b0cee72676c18c01d4692a8a56939', 'd418c451d681ffd95134f5f4dcf7c504'],
]
const REPLACED = [
  ['security.ai_spend_today_v1()', 'f18af72fe3d406341931a5daaa93f987', '0b79a7f732669ee4c59a260e26188d5a'],
  ['security.ai_use_allowed_v1(text)', '201f93054b167c78462086372d64c369', '07b6387d6a30be8a0f86b90b602b6d08'],
]

test('six md5-guarded changes checked after; the fixture run loads the live text and checks the same md5s', () => {
  const edits = [...m.matchAll(/select pg_temp\.edit_once\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, s, b, a]) => [s, b, a])
  expect(edits.map(([s, b]) => [s, b])).toEqual(EDITS.map(([s, b]) => [s, b]))
  for (const [s, b, a] of EDITS) if (a) expect(edits).toContainEqual([s, b, a])
  const reps = [...m.matchAll(/select pg_temp\.replace_once\('([^']+)', '([0-9a-f]{32})', '([0-9a-f]{32})'/g)].map(([, s, b, a]) => [s, b, a])
  expect(reps).toEqual(REPLACED)
  expect(code).toContain('if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then')
  expect(code).not.toContain('__AFTER')
  // the live text held for the fixtures is the text the migration guards
  for (const [s, b] of [...EDITS, ...REPLACED]) if (live[s]) expect(live[s].md5).toBe(b)
  expect(run).toContain('"201f93054b167c78462086372d64c369 f18af72fe3d406341931a5daaa93f987 e40e9847068ccf4b7e6e1244a31c2cee b468dcaaaf6cb9494eb1e5e906464c94 187ad8c1c8b085f61ce3fba7cd0fe247 30267f08ebf396738f2a83d72b853c78 7a9b0cee72676c18c01d4692a8a56939"')
  expect(run).toContain('"07b6387d6a30be8a0f86b90b602b6d08 0b79a7f732669ee4c59a260e26188d5a 5a8176270c18994ef3564a5f59a9ff60 b468dcaaaf6cb9494eb1e5e906464c94 e979d2e3d7319d845a5149e40abe6987 30267f08ebf396738f2a83d72b853c78 d418c451d681ffd95134f5f4dcf7c504"')
  expect(run).toContain("grep -c 'already applied' | grep -qx 6")
  // the two definitions the new rules mirror are guarded unchanged
  expect(code).toContain("md5(pg_get_functiondef('security.layer2_provider_budget_status(uuid,numeric)'::regprocedure)) <> '30267f08ebf396738f2a83d72b853c78'")
  expect(code).toContain("md5(pg_get_functiondef('public.svc_coverage_ai_match_record(bigint,text,jsonb,text,numeric,text)'::regprocedure)) <> 'b468dcaaaf6cb9494eb1e5e906464c94'")
  expect(m).toMatch(/^-- Replaces: security\.ai_use_allowed_v1, security\.ai_spend_today_v1, public\.svc_coverage_ai_match_next, public\.admin_adapter_builder, security\.fc_budget_left_v1, public\.svc_fc_spend/m)
  expect(m).toMatch(/^-- Retires: nothing/m)
})

test('no live value changes: openrouter stays observe; floor, ceiling, guards, plan and daily allowance keep their values', () => {
  expect(code).not.toMatch(/update pipeline\.platform_toolsets/)
  expect(code).not.toMatch(/'stop'\s+where/)
  const updates = code.match(/update pipeline\.platform_toolset_settings set[\s\S]*?\n where [^\n]*;/g) || []
  expect(updates.length).toBe(4)
  for (const u of updates) {
    expect(u).not.toMatch(/\bvalue\s*=/)
    expect(u).toMatch(/^update pipeline\.platform_toolset_settings set\s+help = '[^]*used_by = /)
  }
  expect(code).not.toMatch(/layer2_acquisition_providers\s+set/)
  // the fixtures check it on the applied migration
  for (const c of ["'enforcement stays observe'", "'credit floor stays US$5'", "'ceiling stays US$14'", "'daily total stays 25,000'", "'on-demand stays 2,000'"]) expect(fixtures).toContain(c)
})

test('E-7: one refusal rule for every lane: floor (at or below), daily ceiling across all lanes, lane guard; observe never refuses', () => {
  const r = fn('security.ai_use_refusal_v1')
  expect(r).toContain("if coalesce(v_mode, 'observe') <> 'stop' then return null; end if;")
  expect(r).toContain("v_bal := v_bal - coalesce((select sum(l.cost_usd) from pipeline.ai_spend_ledger l where l.at > v_at and l.source <> 'opening'), 0);")
  expect(r).toContain('if v_bal <= v_floor then')
  expect(r).toContain("v_ceiling := security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14);")
  expect(r).toContain('if v_ceiling > 0 and v_total >= v_ceiling then')
  expect(r).toContain('if coalesce(g.guard, 0) > 0 and coalesce(g.spent, 0) >= g.guard then')
  expect(m).toContain('  return security.ai_use_refusal_v1(p_use) is null;')
  // the two lanes that asked no one
  expect(m).toContain("if not security.ai_use_allowed_v1('course_match') then return '[]'::jsonb; end if;")
  expect(m).toContain("$n$perform security.ai_use_refuse_v1('adapter_builder');  -- Decision 5 E-7 (2 Nov 2026)\n    v_m := security.adapter_builder_model_for_v1(v_d.provider_id);$n$")
  for (const p of ['PASS before: ceiling not enforced; course_match claims past its guard', 'PASS before: at the floor is allowed']) expect(before).toContain(`raise notice '${p}';`)
  for (const p of ['PASS ceiling: under allowed, at or over refused on every lane; observe never refuses',
    'PASS floor: at the floor refused, above allowed, spend since the reading counted, the proposed US$10 refuses at 10',
    'PASS unguarded lanes now guarded: course_match claims nothing, adapter proposals refused, both as before in observe or under the guard',
    'PASS in-flight: claims finish and are counted; new claims refused']) expect(fixtures).toContain(`raise notice '${p}';`)
  expect(fixtures).toContain("'at the ceiling: %s refused'")
  expect(fixtures).toContain("'at the floor: refused'")
  expect(fixtures).toContain("'course_match over its guard: nothing claimed'")
  expect(fixtures).toContain("'the third is not claimed: over the ceiling'")
})

test('E-7 accounting: a ledger written by triggers on all eight cost tables; counted once, on the day recorded; restart-safe', () => {
  expect(m).toContain('create table if not exists pipeline.ai_spend_ledger(')
  expect(m).toContain('comment on table pipeline.ai_spend_ledger is ')
  const triggers = [...m.matchAll(/create or replace trigger ai_spend_capture after insert or update of (\w+) on pipeline\.(\w+)\n\s+for each row execute function security\.ai_spend_capture_v1\('(\w+)', '(\w+)', '([^']+)'\);/g)].map((x) => x.slice(1).join(' '))
  expect(triggers).toEqual([
    'cost_usd scholarship_ai_extractions scholarship_ai delta {cost_usd}', 'recheck scholarship_ai_reviews scholarship_ai delta {recheck,cost_usd}',
    'cost_usd uni_adapter_drafts adapter_builder delta {cost_usd}', 'cost_usd central_ai_queue central_ai delta {cost_usd}',
    'decided_at coverage_ai_match course_match decision {cost_usd}', 'cost_usd field_enrich_items enrich_fields delta {cost_usd}',
    'cost_usd fee_reader_queue fee_ai delta {cost_usd}', 'cost_usd entry_matrix_runs entry_matrix delta {cost_usd}'])
  const cap = fn('security.ai_spend_capture_v1')
  expect(cap).toContain("if tg_op = 'UPDATE' and not (v_old->>'state' = 'leased' and v_new->>'state' <> 'leased'")
  expect(cap).toContain('v_add := coalesce((v_new #>> v_path)::numeric, 0) - coalesce((v_old #>> v_path)::numeric, 0);')
  expect(cap).toContain('if v_add > 0 then')
  // the opening rows are written only while the old definition is live (once)
  expect(m).toContain("where s.spent > 0 and md5(pg_get_functiondef('security.ai_spend_today_v1()'::regprocedure)) = 'f18af72fe3d406341931a5daaa93f987';")
  expect(m).toContain('s as (select x.lane u, sum(x.cost_usd) spent, sum(x.calls) calls from pipeline.ai_spend_ledger x, d where x.at >= d.t group by x.lane)')
  expect(before).toContain("raise notice 'PASS before: accounting counts a past cost again and misses the re-check';")
  for (const p of ['PASS no live value changed; opening rows equal the spend counted before, once',
    'PASS restart and retry: a late answer, a release and a re-written cost add nothing; each real call counts once',
    'PASS accounting: counted on the day recorded; the re-check counted; every lane']) expect(fixtures).toContain(`raise notice '${p}';`)
  expect(fixtures).toContain("'the late answer is refused'")
  expect(fixtures).toContain("'counted once'")
})

test('E-8: one monthly Firecrawl limit on every path (worker spends, on demand, adapter captures); the daily allowance unchanged', () => {
  const r = fn('security.fc_month_refusal_v1')
  expect(r).toContain("where x.provider_key = 'firecrawl'")
  expect(r).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-/)  // no provider id in code
  expect(r).toContain("o.observed_at > now() - interval '2 hours'  -- fixed: the freshness layer2_provider_budget_status trusts (Decision 253)")
  expect(r).toContain('st := security.layer2_provider_budget_status(p.id, p_units);')
  expect(r).toContain('if v_rem - greatest(coalesce(p_units, v_unit), 0) >= v_stop then return null; end if;')
  expect(m).toContain("  if security.fc_month_refusal_v1(1) is not null then return 0; end if;\n  if not coalesce((select (s.value #>> '{}')::boolean")
  expect(m).toContain("  elsif security.fc_month_refusal_v1(p_units) is not null then\n    v_why := 'month_limit';\n  elsif v_od is not null then$n$]]")
  expect(m).toContain("$n$perform security.fc_month_refuse_v1(1);  -- Decision 5 E-8 F2 (2 Nov 2026): a capture spends Firecrawl credits")
  expect(m).toContain('array[1, 2]);')   // the capture line occurs twice (start, add sample)
  // the month boundary finding is recorded with the change
  expect(m).toContain("counts from date_trunc('month', now()) in the session time zone (UTC; the function")
  expect(m).toContain('The vendor period runs from the 2nd')
  expect(before).toContain("raise notice 'PASS before: the month is not checked on the daily or on-demand path';")
  for (const p of ['PASS month: every worker path refused at the limit (course search, reads, scholarships, central, site checks, other)',
    'PASS on demand: plan runs and adapter captures refused at the monthly limit, run as before under it',
    'PASS daily allowance unchanged: shares and totals decide as before while the month has credit',
    'PASS month roll-over: the counted month starts on the 1st at 00:00 UTC; a fresh vendor balance overrides it',
    'PASS the month rule equals layer2_provider_budget_status in 16 cases (fresh and stale vendor balance)']) expect(fixtures).toContain(`raise notice '${p}';`)
  expect(fixtures).toContain("'on-demand: refused'")
  expect(fixtures).toContain("'adapter capture (start): refused'")
})

test('E-9: the hourly watchdog at :24 reads one read-only function with the existing secret, fails visibly, prints no secret, no webhook', () => {
  expect(wf).toContain("- cron: '24 * * * *'")
  expect(wf).toContain('SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}')
  expect(wf).toContain('REF: ${{ vars.SUPABASE_PROJECT_REF }}')
  expect(wf).toContain(`jq -n '{query: "select security.platform_watchdog_v1() as w", read_only: true}'`)
  expect(wf).toContain('https://api.supabase.com/v1/projects/$REF/database/query')
  expect(wf).toContain("if [ \"$(jq -r '.ok' \"$RUNNER_TEMP/w.json\")\" != \"true\" ]; then")
  expect(wf).toContain('permissions:\n  contents: read')
  expect(wf).not.toMatch(/echo[^\n]*\$SUPABASE_ACCESS_TOKEN|set -x|webhook_url|hooks\.slack|office\.com|webhook\.office|curl[^\n]*-v\b/i)
  expect(wf).not.toMatch(/secrets\.(?!SUPABASE_ACCESS_TOKEN\b)/)
  const w = fn('security.platform_watchdog_v1')
  expect(w).toContain("language plpgsql stable security definer set search_path to '' as $$")
  expect(w).toContain("unnest(array['platform-health', 'platform-alerts'])")
  expect(w).toContain("security.pipeline_num_v1('alerts.watchdog_stale_minutes', 30)")
  expect(w).toContain("security.pipeline_num_v1('alerts.collect_within_minutes', 120)")
  expect(w).toContain('order by x.runid desc limit v_scan')
  expect(m).toContain('grant execute on function security.platform_watchdog_v1() to supabase_read_only_user;')
  expect((code.match(/\bgrant\b/g) || []).length).toBe(1)
  expect(m).toContain("('pipeline', 'alerts.watchdog_stale_minutes', 'Watchdog: alert jobs must have run within',")
  expect(m).toContain("'number', to_jsonb(30), 10, 180, 'minutes', 975, 'Alerts', 'security.platform_watchdog_v1; .github/workflows/platform-watchdog.yml',")
  for (const p of ['PASS watchdog: healthy ok; stale, failed, switched off or missing jobs and uncollected alerts fail; windows are settings',
    'PASS watchdog read-only: runs as the read-only role in a read-only transaction; nothing else is granted']) expect(fixtures).toContain(`raise notice '${p}';`)
})

test('E-6 U1: Settings › Backup & restore says plainly it covers settings only, not catalogue data, evidence or Storage', async ({ page }) => {
  expect(ui).toContain('data-backup-scope')
  await mockAdmin(page)
  await page.route('**/rest/v1/rpc/admin_settings_backup', (route) => route.fulfill({ contentType: 'application/json', body: JSON.stringify({ keep_days: 60, backups: [] }) }))
  await page.goto('/#environment?tab=backup')
  // the closed card already says it
  await expect(page.locator('[data-card="settings.backup"] [data-backup-scope-chip]')).toHaveText('Settings only: no catalogue data, evidence or Storage')
  await openCard(page, 'settings.backup')
  const scope = page.locator('[data-settings-backup] [data-backup-scope]')
  await expect(scope).toContainText('Settings only.')
  await expect(scope).toContainText("This backup covers each provider's Published switch and every setting value.")
  await expect(scope).toContainText('It does not include catalogue data (courses, fees, scholarships and the rest), stored evidence or Storage files.')
  await expect(scope).toContainText('The catalogue is covered by the daily database backup (7 days); Storage files have no backup.')
})
