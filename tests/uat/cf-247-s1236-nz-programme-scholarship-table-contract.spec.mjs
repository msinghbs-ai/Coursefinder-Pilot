// Proposed s1236; Admin #1168. Synthetic HTML structure reconstructed from the official WITT page;
// not the immutable stored capture. Controller must qualify against evidence 0071e251-23a7-436d-b446-2ed042c2bdca before release.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
const dir = fs.mkdtempSync('/tmp/s1236-')
const out = dir + '/catalogue.mjs'
execFileSync('node_modules/.bin/esbuild', ['supabase/functions/coverage-sweep/catalogue.ts', '--bundle', '--format=esm', '--outfile='+out, '--log-level=error'])
const { awardSections, sectionHtml, sectionCode } = await import(out)
const url = 'https://www.witt.ac.nz/international-students/international-scholarships'
const fixture = (rows, terms='New full-fee paying international students with an offer for an eligible 2027 programme. Automatic tuition benefit; one year only.') =>
  '<main><h1>International Scholarships</h1><p>Automatic awards for international students, applied to tuition fees.</p><h3>Scholarship details per programme</h3><table><tr><th><h3>Programme Name</h3></th><th><h3>Scholarship</h3></th></tr>'+rows+'</table><h3>Scholarship Disclaimer</h3><p>'+terms+'</p><h3>Need help?</h3><p>Unrelated navigation</p></main>'
const row = (name, value) => '<tr><td>'+name+'</td><td>'+value+'</td></tr>'
const good = row('New Zealand Certificate in Beauty Therapy','$1,500')+row('Bachelor of Applied Management','$2,500')
test('s1236: table rows split using existing stable section keys; exact row and shared eligibility retained',()=>{
  const page=fixture(good+row('Bachelor of Nursing','n/a')+row('Master of Professional Practice (Pending NZQA Approval)','$1,000')+row('Diploma in Cookery (Course page coming soon)','$1,000')+row('New Zealand Diploma in Arts and Design','$1,500')+row('New Zealand Diploma in Arts and Design','$1,500'))
  const a=awardSections(page,url,{labels:true})
  expect(a.map(x=>x.name)).toEqual(['New Zealand Certificate in Beauty Therapy - International Scholarship','Bachelor of Applied Management - International Scholarship'])
  expect(a.map(x=>x.value_text)).toEqual(['$1,500','$2,500'])
  expect(new Set(a.map(x=>x.key)).size).toBe(2)
  for(const x of a){expect(x.url).toBeNull();expect(sectionCode(url+'#award-'+x.key.toLowerCase())).toBe(x.key)}
  const first=sectionHtml(page,a[0].key,{labels:true})
  expect(first).toContain('$1,500');expect(first).toContain('eligible 2027 programme')
  expect(first).not.toContain('$2,500');expect(first).not.toContain('Bachelor of Nursing')
  expect(first).not.toContain('Unrelated navigation')
})
test('s1236: no international eligibility, wrong header, or missing amount cannot invent a programme award',()=>{
  for(const page of [
    fixture(good,'Domestic students only.'),
    fixture(good).replace('Programme Name','Tuition fee'),
    fixture(row('New Zealand Certificate in Beauty Therapy','n/a')+row('Bachelor of Applied Management','contact us')),
    fixture(good).replace('Scholarship Disclaimer','Fees'),
  ])expect(awardSections(page,url,{labels:true}).filter(x=>x.name.endsWith(' - International Scholarship'))).toEqual([])
})
test('s1236: existing label gate off does not activate programme table fallback',()=>{
  expect(awardSections(fixture(good),url).filter(x=>x.name.endsWith(' - International Scholarship'))).toEqual([])
})
