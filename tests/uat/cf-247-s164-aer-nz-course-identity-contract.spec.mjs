// Guards: CF-247 AER NZ course-level identity (Platform Admin mandate 29 Oct 2026 12:23 B4): NZ course pages are read only with an already-approved strong NZ identity proof and a stored official page; title-only refused; AU rules unchanged; no new lane
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029080000_cf247_aer_nz_course_identity.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const TITLE_ONLY = ['adapter_title', 'exact_title', 'title_level', 'degree_name', 'title_match', 'host_page']

test('header: authority, Replaces and Retires, nothing dropped, consumer API untouched, no new job, status or lane', () => {
  expect(m).toMatch(/^-- CF-247 AER NZ course-level identity \(Platform Admin mandate 29 Oct 2026 12:23, B4/)
  expect(m).toMatch(/^-- Replaces: security\.enrich_entry_record_v1 \(same name, md5-guarded edit\)/m)
  expect(m).toMatch(/^-- Retires: nothing$/m)
  expect(m).toContain('-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, status, Layer 4 field or reader')
  expect(code).not.toMatch(/^\s*(drop|delete|truncate|alter table)\b/im)
  expect(code).not.toMatch(/cron\.schedule|insert into pipeline\.(automation_catalogue|admin_job_kinds)|create table|website_|zoho_|\bapi\./)
})

test('NZ reads the stored official page only, with the strong NZ proofs already approved for other NZ fields; no title-only basis', () => {
  expect(code).toContain("values ('NZ', 'entry_requirements', array['ai_stored'],")
  expect(code).toContain("set identities = a.identities || jsonb_build_object('entry_requirements', jsonb_build_array('nzqa_code', 'adapter_code', 'manual'))")
  expect(code).toContain("where k.id = a.country_id and k.iso_alpha2 = 'NZ' and not (a.identities ? 'entry_requirements');")
  // each admitted proof must already be approved for NZ english and intakes
  expect(code).toContain("if not (v_nz->'english' ?& array['nzqa_code', 'adapter_code', 'manual'] and v_nz->'intakes' ?& array['nzqa_code', 'adapter_code', 'manual']) then")
  const admitted = code.match(/jsonb_build_object\('entry_requirements', jsonb_build_array\(([^)]*)\)\)/)[1]
  for (const b of [...TITLE_ONLY, 'cricos_code']) expect(admitted).not.toContain(`'${b}'`)
  // the guard proves title-only and CRICOS proofs refused, and the strong proofs admitted, through security.coverage_identity_allowed
  for (const b of TITLE_ONLY) expect(code).toContain(`security.coverage_identity_allowed('ab12c7f8-e368-453d-9dfe-4ab8bd744829', '${b}', 'entry_requirements')`)
  expect(code).toContain("security.coverage_identity_allowed('39301fa8-bff2-4389-bbcd-32d8415fae04', 'cricos_code', 'entry_requirements') then")
  expect(code).toContain("raise exception 'a title-only or CRICOS proof admits NZ entry requirements';")
  expect(code).toContain("security.coverage_identity_allowed('39301fa8-bff2-4389-bbcd-32d8415fae04', 'nzqa_code', 'entry_requirements')")
})

