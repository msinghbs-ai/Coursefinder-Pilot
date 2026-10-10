import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// CF-247 Phase 2 (8 Oct 2026): CRICOS as the first register adapter, replayed side by side with today's Layer 1 code.
test('register adapter: spec stored switched off, replay is read only, reference is a copy of Layer 1', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008002000_cf247_phase2_cricos_register_adapter.sql', 'utf8')
  expect(m).toContain("switched_on boolean not null default false")
  expect(m).toContain("'au_cricos'")
  expect(m).not.toMatch(/delete\s+from/i)
  expect(m).not.toMatch(/update\s+catalogue\./i)
  expect(m).toContain("'pass'")
  const r = fs.readFileSync('supabase/functions/_shared/cf247-register-zip.ts', 'utf8')
  // the reference must stay byte-for-byte the Layer 1 fingerprint rule
  const depth = fs.readFileSync('supabase/functions/layer1-au-depth/index.ts', 'utf8')
  expect(depth).toContain('rows.push([cc,[J(raw),inst.get(get("CRICOS Provider Code"))||"",...(cl.get(cc)||[]).sort()].join("\\u001d")]);')
  expect(r).toContain('rows.push([cc, [J(raw), inst.get(get("CRICOS Provider Code")) || "", ...(cl.get(cc) || []).sort()].join("\\u001d")])')
  expect(r).toContain('export async function adapterRecords(spec: RegisterSpec, zipBytes: Uint8Array, from = 0, to = Infinity)')
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('if (mode === "register_replay")')
  expect(w).toContain('svc_register_replay_save_v2')
  expect(fs.readFileSync('supabase/migrations-archive/20261008002200_cf247_phase2_replay_slices.sql', 'utf8')).toContain('reference_pos')
  const k = fs.readFileSync('supabase/migrations-archive/20261008002100_cf247_keep_register_files.sql', 'utf8')
  expect(k).toContain("not like 'regulatory/%'")
  const d = fs.readFileSync('supabase/migrations-archive/20261008002300_cf247_phase2_replay_driver.sql', 'utf8')
  expect(d).toContain("perform cron.unschedule('register-replay')")
  const c = fs.readFileSync('supabase/migrations-archive/20261008002600_cf247_replay_compare_numeric.sql', 'utf8')
  expect(c).toContain("'a92345aef63ffb480d636f586d00d58e'")
  expect(c).toContain('then (a.fields->>\'duration_weeks\')::numeric end weeks')
})

// CF-247 Phase 2 (8 Oct 2026): NZQA, a register published as web pages, replayed from the stored Layer 1 batch files.
test('NZQA register adapter: stored switched off, reference is the layer1-nz-live code, replay reads listed files', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008002800_cf247_phase2_nzqa_register_adapter.sql', 'utf8')
  expect(m).toContain("'nz_nzqa'")
  expect(m).toContain('"format": "html_pages"')
  expect(m).not.toMatch(/delete\s+from/i)
  expect(m).not.toMatch(/update\s+catalogue\./i)
  expect(m).not.toContain('switched_on')
  expect(m).toContain('add column if not exists paths text[]')
  // the reference must stay the same code as layer1-nz-live (formatting aside)
  const norm = (s) => s.replace(/\s+/g, '').replace(/;}/g, '}').replace(/\((\w)\)=>/g, '$1=>')
  const live = fs.readFileSync('supabase/functions/layer1-nz-live/index.ts', 'utf8')
  expect(live).toContain('const VERSION="layer1-nz-live-v1.3.0"')
  const l = norm(live)
  const r = fs.readFileSync('supabase/functions/_shared/cf247-register-html.ts', 'utf8')
  for (const f of ['const clean =', 'function mapLevel(', 'function providerNumber(', 'function providerName(', 'function providerWebsite(', 'function parseQualifications(']) {
    const line = r.split('\n').find((x) => x.startsWith(f))
    expect(line, f).toBeTruthy()
    expect(l.includes(norm(line)), f).toBe(true)
  }
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('svc_register_replay_next_v3')
  expect(w).toContain('if (n.spec?.format === "html_pages")')
  expect(w).toContain('n.code === "nz_nzqa" ? nzqaReferenceRecords(batch)')
})

