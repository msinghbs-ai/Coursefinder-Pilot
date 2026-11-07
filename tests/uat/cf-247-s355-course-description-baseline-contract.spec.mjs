// Guards: Platform Admin direction 6 Nov 2026 08:12 (course descriptions: safe parallel planning and independent validation) and decision 19:14 §8
// (production-representative validation). CF-247 agent G. Source contract for the course-description production-parity fixture
// (tests/fixtures/course-description-parity/): the manifest is a verified production capture of the course-description path, the runner pins the
// live md5s the implementation plan guards on, and the baseline covers the held cases the plan changes (too long, too many sentences,
// unsupported claims) with today's outcomes. The database round trip is run.sh, run by .github/workflows/course-descriptions-test.yml.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { verifyManifest } from '../../scripts/prod-parity-capture.mjs'

const FX = 'tests/fixtures/course-description-parity'
const manifest = () => JSON.parse(fs.readFileSync(`${FX}/manifest.json`, 'utf8'))
const LIVE = {
  'security.course_description_check_v1(uuid,jsonb)': 'ff3d6dd7b0f88c85b1fdff6c8a8cd86b',
  'security.enrich_course_text_record_v1(bigint,jsonb)': 'b47c00b19bc6eaa36828dbe4d2371501',
  'security.course_description_trusted_v1(uuid)': '3f056fa4495963ec1d3bca61bfe0642d',
  'security.layer4_course_description_apply_v1(uuid,uuid,jsonb,text)': 'ba97236f3010e248bac44a0a7c09611a',
  'security.course_description_release_held_v1(uuid)': 'dd4b178afcd26b696d70710038e34f1c',
  'security.course_description_review_trg_v1()': 'd143eba24f5896f36a3a93e8e5c075aa',
}

test('the manifest is a verified production capture of the course-description path', () => {
  const m = manifest()
  expect(m.tool).toBe('prod-parity-capture v1')
  expect(m.source).toMatch(/fxcwkweaxjtknorudmwp, read only/)
  expect(verifyManifest(m)).toEqual([])
  expect(m.missing).toEqual([])
  const targets = m.tables.filter((t) => t.kind === 'target').map((t) => t.fq).sort()
  expect(targets).toEqual(['catalogue.courses', 'catalogue.providers', 'pipeline.coverage_course_pages', 'pipeline.evidence_artifacts', 'pipeline.field_enrich_items', 'pipeline.layer4_decisions', 'pipeline.layer4_review_items', 'pipeline.manual_locks', 'pipeline.platform_toolset_settings', 'search.course_documents'])
  const fns = Object.fromEntries(m.functions.map((f) => [f.sig, f.md5]))
  for (const [sig, md5] of Object.entries(LIVE)) expect(fns[sig], sig).toBe(md5)
  // the index courses_provider_title_slug_active_idx calls it; without it the fixture cannot be built
  expect(fns['security.course_title_key(text)']).toBeTruthy()
  // the production constraints the course-description path writes under
  const cons = (fq) => m.tables.find((t) => t.fq === fq).constraints.map((c) => c.def).join('\n')
  expect(cons('pipeline.field_enrich_items')).toContain("'skipped'::text")
  expect(cons('pipeline.field_enrich_items')).toContain('UNIQUE NULLS NOT DISTINCT (job_id, provider_id, course_id, field)')
  expect(cons('pipeline.layer4_review_items')).toContain("'edited_approved'::text")
  expect(cons('catalogue.courses')).toContain('REFERENCES pim.entity_registry(id)')
  const l4 = m.tables.find((t) => t.fq === 'pipeline.layer4_review_items').triggers.map((t) => t.name)
  expect(l4).toContain('layer4_review_items_course_description')
})

test('the runner pins the same live md5s and requires parity before the baseline runs', () => {
  const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
  for (const [sig, md5] of Object.entries(LIVE)) expect(run).toContain(`["${sig}"]=${md5}`)
  expect(run).toContain('check-sql manifest.json')
  expect(run.indexOf('check-sql manifest.json')).toBeLessThan(run.indexOf('baseline.sql'))
  expect(run).toMatch(/DB=\$\{CDESC_DB:-g_/)
})

test('a producer or SQL execution error cannot be hidden as a passing parity fixture', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cdesc-failure-'))
  try {
    // No real database is reached: the mock SQL client consumes the guard and
    // reproduces a fixture SQL error; the node mock can fail the SQL producer.
    fs.writeFileSync(path.join(tmp, 'node'), '#!/usr/bin/env bash\nif [ "$FAIL_STAGE" = producer ]; then echo "producer failed" >&2; exit 41; fi\nprintf "fixture SQL\\n"\n')
    fs.writeFileSync(path.join(tmp, 'psql'), '#!/usr/bin/env bash\nfor arg in "$@"; do\n if [ "$arg" = -f ] && [ "$FAIL_STAGE" = sql ]; then echo "ERROR: fixture failed" >&2; exit 42; fi\ndone\nif [[ " $* " != *" -c "* ]]; then cat >/dev/null; fi\n')
    fs.chmodSync(path.join(tmp, 'node'), 0o755)
    fs.chmodSync(path.join(tmp, 'psql'), 0o755)
    for (const stage of ['producer', 'sql']) {
      const r = spawnSync('bash', [`${FX}/run.sh`], { encoding: 'utf8', env: { ...process.env, PATH: `${tmp}:${process.env.PATH}`, FAIL_STAGE: stage } })
      expect(r.status, stage).not.toBe(0)
      expect(r.stdout, stage).not.toContain('parity: fixture equals')
      expect(r.stdout, stage).not.toContain('course-description queue, reconciliation and sample tests: all passed')
    }
  } finally { fs.rmSync(tmp, { recursive: true, force: true }) }
})

test('the baseline covers the held cases the plan changes, with today\'s first-failing rule', () => {
  const b = fs.readFileSync(`${FX}/baseline.sql`, 'utf8')
  for (const rule of ['ok', 'not_stated', 'sentence_count', 'length', 'unsupported_claim', 'unsupported_marketing', 'quote_not_on_page',
    'incomplete_sentence', 'unsupported_sentence', 'duplicate_other_course']) expect(b, rule).toContain(`'${rule}',`)
  expect(b).toContain('baseline case(s) changed outcome')
  expect(b).toContain('a held reading returned text')
  // the settings are production's, including the D5 hold
  const s = fs.readFileSync(`${FX}/settings.sql`, 'utf8')
  expect(s).toMatch(/'enrich\.course_description_review_first'[\s\S]*?'number', '100000'/)
  expect(s).toMatch(/'enrich\.course_description_max_chars'[\s\S]*?'number', '700'/)
  expect(s).toMatch(/'enrich\.course_description_max_sentences'[\s\S]*?'number', '4'/)
  expect(s).toContain('"students","staff","alumni","award","awards"]')
  expect(s).toContain('insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values')
})

test('the real held readings carry the rule production recorded, and no personal data', () => {
  const h = fs.readFileSync(`${FX}/held-real.sql`, 'utf8')
  for (const rule of ['sentence_count', 'length', 'unsupported_claim']) expect(h).toContain(`'${rule}'`)
  expect(h).not.toMatch(/@[a-z0-9-]+\.[a-z]{2,}/i)
  expect(h).not.toMatch(/\b(updated_by|assigned_to|actor)\b\s*[:=]/)
})

