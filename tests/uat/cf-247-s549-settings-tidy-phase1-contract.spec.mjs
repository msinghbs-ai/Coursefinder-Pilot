// Guards: Settings tidy-up Phase 1 (Platform Admin 16 Nov 2026 05:12 and 05:23, claude/ui-ux-settings-audit-2026-11-15.md decisions 1 to 4): the 39 Serper and ScrapingBee settings and the settings whose only readers are retiring become retiring (never deleted by a migration; the count-guarded paste file removes them after the retirement period); settings still read by a replacement are re-pointed; every setting outside the consumer API sections has used_by and a unit; overlapping sections are merged by label only; every change is logged with its before value; the Website API and Zoho API settings are not touched
// CF-247 S549. Migration 20261116010000_cf247_settings_tidy_phase1 and tests/fixtures/paste/PASTE-20261116-retired-settings-drop.sql.
// G2 (no number in a job or function), G3 (consumer API frozen) and housekeeping (Replaces/Retires, nothing dropped) are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261116010000_cf247_settings_tidy_phase1.sql', 'utf8')
const P = fs.readFileSync('tests/fixtures/paste/PASTE-20261116-retired-settings-drop.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('46 settings become retiring with a register row; the 39 Serper and ScrapingBee settings by toolset, the other 7 by name', () => {
  expect(code).toContain("from pipeline.platform_toolset_settings where toolset_key in ('serper', 'scrapingbee');")
  expect(code).toContain("if v_n <> 39 then raise exception 'expected 39 Serper and ScrapingBee settings, found %', v_n; end if;")
  for (const k of ["('pipeline', 'calendar.university_levels', 'control_class', 'retiring'", "('pipeline', 'batch.course_link_reverse', 'control_class', 'retiring'",
    "('pipeline', 'worker.outcome_failed_runs', 'control_class', 'retiring'", "('pipeline', 'batch.evidence_purge_check', 'control_class', 'retiring'",
    "('pipeline', 'entry.matrix_model', 'control_class', 'retiring'", "('pipeline', 'ops.ai_diagnosis_model', 'control_class', 'retiring'",
    "('firecrawl', 'builder_model', 'control_class', 'retiring'"]) expect(code).toContain(k)
  expect(code).toContain("check (kind = any (array['job', 'table', 'view', 'edge_function', 'screen', 'function', 'setting']));")
  expect(code).toContain("select 'setting', s.toolset_key || '.' || s.key, 'Platform', s.section, s.label, 'retiring', '{}',")
  expect(code).toContain("current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int")
  expect(code).toContain("if v_n <> 46 then raise exception 'post-check: % of 46 settings are retiring with a register row', v_n; end if;")
})

test('the 7 still read by a replacement are re-pointed, not retired; fills never overwrite; nothing unchanged is logged', () => {
  for (const k of ['calendar.countries', 'alerts.max_attempts', 'alerts.retry_minutes', 'alerts.delivery_enabled', 'intake_dates.name_period_lists',
    'intake_dates.deadline_max_days_before', 'batch.calendar_reread']) {
    expect(code).toContain(`('pipeline', '${k}', 'used_by',`)
    expect(code).not.toContain(`('pipeline', '${k}', 'control_class'`)
  }
  expect(code).toContain("update cf_p1_changes set skip = true where before is not distinct from after or (fill_only and nullif(btrim(before), '') is not null);")
  expect(code).toContain("raise exception 'post-check: % setting(s) still have no used_by', v_n;")
  expect(code).toContain("raise exception 'post-check: % setting(s) still have no unit', v_n;")
})

test('metadata only: no value, updated_by or updated_at changes; the consumer API sections are left alone; every change is logged', () => {
  expect(code).not.toMatch(/set\s+value\s*=/i)
  expect(code).not.toMatch(/updated_by\s*=|set updated_at/i)
  expect(code).toContain("and s.section not in ('Website API', 'Zoho API')")
  expect(code).toContain("select 'settings', 'migration', c.toolset_key || '.' || c.key,")
  expect(code).toContain("jsonb_build_object('migration', '20261116010000', 'field', c.field, 'before', c.before, 'after', c.after, 'reason', c.reason), null")
  expect(code).not.toMatch(/website_v2_|zoho_edge_|svc_website_settings_v1|schema api/i)
})

test('sections that overlap are merged by label only, pipeline toolset', () => {
  for (const [from, to] of [['Re-reads and retries', 'Re-read and retry'], ['Storage', 'Storage & retention'], ['Retention', 'Storage & retention'],
    ['Admission', 'Admission checks'], ['Enrich fields', 'Enrichment'], ['Enrichment lanes', 'Enrichment'], ['Layer 4 readiness', 'Layer 4'],
    ['Scholarship eligibility reader', 'Scholarships']]) expect(code).toContain(`('${from}', '${to}')`)
  expect(code).toContain("raise exception 'post-check: % setting(s) are still in a merged section', v_n;")
})

test('sample-run notices: md5-guarded replacement that no longer reads the retiring Serper and ScrapingBee state', () => {
  expect(code).toContain("if md5(v_def) <> 'eaed45914ee054cfc147981c1eace5e3' and position('settings tidy-up Phase 1' in v_def) = 0 then")
  const fn = M.slice(M.indexOf('CREATE OR REPLACE FUNCTION security.toolset_sample_notices_v1()'), M.indexOf('$function$;') + 11)
  expect(fn).toContain("select '[]'::jsonb")
  expect(fn).not.toMatch(/toolset_sample_runs r|toolset_plan_status|'serper'/)
})

test('the paste file: one transaction, date- and count-guarded, refuses while a job or function still names the settings, keeps every row', () => {
  expect(P.match(/^begin;$/gm)).toHaveLength(1)
  expect(P.match(/^commit;$/gm)).toHaveLength(1)
  expect(P).toContain('project fxcwkweaxjtknorudmwp ONLY')
  expect(P).toContain("if v_n <> 46 then raise exception 'refused: % of 46 settings are retiring and past retire_after (29 Nov 2026); nothing was changed', v_n; end if;")
  expect(P).toContain("or j.jobname in ('course-link-reverse', 'worker-outcome-check');")
  for (const f of ['public.admin_search_pass_start', 'public.admin_toolset_sample_write', 'public.admin_toolset_samples_read', 'security.toolset_pass_backlog',
    'security.calendar_default_intakes_apply_v1']) expect(P).toContain(`'${f}'`)
  expect(P.indexOf("select 'settings', 'drop', s.toolset_key || '.' || s.key, to_jsonb(s)")).toBeLessThan(P.indexOf('delete from pipeline.platform_toolset_settings'))
  expect(P).toContain("if v_n <> 46 then raise exception 'post-check: % of 46 settings deleted; rolled back', v_n; end if;")
})
