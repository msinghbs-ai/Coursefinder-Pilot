import { test, expect } from '@playwright/test'
import fs from 'node:fs'

test('Layer 2 Adapter builder tab is wired to its read function and the existing write functions', () => {
  const nav = fs.readFileSync('src/nav-map.js', 'utf8')
  expect(nav).toContain("{ key: 'builder', label: 'Adapter builder', min: 5 }")
  expect(nav).toContain("{ key: 'adapters', label: 'Adapters', min: 5 }")
  const main = fs.readFileSync('src/mature-main.jsx', 'utf8')
  expect(main).toContain("if(tab==='builder')return <AdapterBuilderTab rank={rank} onError={err}/>")
  const ui = fs.readFileSync('src/AdapterBuilderTab.jsx', 'utf8')
  expect(ui).toContain("supabase.rpc('admin_adapter_builder_basics'")
  expect(ui).toContain("supabase.rpc('admin_provider_central_page'")
  expect(ui).toContain('<AdapterEditor key={key} providerId={b.provider_id} hideReview onError={onError}/>')
  expect(ui).toContain('<AdapterReview providerId={b.provider_id}')
  const sql = fs.readFileSync('supabase/migrations/20261007001600_cf247_adapter_builder_tab.sql', 'utf8')
  expect(sql).toContain('coalesce(v_rank, 0) < 5')
  expect(sql).toContain('da0b0eae7ad2566bc09efa0a90356102')
  expect(sql).toContain("revoke all on function public.admin_adapter_builder_basics(text, jsonb) from public, anon")
})
