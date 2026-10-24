// CF-247 R3 (Platform Admin 24 Oct 2026 09:55): the hourly health rollup. Contracts on the migration source.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261024005000_cf247_r3_health_hourly.sql', 'utf8')

test('health_snapshots: table commented, RLS on; every threshold a setting with a range; the headline target starts unset', () => {
  expect(m).toMatch(/^-- Replaces: /m); expect(m).toMatch(/^-- Retires: /m); expect(m).not.toMatch(/^\s*(drop|truncate)\b/im)
  expect(m).toContain('create table if not exists pipeline.health_snapshots (')
  expect(m).toContain('comment on table pipeline.health_snapshots is')
  expect(m).toContain('alter table pipeline.health_snapshots enable row level security;')
  for (const k of ['retention.health_snapshots_days', 'health.bound_empty_hours', 'health.stuck_hours', 'health.binding_drop_pct', 'health.growth_pct', 'health.burn_warn_pct', 'health.headline_target', 'stats.countries']) expect(m).toContain(`'${k}'`)
  expect(m).toContain(`'number', '0'::jsonb, '0', '100000', 'per 24 h', 778, 'Health report', 'security.health_hourly_v1', 'R3: a provisional target, set by the Platform Admin, never by a passing check'`)
})

test('health_hourly_v1 writes the eight metrics from what the platform already keeps; the job is catalogued before it is scheduled at :11', () => {
  for (const metric of ['headline', 'fields_delta', 'lane_wait', 'ledger', 'idle', 'bound_empty', 'negative_movers', 'budget_burn']) expect(m).toContain(`'${metric}'`)
  expect(m).toContain('from pipeline.mode_outcome_ledger where mode = \'read\' and run_at > v_hour')
  expect(m).toContain('from security.lane_queue_wait_v1(1) w')
  expect(m).toContain("security.lane_why_idle_v1(w.key)")
  expect(m).toContain("'look_in', 'pipeline.admin_control_events and supabase_migrations.schema_migrations applied in the window'")
  expect(m.indexOf("insert into pipeline.automation_catalogue(jobname")).toBeLessThan(m.indexOf("select cron.schedule('health-hourly'"))
  expect(m).toContain("select cron.schedule('health-hourly', '11 * * * *', $$select security.health_hourly_v1()$$);")
})

test('retention replaced whole and md5-checked; the stats job reads its countries from a setting instead of the command', () => {
  expect(m).toContain("if md5(pg_get_functiondef('security.ledger_retention_v1()'::regprocedure)) <> '5b5d9103d3d3ec4b90f11f1b06429ace' then")
  expect(m).toContain("delete from pipeline.health_snapshots where at < now() - make_interval(days => security.pipeline_num_v1('retention.health_snapshots_days', 90)::int);")
  expect(m).toContain("perform cron.alter_job(v_id, command := $$select security.stats_15m_v1(array(select jsonb_array_elements_text(coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'stats.countries'), '[\"NZ\",\"CA\"]'::jsonb))))$$);")
})
