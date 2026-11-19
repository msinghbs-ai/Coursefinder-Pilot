// Guards: S752 Windows-1252 punctuation folded inside the AER v2 chunk verifier only (Platform Admin 19 Nov 2026 14:25 AEDT, session S2-BOOST-AER): raw bytes U+0091 to U+0097, their numeric references (&#145;, &#x91;) and the Unicode curly quotes and dashes (and their references) compare as ' " and -, so a page printing "&#145;C&#146;" (KBS Korea) passes quote and minimum checks; the shared AER v1 text converter is frozen and unchanged (Decision 276).
// CF-247 S752. supabase/functions/coverage-sweep/aer-chunk-smoke.ts (cp1252Fold in chunkFlat). G2, G3 and housekeeping: s32, s57, s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { aerChunkVerify, aerChunkVerifyV2, chunkFlat, cp1252Fold } from '../../supabase/functions/coverage-sweep/aer-chunk-smoke.ts'
import { htmlToText } from '../../supabase/functions/coverage-sweep/extract.ts'

const KR = { n: 27, kind: 'table_row', table: 0, context: [], header: 'Countries and Regions | Equivalent Academic Requirement - Diploma | Equivalent Academic Requirement - Bachelor', label: 'Korea',
  quote: 'Korea | Successful completion of High School Leaving Certificate Year 3 with a &#145;C&#146; grade average in 4 academic subjects or CSAT 270', cells: [], country: null, qualification: null }

test('the fold maps Windows-1252 punctuation in every form a page prints it, and nothing else', () => {
  expect(cp1252Fold('&#145;C&#146; &#x93;q&#x94; \u0091a\u0092 ‘b’ “c” 1–2 &#8216;d&#8217; &#x2014;')).toBe('\'C\' "q" \'a\' \'b\' "c" 1-2 \'d\' -')
  expect(cp1252Fold('&#160; &#38; &#233; 70% B+ ATAR of 70')).toBe('&#160; &#38; &#233; 70% B+ ATAR of 70')
  expect(chunkFlat('with a &#145;C&#146; grade')).toBe("with a 'C' grade")
})

test('KBS Korea: a minimum written with plain quotes is inside a quote the page prints with Windows quote codes (both contracts)', () => {
  const rec = { r: 27, no_requirement: false, country: 'Korea', qualification: 'High School Leaving Certificate Year 3', study_level: 'Equivalent Academic Requirement - Diploma',
    minimum: "'C' grade average", quote: 'Successful completion of High School Leaving Certificate Year 3 with a &#145;C&#146; grade average in 4 academic subjects' }
  for (const v of [aerChunkVerify({ rows: [rec] }, [KR]), aerChunkVerifyV2({ rows: [rec] }, [KR])]) expect([v.quotes_in_row, v.minimums_in_quote]).toEqual([1, 1])
  // a quote the model tidied the other way round (curly quotes for the page's codes) also stays inside its row
  const curly = { ...rec, quote: 'with a ‘C’ grade average', minimum: '‘C’ grade average' }
  expect(aerChunkVerifyV2({ rows: [curly] }, [KR]).checks[0]).toMatchObject({ quote_in_row: true, minimum_in_quote: true })
  // a different letter is still a different minimum
  expect(aerChunkVerifyV2({ rows: [{ ...rec, minimum: "'B' grade average" }] }, [KR]).minimums_in_quote).toBe(0)
})

test('the shared AER v1 text converter is untouched: it still prints the references as the page has them, and the verifier does not import it', () => {
  expect(htmlToText('<p>with a &#145;C&#146; grade &#8216;y&#8217; &amp;</p>')).toBe('with a &#145;C&#146; grade &#8216;y&#8217; &')
  const mod = fs.readFileSync('supabase/functions/coverage-sweep/aer-chunk-smoke.ts', 'utf8')
  expect(mod).not.toMatch(/from "\.\/(extract|entry|lean-input)\.ts"/)
  expect(mod).toContain('export const chunkFlat = (s: unknown) => cp1252Fold(String(s ?? "")).normalize("NFKC")')
})
