// CF-247 (Platform Admin 24 Oct 2026 07:32): "cricos is only applicable for au and no other country. Cricos code should not be in any
// logic to admit data other than au." Contracts on the worker identity rule, the migration and the Courses list.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const read = f => fs.readFileSync(f, 'utf8')

test('worker identity-v0.6.0: a CRICOS proof only for Australian pages; NZ code proofs are nzqa_code; other countries use the title rules', () => {
  const x = read('supabase/functions/coverage-sweep/extract.ts')
  expect(x).toContain('if (cc === "AU" && code.length >= 6 && codeOnPage) return "cricos_code"')
  expect(x).toContain('if (cc === "NZ" && /^[A-Z]{2,4}[0-9]{3,5}$/.test(code) && codeOnPage) return "nzqa_code"')
  expect(x).not.toMatch(/^\s*if \(code\.length >= 6 && new RegExp\(`\\\\b\$\{code\}\\\\b`\)\.test\(text\.toUpperCase\(\)\)\) return "cricos_code"/m)
  const w = read('supabase/functions/coverage-sweep/index.ts')
  expect(w).toContain('const IDENTITY_RULE = "identity-v0.6.0";')
  expect(w).toContain('const WORKER = "coverage-sweep-worker-v0.45.0";')
  expect(w).toContain('"cricos_code_on_page", "nzqa_code", "adapter_code", "title_match"')
})

test('migration: policy refuses CRICOS proofs outside Australia; lists cleaned; read record and binder country-aware; re-verification count-guarded', () => {
  const m = read('supabase/migrations/20261024002000_cf247_cricos_australia_only.sql')
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m); expect(m).not.toMatch(/^\s*(drop|truncate|delete\s+from)\b/im)
  expect(m).toContain("select pg_temp.edit_once('security.coverage_identity_allowed(uuid,text,text)', '9509a4103b6257e30310e48effe04c52', array[")
  expect(m).toContain("select case when p_basis in ('cricos_code', 'cricos_code_on_page', 'cricos_search') and not exists (select 1 from catalogue.providers p0 join ref.countries k0 on k0.id = p0.country_id where p0.id = p_provider_id and k0.iso_alpha2 = 'AU') then false")
  expect(m).toContain("where k.id = a.country_id and k.iso_alpha2 <> 'AU' and a.identities::text like '%cricos_code%';")
  expect(m).toContain("if v > 0 then raise exception '% non-Australian proof lists still name cricos_code', v; end if;")
  expect(m).toContain("select pg_temp.edit_once('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)', '8f84bea190b10b532399943a38695e20', array[")
  expect(m).toContain("select pg_temp.edit_once('security.coverage_bind_v2(uuid)', '847f5fb963493f637a056fed74366843', array[")
  expect(m).toContain("(case security.coverage_country(p_provider_id) when 'AU' then 'cricos_code' when 'NZ' then 'nzqa_code' else 'adapter_code' end)")
  expect(m).toContain("if v <> 406 then raise exception 'expected 406 mislabelled non-Australian bindings, found %', v; end if;")
  expect(m).toContain("where p.status = 'bound' and coalesce(p.basis, '') <> 'manual' and k.iso_alpha2 <> 'AU'")
  expect(m).toContain("where l.layer2_state->>'source' = 'identity_basis_reverify' and l.status = 'pending'")
})

test('Courses list: the CRICOS registered fee column is hidden when the country filter is not Australia', () => {
  const ui = read('src/mature-main.jsx')
  expect(ui).toContain(".filter(c=>!(type==='course'&&c.key==='fee_amount'&&filters.country&&String(filters.country).toUpperCase()!=='AU'))")
  expect(ui).toContain("{key:'fee_amount',label:'Tuition Only',width:150,sortKey:'fee'}")
})
