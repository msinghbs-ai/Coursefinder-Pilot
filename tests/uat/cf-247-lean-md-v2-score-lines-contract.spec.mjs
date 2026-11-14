// Guards: Lean AI Phase 1b Run B recall audit referred to S1-AER (14 Nov 2026 15:45, "20 of 51 entry-requirement misses happened because score lines like "70 Guaranteed ATAR or equivalent" were dropped when converting stored pages into [B#] blocks ... preserved in the block output without breaking the [B# ...] format"): lean-md-v2 keeps the page region today's reader sends, decodes numeric character references, and keeps a value-only line with the score label beside it; the [B#] line format is unchanged
import { test, expect } from '@playwright/test'
import { LEAN_CONVERTER, leanText } from '../../supabase/functions/coverage-sweep/lean-input.ts'
import { aerV3Blocks } from '../../supabase/functions/coverage-sweep/aer-v2.ts'

const texts = (h) => leanText(h).blocks.map((b) => b.text)
const offsetsTrue = (h) => { const l = leanText(h); return l.blocks.every((b) => h[b.source_at] === '<' && l.text.slice(b.start, b.end).endsWith(b.text)) }

test('lean-md-v2: the key-facts panel is read (an <aside>, or content outside <main>); navigation, site header, footer and scripts stay out', () => {
  expect(LEAN_CONVERTER).toBe('lean-md-v2')
  const h = '<html><nav>Menu Study Apply</nav><header>Site banner</header><main>' + '<p>About the course.</p>'.repeat(200) + '</main>' +
    '<aside class="key-facts"><div><span>70</span></div><div>Guaranteed ATAR or equivalent</div><div>Bentley Perth</div></aside>' +
    '<section><div>3 years full-time</div></section><script>var atar = 99</script><footer>Contact</footer></html>'
  const t = texts(h)
  expect(t).toContain('70 Guaranteed ATAR or equivalent')
  expect(t).toContain('3 years full-time')
  expect(t.join(' ')).not.toMatch(/Menu Study|Site banner|Contact|var atar/)
  expect(offsetsTrue(h)).toBe(true)
})

test('a value-only line is kept with the score label after it, else before it; never with a line that is not a score label', () => {
  expect(texts('<main><div class="v">80.0</div><div class="l">Guaranteed Entry ATAR or more entry options</div></main>')).toEqual(['80.0 Guaranteed Entry ATAR or more entry options'])
  expect(texts('<main><div>Lowest rank to receive an offer</div><div>58.25</div><div>65.05</div><h2>Fees</h2></main>')).toEqual(['Lowest rank to receive an offer 58.25 65.05', 'Fees'])
  expect(texts('<main><div>Minimum ATAR</div><div>70</div></main>')).toEqual(['Minimum ATAR 70'])
  expect(texts('<main><div>Campus</div><div>Bentley</div><div>2026</div><div>Duration</div></main>')).toEqual(['Campus', 'Bentley', '2026', 'Duration'])
  expect(texts('<main><div>70</div><h2>Guaranteed ATAR</h2></main>')).toEqual(['70', 'Guaranteed ATAR'])  // a heading is never joined
  expect(texts('<main><p>Selection rank 72.5 for 2026 entry.</p></main>')).toEqual(['Selection rank 72.5 for 2026 entry.'])  // a whole sentence is left as it is
})

test('numeric character references are decoded; the [B#] line format is unchanged', () => {
  expect(texts('<main><p>FNS40222 &#8211; Certificate IV in Accounting &#x2019;s</p></main>')).toEqual(['FNS40222 – Certificate IV in Accounting ’s'])
  const h = '<main><h2>Entry</h2><div>70</div><div>Guaranteed ATAR or equivalent</div><ul><li>Mathematics Methods</li></ul></main>'
  const b = aerV3Blocks(leanText(h), 'courseCode: B123')
  expect(b.input).toBe('lean-blocks-v1/lean-md-v2')
  expect(b.text.split('\n')).toEqual(['[B1 @data] courseCode: B123', `[B2 @${h.indexOf('<h2>')}] ## Entry`, `[B3 @${h.indexOf('<div>70')}] 70 Guaranteed ATAR or equivalent`, `[B4 @${h.indexOf('<li>')}] - Mathematics Methods`])
})
