// Guards: Platform Admin decision D12 (overnight autonomous execution mandate 3 Nov 2026 21:59; integration issue IQ-00111): admitted AI fees on
// courses a person already decided go to Layer 4 on the existing "Fee fails the check" card, with the stored copy, evidence and earlier decisions
// attached; no decided item is overwritten; "Keep the CRICOS total" withdraws the AI fee it names; a manual value is never touched. The behaviour
// runs on isolated fixtures by tests/fixtures/fee-l4-route/run.sh (scratch PostgreSQL; the live inbox loaded from its live text and checked
// against its live md5, then the Layer 4 owner's 20261104150000 edit the cards render through; the migration applied twice and never editing the
// inbox; every case asserted; the governed paste run and refused a second time).
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const MIG = 'supabase/migrations/20261104270000_cf247_fee_admitted_recheck.sql'
const m = fs.readFileSync(MIG, 'utf8')
const FX = 'tests/fixtures/fee-l4-route'
const run = fs.readFileSync(`${FX}/run.sh`, 'utf8')
const fixtures = fs.readFileSync(`${FX}/fixtures.sql`, 'utf8')
const paste = fs.readFileSync('docs/paste/PASTE-20261104-fee-admitted-recheck.sql', 'utf8')
const observe = fs.readFileSync('docs/paste/OBSERVE-20261104-fee-reads-v2.15.442.sql', 'utf8')
const md5 = (s) => crypto.createHash('md5').update(s).digest('hex')

test('the Layer 4 inbox is not edited here: the items render through the Layer 4 owner\'s version (20261104150000, 4fc05d14)', () => {
  expect(md5(fs.readFileSync(`${FX}/live/layer4_inbox_items_v1.def`, 'utf8'))).toBe('a56bc3313e02ac0611deb5657da95ce0')
  const l4 = fs.readFileSync(`${FX}/l4-inbox-4fc05d14.sql`, 'utf8')
  expect(l4).toContain("select pg_temp.edit_once('security.layer4_inbox_items_v1()', 'a56bc3313e02ac0611deb5657da95ce0', '4fc05d14f4ba49335ff90496a20f582d', array[")
  expect(m).not.toContain('pg_temp.edit_once')
  expect(m).not.toMatch(/create or replace function security\.layer4_inbox_items_v1/)
  expect(m).toContain('-- Edited live functions: none.')
  expect(m).not.toMatch(/\b(drop|delete|truncate)\s+(table|function|trigger|from)\b/i)
  expect(run).toContain("applied; the Layer 4 inbox is unchanged ($L4)")
  expect(run).toContain('applied twice: the second run changed nothing')
})

test('a re-check is a new item on the existing fee check card; a decided item is never changed', () => {
  expect(m).toContain("values ('course', f.course_id::text, v_c.provider_id, 'fee_ai_recheck', 'fee_crosscheck', left(v_why, 1000), 'fee-reader-recheck', 'hard', 'raised', 'person', v_ev)")
  expect(m).toContain("'earlier_decisions', v_prior")
  expect(m).toContain("'the course has a manual value; it is never re-checked automatically'")
  for (const c of ['raise: the decided item is not changed', 'raise: fee, stored copy, quote, CRICOS total, exclusion and earlier decision attached',
    'refused: a manual value is never touched', 'card: Fee fails the check, stored copy linked, earlier decision in the reason', 'card: the decided item is not listed again'])
    expect(fixtures).toContain(c)
})

test('"Keep the CRICOS total" by a person withdraws the AI fee it names; nothing else, and only while the setting is on', () => {
  expect(m).toContain("if new.release_kind is distinct from 'person' or security.pipeline_num_v1('fees.recheck_keep_withdraws_on', 1) < 1 then return null; end if;")
  expect(m).toContain("for each row when (new.field = 'fee_ai_recheck' and old.state = 'raised' and new.state = 'released')")
  expect(m).toMatch(/\('pipeline', 'fees\.recheck_keep_withdraws_on',[\s\S]*?'number', to_jsonb\(1\)/)
  for (const c of ['keep: the AI fee is withdrawn with the decision in its note', 'keep: the CRICOS row is untouched', 'confirmed on the course: the hand-entered fee stays',
    'switch off: the item is released and the AI fee stays', 'automatic release: nothing withdrawn (only a person decides)'])
    expect(fixtures).toContain(c)
})

test('the governed paste raises exactly the 5 live rows, count- and md5-guarded; the observation query is read only', () => {
  expect(paste).toContain("if v_n <> 5 or v_md5 <> 'ccc44c30f3bf04340cdc7a2ec11223b2' then")
  expect(paste).toContain("if v_raised <> 5 then raise exception 'raised %, expected 5; rolled back', v_raised; end if;")
  expect(paste).not.toMatch(/\b(update|delete)\s+(from\s+)?catalogue\./i)
  expect(run).toContain('paste: second run refused (guard)')
  expect(observe).toMatch(/^begin read only;$/m)
  expect(observe).toMatch(/^rollback;$/m)
  expect(observe).not.toMatch(/\b(insert|update|delete)\s/i)
  expect(observe).toContain("'admitted while held (expected 0)'")
})
