// Guards: Platform Admin direction PC-20261128-DOT-DROPBOX-POC (one temporary high-entropy upload capability URL on the existing endpoint, one package, expiry, revocation, bounded size, no list/read/overwrite/delete, no new connector, account or bucket); CLAUDE.md no drop or delete by an applied migration, public API errors never carry a raw database message
// CF-247 s1351. supabase/migrations/20261201090000_cf247_s1351_dot_dropbox_capability.sql, supabase/functions/dot-intake/index.ts
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261201090000_cf247_s1351_dot_dropbox_capability.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/dot-intake/index.ts', 'utf8')

test('a 256-bit token, kept only as its SHA-256, for one package, with expiry, revocation and a file ceiling; issued only by the Platform Admin', () => {
  expect(sql).toContain("v_token := 'dic_' || encode(extensions.gen_random_bytes(32), 'hex');")
  expect(sql).toContain("values (encode(extensions.digest(v_token, 'sha256'), 'hex'), upper(p_country), p_provider_id, p_package,")
  expect(sql).toContain("security.current_role_rank() >= 6")
  expect(sql).toContain("'data_intake.capability_max_hours'")
  expect(sql).toContain("'data_intake.capability_max_bytes'")
  expect(sql).toContain("revoked_at timestamptz")
  expect(sql).toContain("'data_intake_capability_issued'")
  expect(sql).toContain("'data_intake_capability_revoked'")
  expect(sql).toContain("revoke all on pipeline.data_intake_capabilities from public, anon, authenticated;")
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('the capability replaces identity and scope in the existing gate; an unknown, expired or revoked token is refused before anything is read', () => {
  expect(sql).toContain("c.token_sha256 = lower(coalesce(p_args->>'capability_sha256', '')) and c.revoked_at is null and c.expires_at > now()")
  expect(sql).toContain("'held', 'HELD:CAPABILITY_INVALID'")
  expect(sql).toContain("p_args := p_args || jsonb_build_object('country', v_cap.country, 'provider_id', v_cap.provider_id, 'package', v_cap.package);")
  expect(sql).toContain("md5(pg_get_functiondef('public.svc_data_intake_v1(text,jsonb)'::regprocedure)) <> 'b85d57dadca46e6a826c261fb9caf266'")
  expect(fn).toContain('if (!/^dic_[0-9a-f]{64}$/.test(cap)) return json(401, { error: "invalid_capability" });')
  expect(fn.indexOf('await rpc("gate", {})')).toBeLessThan(fn.indexOf('await req.arrayBuffer()'))
  expect(fn).toContain('const country = String(scope.country || field.get("country")')
})

test('the same endpoint, bucket, immutable paths and writer: no new connector, account or bucket', () => {
  expect(fn).toContain('const BUCKET = "data-intake"')
  expect(fn).toContain('upsert: false')
  expect(sql).not.toMatch(/insert into storage\.buckets|auth\.users|create policy/i)
})
