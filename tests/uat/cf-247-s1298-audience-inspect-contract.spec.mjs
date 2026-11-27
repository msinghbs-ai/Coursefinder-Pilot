// Guards: design coursefinder-admin #1271 Phase B, SS-Programme-Control 27 Nov 2026 12:08 (s1298): stored course pages are inspected for audience and identity read only (no model, no fetch, no write), through a service-role path function limited to 20 courses and a read-only workflow.
// CF-247 S1298. supabase/functions/coverage-sweep/audience.ts, supabase/migrations/20261130141500_cf247_s1298_audience_inspect_paths.sql, scripts/audience-inspect.mjs
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mod = fs.readFileSync('supabase/functions/coverage-sweep/audience.ts', 'utf8')
const idx = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const sql = fs.readFileSync('supabase/migrations/20261130141500_cf247_s1298_audience_inspect_paths.sql', 'utf8')
const wf = fs.readFileSync('.github/workflows/audience-inspect.yml', 'utf8')

test('the audience signals are deterministic and read only', () => {
  expect(mod).toContain('export function audienceSignals(html: string, courseCode: string | null): AudienceSignals')
  expect(mod).not.toMatch(/fetch\(|openrouter|\.upload\(|\.insert\(/i)
  const block = idx.slice(idx.indexOf('if (mode === "audience_inspect")'), idx.indexOf('if (mode === "page_text")'))
  expect(block).toContain('rpc("svc_audience_inspect_paths_v1"')
  expect(block).toContain('readEvidenceCopy(c, String(r.storage_path))')
  expect(block).not.toMatch(/fetchPage|firecrawl|cascadeFetch|\.upload\(|svc_[a-z_]*record/i)
})

test('the path function is service role only and bounded', () => {
  expect(sql).toContain("if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;")
  expect(sql).toContain('where c.id = any(p_course_ids[1:20]));')
  expect(sql).toContain('grant execute on function public.svc_audience_inspect_paths_v1(uuid[]) to service_role;')
  expect(wf).toContain('node scripts/audience-inspect.mjs')
  expect(wf).toContain('contents: read')
})
