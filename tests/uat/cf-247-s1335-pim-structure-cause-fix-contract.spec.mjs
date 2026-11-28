// Guards: DR-19 acceptance ([PC-20261128-0938-S2-RM-Design]): unsupported_website_structure means a structural cause only; description guard holds (held: unsupported_sentence, unsupported_claim) stay insufficient evidence
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201020000_cf247_s1335_pim_structure_cause_fix.sql', 'utf8')

test('s1335: the structure pattern no longer matches guard holds', () => {
  const m = sql.match(/v_new text := \$n\$([\s\S]*?)\$n\$/)
  expect(m !== null).toBe(true)
  const re = /\(unsupported \(page\|site\|format\|file type\|structure\|layout\)\|page layout\|site structure\|javascript\|scanned\|image-only\|no text layer\|client-side render\)/
  expect(re.test(m[1])).toBe(true)
  expect(m[1]).toContain("!~* 'held:'")
  const pattern = new RegExp('(unsupported (page|site|format|file type|structure|layout)|page layout|site structure|javascript|scanned|image-only|no text layer|client-side render)', 'i')
  expect(pattern.test('held: unsupported_sentence: a sentence is not supported by its quote')).toBe(false)
  expect(pattern.test('held: unsupported_claim: a ranking claim')).toBe(false)
  expect(pattern.test('page needs JavaScript to render')).toBe(true)
})

test('s1335: one anchored edit, guarded, read-only', () => {
  expect(sql).toContain("if v_n <> 1 then raise exception")
  expect(sql).toContain('security.consumer_api_check_v1()')
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
