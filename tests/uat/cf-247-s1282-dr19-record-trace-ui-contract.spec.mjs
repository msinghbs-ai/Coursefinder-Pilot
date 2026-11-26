// Guards: DR-19 increments 2 to 4 (SS-Programme-Control 26 Nov 2026 22:52 AEDT), s1282: Data Delivery drills from a stream, field, hold or recovery class to a provider's records and each record's trace; the course record drawer shows field-level processing status, evidence, failures, recovery history and authorised actions; seven facts are kept apart (record returned by consumer, field populated, field value verified, international applicability verified, canonical admission, consumer delivery, actual recovery gain) and consumer presence is never shown as field accuracy; only the existing reads are used (admin_pim_record_trace_v1, admin_pim_provider_trace_v1, admin_pim_operational_recovery_measure_v1, admin_record_journey_v1 through the existing fold); no new page, menu or backend
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')
const rt = read('src/RecordTrace.jsx')

test('only the existing reads: no new diagnostic framework or record-trace function', () => {
  for (const fn of ['admin_pim_record_trace_v1', 'admin_pim_provider_trace_v1', 'admin_pim_operational_recovery_measure_v1', 'admin_field_coverage', 'admin_priority_search'])
    expect(rt).toContain(`'${fn}'`)
  const calls = [...rt.matchAll(/rpc\('([a-z0-9_]+)'/g)].map(x => x[1])
  expect(new Set(calls)).toEqual(new Set(['admin_pim_record_trace_v1', 'admin_pim_provider_trace_v1', 'admin_pim_operational_recovery_measure_v1', 'admin_field_coverage', 'admin_priority_search']))
  expect(rt).toContain("import Layer4Journey,{STATE}from'./Layer4Journey'")  // the existing Processing journey and diagnosis fold
  expect(rt).toContain('<Layer4Journey key={x.id} kind={l4Kind(x.field_code)} refId={x.id}/>')
  // no backend of its own (S2-RM-Design's s1282 migration on main is the separate DR-19 cause slice)
  expect(fs.readdirSync('supabase/migrations').some(f => /record_trace_ui|dr19_record_trace/.test(f))).toBe(false)
})

test('the seven facts are separate rows, and presence is never accuracy', () => {
  for (const k of ['returned', 'populated', 'verified', 'international', 'admission', 'delivery', 'gain']) expect(rt).toContain(`['${k}',`)
  expect(rt).toContain('A returned record says nothing about whether this field is right.')
  expect(rt).toContain("Consistency of delivery, not a check against the source.")
  expect(rt).toContain('no independent check of the value is recorded')
  expect(rt).toContain('the field trace holds no international-applicability evidence')
  expect(rt).toContain("Zoho per field: not measured.")
  expect(rt).toContain('const NV=({why})=><em className="l4j-na" data-rt-nv>Not verified')
  expect(rt).toContain('const NA=({why})=><em className="l4j-na" data-l4j-na')
})

test('Data Delivery: a drill in each stream and in the PIM matrix; records open their trace and the course record', () => {
  const dd = read('src/DataDelivery.jsx'), pim = read('src/PimDelivery.jsx')
  expect(dd).toContain('<RecordDrill label="Records behind this stream" field={s.field||\'\'} rank={rank}/>')
  expect(pim).toContain('<RecordDrill label="Records by field, hold or recovery" rank={rank}/>')
  expect(rt).toContain("readProviderTrace(prov.id,field,cls)")
  // a failed field-list read is said, with Read again; never an empty register
  expect(rt).toContain('The field list could not be read ({regErr}). <button type="button" className="l4j-refresh" onClick={readReg}>Read again</button>')
  // a button disclosure, never a second <summary> inside the stream or matrix fold; the body reads only when opened
  expect(rt).toContain('<button type="button" className="rt-toggle" aria-expanded={open} onClick={()=>setOpen(!open)} data-rt-drill-toggle>')
  expect(rt).toContain('{open&&<DrillBody fieldIn={field} rank={rank}/>}')
  expect(rt).toContain("<a className=\"cf-link\" href={hrefFor('courses','',{id:r.course_id})} data-rt-open-course>Open the course record</a>")
  // a record reads its trace only once opened (a class can list many records)
  expect(rt).toContain('{opened&&<CourseFieldStatus courseId={r.course_id} field={field} open rank={rank}/>}')
})

test('course record drawer: field status fold, read when opened, Layer 4 links only for Curator and above', () => {
  expect(read('src/mature-main.jsx')).toContain('<FieldProvenancePanel entity="course" id={data.id} rank={rank}/><CourseFieldStatus courseId={data.id} rank={rank}/>')
  expect(rt).toContain('<summary>Field processing status and diagnosis</summary>')
  expect(rt).toMatch(/onToggle=\{e=>\{if\(e\.currentTarget\.open&&!t&&!busy\)load\(\)\}\}/)
  expect(rt).toContain('{rank>=3&&l4.map(')
  expect(rt).toContain("hrefFor('layer4','inbox',{ref:x.id})")
})

test('phone width and tokens: controls 44 px, grids wrap, no colour literal', () => {
  const css = read('src/layer4-item-lifecycle.css'), b = css.slice(css.indexOf('/* CF-247 s1282'))
  expect(b).toContain('min-height:44px')
  expect(b).toContain('grid-template-columns:repeat(auto-fit,minmax(min(100%,16rem),1fr))')
  expect(b).not.toMatch(/#[0-9a-f]{3,6}\b|rgb\(/i)
  expect(read('docs/UI-MAP.md')).toContain('Field processing status and diagnosis')
})
