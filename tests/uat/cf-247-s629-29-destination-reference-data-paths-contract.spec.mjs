// Guards: 29-destination readiness (Platform Admin 18 Nov 2026 11:28: onboarding every destination needs only data and Layer 1 configuration, never a new migration): a country's registration scheme and subdivisions are registered as data by a Platform Admin with a reason (planned; an existing row is never changed), and the induction wizard's step 1 offers it.
// CF-247 S629. supabase/migrations-archive/20261118141000_cf247_reference_data_paths_29_destinations.sql; src/ui-v1/Layer1InductionWizardView.jsx.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118141000_cf247_reference_data_paths_29_destinations.sql', 'utf8')
const W = fs.readFileSync('src/ui-v1/Layer1InductionWizardView.jsx', 'utf8')

test('schemes and subdivisions are data: Platform Admin, a reason, added only, logged', () => {
  expect(M).toContain("if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) registers a scheme'")
  expect(M).toContain("values (v_scheme, v_kind, v_cc, v_auth, v_label, v_never, 'planned')\n  on conflict (scheme, kind, country_code) do nothing;")
  expect(M).toContain("on conflict (code) do nothing;")
  expect(M).toContain("if v_code !~ ('^' || v_cc || '-[A-Z0-9]{1,3}$')")
  expect(M).toContain("values ('layer1', 'scheme_register',")
  expect(M).toContain("values ('reference', 'subdivisions_register',")
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate |alter table)/im)
  expect(M).toContain("raise exception 'post-check: a named destination is missing from ref.countries'")
  expect(M).toMatch(/-- Replaces: nothing/)
  expect(M).toMatch(/-- Retires: nothing\./)
})

test('the wizard offers + Register a scheme to a Platform Admin in step 1', () => {
  expect(W).toContain("export function SchemeRegister({country,rpc,onDone}){")
  expect(W).toContain("rpc('admin_registration_scheme_register_v1',{p_args:{...v,country_code:country}})")
  expect(W).toContain("{f.country_code&&!closed&&rank>=6&&<SchemeRegister country={f.country_code} rpc={rpc} onDone={async()=>{await open(id)}}/>}")
  expect(W).not.toContain('(a database change)')
})
