// Guards: F-PDESC (Platform Admin data population mandate 9 Nov 2026, section 2): a provider whose catalogue name carries an abbreviation or an entity list can be proved on its own official page, a wrong institution still cannot, and a provider with no description is selected again after an admitted read (migration 20261109010000)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { descriptionIdentityLabels, descriptionSourceIdentity, descriptionPageText } from '../../supabase/functions/coverage-sweep/description.ts'

const M = fs.readFileSync('supabase/migrations/20261109010000_cf247_pdesc_description_lost.sql', 'utf8')
const run = fs.readFileSync('tests/fixtures/pdesc-self-driving/run.sh', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)

// a page the way an official About page prints it: the title and the h1 carry the institution's own name
const page = (title, h1, body = 'is a university with campuses and courses in many fields.') => `<title>About | ${title}</title><main><h1>${h1}</h1><p>${h1} ${body}</p></main>`
const proof = (html, names) => descriptionSourceIdentity(html, descriptionPageText(html, 16000), names)

test('D4: labels are derived from the catalogue name only; abbreviation parentheticals and the first entity of a list are added, the whole name is kept', () => {
  const l = (n) => descriptionIdentityLabels([n])
  expect(l('University of Technology Sydney (UTS)')).toEqual(['University of Technology Sydney (UTS)', 'University of Technology Sydney'])
  expect(l('The University of Melbourne (UniMelb)')).toContain('The University of Melbourne')
  expect(l('Deakin University (Deakin)')).toContain('Deakin University')
  expect(l('University of Tasmania (UTas)')).toContain('University of Tasmania')
  expect(l('RMIT University (RMIT)')).toContain('RMIT University')
  expect(l('The University of Newcastle (UoN), The University of Newcastle Language Centre, Sydney')).toContain('The University of Newcastle')
  expect(l('Torrens University Australia; Torrens University Language Centre; Chifley Business School at Torrens University Australia CBS at Torrens University Australia')).toContain('Torrens University Australia')
  // a plain name gains nothing
  expect(l('Monash University')).toEqual(['Monash University'])
  // a parenthetical that qualifies the name (its letters are not an abbreviation of it) is kept, so it never widens to a different institution
  expect(l("Queen's University (Belfast)")).toEqual(["Queen's University (Belfast)"])
  expect(l('University of Notre Dame Australia (Sydney)')).toEqual(['University of Notre Dame Australia (Sydney)'])
  // a first entity that is not an institution name, or is a single word, is not added
  expect(l('Smith, John University')).toEqual(['Smith, John University'])
  expect(l('Riverstone; Riverstone University Language Centre')).toEqual(['Riverstone; Riverstone University Language Centre'])
  expect(descriptionIdentityLabels(['', '  ', 'Monash University'])).toEqual(['Monash University'])
})

test('D4: the university\'s own page now proves the name shapes the catalogue holds (UTS, Melbourne, Newcastle, Deakin, UTas, Torrens, RMIT)', () => {
  const cases = [
    ['University of Technology Sydney', ['University of Technology Sydney (UTS)', 'University of Technology Sydney (UTS)']],
    ['The University of Melbourne', ['The University of Melbourne (UniMelb)', 'The University of Melbourne (UniMelb)']],
    ['The University of Newcastle', ['The University of Newcastle (UoN), The University of Newcastle Language Centre, Sydney', 'The University of Newcastle (UoN), The University of Newcastle Language Centre, Sydney']],
    ['Deakin University', ['Deakin University (Deakin)', 'Deakin University (Deakin)']],
    ['University of Tasmania', ['University of Tasmania (UTas)', 'University of Tasmania (UTas)']],
    ['Torrens University Australia', ['Torrens University Australia; Torrens University Language Centre; Chifley Business School at Torrens University Australia CBS at Torrens University Australia', 'Torrens University Australia; Torrens University Language Centre']],
    ['RMIT University', ['RMIT University (RMIT)', 'RMIT University (RMIT)']],
  ]
  for (const [printed, names] of cases) {
    const result = proof(page(printed, printed), names)
    expect(result.ok, `${printed}: ${JSON.stringify(result)}`).toBe(true)
    expect(result.rule).toBe('current_provider_name')
  }
})

