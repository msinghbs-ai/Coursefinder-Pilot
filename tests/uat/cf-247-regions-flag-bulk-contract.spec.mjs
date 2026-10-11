// Decision 219: New Zealand regions and a country-named state filter; bulk decisions on flagged values.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('migration: NZ regions (ISO 3166-2:NZ), town mapping only where no region is held, bulk flag decisions', () => {
  const m = fs.readFileSync('supabase/migrations-archive/20261002181700_cf247_nz_regions_flag_bulk.sql', 'utf8')
  for (const c of ['NZ-AUK', 'NZ-BOP', 'NZ-CAN', 'NZ-GIS', 'NZ-HKB', 'NZ-MWT', 'NZ-MBH', 'NZ-NSN', 'NZ-NTL', 'NZ-OTA', 'NZ-STL', 'NZ-TKI', 'NZ-TAS', 'NZ-WKO', 'NZ-WGN', 'NZ-WTC', 'NZ-CIT']) expect(m).toContain(`'${c}'`)
  expect(m).toContain("and k.iso_alpha2 = 'NZ' and p.subdivision_id is null")
  expect(m).not.toContain("('frankton',")
  expect(m).toContain("if p_action not in ('confirm', 'whole_course', 'remove') then")
  expect(m).toContain("if f.id is null or f.status <> 'open' then v_skipped := v_skipped + 1; continue; end if;")
  expect(m).toContain('grant execute on function public.admin_data_flag_resolve_bulk(uuid[], text, jsonb) to authenticated;')
})

test('the state filter is named the way each country names its divisions', () => {
  const s = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(s).toContain("AU:'State / territory',CA:'Province / territory',NZ:'Region'")
  expect(s).toContain('<PagedFilterSelect kind="subdivision" label={regionLabel(filters.country)}')
  expect(s).not.toContain('label="State / Region"')
})

// v2.15.253 (Platform Admin, 12 Oct 2026): Layer 4 › Flagged values retired (open flags closed); its bulk browser check went with it.
test('platform guide covers regions; Flagged values is retired', () => {
  const g = fs.readFileSync('src/guide/platformGuide.js', 'utf8')
  expect(g).toContain('province or territory (Canada) or region (New Zealand)')
  expect(g).not.toContain('Flagged values in bulk')
})
