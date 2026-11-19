// Guards: course field readiness as plain per-country CSV files (Platform Admin 19 Nov 2026 14:24): one file per country, split into parts by size so each opens directly and stays under 2.9 MB (one Google Drive connector upload), the header in every part, every course once, in matrix order.
// CF-247 S771. scripts/telemetry/course-field-readiness.mjs; .github/workflows/course-field-readiness.yml
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { build, FIELDS, MAX_PART_BYTES } from '../../scripts/telemetry/course-field-readiness.mjs'

const row = (i, cc) => ({ course_id: `c${String(i).padStart(5, '0')}`, country_code: cc, provider_id: `p${cc}`, provider_name: `Provider ${cc}`, course_title: `Course ${String(i).padStart(5, '0')}`,
  cells: Object.fromEntries(FIELDS.map((f) => [f, f === 'duration' ? '3 years' : 'POSSIBLE_NEEDS_SOURCE'])) })

test('the part limit is under 2.9 MB', () => {
  expect(MAX_PART_BYTES).toBe(2_850_000)
  expect(MAX_PART_BYTES).toBeLessThan(2_900_000)
})

test('one file per country; a country over the limit is split into numbered parts, each with the header and under the limit', () => {
  const rows = [...Array.from({ length: 30 }, (_, i) => row(i, 'AU')), ...Array.from({ length: 4 }, (_, i) => row(100 + i, 'CA')), ...Array.from({ length: 9 }, (_, i) => row(200 + i, 'NZ'))]
  const { csv, files, summary } = build(rows, '2026-11-19', 3000)
  const header = csv.split('\n')[0]
  expect(files.map(f => f.name).filter(n => n.includes('_CA_'))).toEqual(['Course_Field_Readiness_CA_2026-11-19.csv'])
  const au = files.filter(f => f.country === 'AU')
  expect(au.length).toBeGreaterThan(1)
  au.forEach((f, i) => expect(f.name).toBe(`Course_Field_Readiness_AU_Part${i + 1}_2026-11-19.csv`))
  for (const f of files) {
    expect(f.bytes).toBeLessThanOrEqual(3000)
    expect(f.content.split('\n')[0]).toBe(header)
    expect(Buffer.byteLength(f.content)).toBe(f.bytes)
  }
  const ids = files.flatMap(f => f.content.trim().split('\n').slice(1).map(l => l.split(',')[0]))
  expect(ids).toHaveLength(rows.length)
  expect(new Set(ids).size).toBe(rows.length)
  expect(ids).toEqual(csv.trim().split('\n').slice(1).map(l => l.split(',')[0]))
  expect(summary.country_files.map(f => f.name)).toEqual(files.map(f => f.name))
})

test('the renderer writes the country files beside the matrix; the workflow commits them', () => {
  const src = fs.readFileSync('scripts/telemetry/course-field-readiness.mjs', 'utf8')
  expect(src).toContain('for (const f of files) fs.writeFileSync(path.join(outDir, f.name), f.content)')
  expect(fs.readFileSync('.github/workflows/course-field-readiness.yml', 'utf8')).toContain('cp "$RUNNER_TEMP"/out/* monitoring/course-readiness/')
})
