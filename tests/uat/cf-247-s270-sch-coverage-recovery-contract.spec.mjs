// Guards: Platform Admin mandate 4 Nov 2026 05:08 §2-§5 and §9 (IQ-00215 Torrens, IQ-00216 TAFE SA, IQ-00219 Box Hill, systemic scholarship coverage
// assurance) and the Integration Controller's "Read again" item (4 Nov 2026): every scholarship coverage case is classified in one of 13 states with an
// owner, evidence, a next recovery time and an escalation; recovery is bounded, once per case, and every spending or admitting switch ships off; a page
// asked for with Read again is read once. The behaviour runs on isolated fixtures by tests/fixtures/sch-coverage-recovery/run.sh (scratch PostgreSQL 16;
// the three live definitions loaded from their live text and checked against the live md5s; the defects reproduced on them; the migration applied, then
// applied again unchanged; every case asserted). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = 'supabase/migrations/20261104390000_cf247_sch_coverage_recovery.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/sch-coverage-recovery'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')

const EDITS = {
  'security.scholarship_university(uuid)': ['00ca2485d894ae4542b643a112c2b764', 'cee99ebcfe6ce05751a879260333e6d2'],
  'security.scholarship_coverage_v1(uuid[])': ['cf9a3828b285791bd3d2dd1e8015d481', '772004147c66c4031ff18a37260008af'],
  'public.svc_scholarship_read_next(integer)': ['b30f59a20dff4c874c9fbed2659586c7', '452c288e17dd7207574808737d88c14a'],
}

test('three live definitions are edited, md5-guarded both ways, from the live text the fixture loads', () => {
  for (const [sig, [b, a]] of Object.entries(EDITS)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${b}', '${a}'`)
    expect(run).toContain(`]=${b}`)
    expect(m).toContain(`'${sig}'::regprocedure)) <> '${a}' then raise exception 'post-check`)
  }
  expect(md5(fs.readFileSync(`${FX}/live/security.scholarship_university.def`, 'utf8'))).toBe('00ca2485d894ae4542b643a112c2b764')
  expect(md5(fs.readFileSync(`${FX}/live/public.svc_scholarship_read_next.def`, 'utf8'))).toBe('b30f59a20dff4c874c9fbed2659586c7')
  // the coverage reader is loaded from its own migration text (live md5 cf9a3828... when replayed)
  const src = fs.readFileSync('supabase/migrations/20261104040000_cf247_ops_c_scholarship_aer_coverage.sql', 'utf8')
  expect(src).toContain(fs.readFileSync(`${FX}/live/security.scholarship_coverage_v1.def`, 'utf8').trimEnd())
  expect(m).toContain("md5(pg_get_functiondef('security.work_item_report_v1(text,text,text,text,jsonb)'::regprocedure)) <> '6a15318c0ecd6644b32f1883463c542e'")
})

test('the 13 coverage states, each with an owner, the existing status it reads, an escalation condition and a work-continuity event', () => {
  const states = ['source_not_discovered', 'source_found_unread', 'traversal_incomplete', 'rejected_incorrectly', 'international_unresolved', 'ownership_conflict',
    'awaiting_layer4', 'admitted_not_published', 'rejected_correctly', 'domestic_only', 'expired', 'published_verified', 'evidence_backed_none']
  for (const s of states) expect(m).toMatch(new RegExp(`^ \\('${s}', '[^']+', (true|false), '`, 'm'))
  expect(m).toContain("if (select count(*) from pipeline.scholarship_coverage_state_codes) <> 13 then raise exception 'post-check: 13 states'")
  expect(m).toContain("perform security.work_item_report_v1('sch_coverage', p.id::text, 'state:' || r.code, v_ev,")
  expect(m).toContain('continue when p.reported->>r.code = v_sig;') // reported only when its signature changes
  // the consumer API is read, never changed
  expect(m).toContain('api.website_v2_scholarship_item(s.id) is not null')
  expect(m).not.toMatch(/create\s+or\s+replace\s+function\s+api\./i)
})

