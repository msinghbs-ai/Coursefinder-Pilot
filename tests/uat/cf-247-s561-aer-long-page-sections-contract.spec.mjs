// Guards: AER long pages (Platform Admin 16 Nov 2026 16:52): a page longer than reading.aer_v2_page_chars is never cut; with reading.aer_v2_long_page_sections_on = 1 the AER v3 reader is sent only its entry requirement sections, with the page's own block numbers, and the answer is verified against the whole page; off by default
// CF-247 S561. Migration 20261116130000_cf247_aer_v2_long_page_sections; worker coverage-sweep v1.0.6 (lean-sections.ts longPageWindow, aer-v2.ts aerV3User, index.ts).
// G2, G3 and housekeeping are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { aerV3Blocks, aerV3User } from '../../supabase/functions/coverage-sweep/aer-v2.ts'
import { longPageWindow, LEAN_SECTIONS } from '../../supabase/functions/coverage-sweep/lean-sections.ts'

const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const M = fs.readFileSync('supabase/migrations-archive/20261116130000_cf247_aer_v2_long_page_sections.sql', 'utf8')

// a synthetic page: a long run of unrelated paragraphs, then an entry requirements section
const filler = 'This paragraph describes the campus gardens, the library opening hours and the student clubs in some detail for visitors. '.repeat(4)
const page = (withEntry) => {
  const blocks = []
  for (let i = 0; i < 160; i++) blocks.push({ kind: i % 20 === 0 ? 'heading' : 'paragraph', text: i % 20 === 0 ? `Campus life part ${i / 20 + 1}` : filler, source_at: i * 500 })
  if (withEntry) {
    blocks.push({ kind: 'heading', text: 'Entry requirements', source_at: 90000 })
    blocks.push({ kind: 'paragraph', text: 'International applicants need a completed secondary qualification equivalent to an Australian ATAR of 80.', source_at: 90100 })
    blocks.push({ kind: 'item', text: 'India - CBSE: overall 75%', source_at: 90200 })
  }
  return aerV3Blocks({ converter: 'lean-md-v1', blocks }, 'Course code: ABC123')
}

test('a short page is sent whole and unchanged; a long page with the switch off is not read', () => {
  const short = aerV3Blocks({ converter: 'lean-md-v1', blocks: [{ kind: 'heading', text: 'Entry requirements', source_at: 0 }, { kind: 'paragraph', text: 'ATAR 70', source_at: 10 }] }, null)
  const a = longPageWindow(short, 60000, true)
  expect(a.send).toBe(short)
  expect(a.window).toBeNull()
  const long = page(true)
  expect(long.text.length).toBeGreaterThan(60000)
  expect(longPageWindow(long, 60000, false)).toEqual({ send: null, window: null })
})

test('switch on: only the entry requirement sections are sent, with the page block numbers, within the limit', () => {
  const long = page(true)
  const { send, window } = longPageWindow(long, 60000, true)
  expect(send).not.toBeNull()
  expect(send.text.length).toBeLessThanOrEqual(60000)
  expect(send.input).toBe(`${long.input}+${LEAN_SECTIONS}`)
  const byN = new Map(long.blocks.map((b) => [b.n, b]))
  for (const b of send.blocks) expect(byN.get(b.n)).toEqual(b)            // the same block, same number
  const texts = send.blocks.map((b) => b.text)
  expect(texts).toContain('Entry requirements')
  expect(texts).toContain('India - CBSE: overall 75%')
  expect(texts).toContain('Course code: ABC123')                             // page data always travels
  expect(texts).not.toContain(filler)
  expect(window).toMatchObject({ selector: LEAN_SECTIONS, field: 'entry_requirements', page_chars: long.text.length, of_blocks: long.blocks.length, no_selection: false, fits: true })
  const user = aerV3User({ title: 'Bachelor of Things', provider: 'Example University' }, [], send, long.blocks.length)
  expect(user).toContain(`PAGE BLOCKS (${send.blocks.length} of the page's ${long.blocks.length} blocks: the entry requirement sections of a long page`)
  expect(aerV3User({ title: 'x', provider: 'y' }, [], long)).toContain('the whole page, in page order')
})

test('switch on, no entry section found: the page stays page_too_long and the window says why', () => {
  const { send, window } = longPageWindow(page(false), 60000, true)
  expect(send).toBeNull()
  expect(window.fits).toBe(false)
})

test('the worker verifies against the whole page, reads the switch, and the switch starts off', () => {
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.50"')  // v1.0.38 from s1037  // v1.0.37 from s1029  // v1.0.36 from s1017  // v1.0.35 from s992  // v1.0.34 from s851  // v1.0.25 from s721  // v1.0.19 from s674
  expect((IX.match(/const longOn = wsNum\("reading\.aer_v2_long_page_sections_on", 0\) === 1;/g) || []).length).toBe(2)
  expect(IX).toContain('const lp = longPageWindow(blocks, pageChars, longOn);')
  expect(IX).toContain('const v = aerV3Verify(a.a, blocks, refs, quoteMax, gapMax);')   // the whole page's blocks, not the selection
  expect(IX).toContain('a cut page is never read')
  expect(M).toContain("'reading.aer_v2_long_page_sections_on'")
  expect(M).toContain("'number', to_jsonb(0), 0, 1, 'switch'")
})
