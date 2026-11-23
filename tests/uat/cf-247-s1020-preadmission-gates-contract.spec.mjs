// Guards: Platform Admin 24 Nov 2026 05:54 and 06:27 AEDT (UI-UX plan v1.2 slice 6: pre-admission gates hold doubtful machine admissions for Layer 4 instead of admitting them silently; active rows never withdrawn; G2 switches; G3 frozen; nothing dropped)
// s1020: fee year, PTE and TOEFL bands on IELTS courses, and campus on the provider's own list, as BEFORE triggers that act only on a machine write
// (no signed-in person, no cf.manual_edit) that would admit a new row; each decision is logged and raises one pending Layer 4 item.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124080000_cf247_s1020_preadmission_gates.sql', 'utf8')
const fn = (name) => MIG.slice(MIG.indexOf(`CREATE OR REPLACE FUNCTION ${name}`), MIG.indexOf('end $function$;', MIG.indexOf(`CREATE OR REPLACE FUNCTION ${name}`)))

test('s1020: each gate passes people and manual edits, has its own switch, and never demotes an active row', () => {
  for (const [f, sw] of [['security.gate_fee_year_tg', 'gates.fee_year_on'], ['security.gate_english_bands_tg', 'gates.english_bands_on'], ['security.gate_campus_provider_tg', 'gates.campus_provider_on']]) {
    const b = fn(f)
    expect(b).toContain("if coalesce(current_setting('cf.manual_edit', true), '') = 'on' or auth.uid() is not null then return new; end if;")
    expect(b).toContain(`security.pipeline_num_v1('${sw}', 1) < 1`)
  }
  for (const f of ['security.gate_fee_year_tg', 'security.gate_english_bands_tg']) {
    expect(fn(f)).toContain("v_refresh := tg_op = 'UPDATE' and old.status = 'active';")
    expect(fn(f)).toContain("if not v_refresh then new.status := 'unverified'; end if;")
  }
})

test('s1020: the fee-year rule uses the Melbourne year, a G2 window, and only held years inside the window', () => {
  const b = fn('security.gate_fee_year_tg')
  expect(b).toContain("v_y := extract(year from now() at time zone 'Australia/Melbourne')::int;")
  expect(b).toContain("security.pipeline_num_v1('gates.fee_year_ahead', 1)")
  expect(b).toContain('and f.fee_year between v_y and v_y + v_ahead;')
  expect(b).not.toMatch(/\b20[2-3][0-9]\b/)
})

test('s1020: English needs an overall score and four bands or a minimum for each; campus links stay on the provider\'s own list', () => {
  const e = fn('security.gate_english_bands_tg')
  expect(e).toContain("v_code not in ('PTE', 'TOEFL_IBT')")
  expect(e).toContain("ti.code = 'IELTS'")
  expect(e).toContain("k in ('listening', 'reading', 'writing', 'speaking')")
  expect(e).toContain("v_cs ? 'minimum_each'")
  const c = fn('security.gate_campus_provider_tg')
  expect(c).toContain('v_campus_provider = v_course_provider then return new;')
  expect(c).toContain('return null;')
})

test('s1020: every decision is logged and raises one pending Layer 4 item; triggers, settings and checks are in place', () => {
  const r = fn('security.preadmission_gate_raise_v1')
  expect(r).toContain("l.field_code = p_field and l.status = 'pending' limit 1;")
  expect(r).toContain('insert into pipeline.preadmission_gate_events')
  expect(MIG).toContain('alter table pipeline.preadmission_gate_events enable row level security;')
  expect(MIG).toContain('comment on table pipeline.preadmission_gate_events is')
  for (const t of ['course_fee_year_gate before insert or update on catalogue.course_fees', 'course_english_bands_gate before insert or update on catalogue.course_english_requirements',
    'course_campus_provider_gate before insert or update on catalogue.course_campuses']) expect(MIG).toContain(`create trigger ${t}`)
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)|delete from|truncate /i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed', 'post-check: a gate trigger is missing']) expect(MIG).toContain(s)
})
