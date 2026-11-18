// Guards: Provider description prompt stored record (Platform Admin 19 Nov 2026 06:49 item 1): the texts of prompt versions 4 and 5 are checked-in fixtures whose checksums are the live rows' checksums, version 5 is exactly version 4 with the three rewrites of 20261118213000 (two to three sentences, the provider's full name at the start of the first, the most-refused words left out), and a stored version is never edited in place.
// CF-247 S760. Migration 20261119080000_cf247_pdesc_prompt_record_and_held_reread_restore. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const md5 = (s) => crypto.createHash('md5').update(s, 'utf8').digest('hex')
const v4 = fs.readFileSync('tests/fixtures/pdesc/provider-description-prompt-v4.txt', 'utf8')
const v5 = fs.readFileSync('tests/fixtures/pdesc/provider-description-prompt-v5.txt', 'utf8')
const code = fs.readFileSync('supabase/migrations/20261119080000_cf247_pdesc_prompt_record_and_held_reread_restore.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const built = fs.readFileSync('supabase/migrations-archive/20261118213000_cf247_held_scholarship_settle_pdesc_prompt_v5.sql', 'utf8')

test('the fixtures are the live rows byte for byte', () => {
  expect(md5(v4)).toBe('985e2613f4970f5936de23a89122bf83')
  expect(md5(v5)).toBe('2784dc0f126d5e72e7817f0f769357d6')
  expect(code).toContain("if v_md5 <> '2784dc0f126d5e72e7817f0f769357d6' then raise exception")
  expect(code).toContain("is distinct from '985e2613f4970f5936de23a89122bf83' then")
})

test('version 5 is version 4 with the three rewrites the building migration names', () => {
  const l3 = '- Do not mention fees, scholarships, visas or entry requirements.'
  const never = '- Never use these words, and leave out a fact that cannot be said without one: accredited, accreditation, excellence, excellent, innovative, leading, vibrant, top, best, premier, renowned, exceptional, cutting-edge, guaranteed, funding, loan, bursary, tuition.'
  const first = 'The first sentence must begin with the provider\'s full name exactly as given and say what kind of institution it is; never begin it with "It", "The college", "The university", "The school" or a short form of the name.'
  expect(v4.replace('Write 3 to 4 sentences (about 60 to 110 words)', 'Write 2 to 3 sentences (about 40 to 90 words)')
    .replace("Begin the first sentence with the provider's full name as given.", first).replace(l3, l3 + '\n' + never)).toBe(v5)
  expect(built).toContain("v5 := replace(v4, l1, 'Write 2 to 3 sentences (about 40 to 90 words)');")
  expect(built).toContain(never)
  expect(built).toContain(first.replace(/'/g, "''"))
})

test('the prompt keeps the grounding rules and no stored version is edited', () => {
  expect(v5).toContain('each copied character for character from the page text')
  expect(v5).toContain('never join two passages into one')
  expect(v5).toContain('Every fact must come from the page. No outside knowledge, no guessing.')
  expect(code).not.toMatch(/update pipeline\.provider_description_prompts|insert into pipeline\.provider_description_prompts/)
})
