// Guards: Admin #1054 NZ/CA AER S3 v1.5, verified stored Toi Ohomai answer quote, exact NCEA Level 2 credits, source-only extraction with no country inference or admission bypass.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { detRead, AER_DET_VERSION } from '../../supabase/functions/coverage-sweep/aer-det-reader.ts'
const migration = fs.readFileSync('supabase/migrations/20261129062000_cf247_s3_aer_scoped_det_v15.sql','utf8')

test('source-backed Toi Ohomai 48 NCEA Level 2 credits are detected without inventing international eligibility', () => {
  // A previously paid, stored, quote-checked shadow answer for course 2bb70b6b:
  // NZ Diploma in Primary Industry Business Management L5, evidence da4cbcb3.
  const stored = 'To be admitted to this course, applicants must meet the following general admission requirements: 48 credits in NCEA Level 2 including 12 credits in English or Māori'
  const r = detRead(stored,{scoped:true}).filter(x => x.key === 'ncea_l2')
  expect(r).toHaveLength(1)
  expect(r[0].value).toEqual({credits:48,basis:'credits'})
  expect(stored.includes(r[0].quote)).toBe(true)
  expect(r[0].quote).toContain('NCEA Level 2')
  expect(r[0].quote).toContain('48 credits')
  // 12 is the subject-specific condition, NOT the course-wide minimum.
  expect(r[0].value.credits).not.toBe(12)
  expect(detRead(stored).filter(x=>x.key==='ncea_l2')).toEqual([])
  expect(r[0].kind).toBe('academic_entry')
  expect(r[0].strength).toBe('mentioned')
})

test('fail closed for bare levels, English-test marks, one-subject-only marks and maximum credits', () => {
  for (const s of [
    'NCEA Level 2 is accepted.',
    'NCEA Level 2 including 12 credits in English.',
    'IELTS Academic 6.5 or NCEA Level 2.',
    'Up to a maximum of 48 credits in NCEA Level 2.',
    'Maximum 48 credits in NCEA Level 2.',
    'International Baccalaureate Diploma at least 30 points.'
  ]) expect(detRead(s,{scoped:true}).filter(x => x.key === 'ncea_l2'),s).toEqual([])
  expect(detRead('NCEA Level 3 with 14 credits in approved subjects.').map(x=>x.key)).toContain('ncea_l3')
})

test('existing worker/proposer/sweep are versioned together with md5, no new executor or controls',()=>{
  expect(AER_DET_VERSION).toBe('aer-det-v1.4')
  expect(fs.readFileSync('supabase/functions/coverage-sweep/aer-det-reader.ts','utf8')).toContain('AER_DET_SCOPED_VERSION = "aer-det-v1.5"')
  expect(fs.readFileSync('scripts/aer-det-read.mjs','utf8')).toContain("const V = 'aer-det-v1.4'")
  expect(fs.readFileSync('scripts/aer-det-read.mjs','utf8')).toContain("const scopedVersion = 'aer-det-v1.5'")
  expect(migration).toContain("security.aer_det_sweep_v1()")
  expect(migration).toContain("security.aer_det_propose_v1()")
  expect(migration).toContain("security.aer_det_record_v2(jsonb)")
  expect(migration).toContain("6d854e35cea21e8227664a4793b20a2a")
  expect(migration).toContain("x->>'key' in ('ncea_l2','ca_secondary_completion')")
  expect(migration).toContain("r->>'key' in ('ncea_l2','ca_secondary_completion')")
  expect(migration).toContain("p->>'extractor'='aer-det-v1.5'")
  expect(migration).toContain('6ff2467906e17f76baa8032f392c99e3')
  expect(migration).toContain('330e281bf013eb6094b6e8932ef73af9')
  expect(migration).toContain("elsif rd.test_key = 'ncea_l2'")
  expect(migration).toContain('security.consumer_api_check_v1()')
  expect(migration).toContain('pipeline.manual_locks')
  expect(migration).not.toMatch(/(?:cron\.schedule|create\s+table|alter\s+table|update\s+catalogue\.|update\s+pipeline\.platform_toolset_settings)/i)
})

test('bounded same-cohort dispatch uses only existing reader and preserves CA scope',()=>{
  const script=fs.readFileSync('scripts/aer-det-read.mjs','utf8')
  const workflow=fs.readFileSync('.github/workflows/aer-det-read.yml','utf8')
  expect(script).toContain('providerIds.length > 15')
  expect(script).toContain("!['NZ','CA'].includes(country)")
  expect(script).toContain('new Set(providerIds).size !== providerIds.length')
  expect(script).toContain('providerScope')
  expect(script).toContain('and c.provider_id in')
  expect(script).toContain('security.aer_det_record_v2')
  const worker=fs.readFileSync('supabase/functions/coverage-sweep/index.ts','utf8')
  expect(worker).toContain('body.scoped_extractor === AER_DET_SCOPED_VERSION')
  expect(worker).toContain('detRead(text, { scoped: scopedAER })')
  expect(worker).toContain('scopedAER ? AER_DET_SCOPED_VERSION : AER_DET_VERSION')
  expect(script).not.toMatch(/cron\.schedule|create\s+table|alter\s+table/i)
  expect(workflow).toContain('provider_ids:')
  expect(workflow).toContain('AER_PROVIDER_IDS: ${{ inputs.provider_ids }}')
  expect(workflow).toContain('"$AER_PROVIDER_IDS"')
  expect(workflow).toContain('concurrency:\n  group: aer-det-read')
  expect(workflow).not.toContain('schedule:')
})

test('source-grounded NIC Nursing Grade 12 completion is a qualitative candidate, never a fabricated percentage',()=>{
  // Existing stored NIC Nursing evidence 51a36319 (CA): this phrase appears
  // verbatim in the deterministic uncovered-clause ledger for course fb977de2.
  const stored='For information regarding the roles of a Registered Nurse: www.bccnm.ca Option A: Bachelor of Science in Nursing Degree Prospective students must submit transcripts as proof of meeting the following academic requirements: Grade 12 or equivalent (completing all the prerequisites below is considered b'
  const r=detRead(stored,{scoped:true}).filter(x=>x.key==='ca_secondary_completion')
  expect(r).toHaveLength(1)
  expect(r[0].value).toEqual({qualification:'Grade 12 or equivalent'})
  expect(r[0].quote).toContain('academic requirements: Grade 12 or equivalent')
  expect(stored.includes(r[0].quote)).toBe(true)
  expect(r[0].value).not.toHaveProperty('average_percent')
  expect(detRead(stored).filter(x=>x.key==='ca_secondary_completion')).toEqual([])
  expect(r[0].strength).toBe('mentioned')
  // A generic page mention alone is not an academic entry requirement.
  for(const s of ['Grade 12 or equivalent','Grade 12 chemistry course outline','International students IELTS Academic 6.5']) {
    expect(detRead(s,{scoped:true}).filter(x=>x.key==='ca_secondary_completion')).toEqual([])
  }
  expect(migration).toContain("rd.test_key = 'ca_secondary_completion'")
  expect(migration).toContain("v_cc is distinct from 'CA'")
  expect(migration).toContain("rd.test_key = 'ca_secondary_completion' and v_aud = 'all' then v_aud := 'domestic'")
  expect(migration).not.toContain("update pipeline.platform_toolset_settings")
})
