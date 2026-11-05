// Guards: Provider Description autonomy mandate (4 Nov 2026): exact current institution, final official source, factual support and evidence preservation before Layer 4.
import { test, expect } from '@playwright/test'
import { aboutPageCheck, descriptionClaimCheck, descriptionCostQuote, descriptionPageText, descriptionRequest, providerDescriptionSentences, descriptionSentences, descriptionSourceIdentity } from '../../supabase/functions/coverage-sweep/description.ts'

test('current full names prove a source; a bare shared name never substitutes a college for its university', () => {
  const html = '<title>About | Riverstone University</title><h1>About our university</h1><main>Riverstone University teaches health, science and law.</main>'
  expect(descriptionSourceIdentity(html, descriptionPageText(html, 16000), ['The Riverstone University', 'Riverstone University']).ok).toBe(true)
  const college = '<title>Riverstone College | Riverstone University</title><h1>Riverstone College</h1><main>Riverstone College is a partner of Riverstone University.</main>'
  expect(descriptionSourceIdentity(college, descriptionPageText(college, 16000), ['Riverstone University'])).toEqual({ ok: false, rule: 'provider_name_conflict' })
  expect(descriptionSourceIdentity(college, descriptionPageText(college, 16000), ['Riverstone'])).toEqual({ ok: false, rule: 'provider_name_not_proved' })
})

test('a historic identity or offshore college heading is held even when the requested university is mentioned', () => {
  for (const subject of ['Former Riverstone College', 'Closed Riverstone College', 'Riverstone Offshore College']) {
    const html = `<title>${subject}</title><h1>${subject}</h1><main>Riverstone University was the former institutional identity.</main>`
    expect(descriptionSourceIdentity(html, descriptionPageText(html, 16000), ['Riverstone University'])).toEqual({ ok: false, rule: 'provider_name_conflict' })
  }
  const offshore = '<title>Riverstone University</title><h1>Riverstone University Malaysia</h1><main>Riverstone University is named on this branch website.</main>'
  expect(descriptionSourceIdentity(offshore, descriptionPageText(offshore, 16000), ['Riverstone University'])).toEqual({ ok: false, rule: 'provider_name_conflict' })
  const offshoreTitle = '<title>Monash University Malaysia | About</title><main><h1>About Malaysia</h1><p>Monash University is an institution based in Australia. Monash University Malaysia provides education at its Malaysian location.</p></main>'
  expect(descriptionSourceIdentity(offshoreTitle, descriptionPageText(offshoreTitle, 16000), ['Monash University'])).toEqual({ ok: false, rule: 'provider_name_conflict' })
  const genericH1 = '<title>About | Monash University</title><h1>About Monash</h1><main>Monash University teaches science and health.</main>'
  expect(descriptionSourceIdentity(genericH1, descriptionPageText(genericH1, 16000), ['Monash University']).ok).toBe(true)
  const specificH1 = '<title>Riverstone University | Prepare for tomorrow</title><h1>Riverstone University</h1><main>Riverstone University teaches science and health.</main>'
  expect(descriptionSourceIdentity(specificH1, descriptionPageText(specificH1, 16000), ['Riverstone University']).ok).toBe(true)
  for (const subject of ['Riverstone University Singapore campus', 'School of Science']) {
    const html = `<title>Riverstone University</title><h1>${subject}</h1><main>Riverstone University teaches science.</main>`
    expect(descriptionSourceIdentity(html, descriptionPageText(html, 16000), ['Riverstone University'])).toEqual({ ok: false, rule: 'provider_subunit_source' })
  }
  const html = '<title>About Te Whare Wānanga o Āwhina</title><main>Te Whare Wānanga o Āwhina is a university.</main>'
  expect(descriptionSourceIdentity(html, descriptionPageText(html, 16000), ['Te Whare Wananga o Awhina']).ok).toBe(true)
})

test('the final redirect must still be an approved official institutional page', () => {
  const allowed = ['riverstone.example'], patterns = ['about', 'overview'], rules = { about_max_segments: 2, refused_path_words: ['news'], refused_host_labels: ['staff'] }
  expect(aboutPageCheck('https://riverstone.example/about', allowed, patterns, rules).ok).toBe(true)
  for (const finalUrl of ['https://other-provider.example/about', 'https://riverstone.example/news/about', 'https://staff.riverstone.example/about', 'https://riverstone.example/study/overview']) {
    expect(aboutPageCheck(finalUrl, allowed, patterns, rules).ok).toBe(false)
  }
})

