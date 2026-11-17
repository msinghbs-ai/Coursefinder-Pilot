// Guards: Admin destination data design v1.9 approvals A-1 to A-4 (Platform Admin 17 Nov 2026 07:29, 07:35) and the RM1B loader handoff (13:12, 14:11, 14:30): SUA localities and ERP from ABS Regional population 2024-25 with attribution and evidence, postcode shares from the ASGS Edition 3 Mesh Block files flagged by destination_postcode_flags_v1, job destination-abs-load with Run now
// CF-247 S574. Migration 20261117180000_cf247_rm1b_destination_abs_geo_loader.sql; edge function layer1-destination-geo-loader v1.0.0; workflow destination-abs-shares-load.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const raw = fs.readFileSync('supabase/migrations/20261117180000_cf247_rm1b_destination_abs_geo_loader.sql', 'utf8')
const mig = raw.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const edge = fs.readFileSync('supabase/functions/layer1-destination-geo-loader/index.ts', 'utf8')
const wf = fs.readFileSync('.github/workflows/destination-abs-shares-load.yml', 'utf8')
const py = fs.readFileSync('scripts/destination/abs_postcode_sua_shares.py', 'utf8')
const fns = JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8')).functions

test('approved sources only (A-1, A-4); the edition, vintage and attribution are fixed in reviewed code', () => {
  expect(edge).toContain('source_url: "https://www.abs.gov.au/statistics/people/population/regional-population/2024-25/32180DS0004_2001-25.xlsx"')
  expect(edge).toContain('reference_period: "2025-06-30"')
  expect(edge).toContain('licensed under CC BY 4.0.')
  expect(mig).toContain("if v_url !~ '^https://www\\.abs\\.gov\\.au/' then raise exception 'population must come from the ABS (approval A-1): %'")
  expect(mig).toContain("if v_url !~ '^https://(data\\.gov\\.au|www\\.abs\\.gov\\.au)/' then raise exception 'shares must come from the ABS allocation files (approval A-4): %'")
  expect(wf).toContain('ZIP_URL: https://data.gov.au/data/dataset/4c9dbd2f-5706-4c89-aeb8-689ccc3ca290/resource/b0c00ec8-4232-4eb5-bf19-45c944c336de/download/asgs-edition-3-2021-allocation-files.zip')
  for (const col of ["'MB_CODE_2021', 'SA2_CODE_2021'", "'MB_CODE_2021', 'POA_CODE_2021', 'AREA_ALBERS_SQKM'", "'SA2_CODE_2021', 'SUA_CODE_2021', 'SUA_NAME_2021'"]) expect(py).toContain(col)
})

test('every locality and figure carries attribution and evidence; everything loads as draft and approved figures keep their value', () => {
  expect(mig).toContain("insert into destination.localities as l(country_code, name, geography_type, geography_code, boundary_vintage, dataset_edition, attribution_text, evidence_id)")
  expect(mig).toContain("raise exception 'boundary vintage, dataset edition, reference period and attribution are required'")
  expect(mig).toContain("select l.id, 'population', 'erp_persons', s.erp, 'persons', v_period, v_edition, v_url, v_attr, v_ev")
  expect(mig).toContain("where t.status in ('draft', 'in_review')")
  expect(mig).toContain("btrim(r->>'name') !~* '^(not in any|migratory|no usual address)'")
  expect(mig).toContain('alter table destination.localities add column if not exists evidence_id uuid references pipeline.evidence_artifacts(id);')
  expect(mig).not.toMatch(/status\s*=\s*'(approved|published)'/)
  expect(mig.replace(/\$function\$[\s\S]*?\$function\$/g, '')).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('postcode flags come only from security.destination_postcode_flags_v1; Layer 4 decisions are left alone', () => {
  expect(mig).toContain('cross join lateral security.destination_postcode_flags_v1(s.share) f')
  expect(mig).toContain("security.pipeline_num_v1('destination.postcode_candidate_min_share', 0.01)")
  expect(mig).toContain('and d.boundary_vintage = p_vintage and d.resolved_at is not null)')
  expect(mig).not.toMatch(/0\.9\b/)
})

test('job destination-abs-load: catalogued with the destination- prefix, monthly at 05:30 Sydney, no number in its command, with Run now', () => {
  expect(mig.indexOf("('destination-abs-load', 'Layer 1 register'")).toBeLessThan(mig.indexOf("cron.schedule('destination-abs-load'"))
  expect(mig).toContain("select cron.schedule('destination-abs-load', '30 18,19 * * *', 'select pipeline.svc_pilot_submit_nonce(''layer1-destination-geo-loader'', jsonb_build_object(''mode'', ''load'', ''trigger'', ''schedule'')) where security.destination_abs_load_due_v1()');")
  expect(mig).toContain("extract(day from (now() at time zone 'Australia/Sydney')) = 1 and extract(hour from (now() at time zone 'Australia/Sydney')) = 5")
  expect(mig).toContain("set value = value || '[\"destination-abs-load\"]'::jsonb")
  expect(mig).toContain("if p_job like 'destination-%' then return security.destination_job_run_now_v1(p_job, p_reason, p_args, p_requester); end if;")
  expect(mig).toContain("if md5(v_src) <> 'e11749672a47b640e0da93d0508f8a62' then raise exception")
  expect(mig).toContain("('destination-abs-load', 'layer1-destination-geo-loader', jsonb_build_object('mode', 'load'))")
  expect(fns['layer1-destination-geo-loader']).toBe(false)
  expect(edge).toContain('await rpc(service, "svc_pilot_consume_nonce", { p_function: FUNCTION_NAME, p_nonce: nonce })')
})

test('the shares workflow confirms the project and writes only through the loader function', () => {
  expect(wf).toContain('if [ -z "${{ vars.SUPABASE_PROJECT_REF }}" ] || [ "$REF" != "${{ vars.SUPABASE_PROJECT_REF }}" ]')
  expect(wf).toContain("printf 'select security.destination_abs_shares_load_v1($abs$'")
  expect(wf).toContain('workflow_dispatch:')
  expect(wf).not.toMatch(/\b(delete from|truncate|drop table)\b/i)
})
