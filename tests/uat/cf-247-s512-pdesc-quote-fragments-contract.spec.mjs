// Guards: F-PDESC Directive 3 (Platform Admin, 9 Nov 2026), quote_not_on_page: a provider-description quote the model joined from separate passages with an ellipsis is proven fragment by fragment (each on the page by the whole-quote rule, long enough, in order, at least two) only when the switch reading.provider_quote_fragments_on is on; off, or on any failed fragment, it is quote_not_on_page as before; the claim checks, identity proof, manual locks and database validation are unchanged.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { providerDescriptionSentences, providerQuoteFragments } from '../../supabase/functions/coverage-sweep/description.ts'

// the model's own quote strings from the live holds (see the note in the fixture); every page below is reconstructed from them
const Q = JSON.parse(fs.readFileSync('tests/fixtures/pdesc-quote-fragments/live-quotes.json', 'utf8'))
const MIN = 20  // the live value of pdesc.min_quote_chars
const FILLER = ['Welcome to our site. Apply now.', 'Student stories and news from the campus.', 'Contact us for more information about enrolment.']
// the page: each fragment stands on it, in order, with other text between them
const pageOf = (q, order = (a) => a) => order(providerQuoteFragments(q)).flatMap((f, i) => [FILLER[i % FILLER.length], f]).concat(['Privacy policy and terms of use.']).join(' ')
const prove = (quote, page, fragments, min = MIN) => providerDescriptionSentences({ sentences: [{ text: 'A sentence the quote supports.', quote }] }, page, min, fragments === undefined ? undefined : { fragments }).sentences[0]

test('the fragments of a joined quote are split at "..", "..." and the single ellipsis character, and nothing else', () => {
  expect(providerQuoteFragments('First part of it... Second part of it')).toEqual(['First part of it', 'Second part of it'])
  expect(providerQuoteFragments('First part of it .. Second part of it … Third part of it.')).toEqual(['First part of it', 'Second part of it', 'Third part of it.'])
  expect(providerQuoteFragments('One whole quote with a full stop. And another sentence.')).toEqual(['One whole quote with a full stop. And another sentence.'])
  expect(providerQuoteFragments('A quote cut short...')).toEqual(['A quote cut short'])
  expect(providerQuoteFragments(Q.acu_faculties)).toHaveLength(4)
  expect(providerQuoteFragments(Q.acu_faculties)[0]).toBe('Find your faculty Faculty of Education and Arts')
})

test('POSITIVE: with the switch on, the live ellipsis-joined quotes whose fragments are all on the page in order are proved, with the fragment count', () => {
  for (const [key, n] of [['acu_faculties', 4], ['nmit_industry', 2], ['tai_poutini_outdoor', 2]]) {
    const s = prove(Q[key], pageOf(Q[key]), true)
    expect(s, key).toEqual({ text: 'A sentence the quote supports.', quote: Q[key], on_page: true, fragments: n })
  }
})

test('the switch is off unless set: the omitted option and false keep every joined quote quote_not_on_page', () => {
  for (const f of [undefined, false]) {
    const s = prove(Q.acu_faculties, pageOf(Q.acu_faculties), f)
    expect(s.on_page).toBe(false)
    expect('fragments' in s).toBe(false)
  }
})

test('a quote that is whole on the page is proved as before, with or without the switch, and carries no fragment count', () => {
  const whole = 'Our tutors are industry-experienced and industry-connected, providing learners with hands-on learning.'
  for (const f of [undefined, false, true]) {
    expect(prove(whole, `Home. ${whole} Apply now.`, f)).toEqual({ text: 'A sentence the quote supports.', quote: whole, on_page: true })
  }
  // an ellipsis that is on the page itself is part of a whole quote
  const own = 'Study with us... and graduate ready for work.'
  expect(prove(own, `Home. ${own} Apply.`, false).on_page).toBe(true)
})

test('NEGATIVE: one missing fragment fails the whole quote', () => {
  const frags = providerQuoteFragments(Q.nmit_industry)
  const page = pageOf(frags[0])   // the second fragment is not on the page
  expect(prove(Q.nmit_industry, page, true).on_page).toBe(false)
  const wrongWord = pageOf(Q.nmit_industry).replace('world-ready', 'job-ready')
  expect(prove(Q.nmit_industry, wrongWord, true).on_page).toBe(false)
})

test('NEGATIVE: fragments out of the page order fail', () => {
  expect(prove(Q.nmit_industry, pageOf(Q.nmit_industry, (a) => [...a].reverse()), true).on_page).toBe(false)
  expect(prove(Q.acu_faculties, pageOf(Q.acu_faculties, (a) => [a[1], a[0], a[2], a[3]]), true).on_page).toBe(false)
})

