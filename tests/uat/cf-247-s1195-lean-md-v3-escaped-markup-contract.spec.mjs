// Guards: Platform Admin 25 Nov 2026 18:26 AEDT (the Holmesglen converter fix after the course entry windows; s1152 finding: requirements published as escaped HTML kept "<br>" in the lean text)
// s1195: lean-md-v3 takes out an escaped tag of a known HTML element like a real tag; text such as "a &lt; b" stays; nothing else in the conversion changes and no page is read again for the new version.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { LEAN_CONVERTER, leanText } from '../../supabase/functions/coverage-sweep/lean-input.ts'

// the stored Holmesglen markup recorded by s1152 (pipeline.lean_section_eval_cases.miss_detail), as the page prints it
const HOLMESGLEN = '<div class="course-entry">&lt;p&gt;&lt;strong&gt;Academic requirements&lt;/strong&gt;&lt;br&gt;You must have successfully completed:&lt;br&gt;• VCE Year 12 or an &lt;a href=&#34;https://www.vcaa.vic.edu.au/assessment&#34;&gt;overseas equivalent&lt;/a&gt; &lt;br&gt;You may also be considered if you have:&lt;br&gt;• Completed an Australian Diploma or Advanced Diploma (or equivalent) in a relevant discipline; or &lt;br&gt;• Partially or fully completed higher education study at a recognised university &lt;p&gt;All applications are assessed individually in accordance with Holmesglen&#39;s admissions policies.</div>'

test('s1195: lean-md-v3 reads escaped markup as words, so the missed Holmesglen line is in the lean text', () => {
  expect(LEAN_CONVERTER).toBe('lean-md-v3')
  const t = leanText(HOLMESGLEN).text
  expect(t).not.toMatch(/<\/?(br|p|strong|a)\b|&lt;|&gt;/i)
  expect(t).toContain('You may also be considered if you have: • Completed an Australian Diploma or Advanced Diploma (or equivalent) in a relevant discipline; or • Partially')
  expect(t).toContain('VCE Year 12 or an overseas equivalent')
  expect(t).toContain("Holmesglen's admissions policies")
})

test('s1195: only escaped tags of known HTML elements are taken out; ordinary text and the rest of the conversion are unchanged', () => {
  expect(leanText('<p>Pass mark: a score &lt; 50 fails &gt; 70 merits.</p>').text).toBe('Pass mark: a score < 50 fails > 70 merits.')
  expect(leanText('<p>Use the &lt;course code&gt; field.</p>').text).toBe('Use the <course code> field.')
  const h = '<h2>Entry</h2><ul><li>ATAR 70</li></ul><table><tr><th>Country</th><th>Score</th></tr><tr><td>India</td><td>65%</td></tr></table>'
  const l = leanText(h)
  expect(l.text).toBe('## Entry\n- ATAR 70\nCountry: India | Score: 65%')
  expect(l.blocks.every((b) => h[b.source_at] === '<')).toBe(true)
})

test('s1195: no queue, job or setting reads on the converter name, so the new version reads no page again', () => {
  // nothing compares or re-queues on the converter name (checked file by file; comments, run labels and notes may name it)
  for (const f of fs.readdirSync('supabase/migrations').filter((f) => f >= '20261129040000')) {
    const code = fs.readFileSync(`supabase/migrations/${f}`, 'utf8').replace(/--.*$/gm, '')
    expect(code, f).not.toMatch(/\bconverter\b\s*(=|<>|!=|is\s+distinct|in\s*\()/i)
    expect(code, f).not.toMatch(/lean_section_eval_cases[^;]*\bconverter\b\s*</i)
  }
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(ix).toContain('// was v1.0.47 // v1.0.47 (26 Nov 2026, CF-247 s1195')
})
