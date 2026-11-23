// Guards: Platform Admin 24 Nov 2026 05:54 and 06:27 AEDT (UI-UX plan v1.2 slice 6, gate 4: a course-linked scholarship GPA threshold is admitted only with its stated scale; held items go to Layer 4 grouped per provider; active rows never withdrawn; G2 switch; G3 frozen; nothing dropped)
// s1021: BEFORE trigger on scholarship.criteria for machine writes, the review table, and the Layer 4 Inbox kind scholarship_gpa_scale (set the scale or mark it not a GPA).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124090000_cf247_s1021_scholarship_gpa_scale_gate.sql', 'utf8')
const fn = (name) => MIG.slice(MIG.indexOf(`CREATE OR REPLACE FUNCTION ${name}`), MIG.indexOf('$function$;', MIG.indexOf(`CREATE OR REPLACE FUNCTION ${name}`) + 40))

test('s1021: the gate passes people and manual edits, has its own switch, acts only on course-linked GPA thresholds, and never demotes an active row', () => {
  const b = fn('security.gate_gpa_scale_tg')
  expect(b).toContain("if coalesce(current_setting('cf.manual_edit', true), '') = 'on' or auth.uid() is not null then return new; end if;")
  expect(b).toContain("security.pipeline_num_v1('gates.gpa_scale_on', 1) < 1")
  expect(b).toContain("new.criterion_type is distinct from 'academic_minimum' or coalesce(new.value_text, '') !~* '^GPA'")
  expect(b).toContain("m.mapping_state = 'mapped'")
  expect(b).toContain("v_refresh := tg_op = 'UPDATE' and old.status = 'active';")
  expect(b).toContain("if not v_refresh then new.status := 'unverified'; end if;")
  expect(b).toContain("insert into pipeline.preadmission_gate_events")
  expect(MIG).toContain('create trigger criteria_gpa_scale_gate before insert or update on scholarship.criteria')
})

test('s1021: the scale is read only from what the source states, never assumed from the number', () => {
  const s = fn('security.gpa_scale_of_v1')
  expect(s).toContain("p_value_json -> 'scale'")
  expect(s).toContain('(?:out of|/)')
  expect(MIG).toContain("security.gpa_scale_of_v1('{}'::jsonb, 'a GPA of 4.0') is not null")
})

test('s1021: the Layer 4 kind is registered, groups by provider, and a decision re-admits only a threshold that fits the scale and is logged', () => {
  expect(MIG).toMatch(/insert into pipeline\.layer4_inbox_kind_hooks[\s\S]*'scholarship_gpa_scale'[\s\S]*security\.layer4_gpa_scale_inbox_decide_v1\(text,text,text,text\)/)
  expect(fn('security.layer4_gpa_scale_inbox_counts_v1')).toContain("'by_provider'")
  const d = fn('security.layer4_gpa_scale_inbox_decide_v1')
  expect(d).toContain('for update;')
  expect(d).toContain('r.threshold > v_scale')
  expect(d).toContain("perform set_config('cf.manual_edit', 'on', true);")
  expect(d).toContain('insert into pipeline.admin_control_events')
  for (const k of ['scale_4', 'scale_7', 'scale_other', 'not_gpa']) expect(fn('security.layer4_gpa_scale_kind_v1')).toContain(`"key": "${k}"`)
})

test('s1021: table, setting and post-checks are in place; nothing is dropped', () => {
  expect(MIG).toContain('comment on table pipeline.gpa_scale_reviews is')
  expect(MIG).toContain('alter table pipeline.gpa_scale_reviews enable row level security;')
  expect(MIG).toContain("'gates.gpa_scale_on'")
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)|delete from|truncate /i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed',
    'post-check: the GPA gate trigger is missing', 'post-check: the Inbox kind is not registered']) expect(MIG).toContain(s)
})
