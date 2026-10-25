// Guards: CF-247 Track C, entry requirements step A (s111): tables, settings, Layer 4 first-run routing, the inactive job, and the declared file boundary (Platform Admin 25 Oct 2026…
// CF-247 Track C, entry requirements step A (s111): tables, settings, Layer 4 first-run routing, the inactive job, and the declared
// file boundary (Platform Admin 25 Oct 2026 18:54: nothing in the search picker, stop gates, course_events or the blade).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261026001000_cf247_entry_matrix_step_a.sql', 'utf8')
const code = m.split('\n').filter(l => !/^\s*--/.test(l)).join('\n') // the header names the boundary; the code must not touch it

test('tables: matrix and course requirements, comment on table, RLS on, no number without a scale', () => {
  for (const t of ['catalogue.provider_entry_matrix', 'catalogue.course_entry_requirements', 'pipeline.entry_matrix_sources', 'pipeline.entry_matrix_runs']) {
    expect(m).toContain(`create table ${t} (`)
    expect(m).toContain(`comment on table ${t} is`)
    expect(m).toContain(`alter table ${t} enable row level security;`)
  }
  expect(m).toContain("constraint provider_entry_matrix_value_needs_scale check (min_value is null or (grade_scale is not null and grade_scale <> 'none'))")
  expect(m).toContain("constraint course_entry_requirements_value_needs_scale check (min_value is null or (grade_scale is not null and grade_scale <> 'none'))")
  expect(m).toContain("check (matrix_kind in ('provider_minimum', 'band_ladder', 'course_minimum', 'rank_band'))")
  expect(m).toContain("'override', 'general_note'")
  expect(m).toContain('quote text not null check (length(quote) between 1 and 300)')
  expect(m).toContain('unique (source_id, content_hash)') // an unchanged page is never read twice
})

test('settings for every tunable (G2), the reader off and the job catalogued but inactive', () => {
  for (const k of ['entry.matrix_enabled', 'entry.countries', 'entry.matrix_model', 'entry.matrix_min_confidence', 'entry.matrix_max_rows_per_page',
                   'entry.matrix_first_run_review', 'entry.matrix_refresh_days', 'entry.matrix_attempts', 'entry.attach_per_provider', 'batch.entry_matrix'])
    expect(m).toContain(`('pipeline', '${k}',`)
  expect(m).toMatch(/\('pipeline', 'entry\.matrix_enabled', [^\n]*'number', '0'::jsonb, 0, 1,/)
  expect(m).toMatch(/\('pipeline', 'entry\.matrix_first_run_review', [^\n]*'number', '1'::jsonb, 0, 1,/)
  expect(m).toContain("('openrouter', 'guard_entry_matrix',")
  expect(m).toContain("('entry-matrix-read', 'Course pages', 37,")
  expect(m).toContain("select cron.schedule('entry-matrix-read', '4-59/5 * * * *', $$select security.entry_matrix_fire_v1()$$);")
  expect(m).toContain("select cron.alter_job((select jobid from cron.job where jobname = 'entry-matrix-read'), active := false);")
  expect(m).toContain("if security.pipeline_num_v1('entry.matrix_enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;")
})

test('Layer 4: the first run goes to a person; approve admits, anything else quarantines (nothing deleted)', () => {
  expect(m).toContain("v_field := case when v_first then 'entry_matrix_first_run' else 'entry_matrix_change' end;")
  expect(m).toContain("if v_first or security.pipeline_num_v1('entry.matrix_first_run_review', 1) >= 1 then")
  expect(m).toMatch(/pg_temp\.edit_n\('security\.layer4_review_decide_impl\(uuid,text,text,jsonb\)', '[0-9a-f]{32}'/)
  expect(m).toContain("v_scalar:=security.entry_matrix_review_apply_v1(v_item.id,'approve',v_final,trim(p_reason));")
  expect(m).toMatch(/pg_temp\.edit_n\('security\.layer4_review_desk_v1_impl\(text,integer\)', '[0-9a-f]{32}'/)
  expect(m).toContain("for each row when (old.status = 'pending' and new.status <> 'pending' and new.field_code in ('entry_matrix_first_run', 'entry_matrix_change'))")
  expect(m).toContain("set status = 'inactive', status_reason = 'quarantined (' || p_action || '): '")
  expect(m).not.toMatch(/delete\s+from|drop\s+(table|function|schema|view|constraint|index|trigger)|truncate/i)
  expect(m).toMatch(/^-- Replaces: nothing\n-- Retires: nothing$/m)
})

test('stored first, robots respected, inside the AI stop', () => {
  expect(m).toContain('create or replace function security.entry_matrix_use_stored_v1()')
  expect(m).toContain("read_via text check (read_via in ('stored', 'direct', 'firecrawl'))")
  expect(m).toContain("when p_status = 'robots_disallowed' then 'robots_disallowed'")
  expect(m).toContain("not security.ai_use_allowed_v1('entry_matrix')")
  expect(m).toMatch(/pg_temp\.edit_n\('security\.ai_spend_today_v1\(\)', '[0-9a-f]{32}'/)
  expect(m).toContain("('entry_matrix', 'Entry matrices with AI', 7)")
})

test('declared boundary: nothing in the search picker, stop gates, course_events or the blade', () => {
  for (const f of ['svc_course_link_search_next', 'link_search_block_v1', 'search_stop_gate_v1', 'svc_fc_spend', 'page_refused_v1', 'course_events'])
    expect(code, f).not.toContain(f)
  expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1/) // consumer API untouched in step A
})
