// Guards: StudySearch P1 (Platform Admin 7 Nov 2026 13:17 and 14:27): an alert is never "sent" because a run took it; delivery has durable attempts, separate transport and receipt states, and only confirmed receipt completes an alert
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261107030000_cf247_alert_delivery_lifecycle.sql', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')

test('append-only outbox: batches, attempts and one live attempt per alert', () => {
  expect(m).toContain('create table if not exists pipeline.alert_delivery_batches')
  expect(m).toContain('create table if not exists pipeline.alert_delivery_attempts')
  expect(m).toContain("create unique index if not exists alert_delivery_attempts_live_uq on pipeline.alert_delivery_attempts (alert_source, alert_id) where state in ('leased', 'output_written', 'receipt_confirmed')")
  expect(m).toContain("transport_state text not null default 'leased' check (transport_state in ('leased', 'output_written', 'transport_acknowledged', 'transport_failed', 'expired'))")
  expect(m).toContain("receipt_state text not null default 'awaiting' check (receipt_state in ('awaiting', 'overdue', 'confirmed', 'not_received'))")
  expect((m.match(/comment on table/g) ?? []).length).toBe(2)
  expect(code(m)).not.toMatch(/\b(drop|truncate)\b|delete from/i)
})

test('taking an alert never stamps it sent; a test batch takes nothing', () => {
  const take = m.slice(m.indexOf('function security.alert_delivery_take_v1'), m.indexOf('function security.alert_delivery_output_v1'))
  expect(take).not.toMatch(/set\s+status\s*=\s*'sent'|sent_at\s*=\s*now/)
  expect(take).toContain("if p_purpose = 'test' then")
  expect(take).toContain("'blocked', 'an earlier delivery is still awaiting receipt")
  expect(take).toContain("security.pipeline_num_v1('alerts.digest_max_items', 15)")
})

test('only a confirmed receipt completes an alert; not received releases it; output is not delivery', () => {
  const out = m.slice(m.indexOf('function security.alert_delivery_output_v1'), m.indexOf('function security.alert_delivery_receipt_v1'))
  expect(out).not.toMatch(/receipt_confirmed|status\s*=\s*'sent'|transport_acknowledged/)
  const rc = m.slice(m.indexOf('function security.alert_delivery_receipt_v1'), m.indexOf('function security.alert_delivery_status_v1'))
  expect(rc).toContain("raise exception 'actor required'")
  expect(rc).toContain("set status = 'sent', sent_at = now(), sent_via = 'scheduled task (receipt confirmed)'")
  expect(rc).toContain("state = 'released'")
})

test('settings carry label, range, unit and used_by; old take functions marked retiring; consumer API untouched', () => {
  for (const k of ['alerts.digest_max_items', 'alerts.receipt_wait_hours']) expect(m).toContain(`'${k}'`)
  expect(m).toContain("set status = 'retiring'")
  expect(m).toContain('-- Replaces:')
  expect(m).toContain('-- Retires:')
  expect(code(m)).not.toMatch(/website_v2_|zoho_|function\s+api\./)
})