// CF-247 Phase 2 (8 Oct 2026): PRISMS and QILT, statistics published as Excel workbooks, replayed from the stored workbooks.
test('PRISMS and QILT register adapters: stored switched off, references are the Layer 1 readers, replay reads stored workbooks', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008003000_cf247_phase2_prisms_qilt_register_adapters.sql', 'utf8')
  for (const code of ['au_prisms_sa4', 'au_qilt_gos', 'au_qilt_ses', 'au_qilt_gosl', 'au_qilt_ess']) expect(m).toContain(`'${code}'`)
  expect(m).toContain('"format":"xlsx_tables"')
  expect(m).not.toMatch(/delete\s+from/i)
  expect(m).not.toMatch(/update\s+catalogue\./i)
  expect(m).not.toContain('switched_on')
  const norm = (s) => s.replace(/\s+/g, '')
  const r = norm(fs.readFileSync('supabase/functions/_shared/cf247-register-xlsx.ts', 'utf8'))
  // QILT reference: the reader lines are copied byte for byte (whitespace aside) from qilt-au-etl v0.3.1
  const q = fs.readFileSync('supabase/functions/qilt-au-etl/index.ts', 'utf8')
  expect(q).toContain('const VERSION="qilt-au-etl-v0.3.1"')
  expect(q).toContain('high:cell.hi,')
  for (const start of [' gos:{', ' ses:{', ' gosl:{', ' ess:{', 'function val(', 'function extract(']) {
    const line = q.split('\n').find((x) => x.startsWith(start))
    expect(line, start).toBeTruthy()
    expect(r.includes(norm(line).replace(/norm\(/g, 'qnorm(')), start).toBe(true)
  }
  // PRISMS reference: the same checks and row rules as prisms-au-etl v0.2.0
  const p = fs.readFileSync('supabase/functions/prisms-au-etl/index.ts', 'utf8')
  expect(p).toContain('const VERSION = "prisms-au-etl-v0.3.0"')
  for (const s of ['/Year-to-date\\s+([A-Za-z]+)\\s+(\\d{4})/i', '/^<\\s*5$/i', 'if (!state && !sa4 && !sector && !broadField) continue;', '`prisms-sa4:${period.collectionVersion}:row:${i + 1}:${metricCode}`'])
    { expect(p, s).toContain(s); expect(r.includes(norm(s)), s).toBe(true) }
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('if (n.spec?.format === "xlsx_tables")')
  expect(w).toContain('stored workbook does not match its recorded hash')
})

// CF-247 Phase 2 (8 Oct 2026): switching a register adapter on is a logged Platform Admin step gated on a passing replay; the Layer 1
// workers read with the adapter only when it is switched on.
test('register adapter switch: gated on a passing replay, logged, and used by the NZQA and PRISMS workers', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008003300_cf247_register_adapter_switch.sql', 'utf8')
  expect(m).toContain("coalesce(security.current_role_rank(), 0) < 6")
  expect(m).toContain("did not pass")
  expect(m).toContain("spec changed after its latest replay")
  expect(m).toContain("'register_adapter_on'")
  expect(m).not.toMatch(/set\s+switched_on\s*=\s*true/i)
  const nz = fs.readFileSync('supabase/functions/layer1-nz-live/index.ts', 'utf8')
  expect(nz).toContain('import { htmlAdapterRows } from "../_shared/cf247-register-html.ts";')
  expect(nz).toContain('rpc(service,"svc_register_adapter_reader",{p_code:"nz_nzqa"})')
  expect(nz).toContain('if(reader?.spec)records=htmlAdapterRows(reader.spec,acquired);else for(const p of acquired){')
  const pr = fs.readFileSync('supabase/functions/prisms-au-etl/index.ts', 'utf8')
  expect(pr).toContain('import { xlsxAdapterRecords } from "../_shared/cf247-register-xlsx.ts";')
  expect(pr).toContain('reader?.spec ? parseWithAdapter(reader.spec, bytes, ctx, editionUrl) : parseWorkbook(bytes, ctx)')
  const h = fs.readFileSync('supabase/functions/_shared/cf247-register-html.ts', 'utf8')
  expect(h).toContain('return htmlAdapterRows(spec, batch).map((r) => ({ k: keyOf(r), x: asText(r) }));')
})

