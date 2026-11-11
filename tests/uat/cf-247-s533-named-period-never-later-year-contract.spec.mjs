// Guards: CF-247 F-INT (11 Nov 2026): a named study period never takes a later year's start in the stated month when it starts sooner in another month (Monash "Semester one (February)" was given 28 Feb 2028); a provider listed for Rule B takes the nearest start, any other is held.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261111170000_cf247_named_period_never_later_year.sql', 'utf8')
const n = MIG.slice(MIG.indexOf('array[$n$'), MIG.indexOf('$n$]);'))

test('one md5-guarded edit before the horizon check', () => {
  expect(MIG).toContain("select pg_temp.edit_all('security.intake_dates_plan_v3(uuid[],integer)', 'ef496c19edb842c19a6aa1aef19e3644', '98ab7972726d0b3ccef7e816be77fd8d',")
  expect(MIG).toContain("array[$o$    -- P0 IQ-00313: the next dated start must lie within the horizon$o$]")
  expect(n.trim().endsWith('-- P0 IQ-00313: the next dated start must lie within the horizon')).toBe(true)
})

test('an earlier start of the named period blocks the later year; listed providers take Rule B with its checks, others are held', () => {
  expect(n).toContain('s.period = any (v_named) and s.year_ok and s.on_date >= v_today and s.on_date < make_date(v_year, v_m, 1)')
  expect(n).toContain('if r.provider_id = any (v_near) then')
  expect(n).toContain('security.intake_nearest_start_v1(r.course_id, r.id, v_m, r.intake_year, v_raw, v_cal, v_today, v_ahead, v_near_days)')
  expect(n).toContain("w.outcome = 'withdrawn'")
  expect(n).toContain('security.intake_course_applicability_v1(v_raw, v_m,')
  expect(n).toContain("rule := 'calendar-v3-nearest-start'")
  expect(n).toContain("the named period starts sooner in another month (")
  expect(MIG).not.toMatch(/update pipeline\.platform_toolset_settings/)
})
