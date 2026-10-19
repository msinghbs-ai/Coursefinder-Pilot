// CF-247 (S74), 19 Oct 2026. Platform Admin 19:04: "how do we simplify evidence collection ... and store them efficiently without bloating
// the DB"; 20:33: "refresh plan for evidence, plan and execute the next steps".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const worker = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const reuse = fs.readFileSync('supabase/migrations/20261019080000_cf247_reuse_unchanged_pages.sql', 'utf8')
const orphans = fs.readFileSync('supabase/migrations/20261019090000_cf247_orphan_files_list.sql', 'utf8')

test('an unchanged course page keeps the copy in use: no file, no new evidence record; switchable', () => {
  expect(worker).toMatch(/const WORKER = "coverage-sweep-worker-v0\.(3[2-9]|[4-9]\d)\.\d+";/)
  expect(worker).toContain('const normText = (t: string) => String(t || "").replace(/\\s+/g, " ").trim();')
  // both read paths (Firecrawl run items and the direct reader) compare the text hash before storing
  expect(worker.match(/if \(identityBasis && textSha === await rpc\("svc_coverage_text_sha", \{ p_course_id: it\.course_id \}\)\.catch\(\(\) => null\)\) \{ path = null; sha = null \}/g).length).toBe(2)
  expect(worker.match(/\(candidates as Record<string, unknown>\)\.text_sha = textSha;/g).length).toBe(2)
  expect(reuse).toContain("security.pipeline_num_v1('evidence.reuse_unchanged_pages', 1) >= 1")
  expect(reuse).toContain("select pg_temp.edit_once('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)', 'e0437f036b88f3a7231e99d5245c6ffe'")
  expect(reuse).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('files no record names are listed once; nothing is removed by the migration', () => {
  expect(orphans).toContain('create temp table used_paths on commit drop as')
  expect(orphans).toContain("and not (split_part(o.name, '/', 3) = 'adapters' and exists (select 1 from pipeline.uni_adapter_drafts d where d.id::text = split_part(o.name, '/', 5)))")
  expect(orphans).toContain("o.created_at < timestamptz '2026-10-19 00:00:00+00'")
  expect(orphans).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(orphans).not.toMatch(/storage\.objects\s+set|delete\s+from\s+storage/i)
})
