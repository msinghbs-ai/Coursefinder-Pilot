// Guards: Platform Admin directive 9-10 Nov 2026 (P0), Provider "Fill fields": on-demand description enrichment inside the Provider Catalogue and Provider Detail over the existing Provider description Run & Validate, and the Description quality level; and the Platform Admin rule of 10 Nov 2026 05:40 (no new human-maintained setting).
// Source contract only. The behaviour against real SQL (old and new page give the same rows, filter counts equal the classification counts, caps, idempotency, rank checks, guards) is the isolated PostgreSQL run
// tests/fixtures/provider-fill-fields/run.sh recorded on the pull request; the screen against the live system is the release controller's check after deploy. Nothing here claims to have exercised the live database.
// G1, G2, G3, G4 and housekeeping are guarded centrally (s42, s32, s57, s120); they are not asserted again here.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PROVIDER_COLUMNS, QUALITY_LEVELS, QUALITY_FILTER_OPTIONS, qualityOf, fieldWords, sortSentence } from '../../src/catalogue-columns.js'

const MIG = fs.readFileSync('supabase/migrations/20261110030000_cf247_provider_fill_fields.sql', 'utf8')
const SQL = MIG.split('\n').filter(l => !/^\s*--/.test(l)).join('\n')
const UI = fs.readFileSync('src/mature-main.jsx', 'utf8')
const PANEL = fs.readFileSync('src/ProviderFillFields.jsx', 'utf8')
const api = fs.readFileSync('src/provider-description-run-api.js', 'utf8')
const FILL_MODES = [...PANEL.matchAll(/\{ id: '([a-z_]+)', label: '[^']+', help: '((?:[^'\\]|\\.)*)' \}/g)].map(m => ({ id: m[1], help: m[2] })) // the panel's modes, read from its source (the component imports a stylesheet)
const CLASSES = ['missing', 'queued', 'processing', 'waiting_decision', 'held', 'basic_registry', 'unrecorded', 'enriched_admitted', 'consumer_pending', 'verified_published']

test('the Description quality levels are the directive\'s, in pipeline order, and the screen, the table\'s check and the rule agree', () => {
  expect(QUALITY_LEVELS.map(l => l.code)).toEqual(CLASSES)
  expect(MIG).toContain(`array['${CLASSES.join("', '")}']::text[]`)
  expect(MIG).toContain(`check (quality_class in ('${CLASSES.join("', '")}'))`)
  expect(QUALITY_LEVELS.map(l => l.label)).toEqual(expect.arrayContaining(['Missing', 'Basic registry profile', 'Enrichment queued', 'Enrichment processing', 'Enriched and admitted', 'Held (evidence, identity or policy)', 'Waiting for human decision', 'Consumer publication pending', 'Verified published']))
  // the filter offers the four groups first, then each single level, and the server takes every value offered
  expect(QUALITY_FILTER_OPTIONS.slice(0, 4).map(o => o.value)).toEqual(['basic', 'enriched', 'missing', 'held'])
  for (const o of QUALITY_FILTER_OPTIONS) expect(MIG, o.value).toContain(`when '${o.value}' then array[`)
  expect(qualityOf('nope').label).toBe('Nope')
  expect(qualityOf(null).label).toBe('Not worked out')
  expect(fieldWords(['phone', 'state_region'])).toEqual(['Phone', 'State / region'])
})

test('Verified published is per consumer: a consumer that does not serve the provider is Not applicable and never a failure', () => {
  expect(SQL).toContain("when 'not_applicable' then 'not_applicable'")
  expect(SQL).toMatch(/when 'pending' in \(security\.provider_description_publication_v1\(p_web\), security\.provider_description_publication_v1\(p_zoho\)\) then 'consumer_pending'/)
  expect(SQL).toMatch(/when 'verified' in \(security\.provider_description_publication_v1\(p_web\), security\.provider_description_publication_v1\(p_zoho\)\) then 'verified_published'/)
  expect(SQL).toContain("else 'enriched_admitted' end")
  expect(qualityOf('verified_published').why).toMatch(/does not serve the provider is Not applicable, not a failure/)
  expect(PANEL).toContain("not_applicable: ['Not applicable', 'neutral']")
  expect(PANEL).toContain('Not served (not applicable) means that consumer does not serve the provider; it is not a failure.')
})

test('the quality table is new, locked down, commented, and the Catalogue never reads it', () => {
  expect(SQL).toContain('create table if not exists pipeline.provider_description_quality (')
  expect(SQL).toContain('alter table pipeline.provider_description_quality enable row level security;')
  expect(SQL).toContain('revoke all on table pipeline.provider_description_quality from public, anon, authenticated;')
  expect(MIG).toMatch(/comment on table pipeline\.provider_description_quality is '/)
  // only the snapshot writer, the counts and the panel's own reads mention the table: the page function works the level out live
  const page = SQL.slice(SQL.search(/create or replace function security\.admin_providers_page_v3/i), SQL.search(/create or replace function public\.admin_provider_description_run_v1/i))
  expect(page).not.toContain('provider_description_quality ')
  expect(page).not.toMatch(/from pipeline\.provider_description_quality/)
  expect(MIG).toMatch(/-- Replaces: .*\n-- Retires: nothing/)
})

test('no new setting and no new job: every limit comes from a setting that exists or is a marked technical constant (Platform Admin 10 Nov 2026 05:40)', () => {
  expect(SQL).not.toMatch(/insert into pipeline\.platform_toolset_settings/i)
  expect(SQL).not.toMatch(/pdesc\.(quality_refresh_max|quality_stale_minutes|fill_poll_seconds|fill_status_max)'\s*,\s*[0-9]/)
  expect(SQL).not.toMatch(/insert into pipeline\.(automation_catalogue|admin_job_kinds)/i)
  expect(SQL).not.toMatch(/cron\.schedule/i)
  // the one cap is the least of the existing settings, used by the screen's limit and the server's check alike
  expect(SQL).toContain("select least(security.pipeline_num_v1('pdesc.queue_per_run', 10), security.pipeline_num_v1('pdesc.pending_max', 10), security.pipeline_num_v1('run_now.pilot_cap', 20), security.pipeline_num_v1('pdesc.queue_cap', 60))::int")
  expect(SQL).toContain("'min_size',1,'max_size',security.provider_description_cohort_cap_v1()")
  expect(SQL).toContain("'status_max',security.provider_description_cohort_cap_v1()")
  // the panel's re-read time follows the reader's own window and carries its reason
  expect(SQL).toMatch(/'poll_seconds',greatest\(30,security\.pipeline_num_v1\('pdesc\.every_minutes',60\)::int\*15\) \/\* fixed: /)
  expect(PANEL).not.toMatch(/poll_seconds\s*\|\|\s*[0-9]/)
})

test('the existing service is extended, not duplicated: md5-guarded edits, same signatures, new actions only', () => {
  expect(MIG).toMatch(/v_page not in \('f3eb9fc6f8efa37566c36ac5ef2e8f0e', '2c906a2b1f7c346522ef7742d74039f1'\)/)
  expect(MIG).toMatch(/v_run not in \('b397cf320a689b6e981aa6747e7156b8', '[0-9a-f]{32}'\)/)
  expect(MIG).toContain("v_facts <> 'abc1345d4cdb341deba65bfd0a38277f'")
  expect(SQL).toContain('create or replace function public.admin_provider_description_run_v1(p_action text,p_args jsonb default')
  expect(SQL).toMatch(/create or replace function security\.admin_providers_page_v3\(p_args jsonb/i)
  // the earlier governed selection is called, not edited
  expect(SQL).not.toMatch(/create or replace function security\.(provider_description_selection_v1|provider_description_machine_blocked_v1|provider_description_machine_admit_v1)\b/i)
  for (const a of ['fill_caps', 'provider_status', 'provider_publication', 'quality_counts', 'quality_refresh']) expect(SQL, a).toContain(`'${a}'`)
  // one transport: the panel calls the existing client, which calls the one RPC
  expect(api).toContain("supabase.rpc('admin_provider_description_run_v1'")
  expect(PANEL).toContain("import { providerDescriptionRunApi } from './provider-description-run-api'")
  expect(PANEL).not.toMatch(/supabase\.(rpc|from)\(/)
  // preview and prepare take a named set; run goes through the same Run Now job kind
  expect(SQL).toContain('security.provider_description_selection_multi_v1(v_args)')
  expect(SQL).toContain('security.provider_description_selection_multi_v1(c.selection)')
  expect(MIG).not.toMatch(/^\s*(drop|delete from|truncate)\b/im)
  expect(SQL).not.toMatch(/^\s*(drop|delete\s+from|truncate)\b/im)
})

test('the eligibility refusal is shown as the backend gives it; the refresh mode does not depend on the eligibility rewrite', () => {
  expect(PANEL).toContain('Reason from the platform: <code>{r.eligibility_reason || \'not recorded\'}</code>')
  expect(FILL_MODES.map(m => m.id)).toEqual(['missing', 'upgrade_basic', 'preview_only', 'verify_publication'])
  expect(FILL_MODES[1].help).toMatch(/the exact reason is shown/)
  expect(PANEL).toContain("fill_mode: fillModeFor()")
  expect(MIG).toMatch(/'not_a_basic_registry_profile'/)
  expect(MIG).toMatch(/'not_selected_by_governed_policy'/)
  expect(MIG).toContain('It does not depend on the eligibility rewrite')
})

test('QA 10 Nov 2026: the refresh mode passes the argument the upgrade change defines, shows the exact refusal while the switch is off, and a NOT_FOUND from a consumer is not an error', () => {
  // the argument is `upgrade` (selection_v1 in the upgrade change), honoured there only behind its own switch; this change reads that switch and creates no setting
  expect(SQL).toContain("'upgrade', v_fill = 'upgrade_basic'));")
  expect(SQL).not.toContain("'upgrade_basic', v_fill = 'upgrade_basic'")
  expect(SQL).toContain("v_up_on boolean := security.pipeline_num_v1('pdesc.registry_upgrade_on', 0) >= 1 and security.pipeline_num_v1('pdesc.machine_admit_on', 0) >= 1;")
  expect(SQL).toContain("'eligibility_reason', 'upgrade_switched_off'")
  expect(SQL).toContain("'upgrade_basic_on',security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1")
  expect(SQL).not.toMatch(/insert into pipeline\.platform_toolset_settings[\s\S]{0,200}registry_upgrade_on/)
  expect(PANEL).toContain('Upgrade is switched off: a Platform Admin policy decision.')
  expect(PANEL).toContain("caps?.upgrade_basic_on === false ? ' (switched off)'")
  // a consumer's NOT_FOUND is not served (Not applicable), checked before the generic error; the Catalogue's own feed state is carried beside the read-back
  expect(SQL.indexOf("->'error'->>'code' = 'NOT_FOUND' then 'not_served'")).toBeGreaterThan(0)
  expect(SQL.indexOf("->'error'->>'code' = 'NOT_FOUND' then 'not_served'")).toBeLessThan(SQL.indexOf("w.body ? 'error' then 'error'"))
  expect(SQL).toContain("'feed', security.provider_description_publication_v1(f.zoho_state)")
  expect(PANEL).toContain("not_served: ['Not served (not applicable)', 'neutral']")
  // a basic profile whose upgrade read is waiting or running shows that level; a lock shows as Locked
  expect(SQL).toContain("case when p_reader = 'reading' then 'processing' when p_reader = 'queued' then 'queued' when p_reader = 'proposed' then 'waiting_decision' else 'basic_registry' end")
  expect(PANEL).toContain('label="Locked"')
  expect(qualityOf('held').label).toBe('Held (evidence, identity or policy)')
  expect(FILL_MODES.find(m => m.id === 'preview_only').help).toMatch(/changes no description and queues no read/)
  // the selection limit fails closed
  expect(UI).toContain('disabled={!on&&(!fillCap||picked.length>=fillCap)}')
  expect(UI).toContain('data-fill-caps-failed')
})

test('the Provider Catalogue gets two registry columns, equal in the screen and the database, off by default and sortable; the filter and the sorts are handled by the page function', () => {
  const rows = [...MIG.matchAll(/\('providers', '([a-z0-9_]+)', '([^']+)', '([^']+)', (\d+), '([a-z0-9_]+)', (true|false), (\d+), (\d+), (true|false)\)/g)]
  expect(rows.map(r => r[1])).toEqual(['description_quality', 'missing_fields'])
  for (const r of rows) {
    const c = PROVIDER_COLUMNS.find(x => x.key === r[1])
    expect(c, r[1]).toBeTruthy()
    expect([c.group, c.label, c.order, c.sortKey, c.defaultVisible, c.width, c.minWidth, c.alwaysVisible]).toEqual([r[2], r[3], +r[4], r[5], r[6] === 'true', +r[7], +r[8], r[9] === 'true'])
    expect(c.defaultVisible).toBe(false)
    expect(MIG).toContain(`case when v_sort='${c.sortKey}' and v_dir='asc'`)
  }
  expect(sortSentence('quality', 'asc', 'providers')).toBe('Description quality level, Missing first')
  expect(sortSentence('missing_fields', 'desc', 'providers')).toBe('Missing enrichment fields, most first')
  // the whole-set filter reads the feeds only when the level needs them (an enriched level depends on the Website and Zoho states)
  expect(SQL).toContain("coalesce(v_quality in ('enriched','enriched_admitted','consumer_pending','verified_published'),false)")
  expect(SQL).toMatch(/unsupported quality filter: %/)
})

test('the screens: a tick box and a Fill fields button on each Provider row (Curator and above), a selection bar bounded by the server\'s cap, the same panel in Provider Detail, and no second dashboard', () => {
  expect(UI).toContain("const ProviderFillFields=lazyPage(()=>import('./ProviderFillFields'))")
  expect(UI).toContain("const fillOn=type==='provider'&&!completenessMode&&Number(rank)>=3")
  expect(UI).toContain("providerDescriptionRunApi.call('fill_caps')")
  expect(UI).toContain('canonical_name:nameCell')
  expect(UI).toContain('data-fill-selection')
  expect(UI).toContain('<ProviderFillFieldsCard providerId={data.id} rank={rank}/>')
  expect(UI).toContain('data-fill-fields-card')
  // the selection stops at the cap the server reports; the panel explains a longer selection and does not read it
  expect(UI).toContain('!fillCap||p.length>=fillCap?p:')
  expect(PANEL).toContain('if (ids.length > Number(c.max_size || 0)) { setStatus(null); return }')
  // no new page, route or dashboard: the panel is one component opened from the two existing screens
  expect(fs.readdirSync('src').filter(f => /fill/i.test(f)).sort()).toEqual(['ProviderFillFields.jsx', 'provider-fill-fields.css'])
  expect(UI).not.toMatch(/PAGES\.[a-z]*[fF]ill|key:'fill/)
  // the panel states what the reader does and does not fill
  expect(PANEL).toContain('The reader produces the <strong>description</strong> only.')
  // a run is saved and read back from the server, so it survives the browser being closed
  expect(PANEL).toContain("requested_by_me && t.cohort_id")
  expect(PANEL).toContain("call('saved', { cohort_id: mine.cohort_id })")
})

test('forward recovery and the post-deploy equivalence check are held outside supabase/migrations', () => {
  expect(fs.readdirSync('supabase/migrations').filter(f => /provider_fill_fields/.test(f))).toEqual(['20261110030000_cf247_provider_fill_fields.sql'])
  const rec = fs.readFileSync('supabase/held/provider_fill_fields_forward_recovery.sql', 'utf8')
  expect(rec).toContain("'f3eb9fc6f8efa37566c36ac5ef2e8f0e'")
  expect(rec).toContain("'b397cf320a689b6e981aa6747e7156b8'")
  expect(rec).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  const eq = fs.readFileSync('supabase/held/provider_fill_fields_equivalence.sql', 'utf8')
  expect(eq).not.toMatch(/^\s*(insert|update|delete|drop|alter|create)\b/im)
  expect(eq).toContain('security.provider_description_quality_counts_v1()')
  expect(eq).toContain("raise exception 'EQUIVALENCE")
})
