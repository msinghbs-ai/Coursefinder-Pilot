// CF-247 v2.15.234 (R3): Platform Admin bug list of 10 Oct 2026 — Fix 2. Public phone and email from the provider's own site (filled
// automatically, never over a value entered by hand); the CRICOS Principal Executive Officer held as an internal contact, never published.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261010006600_cf247_r3_provider_contacts.sql'

test('server: contact tables, service-only worker functions, fill only empty values, internal regulatory contact', () => {
  const sql = fs.readFileSync(MIG, 'utf8')
  expect(sql).toContain('fd6fec4d444de5eb920b8a618e1a7d09')
  expect(sql).toContain("kind text not null check (kind in ('public_general', 'regulatory_peo'))")
  expect(sql).toContain('alter table pipeline.provider_contact_points enable row level security;')
  expect(sql).toContain('update catalogue.providers set phone = coalesce(phone, v_phone), email = coalesce(email, v_email)')
  expect(sql).toContain("'regulatory_contact', case when v_rank >= 5 then")
  expect(sql).toMatch(/revoke all on function public\.svc_provider_contact_next\(integer\)[\s\S]*from public, anon, authenticated;/)
  expect(sql).toContain(`select cron.schedule('cricos-peo', '* * * * *'`)
  expect(sql).toContain("('provider-contact-page', 'Course pages', 15")
  expect(sql).not.toMatch(/\b(drop\s+(table|function|schema)|delete\s+from|truncate)\b/i)
  // no consumer API is changed
  expect(sql).not.toMatch(/website_v2_|zoho_|wix/i)
})

test('worker: own-domain email only; CRICOS page must show the provider code', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toMatch(/coverage-sweep-worker-v0\.17\.(3[3-9]|[4-9][0-9])/)
  expect(w).toContain('if (mode === "contact_page") {')
  expect(w).toContain('if (mode === "cricos_peo") {')
  expect(w).toContain('ownEmail(e)')
  expect(w).toContain('if (i >= 0 && hasCode)')
})

test('UI: contact source note and the internal regulatory contact for PIM Operators', () => {
  const ed = fs.readFileSync('src/RecordEditor.jsx', 'utf8')
  expect(ed).toContain('data-public-contact')
  expect(ed).toContain('{data.can_manage&&<div className="re-row wide" data-regulatory-contact>')
  expect(ed).toContain('Internal only · never published')
})

// v2.15.235: contact quality after the first runs
test('contact quality: no media/security/feedback mailboxes, main contact page first, CRICOS page by code, earlier automated values replaced', () => {
  const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
  expect(w).toContain('coverage-sweep-worker-v0.17.34')
  expect(w).toContain('const NEG = /^(media|press|news|security|privacy|feedback')
  expect(w).toContain('https://cricos.education.gov.au/Institution/InstitutionDetails.aspx?ProviderCode=${code}')
  expect(w).not.toContain('peo_search')
  const sql = fs.readFileSync('supabase/migrations/20261010006700_cf247_contact_quality.sql', 'utf8')
  expect(sql).toContain('7869de71bd8d7ff639d47ef4d6197452')
  expect(sql).toContain('when p.phone is not distinct from v_prev.phone and v_prev.id is not null then v_phone')
  expect(sql).toContain("select cron.alter_job((select jobid from cron.job where jobname = 'cricos-peo'), active := true);")
})
