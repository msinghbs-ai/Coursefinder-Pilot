// Guards: Decision 278 (Platform Admin 14 Nov 2026 16:10) pre-AI admission gate pre-ai-admission-v1 ships in shadow: D1 manifest checked on the stored copy's bytes, D2 scholarship score measured only, linked page in the fingerprint, admission.gate_on = 0
// CF-247 S543. Design: admin docs/audits/studysearch-pre-ai-admission-gate-design.md (D1-D4, section 9). Worker coverage-sweep v0.95.0, module
// supabase/functions/coverage-sweep/admission-gate.ts; migration 20261114091500_cf247_pre_ai_admission_shadow.sql; harness scripts/admission-harness.mjs.
// Storage housekeeping in the same bundle: migration 20261114093000_cf247_adapter_captures_bucket_hardening.sql.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { gzipSync } from 'node:zlib'
import * as G from '../../supabase/functions/coverage-sweep/admission-gate.ts'

const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261114091500_cf247_pre_ai_admission_shadow.sql', 'utf8')
const BUCKET = fs.readFileSync('supabase/migrations/20261114093000_cf247_adapter_captures_bucket_hardening.sql', 'utf8')
const sha = (b) => createHash('sha256').update(b).digest('hex')
const page = (title, body) => `<!doctype html><html><head><title>${title}</title></head><body><nav>Home</nav><main><h1>${title}</h1>${body}</main><footer>Privacy</footer></body></html>`
const para = (s, n = 1) => `<p>${s}</p>`.repeat(n)
const award = page('Global Excellence Scholarship | Example University',
  para('The Global Excellence Scholarship offers a 25% reduction in tuition fees for international students commencing a coursework degree.') +
  '<h2>Eligibility</h2>' + para('Applicants must be international students holding an offer for full-time study.') +
  '<h2>How to apply</h2>' + para('You are automatically considered when you apply for admission. Applications close 30 November.'))
const news = page('Campus news | Example University', para('Our rowing team won the regional regatta this weekend and the library opens late during exams.', 8))
const base = { url: 'https://example.edu/scholarships/global', prompt_key: 'p', model: 'm', schema_key: 's' }

test('the harness self-test passes: every reason, enforcement per reason, parks, D2, linked-page fingerprint, byte hashing', () => {
  const out = execFileSync(process.execPath, ['--experimental-strip-types', '--no-warnings', 'scripts/admission-harness.mjs', '--self-test'], { encoding: 'utf8' })
  expect(out).not.toContain('FAIL')
  expect(out).toMatch(/\nall (\d+) checks passed\n?$/)
  expect(Number(out.match(/all (\d+) checks passed/)[1])).toBeGreaterThanOrEqual(21)
})

