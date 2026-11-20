// Guards: CF-247 s822 (Platform Admin 20 Nov 2026 10:39 AEDT, chat S1-Courses): stuck course description readings are marked reread: from the pages already stored, as a data-only change that never writes a description, never touches the consumer API and keeps the G2 and housekeeping rules
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120114000_cf247_s822_cdesc_reread_stuck_readings.sql', 'utf8')

test('housekeeping lines, no drop, no delete, no new object', () => {
  expect(MIG).toMatch(/^-- Replaces: nothing\.$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\.$/m)
  expect(MIG).not.toMatch(/\b(drop|delete\s+from|truncate|create\s+(table|function|or replace function|view|index))\b/i)
  expect(MIG).not.toMatch(/\balter\s+table\b/i)
})

test('only the latest skipped reading of a course with a stored, identified page and no description is marked, never a locked or hidden one', () => {
  expect(MIG).toContain("c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null")
  expect(MIG).toContain("g.status in ('bound', 'ambiguous')")
  expect(MIG).toContain("g.read_status = 'read' and g.identity_basis is not null")
  expect(MIG).toContain("k.field in ('description', 'course_description', 'all')")
  expect(MIG).toContain('security.provider_hidden_v1 h')
  expect(MIG).toContain("distinct on (e.course_id)")
  expect(MIG).toContain("where e.id = p.id and e.state = 'skipped'")
  expect(MIG).toContain("'reread: s822 ' || v_ver")
})

test('v4 held readings and v4 insufficient readings are not re-marked', () => {
  expect(MIG).toContain("l.reason like 'insufficient\\_verified\\_course\\_facts%' and l.pv <> v_ver")
  expect(MIG).toContain("l.reason like 'the page does not state it%' and l.pv <> v_ver")
  expect(MIG).not.toMatch(/like 'held/)
})

test('catalogue.courses is not written, and the consumer API is checked at 75 and 48 before and after', () => {
  expect(MIG).not.toMatch(/update\s+catalogue\./i)
  expect(MIG).not.toMatch(/insert\s+into\s+catalogue\./i)
  expect((MIG.match(/security\.consumer_api_check_v1\(\)/g) || []).length).toBe(2)
  expect((MIG.match(/<> 75/g) || []).length).toBe(2)
  expect((MIG.match(/<> 48/g) || []).length).toBe(2)
  expect(MIG).toContain("raise exception 'post-check: catalogue.courses descriptions changed")
})

test('G2: no pace, size or spend number in code; the time-out and text limit are marked fixed', () => {
  expect(MIG).not.toMatch(/\blimit\s+\d/i)
  expect(MIG).toMatch(/statement_timeout = '120s';\s+-- fixed:/)
  expect(MIG).toMatch(/left\([^\n]*300\)[^\n]*-- fixed:/)
})