test('D4 negative: a different institution, an offshore branch, a sub-unit, a bare shared name or a qualifier-widened name is still refused', () => {
  // a different university's page for the same abbreviation
  const wrong = page('Utah Tech University', 'Utah Tech University')
  expect(proof(wrong, ['University of Technology Sydney (UTS)'])).toEqual({ ok: false, rule: 'provider_name_not_proved' })
  // the other Newcastle (the aliased label is the whole of a heading, so a longer name never matches)
  const uk = page('Newcastle University', 'Newcastle University')
  expect(proof(uk, ['The University of Newcastle (UoN), The University of Newcastle Language Centre, Sydney']).ok).toBe(false)
  const upon = page('The University of Newcastle upon Tyne', 'The University of Newcastle upon Tyne')
  expect(proof(upon, ['The University of Newcastle (UoN)']).ok).toBe(false)
  // the derived label does not turn a branch or a language centre heading into the university
  expect(proof(page('Deakin University', 'Deakin University Malaysia'), ['Deakin University (Deakin)']).ok).toBe(false)
  expect(proof(page('The University of Newcastle', 'The University of Newcastle Language Centre'), ['The University of Newcastle (UoN), The University of Newcastle Language Centre, Sydney']).ok).toBe(false)
  expect(proof(page('Torrens University Australia', 'Chifley Business School at Torrens University Australia'), ['Torrens University Australia; Torrens University Language Centre; Chifley Business School at Torrens University Australia']).ok).toBe(false)
  // a school of the university is refused as a sub-unit
  expect(proof(page('University of Tasmania', 'School of Engineering'), ['University of Tasmania (UTas)'])).toEqual({ ok: false, rule: 'provider_subunit_source' })
  // a qualifier is not an abbreviation: Queen's University (Belfast) must not be proved by Queen's University in Canada
  expect(proof(page("Queen's University", "Queen's University"), ["Queen's University (Belfast)"]).ok).toBe(false)
  // the bare shared name is still never enough
  expect(proof(page('Deakin', 'Deakin'), ['Deakin University (Deakin)'])).toEqual({ ok: false, rule: 'provider_name_not_proved' })
  // a body mention of the name on another institution's page is a conflict, as before
  const partner = page('Utah Tech University', 'Utah Tech University', 'works with Deakin University and the University of Tasmania.')
  expect(proof(partner, ['Deakin University (Deakin)']).ok).toBe(false)
})

test('D5: one live function is edited under its live md5 with a recorded after md5, once, and nothing else is edited', () => {
  expect(M).toMatch(/--   security\.provider_description_selection_v1\(jsonb\) 1fd3fcde2fcafed6fadf4f6337c0482c -> [0-9a-f]{32}/)
  expect(M).not.toContain('@@AFTER@@')
  expect(C).toContain("select pg_temp.edit_all('security.provider_description_selection_v1(jsonb)', '1fd3fcde2fcafed6fadf4f6337c0482c'")
  expect(C).toContain('must apply exactly once')
  expect(C).toContain('already applied')
  expect(C.match(/pg_temp\.edit_all\('/g)?.length).toBe(1)
  expect(C).not.toMatch(/create or replace function (security|public|api)\./)
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing/m)
  expect(M).toMatch(/^-- Nothing is dropped or deleted\./m)
})

test('D5: description_current needs a held description; description_lost is eligible after every earlier and later guard; the other branches are not touched', () => {
  expect(C).toContain("when r.state in ('admitted','verified') and nullif(btrim(p.description),'') is not null and coalesce(r.last_verified_at,r.updated_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int) then 'description_current'")
  expect(C).toContain("when r.state in ('admitted','verified') and nullif(btrim(p.description),'') is null then 'description_lost'")
  expect(C.match(/'eligible','invalid_description','description_lost'/g)?.length).toBe(3)
  // the CASE branches are replaced as text only where listed; no guard is named in an edit
  for (const guard of ['manual_lock', 'manual_description', 'existing_work', 'dead_letter_requires_retry', 'retry_wait', 'unchanged_unsuitable_evidence', 'recovery_knowledge_unchanged_failure', 'provider_inactive', 'provider_not_published']) expect(C).not.toContain(`then '${guard}'`)
  for (const label of ['lost_admitted|description_lost', 'lost_verified|description_lost', 'lost_past_recheck|description_lost', 'lost_manual_lock|manual_lock', 'lost_then_rejected|retry_wait',
    'lost_identity_finding|identity_identity_unconfirmed', 'lost_open_work|existing_work', 'described_current|description_current', 'enqueued|lost_admitted,lost_verified,lost_past_recheck']) expect(run).toContain(label)
  expect(run).toContain("'lost_admitted|description_current'")
  expect(run).toContain('applied again: no change')
})

test('D5: no setting, flag, job, Layer 4 item or consumer API object is written, and no number is added to code', () => {
  expect(C).not.toMatch(/insert into pipeline\.(platform_toolset_settings|layer4_|provider_description_reads|automation_catalogue)|update pipeline\.(platform_toolset_settings|layer4_|provider_description_reads)|delete from|drop (table|function|view|column)/i)
  expect(C).not.toMatch(/cron\.(schedule|unschedule|alter_job)/)
  expect(C).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
  // the only numbers are the defaults of settings that already exist
  for (const m of C.matchAll(/pipeline_num_v1\('([a-z_.]+)',\s*([0-9.]+)\)/g)) expect(['pdesc.recheck_days', 'pdesc.retry_minutes']).toContain(m[1])
  expect(run).toContain('the migration changed settings')
  expect(run).toContain('the migration changed Layer 4')
  expect(run).toContain('the migration changed jobs')
  expect(run).toContain('the migration changed a function it does not own')
  expect(run).toContain('case "$DB" in g_*)')
  expect(fs.readFileSync('.github/workflows/provider-description-integration.yml', 'utf8')).toContain('bash tests/fixtures/pdesc-self-driving/run.sh')
})