test('D1: the manifest is the record, checked on the bytes of the stored copy; each storage-contract problem is named', async () => {
  const html = page('Bourse d\'excellence — 奨学金', para('Une réduction de 25 % des frais — 留学生向け奨学金。', 4))
  const bytes = new Uint8Array(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(html, 'utf8')]))  // byte-order mark + multi-byte text
  const h = sha(bytes)
  const m = { evidence_id: null, bucket: 'evidence', storage_path: `layer2/AU/scholarships/p/ai/1/${h}.html.gz`, container: 'gzip', content_mime: 'text/html',
    content_sha256: h, stored_bytes: 10, source_url: 'https://example.edu/x', page_status: 200, captured_at: '2026-11-14T00:00:00Z' }
  // the copy is opened as bytes, hashed, then decoded exactly as the worker's storedHtml decodes it (Response.text())
  const gz = new Uint8Array(gzipSync(bytes))
  const opened = await G.openCopy(gz, 'gzip')
  expect(opened.sha256).toBe(h)
  expect(opened.text).toBe(await new Response(new Blob([gz]).stream().pipeThrough(new DecompressionStream('gzip'))).text())
  expect(opened.stored_bytes).toBe(gz.length)
  expect(await G.contentSha256(bytes)).toBe(h)
  // over the bytes: intact. Over decoded-then-encoded text: a false mismatch (why the hash is never taken from text)
  expect(await G.verifyManifest(m, opened.bytes)).toEqual({ ok: true, problems: [], warnings: [] })
  expect(G.checkManifest(m, sha(Buffer.from(opened.text, 'utf8'))).problems).toContain('hash_mismatch')
  // each problem, one at a time
  const p = (x, computed = h, opt) => G.checkManifest({ ...m, ...x }, computed, opt).problems
  expect(p({ captured_at: undefined })).toEqual(['missing_field'])
  expect(p({ stored_bytes: 0 })).toEqual(['zero_bytes'])
  expect(p({ content_sha256: 'XYZ' }, null)).toEqual(['hash_format', 'path_hash_disagrees'])
  expect(p({}, 'not-a-hash')).toContain('hash_format')
  expect(p({}, '0'.repeat(64))).toEqual(['hash_mismatch'])
  expect(p({ storage_path: `layer2/AU/x/${'1'.repeat(64)}.html.gz` })).toEqual(['path_hash_disagrees'])
  expect(p({ page_status: 404 })).toEqual(['page_not_ok'])
  expect(p({ content_mime: 'image/png' })).toEqual(['content_mime_unknown'])
  expect(p({ sidecar: { converter: 'lean-md-v1', storage_path: 'x', content_sha256: 'y', of_sha256: '2'.repeat(64) } })).toEqual(['sidecar_of_other_copy'])
  expect(G.checkManifest({ ...m, page_status: null }, h)).toEqual({ ok: true, problems: [], warnings: ['page_status_unknown'] })  // a warning, not a failure
  // a copy opened without its capture time is checked on what its bytes prove; the full contract still names the missing field
  expect(p({ captured_at: undefined }, h, { require: G.OPENED_COPY_REQUIRED })).toEqual([])
  expect([...G.MANIFEST_REQUIRED].filter((k) => !G.OPENED_COPY_REQUIRED.includes(k))).toEqual(['captured_at'])
  // in the gate: a broken copy is manifest_invalid, a page error alone is page_not_ok; both shadow
  const bad = await G.admit({ ...base, lane: 'scholarship', html: award, manifest: m, raw_bytes: new Uint8Array(Buffer.from('other')) })
  expect(bad.reasons.map((r) => r.code)).toContain('manifest_invalid')
  expect(bad.decision).toBe('admit')
  const e404 = await G.admit({ ...base, lane: 'scholarship', html: opened.text, manifest: { ...m, page_status: 404 }, raw_bytes: opened.bytes })
  expect(e404.reasons.map((r) => r.code)).toContain('page_not_ok')
  expect(e404.signals.input.page_sha256).toBe(h)
})

test('D2: the scholarship score is measured only: recorded with every scholarship decision, never enforced, no enforcement switch', async () => {
  const d = await G.admit({ ...base, lane: 'scholarship', html: news }, { enforce: { scholarship_low_signal: true } })
  expect(d.reasons.map((r) => r.code)).toContain('scholarship_low_signal')
  expect(d.would).toBe('reject')
  expect(d.decision).toBe('admit')
  expect(d.shadow).toBe(true)
  expect(typeof d.signals.scholarship.score).toBe('number')
  expect(G.MEASURE_ONLY.has('scholarship_low_signal')).toBe(true)
  const ok = await G.admit({ ...base, lane: 'scholarship', html: award })
  expect(ok.signals.scholarship.score).toBeGreaterThanOrEqual(2)
  // the migration gives it no switch and refuses to finish if one exists
  expect(MIG).not.toMatch(/'scholarship_low_signal'\s*,/)
  expect(MIG).toContain("raise exception 'post-check: the scholarship score is measured only (Decision 278 D2)';")
})

