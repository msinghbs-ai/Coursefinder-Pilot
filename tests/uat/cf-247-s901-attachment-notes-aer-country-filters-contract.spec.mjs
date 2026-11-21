// Guards: CF-247 s901 (Platform Admin 21 Nov 2026 07:48, chat S1-Coverage-Unlock-UI-Notes): one counsellor notes panel, closed on load, on
// Course detail, Entry requirements and Scholarships; Entry requirements › Provider entry matrix filters by Destination country (where the
// provider is) and Source country (the student's country of prior education, the filter once called "Country") and by Applies to; Course
// detail shows the university-wide entry table that applies; one md5-guarded edit of the admin function public.admin_aer
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const notes = fs.readFileSync('src/AttachmentNotes.jsx', 'utf8')
const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
const aer = fs.readFileSync('src/AerWorkspace.jsx', 'utf8')
const blade = fs.readFileSync('src/CorrelatedBlade.jsx', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261121100000_cf247_s901_aer_destination_source_filters.sql', 'utf8')

test('the notes are one <details>, never opened by the page, on the three pages', () => {
  expect(notes).toContain("export const NOTES_TITLE = 'Notes · How scholarships, AER & field rules attach to courses'")
  expect(notes).toContain('<details className="an-notes" data-attachment-notes={focus}>')
  expect(notes).not.toMatch(/<details[^>]*\bopen\b/)
  expect(notes).not.toMatch(/supabase|rpc\(|useEffect/)
  for (const s of ['data-notes-section="scholarships"', 'data-notes-section="aer"', 'data-notes-section="elr"']) expect(notes).toContain(s)
  // the four scholarship rules, the AER order and both countries, the English and register exceptions
  for (const s of ['Named course.', 'Study level or faculty rule.', 'University-wide.', 'Why a course can show no scholarship.',
                   'Study destination</strong> is where the university is', 'Student\'s education country</strong> (Layer 4: Source country) is where the student earned their prior qualification',
                   'University-wide entry table.', 'Which rule wins', 'Regulated disciplines', 'Register values', 'A value a person has locked is never replaced'])
    expect(notes).toContain(s)
  expect(main).toContain('<AttachmentNotes focus="course"/>')
  expect(main).toContain('<AttachmentNotes focus="scholarships"/><ScholarshipWorkspace')
  expect(aer).toContain('<AttachmentNotes focus="aer"/>{body}')
})

test('Provider entry matrix: Destination country, Source country (was Country) and Applies to; one server edit, md5-guarded', () => {
  expect(aer).toContain('<FilterSelect label="Study destination" value={f.destination}') // REQ-92 (s956): was Destination country
  expect(aer).toContain('<FilterSelect label="Student\'s education country" value={f.country}') // REQ-92 (s956): was Source country
  expect(aer).toContain('<FilterSelect label="Applies to" value={f.scope}')
  expect(aer).not.toContain('<FilterSelect label="Country" value={f.country}')
  expect(aer).toContain("destination:'Study destination',country:'Student\\'s education country',scope:'Applies to'")
  expect(MIG).toContain("select pg_temp.edit_once('public.admin_aer(text,jsonb)', '0593747bb6ddd55c785fc445a06eb242', '0f4af8394ea36e6ef96df2e9130e0cc9', array[")
  expect(MIG).toContain("and ($1->>'destination' is null or p.country_id = (select k9.id from ref.countries k9 where k9.iso_alpha2 = upper($1->>'destination')))")
  expect(MIG).toContain("and ($1->>'scope' is null or ($1->>'scope' = 'university' and m.course_id is null) or ($1->>'scope' = 'course' and m.course_id is not null))")
  expect(MIG).toContain("$n$'destinations', (select coalesce(")
  expect(MIG).toContain('], array[1, 1]);')
  expect(MIG).toMatch(/^-- Replaces: .+$/m)
  expect(MIG).toMatch(/^-- Retires: .+$/m)
  expect(MIG).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('Course detail › Entry requirements shows the university-wide table that applies, with waiting rows marked internal', () => {
  expect(blade).toContain("const uwArgs=s=>({p_action:'matrix_list',p_args:{provider_id:providerId,scope:'university',status:s,page_size:1}})")
  expect(blade).toContain('data-cb-entry-university={Number(uwA.data?.total||0)}')
  expect(blade).toContain('data-vis="layer4_queue_state" data-cb-entry-university-proposed=')
  expect(blade).toContain("They apply to this course unless a course rule above overrides them.")
})

const matrixRow = { kind: 'matrix', id: 'm1', provider_id: 'p-csu', provider_name: 'Charles Sturt University', country: 'IN', country_name: 'India',
  level_label: 'Undergraduate', level_code: 'UG', qualification: 'CBSE Year 12', band: null, min_grade: '65%', min_value: 65, scale: 'percentage',
  matrix_kind: 'provider_minimum', edition: null, intake_year: null, as_at: '2026-11-01', status: 'active', quote: 'CBSE 65%', source_url: 'https://study.csu.edu.au/x', updated_at: '2026-11-01' }

async function mockAer(page) {
  const { mockAdmin } = await import('./support/admin-mock.mjs')
  await mockAdmin(page, { rank: 6 })
  const calls = []
  await page.route('https://example.supabase.co/rest/v1/rpc/admin_aer', async route => {
    const b = route.request().postDataJSON() || {}, a = b.p_args || {}
    calls.push({ action: b.p_action, args: a })
    const j = json => route.fulfill({ json })
    if (b.p_action === 'summary') return j({ matrix: { active: 1, proposed: 7, unverified: 0, inactive: 0, superseded: 0 }, course: { proposed: 0 }, sources: { total: 1, held: 0, fetch_failed: 0, reading: 0, read: 1 }, courses_with_active: 0, courses_waiting: 0, can_edit: true, can_reread: true })
    if (b.p_action === 'options') return j({ providers: [{ id: 'p-csu', name: 'Charles Sturt University' }], countries: [{ code: 'IN', name: 'India' }], all_countries: [{ code: 'IN', name: 'India' }],
      destinations: [{ code: 'AU', name: 'Australia' }, { code: 'NZ', name: 'New Zealand' }], levels: [], level_labels: [], bands: [], editions: [], intake_years: [], matrix_kinds: ['provider_minimum'], requirement_kinds: [], scales: ['percentage'], audiences: ['international'], statuses: ['active', 'proposed'] })
    if (b.p_action === 'matrix_list') return j({ total: 1, offset: 0, page_size: 50, rows: [matrixRow] })
    return j({})
  })
  return calls
}

test.describe('mocked browser', () => {
  test('notes closed on load and open in one click; Destination and Source country go to the server as two filters', async ({ page }) => {
    const calls = await mockAer(page)
    await page.goto('/#entry-requirements')
    const panel = page.locator('details[data-attachment-notes="aer"]')
    await expect(panel).toHaveCount(1)
    await expect(panel).not.toHaveAttribute('open', '')
    await expect(panel.locator('[data-notes-section="aer"]')).toBeHidden()
    await panel.locator('summary').click()
    await expect(panel.locator('[data-notes-section="aer"]')).toBeVisible()
    await expect(panel).toContainText('Study destination is where the university is')
    const bar = page.locator('[data-aer-filters="matrix"]')
    await bar.getByRole('button', { name: /Study destination/ }).click(); await page.locator('.m-filter-popover').getByRole('button', { name: /Australia/ }).click()
    await bar.getByRole('button', { name: /Student's education country/ }).click(); await page.locator('.m-filter-popover').getByRole('button', { name: /India/ }).click()
    await bar.getByRole('button', { name: /Applies to/ }).click(); await page.locator('.m-filter-popover').getByRole('button', { name: /University-wide/ }).click()
    await expect.poll(() => calls.filter(c => c.action === 'matrix_list').at(-1)?.args).toMatchObject({ destination: 'AU', country: 'IN', scope: 'university' })
    await expect(page.locator('[data-aer-chips]')).toContainText('Study destination: Australia')
    await expect(page.locator('[data-aer-chips]')).toContainText('Student\'s education country: India')
    await expect(page.locator('table[data-table="aer-matrix"] thead')).toContainText('Education country')
  })
})
