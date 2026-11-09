// Guards: Website API v2 is additive only (Decisions 257, 258)
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
  expect(edge).toContain('if(contract===V2_CONTRACT) return await handleV2(svc,body,requestId,rateId);')
  expect(edge).toContain('const ACTIONS = ["sync_courses","reference_bundle","lookup","search","scholarships"];')
  expect(edge).toContain('return json(200,{contract_version:CONTRACT_VERSION,source_contract_version:obj.contract_version??null,...obj,request_id:requestId},requestId);')
  // the key is checked before any action, v2 included
  // 15 Oct 2026: the key check returns the key's identity (website_edge_identity_v1) and still happens before any v2 handling
  expect(edge.indexOf('website_edge_identity_v1')).toBeLessThan(edge.indexOf('handleV2(svc,body,requestId,rateId)'))
  expect(edge.indexOf('if(identity!==WIX_CREDENTIAL) return err(401')).toBeGreaterThan(edge.indexOf('handleV2(svc,body,requestId,rateId)'))
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

// R23/R24 (website developer requests; G3 change approved by the Platform Admin 9 Nov 2026): additive-only proof from the migration text and the
// byte-exact live "before" definitions kept with the isolated PostgreSQL fixture. The behaviour proof (end to end as service_role, byte-identical
// apart from the new keys) is tests/fixtures/website-api-v2-r23-r24/run.sh.
const R2324 = 'supabase/migrations/20261109160000_cf247_website_api_v2_r23_r24.sql'
const R2324FX = 'tests/fixtures/website-api-v2-r23-r24/live'
test('R23 provider campuses[] is additive: every existing key and its value expression is kept, exactly three keys are new, nulls mean not held', () => {
  const m = fs.readFileSync(R2324, 'utf8')
  const before = fs.readFileSync(`${R2324FX}/website_v2_provider_campuses.sql`, 'utf8')
  const after = m.slice(m.indexOf('CREATE OR REPLACE FUNCTION api.website_v2_provider_campuses'), m.indexOf('$function$\n$def$'))
  const keys = t => new Set([...t.replace(/^ SET search_path.*$/m, '').matchAll(/'([a-z_][a-z0-9_]*)',\s/g)].map(x => x[1]))
  const b = keys(before), a = keys(after)
  expect([...b].sort()).toEqual(['city', 'metro_area', 'postcode', 'regional_category', 'regional_category_name', 'subdivision_code'])
  for (const k of b) expect(a.has(k), `existing key ${k} is kept`).toBe(true)
  expect([...a].filter(k => !b.has(k)).sort()).toEqual(['campus_id', 'campus_name', 'course_count'])
  // each existing key is built from the same expression as before
  for (const e of ["'city', security.place_presentable(k.city)", "'postcode', k.postcode", "'subdivision_code', s.code", "'metro_area', rc.metro_area",
    "'regional_category', rc.category", "'regional_category_name', rc.category_name"]) { expect(before).toContain(e); expect(after).toContain(e) }
  // same campuses, same joins, same filter; same signature, same search path, still stable SQL
  for (const e of ['left join ref.subdivisions s on s.id = k.subdivision_id', 'left join pipeline.campus_regional_class rc on rc.campus_id = k.id',
    "k.provider_id = p_provider_id and nullif(btrim(k.city),'') is not null and coalesce(k.status,'active') <> 'inactive'",
    "RETURNS jsonb\n LANGUAGE sql\n STABLE\n SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'pipeline', 'security'"]) { expect(before).toContain(e); expect(after).toContain(e) }
  // not held is null (campus_name), never an invented value; an empty provider is still []
  expect(after).toContain("'campus_name', nullif(btrim(k.name),'')")
  expect(after).toContain("'[]'::jsonb")
})

test('R24 scholarship item is additive: the change is a pure insertion of one key after the two lists; every other key and line is untouched', () => {
  const m = fs.readFileSync(R2324, 'utf8')
  const before = fs.readFileSync(`${R2324FX}/website_v2_scholarship_item.sql`, 'utf8')
  const mm = m.match(/array\[\$o\$([\s\S]*?)\$o\$, \$n\$([\s\S]*?)\$n\$\]\]/)
  expect(mm).not.toBeNull()
  const [, o, n] = mm
  expect(before.split(o).length - 1, 'the anchor occurs once in the live definition').toBe(1)
  expect(n.startsWith(o), 'the new text begins with the old text: nothing before the insertion changes').toBe(true)
  const inserted = n.slice(o.length)
  // the insertion adds exactly one key, and it is the only key added
  expect([...inserted.matchAll(/^\s*'([a-z_]+)', case$/gm)].map(x => x[1])).toEqual(['nationality_eligibility_status'])
  // the four values, and an empty list is never read as unrestricted: unrestricted needs an explicit ANY phrase
  for (const v of ["then 'under_review'", "then 'restricted'", "then 'unrestricted'", "else 'unknown' end"]) expect(inserted).toContain(v)
  expect(inserted).toContain("cardinality(nr.codes) = 0 and nr.phrases ? 'ANY'")
  // the edit applies once, to the live text of 5 Nov 2026, and the result is checked by md5
  expect(m).toContain("'d1792cc7161101ce8c22abad70ecbd36', '04532402307717c6dab17567551364e1', array[")
})

test('R23/R24 replace or edit exactly two builders and no wrapper, edge function or table; the other functions of the fixture are pinned to their live text', () => {
  const m = fs.readFileSync(R2324, 'utf8')
  const code = m.replace(/--[^\n]*/g, '')
  const created = [...code.matchAll(/create or replace function ([a-z0-9_.]+)\(/gi)].map(x => x[1].toLowerCase()).sort()
  expect(created).toEqual(['api.website_v2_provider_campuses', 'pg_temp.consumer_drift_v1', 'pg_temp.edit_once', 'pg_temp.replace_once'])
  expect(code).not.toMatch(/create\s+or\s+replace\s+function\s+public\./i)
  expect(code).not.toMatch(/\b(alter|create|drop)\s+(table|view|index|trigger|type)\b|\balter\s+function\b/i)
  const tsv = fs.readFileSync('tests/fixtures/website-api-v2-r23-r24/functions-live.tsv', 'utf8').trim().split('\n').map(l => l.split('\t'))
  expect(tsv.length).toBe(19)
  for (const [sig, md5] of tsv) expect(md5, sig).toMatch(/^[0-9a-f]{32}$/)
  // the wrappers the edge functions call are pinned in the migration (not replaced) and listed as unchanged in the fixture
  for (const w of ['public.website_v2_providers(jsonb,integer,integer,text)', 'public.website_v2_scholarships(jsonb,integer,integer)', 'public.website_v2_scholarship(text)'])
    expect(m).toContain(`('${w}', '`)
})