test('AU rules unchanged: the AU identity row, source rule and provider order are guarded before and after', () => {
  expect(code).not.toMatch(/iso_alpha2 = 'AU' and not \(a\.identities/)
  expect(code).not.toMatch(/values \('AU', 'entry_requirements'/)
  expect(code).toContain(`if v_au->'entry_requirements' is distinct from '["cricos_code", "adapter_code", "manual"]'::jsonb then raise exception`)
  expect(code).toContain("is distinct from current_setting('cf247.nz_entry_au_identities', true) then raise exception 'AU identities changed'; end if;")
  expect(code).toContain("raise exception 'AU entry_requirements source rule changed';")
  expect(code).toContain("from jsonb_array_elements(v_prov) with ordinality t(x, o) where o <= 21)::text")
  expect(code).toContain("is distinct from current_setting('cf247.nz_entry_au_providers', true) then raise exception")
})

test('the plan\'s NZ providers come after the Australian ones, and activation is count-guarded', () => {
  expect(code).toContain("set value = value || '[\"00e5f26c-446e-453c-a3fb-bc5239a4feec\",")  // appended: Australian providers stay first
  const added = code.match(/set value = value \|\| '(\[[^']*\])'::jsonb/)[1]
  const ids = JSON.parse(added)
  expect(ids).toHaveLength(20)
  expect(new Set(ids).size).toBe(20)
  expect(ids.slice(-5)).toEqual(['ea5a3fa6-31f4-4553-9cfd-6bff49c36a6b', 'd72e0120-a3a2-4909-8ddf-bcad1ec60150', 'adeb0bbb-5b07-4130-aaeb-ad404bf40ff7',
    '38f8ea71-2269-407c-aab6-68a5f09fc01a', 'db910e88-67d1-4d2b-a65c-cea290aa0692'])  // EIT, NorthTec, UCOL, Toi Ohomai, Canterbury
  expect(code).toContain("set value = '[\"AU\", \"NZ\"]'::jsonb")
  expect(code).toContain("where toolset_key = 'pipeline' and key = 'entry.course_read_countries' and value = '[\"AU\"]'::jsonb;")
  // the count guard runs after activation in the same migration: NZ in range, none on a weak proof, AU before = after
  expect(code.indexOf("key = 'entry.course_read_countries' and value")).toBeLessThan(code.indexOf('if v_nz not between 380 and 470 then raise exception'))
  expect(code).toContain("if v_weak <> 0 then raise exception 'NZ eligible courses on a title-only or unknown proof: %', v_weak; end if;")
  expect(code).toContain("perform set_config('cf247.nz_entry_au_before', v_au_n::text, true);")
  expect(code).toContain("if v_au::text is distinct from current_setting('cf247.nz_entry_au_before', true) then")
  expect(code).toContain("raise exception 'AU eligible course count changed: % before, % after'")
})

test('the record function edit is md5-guarded and changes only the NZ audience; AU audience rule is byte-identical', () => {
  expect(code).toContain("select pg_temp.edit_n('security.enrich_entry_record_v1(bigint,jsonb)', 'b338ca230101470b3d17bae094167185', array[")
  expect(code).toContain("if md5(v_def) <> p_md5 then raise exception")
  expect(code).toContain("e.captured_at, security.coverage_country(pg.provider_id) cc into g")
  expect(code).toContain("when g.cc = 'NZ' and v_q ~* '(\\mNCEA\\M|University Entrance|\\mUE\\M)' then 'domestic' else 'all' end;")
  expect(code).toContain("], array[1, 1]);")
  // the B1 rules (quote, score basis, English duplicate, Layer 4) are not edited
  const edit = code.slice(code.indexOf("select pg_temp.edit_n('security.enrich_entry_record_v1"), code.indexOf('], array[1, 1]);'))
  expect(edit).not.toMatch(/score_without_basis|english_duplicate|course_entry_first_read|coverage_identity_allowed/)
})

test('pure: the edited audience rule marks NZ school-leaver routes domestic and leaves AU decisions unchanged', () => {
  // the migration's own regular expressions, with Postgres word boundaries (\m, \M) read as \b
  const pg = (s) => new RegExp(s.replace(/\\[mM]/g, '\\b'), 'i')
  const au = pg(code.match(/when v_q ~\* '([^']+)' then 'domestic'\n/)[1])
  const nz = pg(code.match(/when g\.cc = 'NZ' and v_q ~\* '([^']+)' then 'domestic'/)[1])
  const audience = (cc, q) => /\b(international|overseas)\b/i.test(q) ? 'international' : au.test(q) ? 'domestic' : cc === 'NZ' && nz.test(q) ? 'domestic' : 'all'
  expect(audience('NZ', 'University Entrance (UE) and a rank score of 150')).toBe('domestic')
  expect(audience('NZ', 'NCEA Level 3 with 14 credits in Calculus')).toBe('domestic')
  expect(audience('NZ', 'International students need an equivalent of NCEA Level 3')).toBe('international')
  expect(audience('NZ', 'A portfolio of creative work')).toBe('all')
  expect(audience('AU', 'Applicants with NCEA Level 3 are considered')).toBe('all')  // AU unchanged: the NZ rule applies to NZ pages only
  expect(audience('AU', '2027 Guaranteed ATAR 80')).toBe('domestic')
})
