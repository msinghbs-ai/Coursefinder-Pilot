// Guards: Reported data issues R3 (SS-Programme-Control 26 Nov 2026 22:52 AEDT; design admin 2026-11-26-dr19-record-journey-and-diagnosis-design.md section 8), s1285: one read-only Layer 4 view joins the in-app store (Admin and Portal, R1 origin) and the Zoho store with origin flags, Reported and Resolved states, figures (submitted, open, resolved, resolution time, recurrence) and evidence-backed resolution (R1's check, else the current field state said as such; a Fixed with no held value is flagged); each report opens the s1282 field trace and the existing s1272 journey fold and links to its existing card; the course record drawer shows Reported and Resolved per field; nothing closes, changes or verifies a report; Curator and above
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const read = p => fs.readFileSync(p, 'utf8')
const mig = read('supabase/migrations/20261130060000_cf247_s1285_reported_issues_r3_layer4_view.sql')
const ui = read('src/ReportedIssues.jsx'), flags = read('src/reportFlags.jsx'), rt = read('src/RecordTrace.jsx'), inbox = read('src/Layer4Inbox.jsx')
const body = mig.replace(/^--.*$/gm, '')

test('migration: both stores, read only, Curator and above, above R1', () => {
  expect(mig).toMatch(/^-- Replaces: .+$/m); expect(mig).toMatch(/^-- Retires: .+$/m)
  expect(body).toContain("from pipeline.counsellor_feedback f")
  expect(body).toContain("from pipeline.data_flags d")
  expect(body).toContain("where d.flag_code = 'reported'")
  expect(body).toContain("case when d.detail->>'source' = 'zoho' then 'zoho'")
  expect(body).toContain("'counsellor_feedback', 'counsellor_feedback', f.id::text, f.origin")
  // nothing written to either store or to the consumer surface
  expect(body).not.toMatch(/\b(update|delete from|insert into)\s+pipeline\.(counsellor_feedback|data_flags)\b/i)
  expect(body).not.toMatch(/\b(alter|drop)\s+(table|function)\s+(public\.(website_|zoho_)|pipeline\.(counsellor_feedback|data_flags)\b)/i)
  expect(body).toContain("if security.current_role_rank() < 3 then raise exception 'Curator role or above required'")
  expect(body).toContain("pre-check: R1 (s1281, 20261130041500) is not applied")
  expect(body).toContain("(v->>'functions')::int <> 75 or (v->>'relations')::int <> 48")
  expect('20261130060000' > '20261130041500').toBe(true)  // above R1, which it reads
})

test('G2: page size and recurrence window are settings; the Zoho field map is data', () => {
  expect(body).toContain("security.pipeline_num_v1('reports.l4_view_page_max', 50)")
  expect(body).toContain("security.pipeline_num_v1('reports.recurrence_days', 90)")
  for (const k of ['reports.l4_view_page_max', 'reports.recurrence_days']) expect(body).toContain(`('pipeline', '${k}',`)
  expect(body).toContain('create table if not exists pipeline.report_origin_field_map')
  expect(body).toContain('comment on table pipeline.report_origin_field_map')
  expect(body).toContain("left join pipeline.report_origin_field_map m on m.origin = 'zoho' and m.reported_field = d.field_code")
})

test('evidence-backed resolution: R1 check first, else current state said as such; a Fixed with no held value is flagged', () => {
  expect(body).toContain("return jsonb_build_object('basis', 'verification'")
  expect(body).toContain("fs := security.field_state_entity_v1(p_field, p_course)")
  expect(body).toContain("'fixed_without_evidence', p_status = 'fixed' and coalesce(fs->>'completeness', '') <> 'verified'")
  expect(ui).toContain(', not a check made when it was closed')
  expect(ui).toContain('The value itself is not verified here.')
  expect(ui).toContain('label="Fixed, but no value is held"')
})

test('UI: one read when opened, origins and states, figures, links to the existing card, the field trace and the journey fold; no decision control', () => {
  expect(flags).toContain("supabase.rpc('admin_reported_issues_v1',{p_args:args||{}})")
  expect([...ui.matchAll(/rpc\('/g)]).toHaveLength(0)  // every read goes through reportFlags and RecordTrace
  expect(ui).toContain('useEffect(()=>{if(open&&rank>=3)load(0)},[open,origin,state])')
  expect(ui).toContain('if(rank<3)return null')
  expect(ui).toContain("known.map(o=><button key={o} type=\"button\" aria-pressed={origin===o}")
  expect(ui).toContain("[['open','Reported'],['resolved','Resolved'],['all','All']]")
  for (const k of ['Submitted', 'Reported (open)', 'Awaiting verification', 'Resolved', 'Median time to resolve', 'Recurring course fields']) expect(ui).toContain(`<dt>${k}</dt>`)
  expect(ui).toContain("hrefFor('layer4','inbox',{provider:x.provider_id||'',kind:x.l4_kind,ref:x.ref,review_at:x.created_at})")
  expect(ui).toContain('<FieldTrace f={f} consumer={t.consumer} courseId={x.course_id} rank={rank}/>')
  expect(ui).toContain('<Layer4Journey kind={x.l4_kind} refId={x.ref}/>')
  expect(ui).not.toMatch(/inbox_decide|admin_counsellor_reports|report_ack_v1|counsellor_feedback_submit/)
  expect(inbox).toContain('<ReviewReadinessLine/>\n    <ReportedIssues rank={sum.rank}/>')
})

test('course record drawer: Reported and Resolved per field and for the course, read with the trace, Curator and above', () => {
  expect(flags).toContain("if(!active||!courseId||rank<3)return;readReports({mode:'course',course_id:courseId})")
  expect(flags).toContain('label={`Reported: ${fmtNumber(Number(x.open))} open`}')
  expect(flags).toContain('label={`Resolved: ${fmtNumber(Number(x.resolved))}')
  expect(rt).toContain('const rep=useCourseReports(courseId,rank,!!t)')
  expect(rt).toContain('<ReportFlag rep={rep} field={f.field}/>')
  expect(rt).toContain('Reported data issues: <ReportFlag rep={rep}/>')
})

test('phone width and tokens: 44 px links, wrapping grids, no colour literal', () => {
  const css = read('src/layer4-item-lifecycle.css'), block = css.slice(css.indexOf('/* CF-247 s1285'))
  expect(block).toContain('.ri-links a{min-height:44px')
  expect(block).toContain('grid-template-columns:repeat(auto-fit,minmax(min(100%,10rem),1fr))')
  expect(block).not.toMatch(/#[0-9a-f]{3,8}\b|rgb\(/i)
})