test('the fingerprint is the whole scholarship bundle: a changed, added or removed linked page never hits duplicate_input', async () => {
  const L1 = sha('Eligibility: international students with an offer.'), L2 = sha('Eligibility: domestic students only.')
  const first = await G.admit({ ...base, lane: 'scholarship', html: award, linked_sha256: L1 })
  const seen = new Set([first.fingerprint])
  const dup = (d) => d.reasons.some((r) => r.code === 'duplicate_input')
  expect(dup(await G.admit({ ...base, lane: 'scholarship', html: award, linked_sha256: L1, seen_fingerprints: seen }))).toBe(true)
  for (const linked of [L2, null, undefined]) {
    const d = await G.admit({ ...base, lane: 'scholarship', html: award, linked_sha256: linked, seen_fingerprints: seen })
    expect(dup(d), String(linked)).toBe(false)
    expect(d.input_sha256).not.toBe(first.input_sha256)
  }
  // the context (provider, country, currency, a recovery item's award) is part of the input too
  expect(dup(await G.admit({ ...base, lane: 'scholarship', html: award, linked_sha256: L1, context: { currency: 'NZD' }, seen_fingerprints: seen }))).toBe(false)
  // the input hash names each part; "none" when there is no linked page
  const parts = { page_sha256: sha('a'), sent_sha256: sha('b') }
  expect(await G.inputSha256({ ...parts, linked_sha256: null })).toBe(await G.inputSha256({ ...parts, linked_sha256: 'none' }))
  expect(await G.inputSha256({ ...parts, linked_sha256: L1 })).not.toBe(await G.inputSha256({ ...parts, linked_sha256: L2 }))
  expect(await G.inputSha256({ ...parts, context: { b: 1, a: 2 } })).toBe(await G.inputSha256({ ...parts, context: { a: 2, b: 1 } }))  // key order does not matter
  // the worker judges after the linked page is read and before the paid call, and passes the linked text's hash and the request context
  const at = (s) => worker.indexOf(s)
  const gate = at('let dec = await admit(gateIn, gateSettings);')
  expect(gate).toBeGreaterThan(at('const lk = eligibilityLinks(html, finalUrl, 1)[0];'))
  expect(gate).toBeLessThan(at('const ask = async (reqBody: unknown, where: string) => {'))
  expect(worker).toContain('linked_sha256: linked ? await sha256(new TextEncoder().encode(linked.text)) : null,')
  expect(worker).toContain('context: { provider: it.provider || "", country: it.country || null, currency: it.currency || null, scholarship: recovery ? (it.scholarship_name || null) : null,')
  expect(worker).toContain('const pv = Number(it.prompt_version || 0), promptKey = `scholarship-prompt-v${pv}${recovery ? `+${RECOVERY_VARIANT}` : ""}:${(await sha256Hex(String(it.prompt || ""))).slice(0, 16)}`;')
  expect(worker).toContain('rpc("svc_pre_ai_admission_seen_v1", { p_fingerprints: [dec.fingerprint] }).catch(() => null)')
  expect(MIG).toContain('create or replace function public.svc_pre_ai_admission_seen_v1(p_fingerprints text[]) returns text[]')
})

