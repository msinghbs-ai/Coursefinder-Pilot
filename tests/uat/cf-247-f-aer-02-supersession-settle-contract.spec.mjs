// Guards: F-AER.02 AER self-healing (Platform Admin decision delivery item 4, 11 Nov 2026: recover the pending re-reads without duplicate Layer 4 items)
// A corrected read the reader skipped before reading records nothing, so its supersession stayed 'requested' and blocked the waiting item from every recovery. The scheduled
// tick now closes it as refused with the reader's reason; the item is left as it is (no new Layer 4 item). Behaviour is proven by tests/fixtures/aer-supersession-settle/run.sh.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = 'supabase/migrations/20261112123700_cf247_aer_supersession_settle.sql'
const m = fs.readFileSync(MIG, 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('only a read skipped before reading (past its claim timer) or gone is closed, as refused with the reader\'s reason; the item is never touched', () => {
  expect(code).toContain("and (e.id is null or (e.state = 'skipped' and e.updated_at < now() - interval '10 minutes'))")
  expect(code).toContain("perform security.aer_read_supersession_close_v1(r.id, 'refused',")
  expect(code).not.toMatch(/insert into pipeline\.layer4_review_items|update pipeline\.layer4_review_items/)
})

test('the existing hourly tick settles on each real run, never on a preview; md5-guarded; one file for the version', () => {
  expect(code).toContain('if not p_preview then perform security.aer_supersession_settle_v1(); end if;')
  expect(m).toContain('--   security.aer_schedule_tick_v1(boolean) b96163772b72f02b6c9956b1a263224a -> 800af9161234c24387bff6a74d6acb99')
  expect(m).toMatch(/^-- Replaces: security\.aer_schedule_tick_v1/m)
  expect(m).toMatch(/^-- Retires: nothing\./m)
  expect(fs.readdirSync('supabase/migrations').filter((f) => f.startsWith('20261112123700_'))).toEqual(['20261112123700_cf247_aer_supersession_settle.sql'])
})
