// Guards: Platform Admin 19 Nov 2026 16:23 AEDT (chat S1-Build, s780; P1, refs 3A9WTT and 3UD5A2): Provider details opens for every StudySearch role. Both references were public.admin_read('provider_detail') (api.providerDetail and providerRelated in src/lib/supabase.js), refused with "permission denied for schema catalogue" for Curator and above since Pilot #1329 (a18020c8, migration 20261119045000) put a direct catalogue read into public.admin_read, which runs as the signed-in user. The read is now security.provider_accreditations_admin_v1 (security definer), and no public function the signed-in role can run may read schema catalogue as the caller.
// The live rolled-back dry run (label live-dry-run) runs admin_read('provider_detail') as the signed-in role with the Platform Admin's identity before the fix (refused) and after it (allowed, every accreditation returned).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import path from 'node:path'
import { migrationPath } from './support/migration-files.mjs'

const m = fs.readFileSync(migrationPath('20261119173500_cf247_s780_provider_detail_access.sql'), 'utf8')
const c = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
const supa = fs.readFileSync('src/lib/supabase.js', 'utf8')

test('the provider_detail branch reads accreditations through a security definer helper; admin_read is otherwise unchanged', () => {
  expect(c).toContain("select pg_temp.cf_edit_def('public.admin_read(text,jsonb)'::regprocedure, 'f10a3e3340943e304dafb2793eb07acc',")
  expect(c).toContain("||jsonb_build_object('accreditations',security.provider_accreditations_admin_v1(v_id));end if;$n$]);")
  const helper = c.slice(c.indexOf('create or replace function security.provider_accreditations_admin_v1('), c.indexOf('$function$;', c.indexOf('create or replace function security.provider_accreditations_admin_v1(')))
  expect(helper).toContain(' stable security definer')
  expect(helper).toContain("set search_path to ''")
  expect(helper).toContain('if coalesce(security.current_role_rank(), 0) >= 3 then')
  expect(helper).toContain('return security.provider_accreditations_v3_v1(p_provider_id);')
  expect(c).toContain('revoke all on function security.provider_accreditations_admin_v1(uuid) from public, anon;')
  expect(c).toContain('grant execute on function security.provider_accreditations_admin_v1(uuid) to authenticated, service_role;')
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: nothing/m)
  expect(c).not.toMatch(/\b(drop|truncate|delete\s+from|alter\s+table|create\s+(unique\s+)?index)\b/i)
  expect(c).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_/)
})

test('the dry run reproduces the refusal and proves the Platform Admin is allowed, as the signed-in role', () => {
  expect(c).toContain("execute 'set local role authenticated';")
  expect(c).toContain("pg_temp.cf_as_user('63ba56cb-48d4-4169-98c2-7c4d1f72925b',")
  expect(c).toContain("raise exception 'post-check: Provider details still fails for the Platform Admin: %'")
  expect(c).toContain("raise exception 'post-check: % public function(s) run as the caller and read schema catalogue'")
  expect(c).toContain("raise exception 'post-check: public.admin_read must stay security invoker'")
})

test('both reads behind 3A9WTT and 3UD5A2 are admin_read provider_detail', () => {
  expect(supa).toContain("const detail = await adminRead('provider_detail', { id: providerId })")
  expect(supa).toContain("providerDetail: providerId => adminRead('provider_detail', { id: providerId }),")
})

test('no later migration puts a catalogue read back into public.admin_read', () => {
  const dir = path.dirname(migrationPath('20261119173500_cf247_s780_provider_detail_access.sql'))
  for (const f of fs.readdirSync(dir).filter((x) => /^\d{14}_.*\.sql$/.test(x) && x.slice(0, 14) > '20261119173500')) {
    const s = fs.readFileSync(path.join(dir, f), 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')
    if (!/public\.admin_read\(/.test(s)) continue
    // the text a later change puts into public.admin_read: new fragments ($n$ ... $n$) or a whole new definition
    const added = [...s.matchAll(/\$n\$([\s\S]*?)\$n\$/g)].map((x) => x[1]).join('\n')
      + [...s.matchAll(/create or replace function public\.admin_read\([\s\S]*?\$function\$;/gi)].map((x) => x[0]).join('\n')
    expect(added, f).not.toMatch(/\b(from|join)\s+catalogue\./i)
  }
})
