// Guards: REQ-68 (no destination edition is published unless terms_status is approved) and REQ-65/67 destination importer (Platform Admin 15 Nov 2026 23:04, combined build item 4)
// Behaviour is proven on isolated PostgreSQL by tests/fixtures/destination-editions/run.sh (workflow destination-editions-test); these checks keep the rules in the migration.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations-archive/20261115230000_cf247_destination_importer_guard.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('the guard refuses every route to published without approved terms', () => {
  expect(code).toContain("if new.status = 'published' and new.terms_status is distinct from 'approved' then")
  expect(code).toContain('create trigger destination_edition_guard before insert or update on destination.editions')
  expect(code).not.toMatch(/^\s*drop\b/m)
  expect(code).toContain("if v.terms_status is distinct from 'approved' then")
  // taking terms away from a published edition takes it off in the same write
  expect(code).toContain("status = case when x.status = 'published' and p_terms <> 'approved' then 'in_review' else x.status end")
})

test('an import never approves terms and never publishes; fixed editions are refused', () => {
  expect(code).toContain("if v_terms not in ('pending', 'restricted') then")
  expect(code).toContain("values (v_country, v_domain, v_label, (e->>'effective_from')::date, nullif(e->>'effective_to', '')::date, 'draft',")
  expect(code).toContain("if v_ed.status in ('published', 'superseded') then")
  expect(code).not.toMatch(/destination_import_v1[\s\S]*status = 'published'[\s\S]*end \$\$;\s*-- 5\./)
})

test('rows are written only when changed, keyed on the tables’ own unique keys; published rows are fixed', () => {
  for (const k of ['on conflict (edition_id, country_id, visa_subclass) do update', 'on conflict (edition_id, city_id) do update', 'on conflict (edition_id, country_id, occupation_code) do update']) expect(code).toContain(k)
  expect((code.match(/is distinct from/g) || []).length).toBeGreaterThanOrEqual(4)
  expect(code).toContain("DESTINATION_EDITION_FIXED")
  expect(code).toContain('create unique index if not exists uq_destination_editions_label on destination.editions (country_id, domain, edition_label)')
})

test('one published edition per country and domain: the old one is superseded first; only the service role can write', () => {
  expect(code.indexOf("update destination.editions x set status = 'superseded'")).toBeLessThan(code.indexOf("update destination.editions x set status = 'published'"))
  for (const f of ['destination_import_v1(jsonb)', 'destination_edition_set_terms_v1(uuid, text, uuid)', 'destination_edition_publish_v1(uuid, uuid)']) {
    expect(code).toContain(`revoke all on function security.${f} from public, anon, authenticated;`)
    expect(code).toContain(`grant execute on function security.${f} to service_role;`)
  }
  expect(fs.readFileSync('tests/fixtures/destination-editions/run.sh', 'utf8')).toContain('REQ-68: a direct write cannot publish with pending terms')
})
