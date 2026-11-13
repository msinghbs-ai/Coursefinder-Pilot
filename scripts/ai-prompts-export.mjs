// AI prompts export (CF-247 AI models and services, Platform Admin review 13 Nov 2026 22:10, item 7).
// The instructions the worker sends to a model live in the worker's source. Models & services shows them from the generated file
// docs/platform/ai-prompts.json (the page read gives text_ref "ai-prompts.json#<service>"). This script builds that file FROM the worker source:
// it bundles supabase/functions/coverage-sweep/index.ts, calls each request builder and keeps the system message it would send, so the text is
// the text that is sent. Nothing is typed by hand and no prompt is changed here.
//   node scripts/ai-prompts-export.mjs           writes docs/platform/ai-prompts.json
//   node scripts/ai-prompts-export.mjs --check   exits 1 when the checked-in file is not what the source gives (the staleness guard)
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { pathToFileURL } from 'node:url'

const DIR = 'supabase/functions/coverage-sweep', OUT = 'docs/platform/ai-prompts.json'
const sha = (s) => crypto.createHash('sha256').update(s, 'utf8').digest('hex')

export async function build() {
  const { build: esbuild } = await import('esbuild')
  const mods = ['index', 'course-text', 'course-entry', 'entry', 'fees', 'calendar', 'pageid', 'builder', 'description', 'eligibility']
  // every import that is not a file of the worker (npm:, jsr:, https:) is an empty stand-in: the request builders do not use them
  const stub = { name: 'stub', setup(b) {
    b.onResolve({ filter: /^(npm:|jsr:|https?:)/ }, (a) => ({ path: a.path, namespace: 'stub' }))
    b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({ contents: 'module.exports = new Proxy(function () {}, { get: (t, k) => (k === "__esModule" ? false : t) })', loader: 'js' })) } }
  const r = await esbuild({ stdin: { contents: mods.map((m) => `export * as ${m.replace(/-/g, '_')} from "./${m}.ts"`).join('\n'), resolveDir: DIR, loader: 'ts' },
    bundle: true, format: 'esm', platform: 'neutral', write: false, logLevel: 'silent', plugins: [stub] })
  const tmp = path.resolve('test-results', `ai-prompts-bundle-${process.pid}.mjs`)
  fs.mkdirSync('test-results', { recursive: true }); fs.writeFileSync(tmp, r.outputFiles[0].text)
  const had = globalThis.Deno; globalThis.Deno = { serve() {}, env: { get: () => '' } }  // the worker's entry point is not started
  let w; try { w = await import(pathToFileURL(tmp).href) } finally { if (had === undefined) delete globalThis.Deno; else globalThis.Deno = had; fs.rmSync(tmp, { force: true }) }
  const sys = (req) => { const m = (req?.messages || []).find((x) => x.role === 'system'); if (!m || typeof m.content !== 'string' || !m.content.trim()) throw Error('no system message'); return m.content }
  const src = fs.readFileSync(`${DIR}/index.ts`, 'utf8')
  const worker = (src.match(/const WORKER = "([^"]+)"/) || [])[1] || null
  // the instructions written in the handler itself (course fields other than the deadline): the leading text of each `await ask(` call; where the
  // instruction goes on with the request's own data (a list of codes, of regions) the entry says so
  const inline = []
  // reads `"text" + expression + "text", ` from `from`: the string parts joined, each expression shown as <data of the request>
  const readConcat = (from) => {
    let i = from, text = '', complete = true
    for (;;) {
      while (/\s/.test(src[i])) i++
      if (src[i] === '"') { let j = i + 1; while (src[j] !== '"') j += src[j] === '\\' ? 2 : 1; text += JSON.parse(src.slice(i, j + 1)); i = j + 1 }
      else {  // an expression: skipped to the next + or , at the same depth
        let depth = 0, q = null
        for (; i < src.length; i++) { const c = src[i]
          if (q) { if (c === '\\') i++; else if (c === q) q = null; continue }
          if (c === '"' || c === "'" || c === '`') { q = c; continue }
          if ('([{'.includes(c)) depth++; else if (')]}'.includes(c)) depth--
          else if (depth === 0 && (c === '+' || c === ',')) break }
        text += '<data of the request>'; complete = false
      }
      while (/\s/.test(src[i])) i++
      if (src[i] === '+') { i++; continue }
      return { text, complete }
    }
  }
  const lines = src.split('\n'); let off = 0
  lines.forEach((ln, i) => {
    const start = off; off += ln.length + 1
    if (!/= await ask\(\s*$/.test(ln)) return
    const x = readConcat(start + ln.length + 1)
    if (x.text.length < 40) throw Error(`index.ts:${i + 2}: the instruction of this ask( call was not read`)
    const name = ((lines.slice(i + 1, i + 30).join('\n').match(/,\s*"(course_fields|titles|campus_regions|campus_list|address)"\s*,/) || [])[1]) || null
    inline.push({ name: name || `ask_${i + 2}`, where: `index.ts:${i + 2}`, text: x.text, complete: x.complete, ...(x.complete ? {} : { note: 'where the text says <data of the request> the worker puts in data of that request (a list of codes or of regions)' }) })
  })
  // the operations diagnosis instructions are written in the database function (migration 20261113380000)
  const mig = fs.readFileSync('supabase/migrations/20261113380000_cf247_ai_models_services.sql', 'utf8').split('\n')
  const at = mig.findIndex((l) => /^\s*'instructions', '/.test(l)); if (at < 0) throw Error('ops diagnosis instructions not found')
  let ops = ''
  for (let i = at; i < mig.length; i++) { const m = mig[i].match(/^\s*(?:'instructions', |\|\| )'((?:[^']|'')*)',?\s*$/); if (!m) break; ops += m[1].replace(/''/g, "'") }
  const p = (name, where, version, text, extra = {}) => ({ name, where, version: version || null, text, sha256: sha(text), complete: true, ...extra })
  const blank = { provider: '', url: '', text: '' }
  const services = {
    course_description: [p('description', 'course-text.ts CDESC_SYSTEM', w.course_text.CDESC_PROMPT_VERSION, sys(w.course_text.cdescRequest('m', '', 100)))],
    course_other_fields: [p('deadline', 'course-text.ts COURSE_TEXT_SYSTEM', w.course_text.COURSE_TEXT_PROMPT_VERSION, sys(w.course_text.courseTextRequest('m', '', ['deadline'], 100))),
      ...inline.map((x) => ({ name: x.name, where: x.where, version: 'course-fields-v1', text: x.text, sha256: sha(x.text), complete: x.complete, ...(x.note ? { note: x.note } : {}) }))],
    course_entry_requirements: [p('entry requirements', 'course-entry.ts COURSE_ENTRY_SYSTEM', w.course_entry.COURSE_ENTRY_PROMPT_VERSION, sys(w.course_entry.courseEntryRequest('m', '', 100)))],
    entry_matrices: [p('entry matrix', 'entry.ts ENTRY_PROMPT', w.entry.ENTRY_PROMPT_VERSION, sys(w.entry.entryMatrixRequest('m', blank)))],
    fee_reader: [p('fee page', 'fees.ts FEE_AI_PROMPT', null, w.fees.FEE_AI_PROMPT)],
    calendar_reading: [p('calendar', 'calendar.ts CALENDAR_PROMPT', w.calendar.CALENDAR_READER || null, sys(w.calendar.calendarAiRequest('m', blank)), { note: 'notes kept for the provider are added after this text' })],
    central_english_policy: [p('English policy', 'index.ts CENTRAL_AI_PROMPT.english_policy', null, sys(w.index.centralAiRequest('m', 'english_policy', blank))),
      p('calendar (older central read)', 'index.ts CENTRAL_AI_PROMPT.intake_calendar', null, sys(w.index.centralAiRequest('m', 'intake_calendar', blank)))],
    course_matching: [p('course page match', 'index.ts AI_MATCH_SYSTEM', null, w.index.AI_MATCH_SYSTEM)],
    page_identity: [p('page identity', 'pageid.ts PAGE_ID_SYSTEM', w.pageid.PAGE_ID_CONTRACT || null, w.pageid.PAGE_ID_SYSTEM)],
    adapter_builder: [p('adapter proposal', 'builder.ts BUILDER_SYSTEM', null, w.builder.BUILDER_SYSTEM)],
    scholarship_eligibility: [p('eligibility check', 'index.ts scholarshipRecheckRequest', null, sys(w.index.scholarshipRecheckRequest('m', { name: '', provider: '', url: '', title: '', h1: '', text: '' })), { note: 'a note naming the page a link was followed from is added for a linked page (eligibility.ts linkedPageNote)' })],
    scholarship_extraction: [p('recheck', 'index.ts scholarshipRecheckRequest', null, sys(w.index.scholarshipRecheckRequest('m', { name: '', provider: '', url: '', title: '', h1: '', text: '' })), { note: 'the extraction prompt itself is held in the database (pipeline.scholarship_ai_prompts) and is given whole by the page read' })],
    provider_description: [p('fallback when no database prompt is active', 'description.ts DESCRIPTION_SYSTEM', w.description.DESCRIPTION_PROMPT_VERSION, w.description.DESCRIPTION_SYSTEM, { note: 'the prompt in use is held in the database (pipeline.provider_description_prompts) and is given whole by the page read' })],
    ops_diagnosis: [p('diagnosis', 'database function public.svc_ops_diagnosis_next', 'ops-diagnose-v1', ops)],
    entry_requirements_v2_shadow: [],
  }
  for (const [k, list] of Object.entries(services)) for (const x of list) if (typeof x.text !== 'string' || x.text.length < 40) throw Error(`${k}/${x.name}: no prompt text`)
  return { about: 'Generated by scripts/ai-prompts-export.mjs from the worker source. Do not edit: change the source and run the script.', worker,
    services: Object.fromEntries(Object.entries(services).map(([k, prompts]) => [k, { prompts, sha256: prompts.length ? sha(prompts.map((x) => x.text).join('\n\u0000\n')) : null,
      ...(prompts.length ? {} : { note: 'the prompt is held in the database (pipeline.aer_prompt_versions) and is given whole by the page read' }) }])) }
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  const text = JSON.stringify(await build(), null, 2) + '\n'
  if (process.argv.includes('--check')) {
    const have = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : ''
    if (have !== text) { console.error(`${OUT} is not what the worker source gives: run node scripts/ai-prompts-export.mjs`); process.exit(1) }
    console.log(`${OUT} matches the worker source`)
  } else { fs.writeFileSync(OUT, text); console.log(`wrote ${OUT} (${text.length} bytes)`) }
}