test('admission.gate_on ships 0 and every switch 0; the worker reads them; off means the read path is as before; a park is never a drop', async () => {
  expect(MIG).toMatch(/\('pipeline', 'admission\.gate_on', [^\n]+\n[^\n]+\n\s+'number', '0'::jsonb, 0, 1,/)
  expect(MIG).toContain("'number', '0'::jsonb, 0, 1, 'on (1) or off (0)', 1460 + o,")
  expect(MIG).toContain("raise exception 'post-check: the gate ships off';")
  expect(MIG).toContain("raise exception 'post-check: every enforcement switch ships off';")
  // without svc_worker_settings_v1 returning admission.% the worker would never see the switch: edited only from the live definition
  expect(MIG).toContain("select pg_temp.edit_once('public.svc_worker_settings_v1()', '5ef1c297c311ea346d95d04b2d430c34', array[")
  expect(MIG).toContain("or (s.toolset_key = 'pipeline' and s.key like 'admission.%'));")
  expect(worker).toContain('const GATE_ON = wsNum("admission.gate_on", 0) > 0, admissions: unknown[] = [];')
  // gate off: the stored copy is read with storedHtml exactly as before; nothing is judged or recorded
  expect(worker).toContain('if (it.storage_path) { if (GATE_ON) { const cp = await storedCopy(it.storage_path); html = cp.text; rawBytes = cp.bytes; storedBytes = cp.stored_bytes } else html = await storedHtml(it.storage_path) }')
  expect(worker).toContain('const admitted = admissions.length ? await rpc("svc_pre_ai_admission_record_v1", { p_rows: noNul(admissions) }).catch(')
  // only an enforced reject stops a read; this lane has no route for parked items, so it never enforces a park
  expect(worker).toContain('park_routed: false,')
  // the gate never fails a read: an error inside it is counted and the read goes ahead
  expect(worker).toContain('if (GATE_ON) try {')
  expect(worker).toContain('} catch { tally.gate_error = (tally.gate_error || 0) + 1 }')
  const parked = await G.admit({ ...base, lane: 'scholarship', html: award, seen_fingerprints: new Set([(await G.admit({ ...base, lane: 'scholarship', html: award })).fingerprint]) },
    { enforce: { duplicate_input: true }, park_routed: false })
  expect([parked.would, parked.decision, parked.shadow]).toEqual(['park', 'admit', true])
  // with no settings at all nothing is enforced
  for (const html of [news, page('x', '<p>Loading…</p>')]) expect((await G.admit({ ...base, lane: 'scholarship', html })).decision).toBe('admit')
})

test('rejected_admission names enforced reject codes only: never a shadow code, never a park code, and a park writes no rejected_admission at all', async () => {
  const thin = page('Just a moment', '<p>Loading…</p>')
  const b = { ...base, lane: 'scholarship', html: thin }
  const seen = new Set([(await G.admit(b)).fingerprint])
  // three reasons found (thin_page, scholarship_low_signal measured only, duplicate_input a park); one switched on
  const one = await G.admit({ ...b, seen_fingerprints: seen }, { enforce: { thin_page: true } })
  expect(one.reasons.map((r) => r.code)).toEqual(expect.arrayContaining(['thin_page', 'scholarship_low_signal', 'duplicate_input']))
  expect([one.decision, one.enforced]).toEqual(['reject', ['thin_page']])
  // every switch on and parks routed: still only the reject code; the measure-only and park codes stay out
  const all = await G.admit({ ...b, seen_fingerprints: seen }, { enforce: { thin_page: true, scholarship_low_signal: true, duplicate_input: true }, park_routed: true })
  expect([all.decision, all.enforced]).toEqual(['reject', ['thin_page']])
  // a park, even routed and enforced, is not a reject: nothing to write
  const park = await G.admit({ ...b, seen_fingerprints: seen }, { enforce: { duplicate_input: true }, park_routed: true })
  expect([park.decision, park.enforced]).toEqual(['park', []])
  // shadow (nothing switched on): nothing to write
  expect((await G.admit({ ...b, seen_fingerprints: seen })).enforced).toEqual([])
  // the worker writes the prefix only for a reject with enforced codes, from those codes alone
  expect(worker).toContain('if (gateDec?.decision === "reject" && gateDec.enforced.length > 0) {')
  expect(worker).toContain('p_error: `rejected_admission: ${gateDec.enforced.join(",")}`.slice(0, 400),')
  expect((worker.match(/rejected_admission: \$\{/g) || []).length).toBe(1)
  expect(worker).not.toContain('rejected_admission: ${gateDec.reasons')
})

test('R5: a paid answer whose record failed keeps its cost, the fallback cannot fail the batch, and each attempt names its item in ai_invocations', () => {
  expect(worker).toContain('const r = await cascadeFetch(fetch, { service: "scholarship_extraction", source: "scholarship_ai_queue", source_id: it.queue_id },')
  const c = worker.indexOf('p_cost: errorCost(e) || spent, p_storage_path: path')
  expect(c).toBeGreaterThan(0)
  expect(worker.lastIndexOf('try {', c)).toBeGreaterThan(worker.lastIndexOf('} catch (e) {', c))  // the fallback record is inside its own try
  expect(worker.slice(c, c + 400)).toContain('} catch { tally.record_failed = (tally.record_failed || 0) + 1 }')
  expect((worker.match(/cost \+= c1; spent = c1;/g) || []).length).toBe(2)   // single read and the two-part recovery read
  // the attempts go to ai_invocations once, at the end of the call, in their own RPC (not through svc_scholarship_ai_record)
  expect(worker).toContain('await ct.rpc("svc_ai_model_answered_v1", { p_source: null, p_source_id: null, p_model: null, p_attempts: attempts, p_worker: WORKER });')
})

test('storage housekeeping: adapter-captures takes images only up to 10 MiB, guarded on what is stored; the prefix audit only reads', () => {
  expect(BUCKET).toContain("set allowed_mime_types = array['image/png', 'image/webp', 'image/jpeg'],")
  expect(BUCKET).toContain('file_size_limit = 10485760')
  expect(BUCKET).toContain("raise exception 'pre-check: adapter-captures holds an object outside the new rule; measure it before restricting the bucket';")
  expect(BUCKET).toContain("raise exception 'post-check: adapter-captures takes images only, up to 10 MiB';")
  const audit = BUCKET.slice(BUCKET.indexOf('create or replace function security.storage_prefix_audit_v1()'), BUCKET.indexOf('$function$;'))
  expect(audit).toContain('language sql stable security definer')
  expect(audit.replace(/^\s*--.*$/gm, '')).not.toMatch(/\b(insert|update|delete|truncate)\b/i)
  for (const p of ['layer2/<CC>/firecrawl/', 'layer2/<CC>/adapters/', 'layer2/<CC>/companion/', 'adapter-captures/<provider>/<draft>/']) expect(audit, p).toContain(`'${p}'`)
  expect(BUCKET).toContain('grant execute on function security.storage_prefix_audit_v1() to service_role;')
  // the worker already names the type it uploads to that bucket
  expect(worker).toContain('await c.storage.from("adapter-captures").upload(shotPath, new Uint8Array(await img.arrayBuffer()), { contentType: img.headers.get("content-type") || "image/png", upsert: true });')
})