test('register replay: a run is leased to one call and released when the call ends', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008003500_cf247_replay_lease.sql', 'utf8')
  expect(m).toContain("for update skip locked")
  expect(m).toContain("lease_until = now() + interval '150 seconds'")
  expect(m).toContain("'e3617cc0201ad9810879f568a909a846'")
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('} finally { await rpc("svc_register_replay_release", { p_run_id: n.run_id }).catch(() => null) }')
})

// CF-247 Phase 2 (8 Oct 2026): CRICOS adapter version 2 covers provider addresses and both location sets so the CRICOS workers can read
// everything they apply with it once it is switched on.
test('CRICOS adapter v2: address fields and location sets; depth and facts workers read with the adapter when switched on', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008003700_cf247_cricos_adapter_v2.sql', 'utf8')
  expect(m).toContain("where code = 'au_cricos' and version = 1 and not switched_on")
  expect(m).toContain('"Postal Address City", "Postal City"')
  expect(m).toContain('"fallback": "record_provider"')
  expect(m).toContain('"dedupe": ["provider_code", "course_code", "location_code"]')
  const e = fs.readFileSync('supabase/functions/_shared/cf247-register-zip.ts', 'utf8')
  for (const f of ['export function adapterSets(', 'export function adapterSelect(', 'export async function adapterFingerprints(', 'function scanLocations(text:string,wanted:Set<string>)', 'function scanCourseLocations(text:string,wanted:Set<string>,courseProviderMap:Map<string,string>)'])
    expect(e, f).toContain(f)
  const depth = fs.readFileSync('supabase/functions/layer1-au-depth/index.ts', 'utf8')
  // the reference copies of the location scans are the live Layer 1 code
  for (const f of ['function scanLocations(', 'function scanCourseLocations(']) {
    const live = depth.split('\n').find((l) => l.startsWith(f)), copy = e.split('\n').find((l) => l.startsWith(f))
    expect(copy, f).toBe(live)
  }
  expect(depth).toContain('rpc(service,"svc_register_adapter_reader",{p_code:"au_cricos"})')
  expect(depth).toContain('reader?.spec?await adapterFingerprints(reader.spec,adapterTexts(reader.spec,reg.zipBytes)):await courseFingerprints(parts)')
  expect(depth).toContain('const courseScan:any=ab?ab.courseScan:scanCourses(')
  const facts = fs.readFileSync('supabase/functions/layer1-au-cricos-facts/index.ts', 'utf8')
  expect(facts).toContain('reader?.spec?adapterFacts(reader.spec,new TextDecoder().decode(bytes),offset,batchSize,codes):scanCsv(')
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('await referenceRecords(zipBytes, from, to, Boolean(n.spec?.sets))')
})

