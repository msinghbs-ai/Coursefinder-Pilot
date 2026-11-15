// Guards: Job governance quick wins (Platform Admin 15 Nov 2026 20:38, approving the job governance audit of 20:25): search-refresh-requested runs with its own time limit from a setting and its rebuild is unchanged; course-description-stale-retire reads its two classes directly with the same rules and no similarity scan; the eight switched-off jobs are retiring and leave only by the count-guarded paste file; the four collision-risk jobs start on quieter minutes with the same runs an hour
// CF-247 S546. Migration 20261115200000_cf247_cron_quick_wins and docs/paste/PASTE-20261115-cron-legacy-jobs-drop.sql.
// G2 (no number in a job), G3 (consumer API frozen) and housekeeping (Replaces/Retires, nothing dropped) are guarded centrally by s32, s57 and s42.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261115200000_cf247_cron_quick_wins.sql', 'utf8')
const P = fs.readFileSync('docs/paste/PASTE-20261115-cron-legacy-jobs-drop.sql', 'utf8')
const code = M.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

// minutes of the hour a cron minute field starts on
export function minutes(field) {
  const out = new Set()
  for (const part of field.split(',')) {
    const [range, step] = part.split('/')
    const [a, b] = range === '*' ? [0, 59] : range.includes('-') ? range.split('-').map(Number) : [Number(range), step ? 59 : Number(range)]
    for (let m = a; m <= b; m += Number(step || 1)) out.add(m)
  }
  return [...out].sort((x, y) => x - y)
}
const moved = (job) => new RegExp(`jobname = '${job}'\\), schedule := '([^']+)'`).exec(code)?.[1].split(' ')[0]
const before = (job) => new RegExp(`\\('${job}', '([^']+)',`).exec(code)?.[1].split(' ')[0]
const HOT = [0, 10, 20, 30, 40, 50] // the six minutes with 40 or more hourly starts in the 15 Nov audit

test('search-refresh-requested: its own time limit from a setting, set for the run only; nothing it writes changes', () => {
  expect(code).toContain("perform cron.alter_job(v_id, command := 'select set_config(''statement_timeout'', security.pipeline_num_v1(''search.refresh_time_limit_seconds'', 300)::int || ''s'', true); select security.search_refresh_requested_v1();');")
  expect(code).toMatch(/'search\.refresh_time_limit_seconds', 'Search refresh: time limit for one run',[\s\S]*?to_jsonb\(300\), 120, 900, 'seconds', 332,[\s\S]*?'Website API',\s*'job search-refresh-requested/)
  // no search function, search table or refresh function is edited
  expect(code).not.toMatch(/create or replace function search\./i)
  expect(code).not.toMatch(/(alter|update|insert into)\s+search\./i)
  expect(code).not.toMatch(/create or replace function security\.search_refresh_requested_v1/i)
})

test('course-description-stale-retire: the two classes read directly, same rules, same switch and batch, no similarity scan', () => {
  expect(code).toContain("if md5(v_def) <> '64d853f9e0ba648fc14109bc2ab7de14' then")
  const fn = code.slice(code.indexOf('create or replace function security.course_description_retire_stale_v1()'), code.indexOf('end $function$;'))
  expect(fn).not.toContain('course_description_reconcile_v1')
  expect(fn).not.toContain('course_description_check')
  expect(fn).toContain("case when c.lifecycle_status is distinct from 'active' then 'course_inactive' else 'already_filled' end class")
  expect(fn).toContain("where i.status = 'pending' and i.entity_type = 'course' and i.field_code = 'course_description_first_read'")
  expect(fn).toContain("and (c.lifecycle_status is distinct from 'active' or nullif(btrim(c.description), '') is not null)")
  expect(fn).toContain('order by i.created_at limit v_max loop')
  expect(fn).toContain("security.pipeline_num_v1('enrich.course_description_stale_supersede_on', 0) >= 1")
  expect(fn).toContain("security.pipeline_num_v1('layer4.reconcile_batch', 200)::int")
  expect(fn).toContain('continue when not v_on;')
  expect(code).toContain("raise exception 'post-check: stale-retire still reads through the reconcile function'")
})

test('the eight switched-off jobs are retiring; only the paste file removes them, each part count-guarded', () => {
  for (const j of ['course-link-reverse', 'onboarding-pilot-snapshot', 'worker-outcome-check']) expect(code).toMatch(new RegExp(`\\('${j}', 'nothing: `))
  expect(code).toContain("set status = 'retiring', replaced_by = x.replaced_by, retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,")
  expect(code).not.toMatch(/cron\.unschedule/)
  expect(P.match(/^begin;$/gm)).toHaveLength(2)
  expect(P.match(/^commit;$/gm)).toHaveLength(2)
  for (const [part, n] of [['A', 5], ['B', 3]]) {
    expect(P).toContain(`if v_n <> ${n} then raise exception 'PART ${part} refused:`)
    expect(P).toContain(`PART ${part} post-check: a job is still scheduled`)
  }
  expect(P.match(/where j\.jobname = any\(v_jobs\) and not j\.active and r\.status = 'retiring' and r\.retire_after <= current_date/g)).toHaveLength(2)
  expect(P.match(/make_interval\(days => v_idle\)/g)).toHaveLength(2)
  expect(P).toContain('project fxcwkweaxjtknorudmwp ONLY')
})

test('the four collision-risk jobs start on quieter minutes with the same runs an hour', () => {
  for (const job of ['coverage-ai-match-prepare', 'link-refresh', 'consumer-reference-bundle-refresh', 'course-description-machine']) {
    const was = minutes(before(job)), now = minutes(moved(job))
    expect(now.length, job).toBe(was.length)
    expect(now.filter((m) => HOT.includes(m)), job).toEqual([])
  }
  expect(minutes('1-59/10')).toEqual([1, 11, 21, 31, 41, 51])
  // course-description-machine keeps its windows: not :13 (stale-retire), not :35 to :43, not :45 to :49
  const cd = minutes(moved('course-description-machine'))
  expect(cd).toHaveLength(24)
  expect(cd.filter((m) => m === 13 || (m >= 35 && m <= 43) || (m >= 45 && m <= 49))).toEqual([])
})
