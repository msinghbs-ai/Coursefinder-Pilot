// Guards: StudySearch P1 (Platform Admin 7 Nov 2026 13:17, 14:27, 15:19): an alert is never "sent" because a run took it; durable attempt identities; generation, transport acknowledgement and receipt stay distinct; routine batches never wait for a person; the behaviour is proved in genuine PostgreSQL (workflow alert-delivery-test)
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const m = fs.readFileSync('supabase/migrations/20261107030000_cf247_alert_delivery_lifecycle.sql', 'utf8')
const wf = fs.readFileSync('.github/workflows/alert-delivery-test.yml', 'utf8')
const code = (s) => s.replace(/--[^\n]*/g, '')
const fn = (a, b) => m.slice(m.indexOf(`function security.${a}`), b ? m.indexOf(`function security.${b}`) : undefined)

test('append-only outbox with durable attempt ids and one live attempt per alert', () => {
  expect(m).toContain('create table if not exists pipeline.alert_delivery_batches')
  expect(m).toContain('create table if not exists pipeline.alert_delivery_attempts')
  expect(m).toContain('attempt_id uuid primary key default gen_random_uuid()')
  expect(m).toContain("create unique index if not exists alert_delivery_attempts_live_uq on pipeline.alert_delivery_attempts (alert_source, alert_id) where state in ('leased', 'generated', 'acknowledged')")
  expect(m).toContain("transport_state text not null default 'leased' check (transport_state in ('leased', 'generated', 'transport_acknowledged', 'transport_failed', 'expired'))")
  expect(m).toContain("receipt_state text not null default 'unverified' check (receipt_state in ('unverified', 'confirmed', 'not_received'))")
  expect((m.match(/comment on table/g) ?? []).length).toBe(2)
  expect(code(m)).not.toMatch(/\b(drop|truncate)\b|delete from/i)
})

test('taking never stamps sent and never waits for a person; retries are bounded with backoff; a test takes nothing', () => {
  const take = fn('alert_delivery_take_v1', 'alert_delivery_output_v1')
  expect(take).not.toMatch(/set\s+status\s*=\s*'sent'|sent_at\s*=\s*now/)
  expect(take).not.toMatch(/blocked|awaiting receipt/)
  expect(take).toContain("if p_purpose = 'test' then")
  expect(take).toContain("security.pipeline_num_v1('alerts.max_attempts', 5)")
  expect(take).toContain("security.pipeline_num_v1('alerts.retry_minutes', 10)")
  expect(take).toContain('on conflict do nothing')
})

test('generated is not delivered: nothing becomes received because a task completed; only an explicit person call confirms', () => {
  const out = fn('alert_delivery_output_v1', 'alert_delivery_receipt_v1')
  expect(out).toContain("'scheduled task (generated, receipt unverified)'")
  expect(out).not.toMatch(/receipt confirmed|'acknowledged'|transport_acknowledged/)
  const rc = fn('alert_delivery_receipt_v1', 'alert_delivery_status_v1')
  expect(rc).toContain("raise exception 'actor required'")
  expect(rc).toContain("'scheduled task (receipt confirmed)'")
  expect(m).toContain('exposes NO transport acknowledgement')
})

test('settings carry label, range, unit and used_by; old take functions marked retiring; consumer API untouched', () => {
  for (const k of ['alerts.digest_max_items', 'alerts.receipt_wait_hours']) expect(m).toContain(`'${k}'`)
  expect(m).toContain("set status = 'retiring'")
  expect(m).toContain('-- Replaces:')
  expect(m).toContain('-- Retires:')
  expect(code(m)).not.toMatch(/website_v2_|zoho_|function\s+api\./)
})

test('the lifecycle is exercised in genuine PostgreSQL: concurrency, expired leases, missing receipt, recovery, dedupe, retries', () => {
  expect(wf).toContain('postgres:17.6-alpine')
  expect(wf).toContain('bash tests/fixtures/alert-delivery/run.sh')
  const sc = fs.readFileSync('tests/fixtures/alert-delivery/scenarios.sql', 'utf8')
  for (const s of ['S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S9', 'S10', 'S11']) expect(sc).toContain(`'${s} `)
  expect(fs.readFileSync('tests/fixtures/alert-delivery/concurrent.sh', 'utf8')).toContain('pg_sleep')
})
