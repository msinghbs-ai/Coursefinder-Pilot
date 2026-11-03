// Guards: Integration issue IQ-00067 (Platform Admin mandate 3 Nov 2026 15:52 §9): a course locked by hand is never offered to the coverage
// admission apply (held with the named reason manual_lock), one refused item never aborts the batch (per-item isolation, held as apply_refused,
// bounded by admit.item_error_limit), the lock rule itself is unchanged, and the root cause lock_conflict_in_batch is registered with its remedies
// through workstream A's contract. The behaviour runs on isolated fixtures by tests/fixtures/iq67-coverage-admit/run.sh (scratch PostgreSQL; the
// four live definitions loaded from their live text and checked against the live md5s; the 13:53 failure reproduced on them; the migration
// applied without A's contract in a rolled-back transaction, then with it, applied again unchanged; every case asserted). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = 'supabase/migrations/20261104080000_cf247_iq67_coverage_admit_lock_isolation.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/iq67-coverage-admit'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const before = fs.readFileSync(`${FX}/fixtures-before.sql`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')

const LIVE = {
  'security.coverage_admission_apply_v1(integer,text,text[])': '2e85e6cbb5d2e64ea1b50fe490c4da76',
  'security.coverage_admission_gated_v1(text,integer,text,text[])': '4e4e7f9ae2bb5e177774f1e394fdfe0d',
  'security.layer4_course_link_apply_impl(uuid,uuid,jsonb,text)': '75a53dbbcd5e20e1018a05b61f6763aa',
  'security.course_page_rule_v1(text,text)': 'b441e4c76d9bc401dd1604c23456e952',
}
const EDITED = {
  'security.coverage_admission_apply_v1(integer,text,text[])': 'c11a5e76bbaddf8ef5715fb2a3540c6d',
  'security.coverage_admission_gated_v1(text,integer,text,text[])': 'adc4cf19720f361fbce223eb64297ba0',
}

test('the fixture loads the live text of every definition it runs; only the apply and the gate are edited, md5-guarded both ways', () => {
  for (const [sig, b] of Object.entries(LIVE)) {
    const file = `${FX}/live/${sig.slice(0, sig.indexOf('('))}.def`
    expect(md5(fs.readFileSync(file, 'utf8')), file).toBe(b)
    expect(run).toContain(`["${sig}"]=${b}`)
  }
  for (const [sig, a] of Object.entries(EDITED)) {
    expect(m).toContain(`select pg_temp.edit_once('${sig}', '${LIVE[sig]}', '${a}', array[`)
    expect(m).toMatch(new RegExp(`^--   ${sig.replace(/[.()[\]]/g, '\\$&')} ${LIVE[sig]} -> ${a}`, 'm'))
  }
  expect(m).not.toMatch(/edit_once\('security\.layer4_course_link_apply_impl/)
  expect(m).not.toMatch(/edit_once\('security\.course_page_rule_v1/)
  expect(m).not.toMatch(/edit_once\('security\.(course_relink_|enrich_plan_|course_link_search_|source_proof_)/)
  expect(m).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(run).toContain('applied twice: the second run changed nothing')
})

test('the 13:53 failure is reproduced on the live definitions, and nothing persists from it', () => {
  expect(before).toContain("v_err not like 'this course''s page was set by hand on the course record%'")
  expect(before).toContain("layer4_course_link_apply_impl(uuid,uuid,jsonb,text) line 17 at RAISE")
  expect(before).toContain('nothing persisted (no Layer 4 item, decision, write, job mark or baseline)')
  expect(before).toContain('bachelor-nursing-science.html/1000.html')
})

test('a course locked by hand is held as manual_lock before the batch and never offered to apply; the lock rule is unchanged', () => {
  expect(m).toContain("when 'official_url' then array['official_url', 'course_url', 'all']")
  expect(m).toMatch(/'manual_lock', jsonb_build_object\('lock_fields', k\.f, 'current', a\.current\)/)
  expect(m).toContain('get diagnostics v_lock = row_count; delete from _adm a where exists (select 1 from pipeline.manual_locks l')
  expect(m).toContain("check (reason in ('manual_lock', 'apply_refused'))")
  expect(m).toContain('primary key (course_id, attribute, proposed_md5)')
  expect(fixtures).toContain('the locked course is never offered to apply: no Layer 4 item and no rule decision for C1 or C4')
  expect(fixtures).toContain('the locked course keeps the page set by hand (link and course record untouched)')
  expect(fixtures).toContain('the lock rule is unchanged: approving the locked course\'\'s page is still refused')
})

test('one refused item never aborts the batch: isolated, held as apply_refused with the error, bounded, not retried until the setting allows', () => {
  expect(m).toContain('    exit when v_stop;\n    begin\n    v_rule := case')
  expect(m).toMatch(/exception when others then\n      -- IQ-00067 \(Platform Admin 3 Nov 2026 15:52 §9\): one item never aborts the batch/)
  expect(m).toContain("security.pipeline_num_v1('admit.item_error_limit', 25)")
  expect(m).toContain("security.pipeline_num_v1('admit.refused_recheck_hours', 24)")
  expect(m).toContain("h.reason = 'apply_refused' and h.last_seen_at > now() - v_recheck")
  expect(m).toContain("or coalesce((v->>'stopped_at_limit')::boolean, false)")
  for (const k of ['admit.item_error_limit', 'admit.refused_recheck_hours', 'admit.remedy_max_attempts', 'admit.remedy_cooldown_minutes'])
    expect(m).toContain(`('pipeline', '${k}', `)
  expect(fixtures).toContain('the batch continued past the locked course: C2\'\'s rule decision applied its page')
  expect(fixtures).toContain('the refused rule decision rolled back on its own (C7: no approved item, no link), and nothing else rolled back with it')
  expect(fixtures).toContain('with admit.item_error_limit 1 the run stops after one refusal, holds it, and still commits')
  expect(fixtures).toContain('run 3 committed and is marked "more", so the next run is not skipped for no new input')
})

test('root cause and remedies go through workstream A\'s contract when it exists; the fix does not wait for it', () => {
  expect(m).toContain("if to_regclass('pipeline.ops_remedies') is null then")
  expect(m).toContain("if to_regprocedure('security.ops_remedy_register_v1(text,jsonb)') is null then return; end if;")
  expect(m).toContain("perform security.ops_root_cause_register_v1('lock_conflict_in_batch', jsonb_build_object(")
  expect(m).toContain("perform security.ops_remedy_register_v1('coverage_admit_lock_hold', jsonb_build_object(")
  expect(m).toMatch(/ops_remedy_register_v1\('coverage_admit_recheck'[\s\S]*?'authority', 'auto',\n\s+'action_fn', 'security\.coverage_admit_recheck_v1\(bigint\)', 'verify_fn', 'security\.coverage_admit_recheck_verify_v1\(bigint\)'/)
  expect(run).toContain("without A's contract: applies (checked in a rolled-back transaction) and registers nothing")
  expect(fixtures).toContain('remedy verification passes once a full run committed after the action')
  const stub = fs.readFileSync(`${FX}/stub-ops-contract.sql`, 'utf8')
  expect(stub).toContain('create or replace function security.ops_remedy_register_v1(p_code text, p_spec jsonb) returns jsonb')
})
