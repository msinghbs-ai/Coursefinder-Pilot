import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// CF-247 Phase 2 (8 Oct 2026): CRICOS as the first register adapter, replayed side by side with today's Layer 1 code.
test('register adapter: spec stored switched off, replay is read only, reference is a copy of Layer 1', () => {
  const m = fs.readFileSync('supabase/migrations/20261008002000_cf247_phase2_cricos_register_adapter.sql', 'utf8')
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
  expect(fs.readFileSync('supabase/migrations/20261008002200_cf247_phase2_replay_slices.sql', 'utf8')).toContain('reference_pos')
  const k = fs.readFileSync('supabase/migrations/20261008002100_cf247_keep_register_files.sql', 'utf8')
  expect(k).toContain("not like 'regulatory/%'")
  const d = fs.readFileSync('supabase/migrations/20261008002300_cf247_phase2_replay_driver.sql', 'utf8')
  expect(d).toContain("perform cron.unschedule('register-replay')")
  const c = fs.readFileSync('supabase/migrations/20261008002600_cf247_replay_compare_numeric.sql', 'utf8')
  expect(c).toContain("'a92345aef63ffb480d636f586d00d58e'")
  expect(c).toContain('then (a.fields->>\'duration_weeks\')::numeric end weeks')
})

// CF-247 Phase 2 (8 Oct 2026): NZQA, a register published as web pages, replayed from the stored Layer 1 batch files.
test('NZQA register adapter: stored switched off, reference is the layer1-nz-live code, replay reads listed files', () => {
  const m = fs.readFileSync('supabase/migrations/20261008002800_cf247_phase2_nzqa_register_adapter.sql', 'utf8')
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
  const m = fs.readFileSync('supabase/migrations/20261008003000_cf247_phase2_prisms_qilt_register_adapters.sql', 'utf8')
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
  const m = fs.readFileSync('supabase/migrations/20261008003300_cf247_register_adapter_switch.sql', 'utf8')
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
  const m = fs.readFileSync('supabase/migrations/20261008003500_cf247_replay_lease.sql', 'utf8')
  expect(m).toContain("for update skip locked")
  expect(m).toContain("lease_until = now() + interval '150 seconds'")
  expect(m).toContain("'e3617cc0201ad9810879f568a909a846'")
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('} finally { await rpc("svc_register_replay_release", { p_run_id: n.run_id }).catch(() => null) }')
})
