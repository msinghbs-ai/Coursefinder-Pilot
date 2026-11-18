// Guards: feed stored pages to Boost (Platform Admin 18 Nov 2026 10:12): stored course-page copies of active courses still lacking a study load or a description become the plain-text pages Boost reads, in Boost priority-matrix order, each copy once, with no Firecrawl and no AI; sizes are settings; the job is catalogued; nothing is written to the catalogue
// CF-247 S619. Migration 20261118113000_cf247_page_text_feed_for_boost.sql; coverage-sweep worker v1.0.15 mode page_text.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations-archive/20261118113000_cf247_page_text_feed_for_boost.sql', 'utf8')
const IX = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8')
const block = IX.slice(IX.indexOf('if (mode === "page_text") {'), IX.indexOf('return j({ ok: false, error: "supported modes: '))

test('the queue: bound, read, stored copies of active courses lacking a study load or a description, in Boost matrix order, each copy once', () => {
  expect(M).toContain("join pipeline.evidence_artifacts e on e.id = cp.evidence_id and e.evidence_type = 'source_snapshot' and e.storage_path is not null")
  expect(M).toContain("where cp.status = 'bound' and cp.read_status = 'read'")
  expect(M).toContain("and (c.study_load is null or nullif(btrim(c.description), '') is null)")
  expect(M).toContain("from security.boost_country_category_matrix_v1() m")
  expect(M).toContain("order by mx.weight desc, csort, cp.course_id")
  expect(M).toContain("x.outcome in ('done', 'too_short')")
  expect(M).toContain("t.metadata->>'derived_from_evidence_id' = e.id::text")
  expect(M).toContain("not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)")
})

test('the record: evidence provider_course_page_text derived from the copy, never a catalogue value', () => {
  expect(M).toContain("'provider_course_page_text', e.source_url, p_storage_path, p_content_hash, 'text/plain'")
  expect(M).toContain("jsonb_build_object('derived_from_evidence_id', p_source_evidence_id")
  expect(M).not.toMatch(/update catalogue\.|insert into catalogue\./i)
  expect(M).toContain("comment on table pipeline.page_text_conversions is")
  expect(M).toMatch(/-- Replaces: .+\n-- Retires: nothing\./)
  expect(M).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

test('job, settings and worker: catalogued, sized by settings, no Firecrawl and no AI in the mode', () => {
  expect(M).toContain("('page-text', 'Coverage sweep', 395, 'Page text for Boost',")
  expect(M).toContain("security.pipeline_num_v1(''batch.page_text'', 40)::int")
  expect(M).toContain("'page_text.min_chars'")
  expect(IX).toContain('const WORKER = "coverage-sweep-worker-v1.0.24"')  // v1.0.24 from s721  // v1.0.19 from s674
  expect(block).toContain('rpc("svc_page_text_next_v1"')
  expect(block).toContain('htmlToText(await readEvidenceCopy(c, String(it.storage_path)))')
  expect(block).toContain('const path = `coverage-text/${it.course_id}/${hash.slice(0, 32)}.txt`;')
  expect(block).not.toMatch(/cascadeFetch|fcx\.|useFc\(|openrouter/i)
})
