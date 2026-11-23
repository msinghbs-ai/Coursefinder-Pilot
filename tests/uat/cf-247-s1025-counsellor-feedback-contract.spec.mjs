// Guards: Platform Admin 24 Nov 2026 05:54 and 09:06 AEDT (UI-UX plan v1.2 slice 7: in-app counsellor feedback; rank 2 sends and reads own, rank 3+ reads all and triages in Layer 4; categories from the database; G2 limits; G3 frozen)
// s1025: pipeline.counsellor_feedback with row-level policies, public.counsellor_feedback_submit_v1 and _list_v1, Inbox kind counsellor_feedback.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124110000_cf247_s1025_counsellor_feedback.sql', 'utf8')
const fn = (name) => MIG.slice(MIG.indexOf(`CREATE OR REPLACE FUNCTION ${name}`), MIG.indexOf('$function$;', MIG.indexOf(`CREATE OR REPLACE FUNCTION ${name}`) + 40))

test('s1025: rank 2 inserts and reads their own; rank 3 reads and triages all; signed-in users reach the table only through the RPCs', () => {
  expect(MIG).toContain('create policy counsellor_feedback_insert_own on pipeline.counsellor_feedback for insert to authenticated')
  expect(MIG).toContain("with check (created_by = auth.uid() and coalesce(security.current_role_rank(), 0) >= 2 and status = 'open')")
  expect(MIG).toContain('using (created_by = auth.uid() or coalesce(security.current_role_rank(), 0) >= 3)')
  expect(MIG).toContain('revoke all on pipeline.counsellor_feedback from public, anon, authenticated;')
  expect(MIG).toContain('alter table pipeline.counsellor_feedback enable row level security;')
  const l = fn('public.counsellor_feedback_list_v1')
  expect(l).toContain("v_all := v_rank >= 3 and coalesce(a->>'scope', 'all') = 'all';")
  expect(l).toContain('where (v_all or x.created_by = auth.uid())')
})

test('s1025: a report is checked: signed in at rank 2, a real course, a campus of its university, known categories, an https link, G2 limits', () => {
  const s = fn('public.counsellor_feedback_submit_v1')
  expect(s).toContain("if auth.uid() is null then raise exception 'authentication required'")
  expect(s).toContain('coalesce(security.current_role_rank(), 0) < 2')
  expect(s).toContain('k.id = v_campus and k.provider_id = v_provider')
  expect(s).toContain('from pipeline.counsellor_feedback_categories k where k.key = x and k.active')
  expect(s).toContain("v_url !~* '^https://[^\\s/]+'")
  for (const k of ['feedback.notes_max_chars', 'feedback.snapshot_max_kb', 'feedback.max_per_user_day']) expect(s).toContain(`security.pipeline_num_v1('${k}'`)
  expect(fn('public.counsellor_feedback_list_v1')).toContain("from pipeline.counsellor_feedback_categories k where k.active")
})

test('s1025: Layer 4 triage needs a note for the counsellor, is logged, and leaves the Zoho counsellor reports alone', () => {
  const d = fn('security.layer4_counsellor_feedback_inbox_decide_v1')
  expect(d).toContain('if v_reason is null then')
  expect(d).toContain('insert into pipeline.admin_control_events')
  expect(MIG).toMatch(/insert into pipeline\.layer4_inbox_kind_hooks[\s\S]*'counsellor_feedback'/)
  const code = MIG.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
  expect(code).not.toMatch(/pipeline\.data_flags|counsellor_report'/)
  expect(MIG).not.toMatch(/cron\.schedule/)
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)|delete from|truncate /i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed', 'post-check: the row-level policies are not in place']) expect(MIG).toContain(s)
})
