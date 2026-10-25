// Guards: CF-247 (S58) 18 Oct 2026: Providers › Logos & assets kept; the earlier logo-discovery leftovers retired (Platform Admin 12:43).
// CF-247 (S58) 18 Oct 2026: Providers › Logos & assets kept; the earlier logo-discovery leftovers retired (Platform Admin 12:43).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261018060000_cf247_logo_screen_cleanup.sql', 'utf8')
const fnBody = mig.slice(mig.indexOf('CREATE OR REPLACE FUNCTION security.admin_provider_asset_read'), mig.indexOf('$function$;') )

test('the logo screen read is guarded and no longer reads the retired candidates', () => {
  expect(mig).toContain("<> 'c7f5f096a9bb09eddb91beef4540bc14' then")
  expect(fnBody).not.toContain('provider_asset_candidates')
  expect(fnBody).not.toContain("'provider_asset_context'")
  for (const k of ["'expected'", "'approved'", "'missing'", "'total'", "'items'", 'primary_mime_type', 'primary_verified_at', 'coverage_state', 'provider_name', 'country_code']) expect(fnBody).toContain(k)
})

test('retired pieces are marked retiring, not dropped; the website logo is untouched', () => {
  expect(mig).toMatch(/-- Retires: pipeline\.provider_asset_candidates; public\.layer2_hotcourses_directory_apply/)
  expect(mig).not.toMatch(/^(delete|drop|truncate)\b/im)
  const code = mig.split('\n').filter(l => !l.trim().startsWith('--')).join('\n')
  expect(code).not.toMatch(/website_v2_provider_logo|catalogue\.provider_assets\s+(set|add|drop)/i)
})

test('the screen still uses only the kept fields', () => {
  const ui = fs.readFileSync('src/mature-main.jsx', 'utf8')
  const ws = ui.slice(ui.indexOf('function ProviderAssetsWorkspace'), ui.indexOf('function RankingImportPanel'))
  const used = [...new Set([...ws.matchAll(/\br\.([a-z_]+)/g)].map(m => m[1]))].sort()
  expect(used).toEqual(['country_code', 'coverage_state', 'primary_mime_type', 'primary_verified_at', 'provider_id', 'provider_name'])
})
