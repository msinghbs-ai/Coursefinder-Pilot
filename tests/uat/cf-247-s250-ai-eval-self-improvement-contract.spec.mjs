// Guards: Platform Admin mandate 3 Nov 2026 15:37 §6 and §15 (P0 autonomous AI operations, workstream E): AI evaluation sets are built only from
// trusted ground truth (Layer 4 decisions by a person, people's corrections and locks, quote-checked readings), never from unreviewed AI output;
// AI instructions are versioned with their live text's md5 and pinned to one listed model (no "auto" routing); candidates are judged offline
// and by canary on the §6 criteria, rejected changes are not proposed again, rollback keeps the previous version; the AI can never accept its
// own prompt, rule, admission, security, code, schema or paid change, nor change its approval boundaries; spending and live-changing switches
// ship off. The behaviour runs on isolated fixtures by tests/fixtures/ops-ai-eval/run.sh (scratch PostgreSQL; workstream A's contract loaded;
// the migration applied twice; recorded answers, no AI call). This spec holds the contract.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = 'supabase/migrations/20261104070000_cf247_ai_eval_self_improvement.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/ops-ai-eval'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const seed = fs.readFileSync(`${FX}/seed.sql`, 'utf8')
const W = 'supabase/functions/coverage-sweep/'
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')