// CF-247 Phase 2 (8 Oct 2026): Canadian catalogue adapters (text_items); each reference is a verbatim copy of its Layer 1 reader.
test('Canada register adapters: switched off, every copied reader piece is still in its Layer 1 worker', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008003900_cf247_canada_register_adapters.sql', 'utf8')
  for (const c of ['ca_algonquin', 'ca_boreal', 'ca_cambrian', 'ca_conestoga', 'ca_confederation', 'ca_durham', 'ca_fanshawe_pgwp', 'ca_fleming', 'ca_georgian', 'ca_lambton', 'ca_loyalist', 'ca_mohawk', 'ca_niagara', 'ca_seneca', 'ca_sheridan', 'ca_stclair', 'ca_ircc_dli'])
    expect(m, c).toContain(`'${c}'`)
  expect(m).toContain('"format": "text_items"')
  expect(m).not.toMatch(/delete\s+from/i)
  expect(m).not.toContain('switched_on')
  const ref = fs.readFileSync('supabase/functions/_shared/cf247-register-ca-ref.ts', 'utf8')
  const pieces = JSON.parse(fs.readFileSync('tests/uat/cf-247-ca-ref-pieces.json', 'utf8'))
  expect(Object.keys(pieces).length).toBe(20)
  // Seneca: the adapter copies reader v0.1.0 (cat.senecapolytechnic.ca), which was the checked-in code. The deployed reader is v0.3.1
  // (alphabetical list plus availability API), checked in 9 Oct 2026. The copy is checked against v0.1.0 kept in the test fixture;
  // the adapter stays switched off and must be re-derived from v0.3.1 before any switch-on (FOLLOW-UPS).
  const superseded = { seneca: 'layer1-ca-seneca-catalogue-v0.3.1' }
  for (const [code, p] of Object.entries(pieces)) {
    const w = superseded[code] ? fs.readFileSync('tests/uat/fixtures/layer1-ca-seneca-catalogue-v0.1.0.ts.txt', 'utf8') : fs.readFileSync(`supabase/functions/${p.worker}/index.ts`, 'utf8')
    if (superseded[code]) expect(fs.readFileSync(`supabase/functions/${p.worker}/index.ts`, 'utf8')).toContain(superseded[code])
    expect(ref, code).toContain(`export function ref_${code}(`)
    for (const piece of p.pieces) { expect(w.includes(piece), `${code} worker`).toBe(true); expect(ref.includes(piece), `${code} copy`).toBe(true) }
  }
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('if (n.spec?.format === "text_items")')
})

// CF-247 Phase 2 (8 Oct 2026): the eleven Canadian readers that kept only their own parsed output also store the raw pages they fetched.
test('Canada raw capture: each reader stores a -raw.json bundle beside its evidence and reports it', () => {
  for (const f of ['centennial-programs', 'cna-programs', 'fanshawe-programs', 'firstparty-catalogues', 'mb-programs', 'northern-programs', 'ns-sk-programs', 'on-college-programs', 'sault-programs', 'sk-programs', 'stlawrence-programs']) {
    const w = fs.readFileSync(`supabase/functions/layer1-ca-${f}/index.ts`, 'utf8')
    expect(w, f).toContain('async function rawEvidence(')
    expect(w, f).toContain('-raw.json')
    expect(w, f).toContain('raw_capture:true')
    expect(w, f).toContain('raw_evidence:rawEv')
  }
})

test('text_items engine reads fields in dependency order (jsonb does not keep key order)', () => {
  const e = fs.readFileSync('supabase/functions/_shared/cf247-register-items.ts', 'utf8')
  expect(e).toContain('const deps = (r: ItemRule) => [r.from, r.same_as, r.cell?.anchor')
  expect(e).toContain('for (const name of fieldOrder) {')
})

test('Canada ALIS and EPBC adapters: bundles of stored pages, references copied from the readers', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008004200_cf247_canada_alis_epbc_adapters.sql', 'utf8')
  expect(m).toContain("'ca_alis'"); expect(m).toContain("'ca_epbc'")
  expect(m).toContain('"bundle": {"pages": "raw_pages"')
  expect(m).not.toContain('switched_on')
  const ref = fs.readFileSync('supabase/functions/_shared/cf247-register-ca-ref.ts', 'utf8')
  expect(ref).toContain('export function ref_alis('); expect(ref).toContain('export function ref_epbc(')
})

test('register replay: a run stops after three calls end without saving, and the CRICOS adapter reads only its slice', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261008004300_cf247_replay_attempts.sql', 'utf8')
  expect(m).toContain("'6734bb9841dd3b9344b9c494a8685c05'")
  expect(m).toContain('r.attempts >= 3')
  expect(m).toContain('(lease_until is null or lease_until <= now())')
  const e = fs.readFileSync('supabase/functions/_shared/cf247-register-zip.ts', 'utf8')
  expect(e).toContain('if (at < from || at >= to) return;')
})

test('CRICOS v2 replay reads each location set in a call of its own', () => {
  const e = fs.readFileSync('supabase/functions/_shared/cf247-register-zip.ts', 'utf8')
  expect(e).toContain('export const setNames = (spec: { sets?: Record<string, unknown> }) => Object.keys(spec.sets || {}).sort();')
  expect(e).toContain('const which = ["course_locations", "locations"][from - rows.length];')
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('const last = (out0 as any).done ?? (to >= out0.total);')
})
