// S3-AER-ChatGPT, AER-FU-07/09/10: regression for the existing NZ/CA semantic-block reader.
// Source-shaped structural fixture, not stored-copy admission evidence. Preserve strict
// country/level/grade attribution, AU reader behavior, review and publication gates.
import { test, expect } from '@playwright/test'
import path from 'node:path'
import os from 'node:os'
import { execFileSync } from 'node:child_process'

async function reader() {
  const output = path.join(os.tmpdir(), 's1080-nzca-' + process.pid + '.mjs')
  execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/entry-html-table.ts',
    '--bundle', '--platform=node', '--format=esm', '--outfile=' + output, '--log-level=error'])
  return import(output)
}
const refs = [{a2:'IN',name:'India'}, {a2:'NP',name:'Nepal'}]

test('NZ/CA country blocks recognise only printed graduate and postgraduate level labels', async () => {
  const m = await reader()
  const html = [
    '<h2>India</h2>',
    '<p>Graduate Diploma (Level 7)</p><p>Recognised bachelor degree, minimum 65% overall</p>',
    '<p>Postgraduate Certificate (Level 8)</p><p>Bachelor degree with GPA of 3.5</p>',
    '<h2>Nepal</h2>',
    '<p>Graduate Certificate</p><p>Bachelor degree with 60% overall</p>',
    '<p>Postgraduate Diploma</p><p>Bachelor degree with minimum 70% overall</p>'
  ].join('')
  for (const country of ['NZ','CA']) {
    const r = m.entryHtmlTableRead(html, refs, [], {}, {providerCountry:country})
    expect(r).not.toBeNull()
    expect(r.answer.rows).toHaveLength(4)
    expect(new Set(r.answer.rows.map(x=>x.country_code))).toEqual(new Set(['IN','NP']))
    expect(r.answer.rows.map(x=>x.min_value)).toEqual([65,3.5,60,70])
    expect(r.answer.rows.every(x=>r.text.includes(x.quote))).toBe(true)
    expect(m.entryHtmlTableCompleteness(r).status).toBe('complete')
  }
  // This reader extension is explicitly NZ/CA scoped.
  expect(m.entryHtmlTableRead(html, refs, [], {}, {providerCountry:'AU'})).toBeNull()
})

test('a single level or ambiguous country cannot become admitted-looking output', async () => {
  const m = await reader()
  const lone = '<h2>India</h2><p>Graduate Diploma (Level 7)</p><p>Minimum 65% overall</p>'
  expect(m.entryHtmlTableRead(lone,refs,[],{},{providerCountry:'NZ'})).toBeNull()
  expect(m.entryHtmlTableRead(lone.replace('India','International applicants')+
    '<p>Postgraduate Certificate (Level 8)</p><p>GPA of 3.5</p>',refs,[],{},{providerCountry:'CA'})).toBeNull()
})
