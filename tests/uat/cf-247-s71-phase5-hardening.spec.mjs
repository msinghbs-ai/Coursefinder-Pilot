// CF-247 (S71) Phase 5, 19 Oct 2026 (Platform Admin 09:29 "Phase 5: hardening, plus retiring the leftovers"; "keep in mind the Consumer
// API wont get affected").
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const mig = fs.readFileSync('supabase/migrations/20261019030000_cf247_phase5_hardening.sql', 'utf8')
const code = mig.split('\n').filter(l => !l.trim().startsWith('--')).join('\n')
const retired = fs.readFileSync('.github/workflows/deploy-edge-functions.yml', 'utf8')

test('the hardening never alters a consumer API object (Decision 266)', () => {
  for (const c of ['website_v2_', 'website_edge_', 'website_api_v2_', 'zoho_edge_', 'svc_website_settings_v1', 'api.',
                   'provider_presentable_name', 'place_presentable']) {
    expect(code.includes(c), c).toBe(false)
  }
  // grants on existing objects change only for the two scholarship-AI wrappers
  expect(code.match(/^revoke .+$/gm)).toEqual([
    'revoke execute on function public.scholarship_ai_control_read(text) from anon;',
    'revoke execute on function public.scholarship_ai_run_create(text,text,uuid,integer,text,boolean) from anon;'])
  // before and after, the live consumer API check must report no drift
  expect(code.match(/security\.consumer_api_check_v1\(\) -> 'drift'/g).length).toBe(2)
})

test('defaults in public stop opening new objects to anon; search_path fixed on the reviewed 32', () => {
  for (const k of ['functions', 'tables', 'sequences']) expect(code).toMatch(new RegExp(`alter default privileges for role postgres in schema public revoke \\w+ on ${k} from anon;`))
  expect(code).toContain("set search_path = public, extensions")
  expect(code).toContain('if v_n <> 32')
  expect(code).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('the 18 retired edge functions are recorded and on the deploy workflow retired list, with no source', () => {
  const names = [...code.matchAll(/\('edge_function', '([a-z0-9-]+)'/g)].map(m => m[1])
  expect(names.length).toBe(18)
  for (const n of names) {
    expect(retired.includes(` ${n} `), n).toBe(true)
    expect(fs.existsSync(`supabase/functions/${n}`), n).toBe(false)
  }
})
