// Guards: Missing-field enrichment P1 provider descriptions (Platform Admin 2 Nov 2026 10:28)
// "Create or extend the university/provider description reader ... Reuse existing stored evidence before fetching a page ... Use the existing
// AI enrichment mechanism ... Verify that statements are supported by the official source ... Preserve the source URL, evidence ID, source
// timestamp, last verification date and AI extraction metadata ... Detect duplicate or outdated descriptions ... Submit proposed descriptions
// through the appropriate existing admission and review controls ... Publish only approved values. Do not invent rankings, facilities,
// employment outcomes, accreditations or other claims." (admin docs/platform/nz-enrichment-brief/2026-11-02-missing-field-enrichment-mandate.md)
// The behaviour runs on isolated fixtures by tests/fixtures/p1-provider-descriptions/run.sh (scratch PostgreSQL; the five live functions the
// migration edits are loaded from their live text and checked against the live md5s); this spec holds the contract, the worker's pure
// functions and the fixture coverage.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { centralCandidates, weakKinds } from '../../supabase/functions/coverage-sweep/central.ts'
import { lengthNote, aboutPageCheck, aboutLinks, descriptionAnswer, descriptionRequest, descriptionSentences, ownHost, DESCRIPTION_SYSTEM } from '../../supabase/functions/coverage-sweep/description.ts'

const MIG = 'supabase/migrations/20261102090000_cf247_p1_provider_descriptions.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const FX = 'tests/fixtures/p1-provider-descriptions'
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const fn = (name) => { const a = m.indexOf(`create or replace function ${name}(`); expect(a, name).toBeGreaterThan(-1); return m.slice(a, m.indexOf('$function$;', a)) }
const edit = (sig) => { const a = m.indexOf(`select pg_temp.edit_once('${sig}'`); expect(a, sig).toBeGreaterThan(-1); return m.slice(a, m.indexOf(']]', a)) }

const MD5 = {
  'security.layer4_review_decide_impl(uuid,text,text,jsonb)': ['67966cebe3184b9acad1a3451fd0021b', '073889b7c5319019b25212ce08705a37'],
  'security.ai_spend_today_v1()': ['0b79a7f732669ee4c59a260e26188d5a', '0a8e30c2d38c37071474fdd23fa31cfc'],
  'l4_api.layer4_review_bulk_decide(text,text,text,text,text,text,integer)': ['512226a0d25891c137195bde221d40b4', 'dbee9ff4d7a1b29b6c45770c0c669428'],
  'security.layer4_batch_decide_v1_impl(uuid[],text,text,text,text)': ['d3135163affa549deca5d2454133b188', '4501ca1a69a9cd17bb805e403940e5f0'],
  'security.layer4_inbox_kinds_v1()': ['629fcbda204cd79fdba97a096a6dc26b', 'f5fc812e0971a415b664926ec5dbdf8c'],
  'security.layer4_inbox_items_v1()': ['c1a133c3260c3c160397151bd0664957', 'c31b009df674a4a6ff531f00b99a9a45'],
  'public.admin_layer4_inbox(text,jsonb)': ['417f181d12155f79f68c1e70c27a1892', 'f1f0d760b682d6d132af0e8b55151292'],
}

test('live functions are edited only from their live md5 and checked after; the fixture run loads them from their live text', () => {
  for (const [sig, [b, a]] of Object.entries(MD5)) {
    const e = edit(sig)
    expect(e).toContain(`'${b}'`)
    expect(e).toContain(`'${a}'`)
    expect(m).toContain(`${b} -> ${a}`)
    expect(run).toContain(b)
  }
  expect(code).toContain("if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;")
  expect(code).toContain("raise exception '% after the edit has md5 %, expected %'")
  expect(run).toContain("grep -c 'already applied' | grep -qx 7")
  expect(m).toMatch(/^-- Replaces: security\.layer4_review_decide_impl, security\.layer4_inbox_kinds_v1, security\.layer4_inbox_items_v1, public\.admin_layer4_inbox, security\.ai_spend_today_v1, l4_api\.layer4_review_bulk_decide, security\.layer4_batch_decide_v1_impl/m)
  expect(m).toMatch(/^-- Retires: nothing$/m)
})

