// Guards: CRICOS 11 Nov 2026 edition apply timeout (Platform Admin 17 Nov 2026 14:30): Layer 1 register apply calls take their size from setting layer1.register_apply_chunk, so each call stays within the 8-second service statement limit
// CF-247 S573. Migration 20261117150000_cf247_layer1_register_apply_chunk.sql; layer1-au-depth v1.9.0; layer1-nz-live v1.4.0.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261117150000_cf247_layer1_register_apply_chunk.sql', 'utf8')
const au = fs.readFileSync('supabase/functions/layer1-au-depth/index.ts', 'utf8')
const nz = fs.readFileSync('supabase/functions/layer1-nz-live/index.ts', 'utf8')

test('the setting exists with a range, a unit and its users, and a service-only reader gives it to the workers', () => {
  expect(mig).toContain("('pipeline', 'layer1.register_apply_chunk', 'Layer 1 register: records per apply call',")
  expect(mig).toContain("'number', to_jsonb(50), 10, 250, 'records'")
  expect(mig).toContain("where s.toolset_key = 'pipeline' and s.key like 'layer1.%'")
  expect(mig).toContain('grant execute on function public.svc_layer1_register_settings_v1() to service_role;')
  expect(mig).toContain('revoke all on function public.svc_layer1_register_settings_v1() from public, anon, authenticated;')
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

for (const [name, src, scheme] of [['layer1-au-depth', au, 'cricos'], ['layer1-nz-live', nz, 'nzqa']]) {
  test(`${name}: every register apply call takes its size from the setting`, () => {
    expect(src).toContain('const s=await rpc(service,"svc_layer1_register_settings_v1",{});const n=Math.floor(Number(s?.["layer1.register_apply_chunk"]))')
    const calls = [...src.matchAll(/svc_layer1_apply_register_records",\{[^}]*\}/g)].map((m) => m[0])
    expect(calls.length).toBe(1)
    expect(calls[0]).toContain(`p_registration_scheme:"${scheme}"`)
    expect(calls[0]).toContain('.slice(i,i+chunk)')
    expect(src).toContain('const chunk=await applyChunk(service);for(let i=0;')
  })
}
