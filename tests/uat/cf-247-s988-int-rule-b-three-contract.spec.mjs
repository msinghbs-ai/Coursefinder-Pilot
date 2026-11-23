// Guards: CF-247 s988 (session S2-INT, Platform Admin 23 Nov 2026 15:38 AEDT, Rule B Decision 271): Rule B lists Federation, Canterbury and Waikato only; Southern Cross is never listed; a start in a month the page does not name is held, not admitted; dates come only from the planner.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const F = [1, 2, 3].map((n) => fs.readFileSync(`supabase/migrations/2026112315000${n - 1}_cf247_s988_int_rule_b_three_${n}.sql`, 'utf8'))
const IDS = ['9cc8ef21-52ec-4c18-849a-598ba1072459', 'db910e88-67d1-4d2b-a65c-cea290aa0692', '00e5f26c-446e-453c-a3fb-bc5239a4feec']
const SC = 'f30cd2cd-01fc-458e-a061-b7aa5faa8a00'

test('every part lists exactly Federation, Canterbury and Waikato (idempotent) and refuses to list Southern Cross', () => {
  for (const m of F) {
    for (const id of IDS) expect(m).toContain(id)
    expect(m).toContain("raise exception 's988: Southern Cross must not be listed'")
    expect(m).toContain('if v_after is distinct from v_before then')
    expect(m).toContain('pipeline.admin_control_events')
  }
})

test('Southern Cross appears only in the guard, never in a list, an update or an apply', () => {
  for (const m of F) {
    const uses = m.split(SC).length - 1
    expect(uses).toBeLessThanOrEqual(3) // header note, variable, guard
    expect(m).not.toMatch(new RegExp(`array\\[[^\\]]*${SC}`))
  }
})

test('the cross-month Waikato days are held by a recorded withdrawal the planner never re-admits', () => {
  expect(F[0]).toContain("i.intake_label !~* to_char(p.new_start, 'Mon')")
  expect(F[0]).toContain("'withdrawal', 'withdrawn'")
  expect(F[0]).toContain("w.outcome = 'withdrawn'")
  expect(F[2]).not.toContain("'withdrawal'")
})

test('apply parts use the existing apply function and refuse a fill outside the stated month or without quote and calendar', () => {
  for (const m of [F[1], F[2]]) {
    expect(m).toContain('security.intake_dates_apply_v1(v_lim, v_ids)')
    expect(m).toContain("d.rule = 'calendar-v3-nearest-start'")
    expect(m).toContain("i.intake_label !~* to_char(i.start_date, 'Mon')")
    expect(m).toContain('a Rule B fill is outside the stated month or lacks its quote or calendar')
  }
})

test('live at once; no new setting, job, schedule, function or drop; consumer API 75/48 and locks checked', () => {
  for (const m of F) {
    expect(m).not.toMatch(/insert into pipeline\.platform_toolset_settings|cron\.|create (or replace )?function (?!pg_temp)/i)
    expect(m).not.toMatch(/\bdrop\s+(function|table|index)/i)
    expect(m).not.toMatch(/update catalogue\.course_intakes|insert into catalogue\.course_intakes/)
    expect(m).toContain("(v->>'functions')::int <> 75")
    expect(m).toContain('pipeline.manual_locks')
    expect(m).toMatch(/^-- Replaces: nothing/m)
    expect(m).toMatch(/^-- Retires: nothing/m)
  }
})