// the text of a worker constant: a template literal without interpolation, or concatenated double-quoted strings
function constText(src, name) {
  const t = src.match(new RegExp(`(?:export )?const ${name}\\s*=\\s*\`([^\`]*)\`;`))
  if (t) { expect(t[1], `${name} interpolates`).not.toContain('${'); return t[1] }
  const c = src.match(new RegExp(`(?:export )?const ${name}\\s*=\\s*((?:"(?:[^"\\\\]|\\\\.)*"\\s*\\+?\\s*)+);`))
  expect(c, name).not.toBeNull()
  return [...c[1].matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((x) => JSON.parse(`"${x[1]}"`)).join('')
}

const BASELINES = [
  ['course-text', 'course-text.ts', 'COURSE_TEXT_SYSTEM'],
  ['page-identity', 'pageid.ts', 'PAGE_ID_SYSTEM'],
  ['course-page-match', 'index.ts', 'AI_MATCH_SYSTEM'],
  ['entry-matrix', 'entry.ts', 'ENTRY_PROMPT'],
  ['course-entry', 'course-entry.ts', 'COURSE_ENTRY_SYSTEM'],
  ['provider-description', 'description.ts', 'DESCRIPTION_SYSTEM'],
]

test('every live prompt is registered with the md5 of the worker text it runs: a prompt edited in code without a new version fails here', () => {
  for (const [code, file, name] of BASELINES) {
    const h = md5(constText(fs.readFileSync(W + file, 'utf8'), name))
    const row = m.match(new RegExp(`'code', '${code}', 'kind', 'prompt', 'version', '([^']+)', 'status', 'current'[\\s\\S]*?'body_md5', '([0-9a-f]{32})'`))
    expect(row, code).not.toBeNull()
    expect(row[2], `${code}: ${file} ${name} changed; register a new version`).toBe(h)
  }
  expect(m).toContain("'home', 'pipeline.scholarship_ai_prompts version 2 (active)', 'body_md5', coalesce((select md5(p.text) from pipeline.scholarship_ai_prompts p where p.version = 2)")
  // the P1 candidate changes only the deadline paragraph of course-text-v1
  const v1 = constText(fs.readFileSync(W + 'course-text.ts', 'utf8'), 'COURSE_TEXT_SYSTEM')
  const v2 = m.match(/'body', \$b\$([\s\S]*?)\$b\$/)[1]
  const cut = v1.indexOf('deadlines:')
  expect(v2.slice(0, cut)).toBe(v1.slice(0, cut))
  expect(v2).toContain('it must contain the date exactly as printed')
})

test('models stay pinned: one listed model per prompt, never a router or "auto"; spending and live-changing switches ship off', () => {
  expect(m).toContain("p_model !~* '(^openrouter/|(^|[/:._-])auto([/:._-]|$)|router)'")
  expect(m).toContain("raise exception 'ai_eval: % % must name one pinned, listed model (got %); routing across models is not allowed'")
  for (const k of ['ai_eval.canary_on', 'ai_eval.auto_accept_on', 'ai_eval.offline_runs_on']) expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}',[^\\n]*\\n[^\\n]*\\n\\s*'number', to_jsonb\\(0\\)`))
  expect(m).toMatch(/\('pipeline', 'ai_eval\.refresh_on',[^\n]*\n[^\n]*\n\s*'number', to_jsonb\(1\)/)
  expect(m).toContain("if security.pipeline_num_v1('ai_eval.offline_runs_on', 0) <> 1 then return jsonb_build_object('run', null")
  expect(m).not.toMatch(/openrouter\.ai|net\.http_post|api\.firecrawl/)
  expect(m).toContain("if to_regclass('pipeline.ops_remedies') is null then")
  expect(run).toContain('refused without workstream A')
  for (const s of ['ships off: ai_eval.canary_on, ai_eval.auto_accept_on, ai_eval.offline_runs_on', 'applied twice: the second run changed nothing']) expect(run).toContain(s)
})

test('ground truth only: people, quote-checked readings and nothing else; unreviewed AI output is refused in data', () => {
  expect(m).toContain("check (source_kind in ('l4_decision', 'human_correction', 'manual_lock', 'quote_evidence', 'scholarship_review', 'match_case'))")
  expect(m).toContain("raise exception 'ai_eval: % is not ground truth: no person decided it'")
  expect(m).toContain("raise exception 'ai_eval: % is not ground truth: no quote on a stored page'")
  expect((m.match(/exists \(select 1 from auth\.users u where u\.id = /g) || []).length).toBe(4)
  expect(m).toContain("where d.action in ('approve', 'edit_and_approve', 'reject') and coalesce(btrim(d.reason), '') <> ''")
  expect(m).toContain("where i.state = 'filled' and coalesce(btrim(i.quote), '') <> '' and (i.evidence_id is not null or i.storage_path is not null)")
  expect(m).toContain("set active = false, inactive_reason = 'a person decided otherwise (example '")
  // a canary is judged only on later decisions by a person
  expect(m).toContain("and x.tier = 'person' and x.active\n                       and x.decided_at > c.answered_at")
  for (const s of ['not ground truth: a decision by a non-person, a return to Layer 2, a decision without a reason', 'unreviewed AI output is not a source kind',
    'a later quote-checked reading judges nothing: 0 judged', 'a set of quote-checked readings only (0 person decisions) never judges a change: it stays evaluating'])
    expect(fixtures).toContain(s)
  expect(seed).toContain("(fx.u('e5'), fx.u('d5'), 'reject', fx.u('ff'), 'automated'")
})

test('every proposal records the mandate fields; the ledger refuses a rejected change; the §6 criteria judge candidates', () => {
  for (const c of ['problem_observed text not null', 'current_method text not null', 'proposed_change text not null', 'production_evidence jsonb not null', 'expected_benefit text not null',
    'risks text not null', 'acceptance_criteria jsonb not null', "actual_results jsonb not null default '{}'",
    "status text not null default 'proposed' check (status in ('proposed', 'evaluating', 'canary', 'accepted', 'rejected', 'rolled_back'))"]) expect(m).toContain(c)
  for (const k of ['accuracy', 'source_integrity', 'coverage', 'admission_safety', 'cost', 'execution_reliability', 'consumer_compatibility']) expect(m).toContain(`'${k}', jsonb_build_object(`)
  expect(m).toContain("raise exception 'ai_eval: this change was % before (proposal %); it is not proposed again'")
  expect(m).toContain("coalesce(p_spec->'acceptance_criteria_extra', '{}'::jsonb) || security.ai_proposal_criteria_v1()")
  for (const code of ['ai-p1-deadline-verbatim', 'ai-p2-not-stated-sections', 'ai-p3-page-identity-rules']) expect(m).toContain(`'code', '${code}'`)
  for (const s of ["'held_intake_not_matched', 178", "'intakes_not_stated', 13900", "'english_not_stated', 12834", "'l4_url_rejected', 448", "'matcher_agreed_with_person', 986"]) expect(m).toContain(s)
  for (const s of ['fx-b rejected: accuracy +25 points but coverage -50 points and cost +100%', 'the same change under a new code is refused: rejected before',
    'fx-d canary did worse on later decisions by a person: rolled back automatically and put in the ledger', 'the previous version is current again; fx-a is in the ledger as rolled back',
    'baseline scored: accuracy 50%, 2 false positives']) expect(fixtures).toContain(s)
})

test('approval boundaries are enforced in data: the AI path cannot accept its own changes or widen its authority', () => {
  for (const [c, a] of [['operational_adjustment', 'auto'], ['prompt', 'release'], ['extraction_schema', 'release'], ['rule_set', 'release'], ['admission_rule', 'release'],
    ['security', 'release'], ['code', 'release'], ['schema', 'release'], ['paid_permission', 'admin'], ['approval_boundary', 'admin']]) expect(m).toContain(`('${c}', '${a}', `)
  expect(m).toContain("raise exception 'ai guard: the AI cannot change its approval boundaries (%)'")
  expect(m).toContain("if coalesce(current_setting('cf247.release', true), '') !~ '^[0-9]{14}$' then")
  expect(m).toContain("select coalesce(current_setting('cf247.ai_eval_path', true), '') = 'on' or security.ops_remedy_guard_active_v1()")
  expect(m).toContain("if new.status = 'accepted' and old.authority <> 'auto' and (v_path = 'ai' or coalesce(new.release_ref, '') = '') then")
  expect(m).toContain("raise exception 'ai_eval: the AI cannot accept its own % change'")
  expect(m).toContain("from anon, authenticated, service_role;")
  for (const s of ['the AI cannot accept its own prompt change', 'the AI cannot extend its allow-list', 'not while an ops remedy runs', "a proposal''s authority cannot be changed",
    "a setting''s ceiling is never part of a proposal", 'an AI proposal to widen its boundaries is recorded with authority admin', 'no non-operational change was ever accepted on the AI path',
    'the worker role has no write on the boundaries']) expect(fixtures).toContain(s)
})
