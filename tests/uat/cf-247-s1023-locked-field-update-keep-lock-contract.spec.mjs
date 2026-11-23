// Guards: Platform Admin 24 Nov 2026 05:51 and 08:22 AEDT (UI-UX plan v1.2 slice 5: a machine re-read of a locked fee or intake never writes it and opens one Periodic Audit - Locked Field Update item; Approve & Keep Lock, single and bulk, rank 3+, reason required, lock kept; G2 settings; no job; G3 frozen)
// s1023: the shadow audit sits in security.manual_fact_guard (md5-guarded edit), the Inbox kind locked_field_update and the bulk RPC.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124100000_cf247_s1023_locked_field_update_keep_lock.sql', 'utf8')
const fn = (name) => MIG.slice(MIG.indexOf(`CREATE OR REPLACE FUNCTION ${name}`), MIG.indexOf('$function$;', MIG.indexOf(`CREATE OR REPLACE FUNCTION ${name}`) + 40))

test('s1023: the guard still drops every machine write to a locked field, and records tuition and intakes without ever failing the write', () => {
  const g = fn('security.manual_fact_guard')
  expect(MIG).toContain("<> 'd0490f3707199988e87b5f37ca5e7342' then")
  expect(g).toContain("if coalesce(current_setting('cf.manual_edit', true), '') = 'on' then")
  expect(g).toContain("perform security.locked_field_update_raise_v1(v_field, r, case when TG_OP = 'UPDATE' then to_jsonb(OLD) end);")
  expect(g).toContain('exception when others then')
  expect(g.indexOf('perform security.locked_field_update_raise_v1')).toBeLessThan(g.indexOf('return null;'))
  expect(MIG).toContain("post-check: the guard is not on its four tables")
})

test('s1023: one open item per course, field and proposed value; a value equal to the live one opens nothing; a G2 switch', () => {
  const r = fn('security.locked_field_update_raise_v1')
  expect(r).toContain("security.pipeline_num_v1('layer4.locked_update_audit_on', 1) < 1")
  expect(r).toContain('if v_live @> jsonb_build_array(v_val) then return null; end if;')
  expect(r).toContain("on conflict (course_id, field, proposed_key) where status = 'open'")
  expect(MIG).toContain("create unique index if not exists locked_field_updates_open_uq on pipeline.locked_field_updates (course_id, field, proposed_key) where status = 'open';")
})

test('s1023: Approve & Keep Lock needs a reason, writes as a person, keeps the lock count, and is logged; Reject changes nothing', () => {
  const d = fn('security.layer4_locked_update_inbox_decide_v1')
  expect(d).toContain("if v_reason is null then")
  expect(d).toContain("perform set_config('cf.manual_edit', 'on', true);")
  expect(d).toContain("raise exception 'a Locked Field Update decision must not change the manual locks'")
  expect(d).toContain('insert into pipeline.admin_control_events')
  expect(d).not.toMatch(/(insert into|delete from|update)\s+pipeline\.manual_locks/i)
  const k = fn('security.layer4_locked_update_kind_v1')
  expect(k).toContain('"key": "approve_keep_lock", "label": "Yes (Approve & Keep Lock)", "rank": 3, "reason": true')
  expect(k).toContain('"key": "reject"')
})

test('s1023: bulk is capped by a G2 setting and needs Curator rank; the kind is registered; no job; nothing dropped', () => {
  expect(fn('security.layer4_locked_update_bulk_v1')).toContain("security.pipeline_num_v1('layer4.locked_update_bulk_max', 100)")
  expect(fn('public.admin_layer4_locked_update_bulk')).toContain('coalesce(security.current_role_rank(), 0) < 3')
  expect(MIG).toMatch(/insert into pipeline\.layer4_inbox_kind_hooks[\s\S]*'locked_field_update'/)
  expect(MIG).toContain('comment on table pipeline.locked_field_updates is')
  expect(MIG).not.toMatch(/cron\.schedule/)
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)|delete from|truncate /i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed']) expect(MIG).toContain(s)
})
