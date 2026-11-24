// Guards: Platform Admin 24 Nov 2026 17:14 AEDT (Item 2 approved: register and read the official university URLs; 2027 fee lists through the fee reader, the universities' published English equivalence tables to their courses, GPA thresholds read with their stated scale)
// s1053: official sources registered and fetched under one on-demand request; English equivalence tables applied insert only; "on a N scale" read.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261125040000_cf247_s1053_item2_official_sources.sql', 'utf8')
const fnStart = MIG.indexOf('CREATE OR REPLACE FUNCTION security.provider_english_concordance_apply_v1')
const fn = MIG.slice(fnStart, MIG.indexOf('$function$;', fnStart))

test('s1053: the official pages are registered as a person registers them, logged with the approval, and fetched under one on-demand request', () => {
  for (const u of ['2027-international-student-guide.pdf', '2027-Undergraduate-International-Course-Fee-List.pdf', '2027-Postgraduate-International-Course-Fee-List.pdf', 'English-Language-Proficiency-Procedure.pdf']) expect(MIG).toContain(u)
  expect(MIG).toContain("values (r.provider_id, r.kind, r.url, null, 9, 'manual', 'found')")
  expect(MIG).toContain("'approved_by', v_approval")
  expect(MIG).toContain("perform security.on_demand_open_v1('claude_session', v_reason, v_ids, v_est, null, array['firecrawl'])")
  expect(MIG).toContain("perform security.on_demand_scope_v1(v_id, array['central'])")
  expect(MIG).toContain('insert into pipeline.elr_central_fetches(fact_source_id, provider_id, url, status)')
  expect(MIG).not.toMatch(/insert into catalogue\.course_fees|update catalogue\.course_fees/i)
})

test('s1053: equivalence rows are insert only, four section scores, from the stored table page, not for regulated disciplines, logged', () => {
  expect(fn).toContain("if v_ev is null then return jsonb_build_object('skipped', 'the table''s page is not stored yet'")
  expect(fn).toContain('on conflict (course_id, english_test_id) do nothing')
  expect(fn).toContain("where not exists (select 1 from catalogue.course_english_requirements o where o.course_id = i.course_id and o.english_test_id = t.id and o.status = 'active')")
  expect(fn).toContain("where k in ('listening', 'reading', 'writing', 'speaking')) = 4")
  expect(fn).toContain("where k in ('listening', 'reading', 'writing', 'speaking')) = 1")
  expect(fn).toMatch(/canonical_title !~\* '\(nurs\|midwi\|medic/)
  expect(fn).toContain("'concordance:' || v_src || ':' || lower(co.test_code)")
  expect(fn).toContain('insert into pipeline.admin_control_events')
  expect(fn).not.toMatch(/update catalogue\.course_english_requirements|delete from/i)
  expect(MIG).toContain('create or replace trigger english_concordance_on_store after update of status on pipeline.elr_central_fetches')
  expect(MIG).toContain("exception when others then")
})

test('s1053: the published tables are loaded as written (Adelaide and Newcastle, 30 rows)', () => {
  expect(MIG).toContain("6.5, 'TOEFL_IBT', 79, '{\"speaking\": 20, \"reading\": 19, \"listening\": 20, \"writing\": 24}'")
  expect(MIG).toContain("6.5, 'PTE', 64,")
  expect(MIG).toContain("6.5, 'TOEFL_IBT', 85, '{\"reading\": 19, \"listening\": 20, \"speaking\": 20, \"writing\": 24}'")
  expect(MIG).toContain("6.0, 'PTE', 52,")
  expect(MIG).toContain("raise exception 'post-check: the equivalence tables did not load (30 rows expected)'")
})

test('s1053: a stated scale "on a 7.0 scale" is read; no scale is invented; only a threshold within its scale is admitted', () => {
  expect(MIG).toContain("'\\mon an?\\s+([0-9]+(?:\\.[0-9]+)?)(?:[ -]point)?\\s+(?:GPA\\s+)?scale\\M'")
  expect(MIG).toContain("raise exception 'post-check: a scale was read where none is stated'")
  expect(MIG).toContain('and (g.threshold is null or g.threshold <= security.gpa_scale_of_v1(null, c.human_text))')
  expect(MIG).toContain('"4.5 / 7 GPA in an eligible qualification (for postgraduate students)"')
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)|truncate |cron\.schedule/i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