test('NEGATIVE: a fragment shorter than the governed shortest quote fails (the live Auscanus list is made of short course names)', () => {
  expect(providerQuoteFragments(Q.auscanus_list).some((f) => f.replace(/[^A-Za-z0-9]/g, '').length < MIN)).toBe(true)
  expect(prove(Q.auscanus_list, pageOf(Q.auscanus_list), true).on_page).toBe(false)
  // the same ACU quote fails when the governed minimum is raised above its shortest fragment
  expect(prove(Q.acu_faculties, pageOf(Q.acu_faculties), true, 30).on_page).toBe(false)
})

test('NEGATIVE: a trailing or single fragment is not a joined quote; a quote of one passage that is not on the page stays failed', () => {
  const cut = 'Our popular Outdoor Education programmes teach technical, leadership and teamwork skills...'
  expect(prove(cut, 'Home. Our popular Outdoor Education programmes teach technical, leadership and teamwork skills on rivers. Apply.', true).on_page).toBe(false)
  expect(prove('A quote of one passage that is not anywhere on the page at all.', pageOf(Q.nmit_industry), true).on_page).toBe(false)
  // the live Lincoln quote has a fragment that is on a page only if the page carries it exactly; here a changed word fails it
  expect(prove(Q.lincoln_scope, pageOf(Q.lincoln_scope).replace('viticulture', 'viniculture'), true).on_page).toBe(false)
  expect(prove(Q.lincoln_scope, pageOf(Q.lincoln_scope), true).on_page).toBe(true)
})

test('NEGATIVE: each fragment keeps the whole-quote boundary rules (part of a word, a number inside a longer number, case)', () => {
  const q = 'The faculty of health science offers courses... Fees are set at 1200 dollars per unit'
  const part = (p) => prove(q, p, true).on_page
  expect(part('Home. The faculty of health science offers courses. Fees are set at 1200 dollars per unit. End')).toBe(true)
  expect(part('Home. The faculty of health sciences offers courses. Fees are set at 1200 dollars per unit. End')).toBe(false)
  expect(part('Home. The faculty of health science offers courses. Fees are set at 11200 dollars per unit. End')).toBe(false)
  expect(part('Home. The faculty of health science offers courses. Fees are set at 1200 dollars per unit. End'.replace('Fees', 'FEES'))).toBe(false)
})

test('NEGATIVE: arrows or bullets between items are not an ellipsis; the live Danford quote stays quote_not_on_page', () => {
  expect(providerQuoteFragments(Q.danford_arrows)).toHaveLength(1)
  expect(prove(Q.danford_arrows, 'Home. ELICOS and English programs. Vocational programs. Bachelor and master degrees.', true).on_page).toBe(false)
})

test('the sentence text, the quote and the other sentences are passed on unchanged; only on_page (and the count) differ', () => {
  const answer = { about_page: true, sentences: [{ text: 'Whole one.', quote: 'Home. Welcome to our own campus today.' }, { text: ' Joined  one. ', quote: Q.nmit_industry }, { text: 'Missing one.', quote: 'This quote is nowhere on the page given.' }, { text: '', quote: 'dropped, no text' }] }
  const page = `Home. Welcome to our own campus today. ${pageOf(Q.nmit_industry)}`
  const off = providerDescriptionSentences(answer, page, MIN)
  const on = providerDescriptionSentences(answer, page, MIN, { fragments: true })
  expect(off.about_page).toBe(true)
  expect(off.sentences.map((s) => s.on_page)).toEqual([true, false, false])
  expect(on.sentences.map((s) => s.on_page)).toEqual([true, true, false])
  expect(on.sentences.map((s) => s.text)).toEqual(['Whole one.', 'Joined one.', 'Missing one.'])
  expect(on.sentences[1].quote).toBe(Q.nmit_industry)
  expect(on.sentences[1].fragments).toBe(2)
})

test('contract: the worker reads the switch from the worker settings (ships off), is v0.59.14, and adds no operational number', () => {
  const ix = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  const ds = fs.readFileSync('supabase/functions/coverage-sweep/description.ts', 'utf8')
  expect(ix).toMatch(/(?:const WORKER = "coverage-sweep-worker-v0\.59\.14"; |\/\/ was v0\.59\.14 )\/\/ v0\.59\.14 \(9 Nov 2026/)  // later versions keep the note ("was v0.59.14")
  expect(ix.match(/providerDescriptionSentences\(ans\.a, page, minQuote, \{ fragments: Number\(ws\["reading\.provider_quote_fragments_on"\]\) >= 1 \}\)/g)).toHaveLength(2)
  expect(ix).not.toMatch(/providerDescriptionSentences\(ans\.a, page, minQuote\)/)
  // the shortest fragment is the governed shortest quote that already limits a whole quote
  const fn = ds.slice(ds.indexOf('const provedFragments'), ds.indexOf('const sentences = (Array.isArray(a?.sentences)'))
  expect(fn).toContain('flatText(f).length < minQuoteChars')
  expect(fn).toContain('// fixed:')
  expect(ds).toContain('opts.fragments === true')
  // the claim checks and the identity proof are called as before
  expect(ix).toContain('descriptionClaimCheck(ans.a, Number(w.verbatim_span_max_chars))')
  expect(ix).toContain('descriptionSourceIdentity(html, page,')
})