test('the consumer API is not touched: the description already projected is filled as a value, only on admission', () => {
  expect(code).not.toMatch(/create or replace function (public\.website_v2_|public\.website_edge_|public\.website_api_v2_|public\.zoho_edge_|api\.)|alter table catalogue\.providers|edit_once\('public\.website_v2_/)
  // the only writer of catalogue.providers.description is the Layer 4 apply function
  const writes = [...code.matchAll(/update catalogue\.providers set description/g)]
  expect(writes.length).toBe(1)
  const apply = fn('security.layer4_provider_description_apply_impl')
  expect(apply).toContain('update catalogue.providers set description = v_text, updated_at = now() where id = i.entity_id;')
  expect(apply).toContain("if p_value is distinct from i.proposed_value then raise exception 'a description is approved as read")
  expect(apply).toContain("l.field in ('description', 'p_description', 'all')")
  expect(apply).toContain('if v_now is distinct from nullif(btrim(i.before_value->>\'description\'), \'\') then')
  expect(apply).toContain("v_pub := public.website_v2_provider(v_key);")  // verify publication
  expect(fn('public.svc_provider_description_record')).not.toMatch(/update catalogue\./)
})

test('Layer 4: its own kind, admitted by a person only through the live decide; no auto-admission', () => {
  const d = edit('security.layer4_review_decide_impl(uuid,text,text,jsonb)')
  expect(d).toContain("elsif v_item.entity_type='provider' and v_item.field_code='provider_description' then")
  expect(d).toContain('v_scalar:=security.layer4_provider_description_apply_impl(v_actor,v_item.id,v_final,trim(p_reason));')
  const rec = fn('public.svc_provider_description_record')
  expect(rec).toContain("values ('provider', r.provider_id, 'provider_description', r.evidence_id,")
  expect(rec).toContain("'pending', 'Provider description read from the official page")
  expect(code.replace(/\$[on]\$[\s\S]*?\$[on]\$/g, '')).not.toMatch(/layer4_review_decide(_impl)?\((?!uuid,)/)  // nothing decides by itself (only the Inbox edit calls the decide)
  expect(code).not.toMatch(/status\s*=\s*'approved'/)
  expect(m).toContain('create or replace trigger layer4_review_items_provider_description after update of status on pipeline.layer4_review_items')
  expect(edit('security.layer4_inbox_kinds_v1()')).toContain('"provider_description": {"label": "University description"')
  expect(edit('security.layer4_inbox_items_v1()')).toContain("then 'provider_description'")
  expect(edit('public.admin_layer4_inbox(text,jsonb)')).toContain("elsif v_kind = 'provider_description' then")
})

test('validation: host, about page, quotes, support, marketing words, claims, length, age, duplicates; every rule a setting (G2)', () => {
  const v = fn('security.provider_description_validate_v1')
  for (const r of ['wrong_host', 'not_stated', 'sentence_count', 'quote_not_on_page', 'unsupported_marketing', 'unsupported_claim', 'unsupported_sentence', 'length',
    'source_outdated', 'duplicate_other_provider', 'same_as_current']) expect(v, r).toContain(`'${r}'`)
  for (const k of ['pdesc.support_min_share', 'pdesc.duplicate_share', 'pdesc.min_sentences', 'pdesc.max_sentences', 'pdesc.min_chars', 'pdesc.max_chars', 'pdesc.source_max_age_days'])
    expect(v).toContain(`security.pipeline_num_v1('${k}', `)
  for (const k of ['pdesc.superlatives', 'pdesc.claim_words']) expect(v).toContain(`security.toolset_setting('pipeline', '${k}')`)
  // the provider's own hosts: the same sources as the E16 course page check
  const h = fn('security.provider_hosts_v1')
  expect(h).toContain("security.toolset_setting('pipeline', 'binding.provider_host_aliases')")
  expect(h).toContain('from pipeline.provider_extra_domains d where d.provider_id = p_provider')
  expect(fn('security.provider_page_host_v1')).toContain("o.lifecycle_status = 'active'")
  for (const k of ['pdesc.enabled', 'pdesc.every_minutes', 'batch.provider_description', 'pdesc.queue_per_run', 'pdesc.countries', 'pdesc.provider_types', 'pdesc.provider_keys',
    'pdesc.tries', 'pdesc.retry_minutes', 'pdesc.recheck_days', 'pdesc.pending_max', 'pdesc.page_chars', 'pdesc.min_quote_chars', 'pdesc.min_sentences', 'pdesc.max_sentences',
    'pdesc.min_chars', 'pdesc.max_chars', 'pdesc.support_min_share', 'pdesc.duplicate_share', 'pdesc.source_max_age_days', 'pdesc.about_patterns', 'pdesc.superlatives',
    'pdesc.claim_words', 'reading.answer_tokens.provider_description'])
    expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace(/\./g, '\\.')}', '[^']+',\\s+'`))
  expect(m).toMatch(/\('openrouter', 'guard_provider_description', 'Daily guard: provider descriptions with AI',/)
})

test('the job: catalogued, off by default, no number in its command, bounded and guarded', () => {
  expect(m).toMatch(/\('pipeline', 'pdesc\.enabled', [^\n]*\n[^\n]*\n  'number', '0'::jsonb, 0, 1, 'on\/off'/)
  // acquisition off until the pilot cost is approved (decision pack 2 Nov 2026 10:56, Decision 7)
  for (const k of ['pdesc.acquire_direct', 'pdesc.acquire_firecrawl']) expect(m).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}', [^\\n]*\\n[^\\n]*\\n  'number', '0'::jsonb, 0, 1, 'on/off'`))
  expect(fn('public.svc_provider_description_next')).toContain("and (security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 or security.provider_description_stored_v1(r.provider_id) is not null)")
  expect(m).toContain("perform cron.schedule('provider-description-read', '6,16,26,56 * * * *', $j$select security.provider_description_fire_v1()$j$);")
  expect(m).toContain("perform cron.alter_job((select jobid from cron.job where jobname = 'provider-description-read'), active := false);")
  expect(m).toContain(" ('provider-description-read', 'Course pages', 38, 'Provider descriptions: find, read and propose',")
  const f = fn('security.provider_description_fire_v1')
  expect(f).toContain("if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;")
  expect(f).toContain("if not security.ai_use_allowed_v1('provider_description') then")
  expect(f).toContain("security.pipeline_num_v1('pdesc.pending_max', 10)")
  expect(f).toContain("make_interval(mins => security.pipeline_num_v1('pdesc.every_minutes', 60)::int)")
  expect(f).toContain("'limit', security.pipeline_num_v1('batch.provider_description', 3)::int")
  expect(f).toContain('-- fixed: fire guard')
  const n = fn('public.svc_provider_description_next')
  expect(n).toContain('-- fixed: claim timer')
  expect(n).toContain("select c.model_identifier into v_model from pipeline.central_ai_settings c where c.id = 1;")  // the pinned Enrich fields model
  expect(edit('security.ai_spend_today_v1()')).toContain("('provider_description', 'Provider descriptions with AI', 8)")
  // the shared AI rule and ledger of v2.15.404: one rule, no separate count
  expect(m).toContain("create or replace trigger ai_spend_capture after insert or update of cost_usd on pipeline.provider_description_reads\n  for each row execute function security.ai_spend_capture_v1('provider_description', 'delta', '{cost_usd}');")
  expect(n).toContain("if not security.ai_use_allowed_v1('provider_description') then return jsonb_build_object('idle', true, 'reason', 'ai_refused'")
  expect(n).toContain("from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening'")
  // generic bulk and batch decide skip descriptions (Platform Admin 2 Nov 2026 14:50)
  expect(edit('l4_api.layer4_review_bulk_decide(text,text,text,text,text,text,integer)')).toContain("if p_field_code = 'provider_description' then")
  expect(edit('security.layer4_batch_decide_v1_impl(uuid[],text,text,text,text)')).toContain("if v_field = 'provider_description' then")
})

test('worker v0.57.0: stored copy first, own hosts only, direct before Firecrawl, pinned model, every quote checked; minimal change', () => {
  expect(worker).toMatch(/(const WORKER = "coverage-sweep-worker-v0\.57\.0"; |\/\/ was v0\.57\.0 )\/\/ v0\.57\.0 \(2 Nov 2026, CF-247 missing-field enrichment P1/)  // later versions keep the note
  const a = worker.indexOf('if (mode === "provider_description") {'), b = worker.indexOf('if (mode === "enrich_ai") {')
  expect(a).toBeGreaterThan(0); expect(b).toBeGreaterThan(a)
  const w = worker.slice(a, b)
  expect(w.indexOf('if (it.stored?.storage_path)')).toBeLessThan(w.indexOf('const h = await readPage(home, it);'))
  expect(w).toContain('const g = await useFcWhy("provider_description", it.provider_id, url, true);')  // the existing Firecrawl budget
  expect(w.indexOf('if (!acquireFc) return')).toBeLessThan(w.indexOf('const g = await useFcWhy("provider_description"'))
  expect(w.indexOf('if (fcLeft <= 0) return')).toBeLessThan(w.indexOf('const g = await useFcWhy("provider_description"'))
  expect(w).toContain('for (const o of out) o.fc_reads = fcBy.get(String(o.item_id)) || 0;')
  expect(fn('public.svc_provider_description_next')).toContain("if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then")
  expect(w.indexOf('if (!acquireDirect) {')).toBeLessThan(w.indexOf('const h = await readPage(home, it);'))
  expect(w.indexOf('let target = suggested[0] || "";')).toBeLessThan(w.indexOf('const h = await readPage(home, it);'))
  expect(w).toContain('if (d?.model && !String(d.model).startsWith(model))')  // pinned: no other model's answer
  expect(w).toContain('const ans = descriptionAnswer(d, maxTokens); cost += ans.cost;')
  expect(w).toContain('rpc("svc_provider_description_record", { p_results: noNul(out) })')
  expect(w).not.toMatch(/catalogue\.providers|description:\s*ans/)
  expect(DESCRIPTION_SYSTEM).toContain('Do not state rankings, ratings, awards, facilities, employment or graduate outcomes, accreditations')
  const req = descriptionRequest('openai/gpt-4.1-mini', 'U', 'https://u.edu.au/about', 'text', 1500)
  expect(req.model).toBe('openai/gpt-4.1-mini'); expect(req.provider).toEqual({ require_parameters: true }); expect(req.max_tokens).toBe(1500)
  expect(req.response_format.json_schema.strict).toBe(true)
})

test('the central page finder suggests About pages from the whole-site map only (no extra targeted map)', () => {
  const links = [{ url: 'https://www.alpha.edu.au/about' }, { url: 'https://www.alpha.edu.au/international/about-us' }, { url: 'https://www.alpha.edu.au/news/about-our-new-library' },
    { url: 'https://www.alpha.edu.au/about-the-university/overview', title: 'About the University' }, { url: 'https://www.other.edu.au/about' }, { url: 'https://www.alpha.edu.au/study/fees' }]
  const about = centralCandidates(links, 'www.alpha.edu.au').filter((c) => c.kind === 'about_page').map((c) => c.url)
  expect(about).toEqual(['https://www.alpha.edu.au/about', 'https://www.alpha.edu.au/about-the-university/overview'])
  expect(weakKinds([])).not.toContain('about_page')
  expect(weakKinds([])).not.toContain('entry_requirements')
})

// Pilot finding (2 Nov 2026 16:16, v2.15.406): Monash read a stored Pharmacy news article, ACU a research page on a staff subdomain, CDU the
// right page. One page rule decides every source (security.provider_description_page_v1; the worker's aboutPageCheck), with its lists as settings.
const PILOT = 'supabase/migrations/20261102130000_cf247_pdesc_page_choice.sql'
test('page rule (pilot 2 Nov 2026 16:16): only the provider\'s own About or Overview page; news, research and staff pages refused', () => {
  const p = fs.readFileSync(PILOT, 'utf8')
  const rule = { about_prefixes: ['about-', 'about_'], refused_path_words: ['news', 'events', 'media', 'research', 'staff', 'faculty', 'school', 'study'],
    refused_host_labels: ['staff', 'intranet', 'news'], about_max_segments: 2 }
  const hosts = ['monash.edu.au', 'monash.edu'], pats = ['about', 'about-us', 'our-university', 'who-we-are', 'overview']
  expect(aboutPageCheck('https://www.monash.edu/pharm/about/news/2025/new-dean', hosts, pats, rule).rule).toBe('refused_word')
  expect(aboutPageCheck('https://staff.acu.edu.au/our_university/research', ['acu.edu.au'], pats, rule).rule).toBe('refused_host')
  expect(aboutPageCheck('https://www.acu.edu.au/our_university/research', ['acu.edu.au'], pats, rule).rule).toBe('refused_word')
  expect(aboutPageCheck('https://www.cdu.edu.au/about-cdu', ['cdu.edu.au'], pats, rule)).toEqual({ ok: true, rule: 'about_page', main: true })
  expect(aboutPageCheck('https://www.monash.edu/about', hosts, pats, rule)).toEqual({ ok: true, rule: 'about_page', main: true })
  expect(aboutPageCheck('https://www.uq.edu.au/en/about/overview/history', ['uq.edu.au'], pats, rule).rule).toBe('not_about_page')
  const html = '<a href="https://staff.acu.edu.au/our_university/research">Our university</a><a href="/news/about-our-new-library">x</a><a href="/about-acu">About ACU</a>'
  expect(aboutLinks(html, 'https://www.acu.edu.au/', ['acu.edu.au'], pats, rule).map((l) => l.url)).toEqual(['https://www.acu.edu.au/about-acu'])
  // the database rule: settings, used for stored copies, suggestions and the validation
  const f = p.slice(p.indexOf('create or replace function security.provider_description_page_v1('), p.indexOf('$function$;', p.indexOf('create or replace function security.provider_description_page_v1(')))
  for (const k of ['pdesc.refused_host_labels', 'pdesc.refused_path_words', 'pdesc.about_patterns', 'pdesc.about_prefixes']) expect(f).toContain(`security.toolset_setting('pipeline', '${k}')`)
  expect(f).toContain("security.pipeline_num_v1('pdesc.about_max_segments', 2)")
  for (const k of ['pdesc.about_prefixes', 'pdesc.refused_path_words', 'pdesc.refused_host_labels', 'pdesc.about_max_segments']) expect(p).toMatch(new RegExp(`\\('pipeline', '${k.replace('.', '\\.')}', '[^']+',\\s+'`))
  expect(p).toContain("and (security.provider_description_page_v1(p_provider, a.source_url)->>'ok')::boolean")
  expect(p).toContain("and (security.provider_description_page_v1(u.provider_id, e->>'url')->>'ok')::boolean) z")
  expect(p).toContain("if not (security.provider_description_page_v1(p_provider, p_url)->>'ok')::boolean then")
  for (const [b, a] of [['d9f9244ea3dd37c511b0ff75f04d5e30', '6ddc25869e9865c9aeebf11c819feee2'], ['d4fd17854056f1ad69c0d1dc0e0abf11', '33d735da514a7d37e2815bbb0073af03'],
    ['9a3fbd7f15f5cf30d1a13359d6062280', '528d5a3d2e3780fcb58e2c19db31c199']]) { expect(p).toContain(`'${b}', '${a}'`); expect(run).toContain(b) }
  expect(p).toMatch(/^-- Replaces: .+/m); expect(p).toMatch(/^-- Retires: .+/m)
  expect(p).not.toMatch(/cron\.alter_job|cron\.schedule/)  // nothing switched on
  // no existing setting value is changed: pdesc.max_chars 1,200 is a proposal held for the Platform Admin (direction 2 Nov 2026 23:24 §1 "prepare")
  expect(p).not.toMatch(/update pipeline\.platform_toolset_settings set/)
  expect(p).not.toMatch(/to_jsonb\(1200\)/)
  // a fragment is held, never cut or completed
  expect(p).toContain("'rule', 'incomplete_sentence'")
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.58\.0"; \/\/ v0\.58\.0 \(2 Nov 2026, CF-247 P1 pilot finding 16:16\)/)
  expect(worker).toContain('const suggested: string[] = (it.candidates || []).map(String).filter((u: string) => aboutPageCheck(u, hosts, patterns, pageRule).ok);')
  expect(worker).toContain('const links = aboutLinks(h.html, h.url || home, hosts, patterns, pageRule);')
  expect(fixtures).toContain("raise notice 'PASS page rule: Monash news copy, ACU staff research page refused; CDU about page allowed; lists are settings';")
  expect(fixtures).toContain("raise notice 'PASS length 1,200: CDU 916 characters pass whole to the projection; 1,250 held; cut sentence or condition held, never truncated';")
  // the model is told the limits the validation applies (CDU was held at 916 characters against pdesc.max_chars 900, never stated to it)
  expect(p).toContain("'max_chars', security.pipeline_num_v1('pdesc.max_chars', 900)::int)")
  expect(lengthNote({ min_sentences: 2, max_sentences: 5, min_chars: 150, max_chars: 900 })).toBe('Length: 2 to 5 sentences, 150 to 900 characters in all (the sentences, not the quotes).\n')
  expect(lengthNote(null)).toBe('')
  expect(worker).toContain('descriptionRequest(model, String(it.provider || ""), String(rec.url || ""), page, maxTokens, w.length)')
})

test('nothing cuts a description (Platform Admin 2 Nov 2026 23:24): the worker keeps every sentence and quote whole', () => {
  const long = 'Zeta University '.repeat(60).trim() + '.'  // about 960 characters in one sentence
  const many = Array.from({ length: 14 }, (_, k) => ({ text: `Sentence ${k + 1} of the page.`, quote: `Sentence ${k + 1} of the page.` }))
  const page = long + ' ' + many.map((x) => x.text).join(' ')
  const r = descriptionSentences({ about_page: true, sentences: [{ text: long, quote: long }, ...many] }, page, 20)
  expect(r.sentences[0].text).toBe(long); expect(r.sentences[0].quote).toBe(long)  // was cut at 600 characters
  expect(r.sentences.length).toBe(15)  // was cut at 12: the database holds too many sentences (sentence_count), never a shortened list
  const d = fs.readFileSync('supabase/functions/coverage-sweep/description.ts', 'utf8')
  expect(d).not.toMatch(/\.slice\(0, (600|12)\)/)
})

test('pure functions: About link discovery on own hosts, quotes checked against the page, cut answers held', () => {
  const html = '<nav><a href="/study">Study</a><a href="/about">About us</a><a href="https://other.edu.au/about">About</a><a href="https://news.alpha.edu.au/about-us/overview">x</a></nav>'
  const links = aboutLinks(html, 'https://www.alpha.edu.au/', ['alpha.edu.au'], ['about', 'about-us', 'overview'])
  expect(links.map((l) => l.url)).toEqual(['https://www.alpha.edu.au/about', 'https://news.alpha.edu.au/about-us/overview'])
  expect(ownHost('www.alpha.edu.au', ['alpha.edu.au'])).toBe(true)
  expect(ownHost('alpha.edu.au.evil.com', ['alpha.edu.au'])).toBe(false)
  const page = 'The University of Alpha is a public university founded in 1911 in Perth. We teach health and law.'
  const s = descriptionSentences({ about_page: true, sentences: [
    { text: 'Alpha is a public university in Perth founded in 1911.', quote: 'The University of Alpha is a public university founded in 1911 in Perth.' },
    { text: 'It is ranked first in Australia.', quote: 'Alpha is ranked first in Australia.' }] }, page, 20)
  expect(s.sentences.map((x) => x.on_page)).toEqual([true, false])
  expect(descriptionAnswer({ choices: [{ finish_reason: 'length', message: { content: '{"about' } }], usage: { cost: 0.001 } }, 1500))
    .toEqual({ ok: false, cost: 0.001, error: 'held_partial: output_truncated: provider_description reached reading.answer_tokens.provider_description (1500)' })
  expect(descriptionAnswer({ choices: [{ message: { content: '{"about_page":false,"sentences":[]}' } }] }, 1500)).toEqual({ ok: true, a: { about_page: false, sentences: [] }, cost: 0 })
})

test('screens: the Inbox shows the description with its quotes; Coverage shows the metrics and the dead-letter retry', () => {
  const inbox = fs.readFileSync('src/Layer4Inbox.jsx', 'utf8'), cov = fs.readFileSync('src/FieldCoverage.jsx', 'utf8')
  expect(inbox).toContain("{it.kind==='provider_description'&&<div className=\"l4i-dl\" data-l4-description>")
  expect(cov).toContain("supabase.rpc('admin_provider_descriptions',{p_action:'metrics'")
  expect(cov).toContain('<ProviderDescriptions country={country} rank={rank} onError={onError}/>')
  const a = fn('public.admin_provider_descriptions')
  for (const k of ['eligible', 'present', 'missing', 'proposed', 'held', 'admitted', 'dead_letter', 'stored_pages_available', 'pages_acquired', 'ai_reads', 'cost_usd',
    'cost_per_admitted_usd', 'rejections', 'layer4_pending', 'last_run', 'backlog', 'by_country', 'providers']) expect(a, k).toContain(`'${k}'`)
  expect(a).toContain("if v_rank < 5 then raise exception 'PIM Admin role required'")
})

test('the fixtures cover stored copy reuse, unsupported claims, wrong host, duplicates, Layer 4 without auto-admission, admitted-only projection, off by default, batch and retry bounds', () => {
  for (const p of ['PASS job off by default', 'PASS scope and bounded queue (type, country, unpublished, locked, one open read a provider)',
    'PASS stored copy reuse (own host, About page, set age; provenance kept); acquisition off by default; About suggestions', 'PASS proposal into Layer 4 without auto-admission',
    'PASS unsupported claim, marketing word, unsupported sentence and missing quote held', 'PASS wrong-host page refused', 'PASS duplicate and outdated detection',
    'PASS batch and retry bounds (lease cap, Layer 4 cap, retry wait, tries, dead letter, recovery)', 'PASS fire: once a run interval, batch from its setting',
    'PASS admission by a person only; projection shows only admitted values', 'PASS rejected proposal never published; acquired page registered as evidence',
    'PASS AI daily guard (guard_provider_description)', 'PASS pilot ceilings (AI spend, Firecrawl reads)', 'PASS shared AI ledger counts the reader; bulk and batch decide skip descriptions', 'PASS Layer 4 Inbox: its own kind and choices',
    'PASS metrics (eligible published providers, present, missing, proposed, held, admitted, cost)', 'PASS privileges'])
    expect(fixtures).toContain(`raise notice '${p}';`)
  expect(run).toContain('createdb "$DB"'); expect(run).not.toMatch(/supabase\.co|fxcwkweaxjtknorudmwp/)
})
