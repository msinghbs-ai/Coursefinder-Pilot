// Guards: Platform Admin 20 Nov 2026 22:58 AEDT (S1-CourseLink-2027-CRICOS s892): Layer 4 Review › By university shows Preview & Settle Batch on a rule group
// of one queue that can be settled (Course link among them; never entry requirements, departures or descriptions): one decision, a reason and a typed SETTLE n,
// then one decide per card at the person's own rank.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { settleChoices } from '../../src/lib/l4-rules.js'

const RG = fs.readFileSync('src/Layer4RuleGroups.jsx', 'utf8')
const IN = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8')
const LINK = [{ key: 'keep', label: 'Keep the page we hold' }, { key: 'use', label: 'Use the new page' }, { key: 'enter', input: 'url', label: 'Enter another address' }, { key: 'refuse', label: 'Refuse this proposal' }]

test('s892: Course link groups can be settled; entry requirements and descriptions never', () => {
  expect(settleChoices('course_link', LINK).map(c => c.key)).toEqual(['keep', 'use', 'refuse'])
  expect(settleChoices('aer_review', LINK)).toEqual([])
  expect(settleChoices('provider_description', LINK)).toEqual([])
})

test('s892: the university view passes the queues and shows the settle box with a typed confirmation, one decide per card', () => {
  expect(IN).toContain('<Layer4RuleGroups items={items.items} kinds={kinds} onSettled=')
  expect(RG).toContain("settleChoices(ks[0],kinds?.[ks[0]]?.choices)")
  expect(RG).toContain('const n=list.length,word=`SETTLE ${n}`')
  expect(RG).toContain("disabled={!sc||why.trim().length<5||typed.trim()!==word||run?.busy}")
  expect(RG).toContain("for(const it of list){try{await decide({kind:it.kind,ref:it.ref,choice:sc.key,reason:why.trim(),value:''})")
  expect(RG).toContain('data-l4-uni-settle')
})
