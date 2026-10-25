// Guards: CF-247 NZ enrichment brief, Release 1 (Platform Admin decisions 23 Oct 2026 20:42, 20:52, 20:56): transition register, domain-moved action, fee floor and the C4 pass.
// CF-247 NZ enrichment brief, Release 1 (Platform Admin decisions 23 Oct 2026 20:42, 20:52, 20:56): transition register, domain-moved
// action, fee floor and the C4 pass. Contracts on the migrations and the UI source.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const read = f => fs.readFileSync(f, 'utf8')
const housekeeping = m => { expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m); expect(m).not.toMatch(/^\s*(drop|truncate|delete\s+from)\b/im) }

test('item 1: transition register with a Government source per row, a daily re-check job and settings', () => {
  const m = read('supabase/migrations/20261023023000_cf247_nz_provider_transitions.sql')
  housekeeping(m)
  expect(m).toContain("risk text not null check (risk in ('none', 're_established_2026', 'standalone_from_2027', 'operations_transfer_2027', 'nzist_federation_until_2027', 'nzist_entity'))")
  expect(m).toContain("source_url text not null check (source_url ~* '^https://')")
  expect(m).toContain('recheck_days int check (recheck_days between 7 and 180)')
  expect(m).toContain('comment on table pipeline.provider_transitions is')
  expect(m).toContain("('pipeline', 'transition.recheck_days', 'Transition: re-check every',")
  expect(m.indexOf("insert into pipeline.automation_catalogue(jobname")).toBeLessThan(m.indexOf("select cron.schedule('transition-recheck'"))
  expect(m).toContain("select cron.schedule('transition-recheck', '41 3 * * *', $$select security.transition_recheck_v1()$$);")
  expect(m).toContain("coalesce(t.recheck_days, security.pipeline_num_v1('transition.recheck_days', 30)::int)")
  const seed = read('supabase/migrations/20261023024000_cf247_nz_provider_transitions_seed.sql')
  housekeeping(seed)
  for (const code of ['6006', '6007', '6011', '6015', '6025', '6019', '6004', '6010', '6013', '6009', '6022', '6012', '6017', '6014', '6024', '6683', '6044']) expect(seed).toContain(`('${code}', `)
  expect(seed).toContain("('6022', 're_established_2026', 'anchor of the federation'")
  expect(seed).toContain("('6024', 'operations_transfer_2027'")
  expect(seed).toContain("('6012', 'standalone_from_2027'")
  expect(seed).toContain("if v < 17 then raise exception")
  expect(seed).not.toContain('nzist_federation_until_2027')
})

test('item 2: domain-moved action keeps the proof, reads first in line, refuses the same host (N5)', () => {
  const m = read('supabase/migrations/20261023025000_cf247_provider_domain_moved.sql')
  housekeeping(m)
  expect(m).toContain("if v_old = v_new then raise exception 'the website already is %: nothing to move', v_old; end if;")
  expect(m).toContain("and g.status in ('bound', 'ambiguous') and g.url ~* v_rx;")
  expect(m).toContain("next_read_at = now(), read_attempts = 0, leased_until = null")
  expect(m).toContain("grant execute on function public.admin_provider_domain_moved(uuid, text, text) to authenticated;")
  const ui = read('src/AdapterBuilderTab.jsx')
  expect(ui).toContain("data-website-move-pages")
  expect(ui).toContain("supabase.rpc('admin_provider_domain_moved'")
})

test('item 4: fee floor per country quarantines at the one admission path; C4 pass is NZ-only (F2); settings UI', () => {
  const m = read('supabase/migrations/20261023026000_cf247_fee_floor.sql')
  housekeeping(m)
  expect(m).toContain("alter table pipeline.coverage_admission_countries add column min_annual_international numeric check (min_annual_international > 0);")
  expect(m).toContain("where c.id = p_course_id and p_basis in ('annual', 'indicative_annual') and a.min_annual_international is not null and p_amount < a.min_annual_international")
  expect(m).toContain("'security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)', '0f3beaac5ed5d4f2ded8a125f569cdfc'")
  expect(m).toContain("'public.svc_fee_ai_record(uuid,jsonb,numeric,text)', '87f3a16a63d691b3195ee1ab857fe7c7'")
  expect(m).toContain("case when v_floor is not null then 'unverified' else 'active' end, now(), now(), now())")
  expect(m).toContain("'international fee below the country floor (' || v_cur || ' ' || to_char(v_floor, 'FM999,999,999') || ' a year): '")
  expect(m).toContain("where k.iso_alpha2 = 'NZ' and f.audience = 'international' and f.status = 'active' and f.basis = 'annual' and f.amount < 8000;")
  expect(m).toContain("if v <> 22 then raise exception 'expected 22 NZ rows below the floor, found %', v; end if;")
  expect(m).toContain("when 'fee.floor' then")
  // the website never returns an unverified fee (G3 unchanged): the refresh and website functions read status = 'active' only
  expect(m).not.toContain("alter table catalogue.course_fees")
  const ui = read('src/PipelineSettings.jsx')
  expect(ui).toContain('data-fee-floor={cc}')
  expect(ui).toContain("write('fee.floor',{country:cc,value:n}")
})
