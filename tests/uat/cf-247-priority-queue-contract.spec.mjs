// Guards: CF-247 priority queue: v2.15.113 priority queue: pin universities, states, countries or courses to the front and reorder them.
// v2.15.113 priority queue: pin universities, states, countries or courses to the front and reorder them.
// v2.15.300 (Platform Admin, 20 Oct 2026, "Priority queue"): the screen retired (no use in 7 days; the focus list and Build adapter waves
// order the work); its database functions stay until their own retirement. The old address opens Layer 2/3 › Build adapter.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { PAGES, resolveTarget } from '../../src/nav-map.js'

const read = p => fs.readFileSync(p, 'utf8')

test('the Priority queue tab is retired; its address opens Build adapter; the database functions stay guarded and admin-only', () => {
  expect(PAGES.jobs.tabs.map(t => t.key)).toEqual(['automations', 'jobs', 'tasks'])
  expect(resolveTarget('scheduled-jobs', new URLSearchParams({ tab: 'priority' }))).toMatchObject({ page: 'layer2', tab: 'build' })
  expect(fs.existsSync('src/PriorityQueue.jsx')).toBe(false)
  const m = read('supabase/migrations-archive/20260930100000_cf247_priority_queue.sql')
  expect(m).toContain("security.current_role_rank()<5 then raise exception 'Platform Admin role required'")
  for (const f of ['admin_priority_read()', 'admin_priority_search(text,text)', 'admin_priority_control(text,jsonb)']) expect(m).toContain(`revoke all on function public.${f} from public, anon;`)
})