test('recovery is bounded, once per case, admission-eligible providers only; every spending or admitting switch ships off', () => {
  for (const k of ['sch_cov.legal_name_identity_on', 'sch_cov.policy_disposition_on', 'sch_cov.recover_register_pages_on', 'sch_cov.recover_stored_reads_on', 'sch_cov.recover_listings_on'])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace(/\./g, '\\.')}',[\\s\\S]*?'number', to_jsonb\\(0\\), 0, 1, 'on \\(1\\) or off \\(0\\)'`))
  expect(m).toMatch(/\('pipeline', 'sch_cov\.classify_on',[\s\S]*?'number', to_jsonb\(1\)/)
  expect(m).toContain('unique (item_key, action)')
  expect(m).toContain('not exists (select 1 from pipeline.scholarship_coverage_recoveries x where x.item_key = i.item_key and x.action = i.recovery)')
  expect(m).toContain('if not security.scholarship_admission_provider_ok_v1(r.provider_id) or security.fc_sch_held_v1(r.provider_id, true)')
  expect(m).toContain("next_read_at = 'infinity'") // a stored-copy re-read never reaches the paid candidate reader
  expect(m).toContain("and c.read_status is null and c.matched_scholarship_id is null") // reopen only a page never read
  expect(m).toContain("(select authority from pipeline.ops_remedies where code = 'sch_coverage_recover') <> 'release'")
  // nothing admits, decides or publishes
  expect(m).not.toMatch(/scholarship_ai_apply_v1|scholarship_admit_from_provider_page_v1|publication_status\s*=\s*'published'\s*,/)
})

test('Read again: a page asked for since its last read is due, once', () => {
  expect(m).toContain("where (p.next_read_at<=now() or (p.requested_at is not null and coalesce(p.read_at,''-infinity'')<p.requested_at))")
  expect(before).toContain('before D7')
  expect(fixtures).toContain("'D7: read once per request'")
})

test('the fixture reproduces the defects first and asserts every case after', () => {
  for (const s of ['before D1', 'before D5', 'before D7']) expect(before).toContain(s)
  expect(run).toContain("grep -c ': applied$')\" = 3")
  expect(run).toContain("grep -c ': already applied$')\" = 3")
  for (const s of ['IQ-00215: Motivational Scholarship rejected incorrectly', 'IQ-00216: listing not traversed', 'IQ-00219: Box Hill source not discovered',
    'evidence-backed none', 'every unresolved case has an owner, evidence, a next recovery time and an escalation condition', 'a third run takes nothing: each case once',
    'TAFE SA (outside the admission policy) is never recovered', 'a recovery that did not move its case fails and is escalated', 'nothing admitted, no Layer 4 item decided or added, nothing published'])
    expect(fixtures).toContain(s)
})

// Integration Controller, 4 Nov 2026 (v2.15.460 production defect): job scholarship-coverage-classify failed its first run because a listing lists
// the same address twice, so one insert met the same (provider_id, item_key) twice.
const FIX = fs.readFileSync('supabase/migrations/20261104430000_cf247_sch_coverage_classify_fix.sql', 'utf8')
test('classification fix: one row per case with a deterministic winner; a failed report write never aborts the run', () => {
  expect(FIX).toContain("select pg_temp.edit_once('security.scholarship_coverage_classify_v1(uuid[])', 'a268ce816990d71ef545dbdc0ae28a5e', 'c072494c5e0082e2a8b58a06dfd94a00'")
  expect(FIX).toContain("md5(pg_get_functiondef('security.scholarship_coverage_items_v1(uuid[])'::regprocedure)) <> 'd3dfacf0e70fd33162eab7a57aca72e4'")
  expect(FIX).toContain('select distinct on (n.provider_id, n.item_key) n.provider_id')
  expect(FIX).toContain('order by n.provider_id, n.item_key, k.sort, md5(n.evidence::text)')
  expect(FIX).toContain("v_rerr := v_rerr + 1; v_rlast := left(r.code || ': ' || sqlerrm, 300); v_rep := v_rep - r.code;")
  expect(FIX).toContain("'duplicate_cases', v_dup, 'report_errors', v_rerr")
  const dup = fs.readFileSync(`${FX}/fixtures-dup-before.sql`, 'utf8'), fx = fs.readFileSync(`${FX}/fixtures-fix.sql`, 'utf8')
  expect(dup).toContain('exception when cardinality_violation')
  expect(run).toContain('fixtures-dup-before.sql')
  for (const s of ['an address listed twice is one case', 'the winner is deterministic', 'a failed report write is counted and the run completes for every provider',
    'the next run sends the report that failed']) expect(fx).toContain(s)
})