test('numerical facts require their own quote and an unsupported answer keeps whole text and evidence', () => {
  const page = 'Riverstone University was established in 1912. It has 2 campuses and teaches science.'
  const answer = { about_page: true, sentences: [{ text: 'Riverstone University was established in 1912.', quote: 'Riverstone University was established in 1912.' }, { text: 'It has 20 campuses and teaches science.', quote: 'It has 2 campuses and teaches science.' }] }
  expect(descriptionClaimCheck(answer)).toEqual({ ok: false, rule: 'unsupported_numeric_claim', reason: 'A numerical fact is absent from its supporting quote.' })
  const preserved = providerDescriptionSentences(answer, page)
  expect(preserved.sentences[1]).toEqual({ ...answer.sentences[1], on_page: true })
  expect(descriptionClaimCheck({ sentences: [{ text: 'It has 2 campuses.', quote: 'It has 2 campuses and teaches science.' }] })).toEqual({ ok: true })
  expect(descriptionClaimCheck({ sentences: [{ text: 'It has 20% of enrolments.', quote: 'It has 20 enrolments.' }] }).ok).toBe(false)
  expect(descriptionClaimCheck({ sentences: 'invalid model output' }).rule).toBe('invalid_answer')
  expect(providerDescriptionSentences({ sentences: 'invalid model output' }, page).sentences).toEqual([])
  const decimalPage = 'Riverstone University reports 1.2% growth in enrolments, with fees of -$1,200 under the stated adjustment.'
  for (const fakeQuote of ['Riverstone University reports 12% growth in enrolments.', 'Riverstone University reports 1.2 growth in enrolments.', 'with fees of $1,200 under the stated adjustment.']) {
    const contaminated = providerDescriptionSentences({ sentences: [{ text: fakeQuote, quote: fakeQuote }] }, decimalPage)
    expect(contaminated.sentences[0].on_page).toBe(false)
  }
  const rawQuote = '  Riverstone\tUniversity reports\n1.2% growth in enrolments,  '
  const normalized = providerDescriptionSentences({ sentences: [{ text: 'Riverstone University reports enrolment growth.', quote: rawQuote }] }, decimalPage)
  expect(normalized.sentences[0].on_page).toBe(true)
  expect(normalized.sentences[0].quote).toBe(rawQuote)
  expect(providerDescriptionSentences({ sentences: [{ text: 'A university.', quote: 'L’universite\u0301 Riverstone teaches science.' }] }, 'L’université Riverstone teaches science.').sentences[0].on_page).toBe(true)
  expect(providerDescriptionSentences({ sentences: [{ text: 'An unsupported percentage.', quote: '2% growth in enrolments across the institution.' }] }, '12% growth in enrolments across the institution.').sentences[0].on_page).toBe(false)
  expect(providerDescriptionSentences({ sentences: [{ text: 'An unsupported decimal percentage.', quote: '2% growth in enrolments across the institution.' }] }, '1.2% growth in enrolments across the institution.').sentences[0].on_page).toBe(false)
})

test('a conservative quote requires the exact approved model and complete non-negative pricing', () => {
  const request = descriptionRequest('approved-model', 'Riverstone University', 'https://riverstone.example/about', 'Official institutional source text.', 1500)
  const models = { data: [{ id: 'approved-model', pricing: { prompt: '0.0000004', completion: '0.0000016', request: '0', input_cache_read: '0.0000001' } }] }
  const quote = descriptionCostQuote(request, models)
  expect(quote.ok).toBe(true)
  expect(quote.input_tokens_bound).toBeGreaterThan(new TextEncoder().encode(JSON.stringify(request)).length)
  expect(quote.output_tokens_bound).toBe(1500)
  expect(quote.provider_max_price).toEqual({ prompt: 0.4, completion: 1.6, request: 0 })
  expect(quote.max_cost_usd).toBeGreaterThanOrEqual(quote.input_tokens_bound * 0.0000005 + 1500 * 0.0000016)
  expect(descriptionCostQuote({ ...request, model: 'unapproved-similar-model' }, models).ok).toBe(false)
  expect(descriptionCostQuote(request, null).ok).toBe(false)
  for (const pricing of [{ prompt: '-1', completion: '0' }, { prompt: '', completion: '0' }, { prompt: '0' }, { prompt: '0', completion: '0', future_unknown_charge: '1' }]) {
    expect(descriptionCostQuote(request, { data: [{ id: 'approved-model', pricing }] }).ok).toBe(false)
  }
})

test('long copied official spans are held without truncating the answer or its evidence', () => {
  const passage = 'Riverstone University provides a comprehensive range of undergraduate and postgraduate programmes across science, health, education and professional disciplines for students from Australia and overseas.'
  const copied = { about_page: true, sentences: [{ text: passage, quote: passage }] }
  expect(descriptionClaimCheck(copied, 120).rule).toBe('verbatim_passage')
  expect(providerDescriptionSentences(copied, passage).sentences[0].text).toBe(passage)
  expect(descriptionClaimCheck({ sentences: [{ text: 'Riverstone University teaches science and health.', quote: passage }] }, 120)).toEqual({ ok: true })
  expect(descriptionClaimCheck(copied, NaN).rule).toBe('invalid_verbatim_limit')
  expect(descriptionClaimCheck({ sentences: [{ text: 'a'.repeat(120), quote: 'a'.repeat(120) }] }, 120).rule).toBe('verbatim_passage')
  expect(descriptionClaimCheck({ sentences: [{ text: 'a'.repeat(119), quote: 'a'.repeat(119) }] }, 120).ok).toBe(true)
  expect(descriptionClaimCheck({ sentences: [{ text: 'Riverstone College is the current institution.', quote: 'Riverstone College became Current University in 2020.' }] }, 120).rule).toBe('historic_claim_context')
  expect(descriptionClaimCheck({ sentences: [{ text: 'Current University was formerly named Former College.', quote: 'Current University was formerly named Former College.' }] }, 120).ok).toBe(true)
})

test('the course-description reader keeps its shared quote matching; only provider descriptions use the exact-source match', () => {
  const page = 'Riverstone University — Bachelor of Science. Students study chemistry, physics and biology across three years.'
  const quote = 'students study Chemistry physics and biology across three years'
  // course-text.ts uses descriptionSentences: letters and digits only, case and punctuation ignored (unchanged from main)
  expect(descriptionSentences({ sentences: [{ text: 'Students study three sciences.', quote }] }, page, 20).sentences[0].on_page).toBe(true)
  // provider descriptions: case and punctuation remain evidence
  expect(providerDescriptionSentences({ sentences: [{ text: 'Students study three sciences.', quote }] }, page, 20).sentences[0].on_page).toBe(false)
})
