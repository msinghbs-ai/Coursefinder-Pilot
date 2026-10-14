// CF-247 Website API v2 (website-search-v2), Decision 257. Live on Pilot since 8 Oct 2026, extended 14 Oct 2026.
// The nine 8 Oct migrations were applied live before the 10 Oct baseline (which holds their objects) and are kept in the
// archive, byte-identical to the live migration history. The 14 Oct changes are normal migrations after the baseline. This file guards the contract: opt-in on the same key, v1 untouched, service-only functions, signed
// logos, the provider Published switch, display codes and QILT at provider grain only.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = 'supabase/migrations'
const A = 'supabase/migrations-archive'
const at = f => (f.startsWith('20261008') ? A : M)
const read = f => fs.readFileSync(`${at(f)}/${f}`, 'utf8')
const edge = fs.readFileSync('supabase/functions/wix-course-api/index.ts', 'utf8')
const files = [
  '20261008032403_cf247_website_gates_manual_entry_and_canada.sql',
  '20261008032806_cf247_website_v2_helpers.sql',
  '20261008032949_cf247_website_v2_courses.sql',
  '20261008033043_cf247_website_v2_tuition_zero_not_a_price.sql',
  '20261008033254_cf247_website_v2_fee_performance.sql',
  '20261008033450_cf247_website_v2_fee_inline.sql',
  '20261008033739_cf247_website_v2_providers_rankings_reference.sql',
  '20261008034048_cf247_website_v2_scholarships.sql',
  '20261008034140_cf247_website_v2_scholarship_areas_from_courses.sql',
  '20261014032122_cf247_website_v2_course_display_code.sql',
  '20261014034927_cf247_website_v2_course_publication_follows_provider.sql',
  '20261014040646_cf247_website_v2_qilt_admitted.sql',
]

test('every v2 migration is checked in and drops or deletes nothing', () => {
  for (const f of files) {
    expect(fs.existsSync(`${at(f)}/${f}`), f).toBe(true)
    expect(read(f), f).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  }
})

test('edge function: v2 is opt-in on the same key and v1 is untouched', () => {
  expect(edge).toContain('const V2_CONTRACT = "website-search-v2";')
  // v2.15.277 adds "sync" at the end (additive); every earlier action stays
  expect(edge).toContain('const V2_ACTIONS = ["reference","search","course","providers","provider","rankings","scholarships","scholarship","sync"];')
  expect(edge).toContain('if(contract===V2_CONTRACT) return await handleV2(svc,body,requestId);')
  expect(edge).toContain('const ACTIONS = ["sync_courses","reference_bundle","lookup","search","scholarships"];')
  expect(edge).toContain('return json(200,{contract_version:CONTRACT_VERSION,source_contract_version:obj.contract_version??null,...obj,request_id:requestId},requestId);')
  // the key is checked before any action, v2 included
  expect(edge.indexOf('website_edge_auth_v1')).toBeLessThan(edge.indexOf('handleV2(svc,body,requestId)'))
})

test('edge function: logos leave the private bucket only as short-lived signed links', () => {
  expect(edge).toContain('const LOGO_BUCKET = "provider-assets";')
  expect(edge).toContain('createSignedUrls(paths,LOGO_TTL_SECONDS)')
  expect(edge).toContain('delete l.storage_path;')
  expect(edge).toContain('if(e && e.code==="NOT_FOUND") return err(404,"NOT_FOUND",requestId);')
})

test('database functions: service role only', () => {
  const all = files.map(read).join('\n')
  for (const fn of ['website_v2_course_search(jsonb, integer, integer, text)', 'website_v2_course(text)', 'website_v2_scholarships(jsonb, integer, integer)', 'website_v2_scholarship(text)']) {
    expect(all).toContain(`revoke all on function public.${fn} from public, anon, authenticated;`)
    expect(all).toContain(`grant execute on function public.${fn} to service_role;`)
  }
})

test('14 Oct: display code, course status follows the provider switch, QILT at provider grain only', () => {
  const code = read(files[9]), pub = read(files[10]), qilt = read(files[11])
  expect(code).toContain("'display_code', security.course_display_code_v1(d.course_id)->>'code',")
  expect(code).toContain("i.scheme = 'studysearch'")
  expect(pub).toContain("security.provider_hidden_v1")
  expect(pub).toContain("then 'unpublished' else 'published' end")
  expect(qilt).toContain("'courses', 'provider_outcomes', 'approved'")
  expect(qilt).toContain("left(sv.code, 5) = 'qilt_'")
  // the course-grain gate is never opened here
  expect(qilt).not.toMatch(/domain_code\s*=\s*'qilt'|'qilt',\s*'approved'/)
  // each change is guarded by the md5 of the live definition it replaces
  for (const s of [code, pub, qilt]) expect(s).toMatch(/if md5\(v\) <> '[0-9a-f]{32}' then raise exception/)
})
