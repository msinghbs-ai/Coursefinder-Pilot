// Settings page (v2.15.160, Decision 238): every throttle, budget and page-identity proof editable by a Platform Admin
// from one page; numbers apply at once and are logged; prompts are listed, never edited in place.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES } from '../../src/nav-map.js'

const read = p => fs.readFileSync(p, 'utf8')

test('Settings page: one page by pipeline step, backed by the read/write pair, logged, prompts read-only', () => {
  expect(PAGES.environment.label).toBe('Settings')
  const main = read('src/mature-main.jsx')
  expect(main).toContain(`case'environment':return <><PipelineSettings onError={err}/><EnvironmentMigrationWorkspace`)
  const ps = read('src/PipelineSettings.jsx')
  expect(ps).toContain("supabase.rpc('admin_pipeline_settings_read')")
  expect(ps).toContain("supabase.rpc('admin_pipeline_settings_write',{p_key:key,p_value:value})")
  for (const key of ['course_pages.matcher_prepare_universities', 'course_pages.matcher_items_per_minute', 'course_pages.search_monthly_credit_cap', 'reading.read_batch_per_30s',
    'layer3.requests_per_day', 'layer3.daily_usd_max', 'layer3.credit_floor_usd', 'budgets.firecrawl_monthly_limit', 'budgets.firecrawl_stop_at_remaining', 'identity.attribute'])
    expect(ps).toContain(`'${key}'`)
  expect(ps).not.toContain('prompt_system') // prompts are shown by version and hash only
  expect(ps).not.toMatch(/toLocale|Intl\./)
  const m = read('supabase/migrations/20261003001200_cf247_pipeline_settings.sql')
  expect(m).toContain("if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required'")
  expect(m).toContain("values ('settings', 'change', p_key, jsonb_build_object('value', p_value, 'before', v_before #> string_to_array(p_key, '.')), auth.uid())")
  expect(m).not.toContain('prompt_system =') // no prompt edits here
  for (const word of ['drop', 'delete from', 'truncate', 'on delete cascade']) expect(m.toLowerCase()).not.toContain(word)
})
