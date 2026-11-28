// Guards: SS-Programme-Control 28 Nov 2026 PC-20261128-DOT-STORAGE-APPROVED (private data-intake bucket, restricted expiring DOT identity, immutable package paths, READY manifest last, existing structured intake writer); CLAUDE.md "A passing qualification never switches anything on by itself", Layer 4 human decisions, no drop or delete by an applied migration, public API errors never carry a raw database message
// CF-247 s1344. supabase/migrations/20261201040000_cf247_s1344_data_intake_dropoff.sql, supabase/functions/dot-intake/index.ts, .github/edge-functions.json
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201040000_cf247_s1344_data_intake_dropoff.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/dot-intake/index.ts', 'utf8')
const edges = JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8')).functions

test('an isolated private bucket, separate from BOOST, with no storage policy; only the service role reaches it', () => {
  expect(sql).toContain("values ('data-intake', 'data-intake', false, 52428800,")
  expect(sql).toContain("raise exception 'post-check: data-intake has a storage policy'")
  expect(fn).toContain('const BUCKET = "data-intake"')
  expect(fn).not.toContain('staging-boost')
  expect(sql).not.toMatch(/create policy/i)
  expect(sql).toContain('revoke all on function public.svc_data_intake_v1(text, jsonb) from public, anon, authenticated;')
  expect(sql).toContain('revoke all on pipeline.data_intake_packages, pipeline.data_intake_files from public, anon, authenticated;')
})

test('identity is narrow and expires: an active, unexpired dot_submitter assignment, decided before the file is read; no one is assigned here', () => {
  expect(sql).toContain("('dot_submitter', 'DOT evidence submitter', 0,")
  expect(sql).toContain('(ur.expires_at is null or ur.expires_at > now())')
  expect(sql).toContain("'held', 'HELD:NOT_DOT_SUBMITTER'")
  expect(sql).toContain("'held', 'HELD:SWITCHED_OFF'")
  expect(sql).not.toMatch(/insert into security\.user_roles/i)
  expect(sql).toContain("raise exception 'post-check: a role was assigned'")
  expect(fn.indexOf('await rpc("gate", {})')).toBeGreaterThan(0)
  expect(fn.indexOf('req.formData()')).toBeGreaterThan(fn.indexOf('await rpc("gate", {})'))
  expect(edges['dot-intake']).toBe(true)
})

test('immutable paths derived by the server; actual bytes, hash, MIME and size checked; no overwrite; a finalised package takes nothing new', () => {
  expect(fn).toContain('const root = `dot/${country}/${provider}/${pkg}/`')
  expect(fn).toContain('const path = `${root}files/${sha}.${ext}`')
  expect(fn).toContain('const mpath = `${root}manifest-${sha}.json`')
  expect(fn).toContain('upsert: false')
  expect(fn).toContain('if (sha !== stated) return json(422, { error: "sha256_mismatch"')
  expect(fn).toContain('if (!MIME[ext] || !MIME[ext].includes(type))')
  expect(fn).toContain('!== "%PDF-"')
  expect(sql).toContain("raise exception 'INVALID_INPUT: package % is finalised (%) and takes no more files'")
  expect(sql).toContain("'files/' || (p_args->>'sha256') || '.' || coalesce(p_args->>'ext', '')")
  expect(sql).toContain('k.iso_alpha2 = v_cc')
  expect(sql).not.toMatch(/\bdelete\s+from\b/i)
})

test('the READY manifest is finalised last: every original recorded, every candidate the package provider, then the existing writer; replay returns the same receipt', () => {
  expect(sql).toContain("'held', 'HELD:MANIFEST_INCOMPLETE'")
  expect(sql).toContain("coalesce(x->>'provider_id', '') <> v_prov::text")
  expect(sql).toContain("public.svc_structured_intake_v1('submit', jsonb_build_object('submitter', 'dot'")
  expect(sql).toContain("return jsonb_build_object('ok', true, 'package', v_pkg, 'status', 'received', 'replay', true, 'receipt', v_p.receipt)")
  expect(sql).toContain("'data_intake_finalise'")
  for (const s of [sql, fn]) expect(s).not.toMatch(/insert into (catalogue|evidence)\.|publication_status\s*=/i)
})

test('errors carry fixed codes; only the platform INVALID_INPUT text is passed on', () => {
  expect(fn).toContain('m.startsWith("INVALID_INPUT:")')
  expect(fn).toContain('{ error: "request_failed" }')
  expect(fn).not.toMatch(/gateErr\.message/)
})
