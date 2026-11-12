// Guards: E16 course-page identity (Platform Admin 12 Nov 2026 20:57, course-page identity for Adelaide and Southern Cross): the identity check reads the stored page under its trailing-slash variant or the same path on the provider's own hosts only; every identity rule is unchanged.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261113181000_cf247_e16_title_lookup_own_hosts.sql', 'utf8')

test('the variants: the address with and without its slash, and the same path on the provider\'s own hosts only', () => {
  const fn = mig.slice(mig.indexOf('create or replace function security.course_page_url_variants_v1'), mig.indexOf('comment on function security.course_page_url_variants_v1'))
  expect(fn).toContain("select rtrim(p_url, '/') b")
  expect(fn).toContain("unnest(array[b, b || '/'])")
  // another host is used only when the course address is itself on one of the provider's own hosts
  expect(fn).toContain('where u.host <> \'\' and exists (select 1 from own o2 where o2.h = u.host)')
  expect(fn).toContain("security.toolset_setting('pipeline', 'binding.provider_host_aliases')")
  expect(fn).toContain('pipeline.provider_extra_domains d where d.provider_id = p_provider')
  expect(fn).toContain('stable security definer set search_path = \'\'')
})

test('two md5-guarded edits: the title lookup (same provider) and the identity-proof lookup (same course); the result md5 is checked', () => {
  expect(mig).toContain("pg_temp.edit_all('security.course_page_check_v1(uuid,text,text,text)', 'f6d135b669c6a1d64533d691080a708e', '554d95af03219a28a2b7274914a46af6'")
  expect(mig).toContain("or g.url = any (security.course_page_url_variants_v1(c.provider_id, p_url))) and g.read_status = 'read'")
  expect(mig).toContain("where g.course_id = t.id and (g.url = p_url or g.candidates->>'final_url' = p_url\n                                                        or g.url = any (security.course_page_url_variants_v1(t.provider_id, p_url)))")
  expect(mig).toContain("if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)'")
  expect(mig).toMatch(/<> '554d95af03219a28a2b7274914a46af6' then\s+raise exception 'post-check/)
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(mig).toMatch(/^-- Replaces: security\.course_page_check_v1/m)
  expect(mig).toMatch(/^-- Retires: nothing/m)
})

test('the intake wording lookup (same course) also reads the page under its variants, and the variants are taken once per call; md5-guarded', () => {
  const w = fs.readFileSync('supabase/migrations/20261113182000_cf247_intake_wording_url_variants.sql', 'utf8')
  expect(w).toContain("pg_temp.edit_all('security.intake_page_wording_v1(uuid,uuid,text)', 'daa96acbe87de1cf0a2bec523a911c7a', 'eb380f591dc17bf536c94d999f4f1b26'")
  // speed: the variants come once per call from the function's own arguments, never per scanned page
  const once = "or g.url = any ((select security.course_page_url_variants_v1(co.provider_id, p_url) from catalogue.courses co where co.id = p_course)::text[]))"
  expect(w.split(once).length - 1).toBe(3)
  expect(w).toContain("pg_temp.edit_all('security.course_page_check_v1(uuid,text,text,text)', '554d95af03219a28a2b7274914a46af6', '38c776ca90378d866167390f7d40d42b'")
  expect(w).toMatch(/^-- Replaces: security\.intake_page_wording_v1/m)
  expect(w).toMatch(/^-- Retires: nothing/m)
  expect(w).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})
