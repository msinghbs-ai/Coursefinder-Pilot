// Guards: Platform Admin Firecrawl priority order 8 Nov 2026 (course page search is the lowest priority and is held by the priority floor; hold messages must be true); G3 (neither function is in the consumer API); the Firecrawl budget functions are the Integration Controller's and are not edited.
// CF-247 AER lane aer2: migration 20261108150100 words two hold messages for the priority floor. The PostgreSQL 16 run is tests/fixtures/aer-hold-wording/run.sh.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const M = fs.readFileSync('supabase/migrations/20261108150100_cf247_course_search_hold_wording.sql', 'utf8')
const run = fs.readFileSync('tests/fixtures/aer-hold-wording/run.sh', 'utf8')
const fx = fs.readFileSync('tests/fixtures/aer-hold-wording/fixtures.sql', 'utf8')
const code = (t) => t.split('\n').filter((l) => !l.trim().startsWith('--')).join('\n')
const C = code(M)

test('two live functions are edited under their live md5 with a recorded after md5; the Firecrawl budget functions are called, never edited', () => {
  expect(M).toMatch(/--   security\.link_search_block_v1\(uuid,uuid\[\]\)\s+95e26930e1a9ae9e2e989febf95bfbf7 -> [0-9a-f]{32}/)
  expect(M).toMatch(/--   public\.admin_course_search_queue\(uuid\)\s+e970d9a3c2b1d398d0c7387e37b484d9 -> [0-9a-f]{32}/)
  expect(M).not.toMatch(/AFTER_LSB|AFTER_ACSQ|00000000000000000000000000000000/)
  expect(C).toContain("pg_temp.edit_once('security.link_search_block_v1(uuid,uuid[])', '95e26930e1a9ae9e2e989febf95bfbf7'")
  expect(C).toContain("pg_temp.edit_once('public.admin_course_search_queue(uuid)', 'e970d9a3c2b1d398d0c7387e37b484d9'")
  expect(C).not.toMatch(/create or replace function (security|public)\.(fc_|lane_paid_hold|course_search_paid_cap|svc_fc_spend|svc_course_link_search|queue_watch)/i)
  expect(M).toMatch(/^-- Replaces: .+/m)
  expect(M).toMatch(/^-- Retires: nothing/m)
})

test('the floor message is chosen from security.fc_priority_room_v1; the hold code and the share message are unchanged; no number is added', () => {
  expect(C).toContain("if coalesce(security.fc_priority_room_v1(), 2) < 2 then  -- fixed: 2 credits are one search")
  expect(C).toContain("''code'', ''day_budget''")
  expect(C).toContain("Today''''s Firecrawl share for course search is used")
  expect(C).toContain("Waits for tomorrow''''s share")
  expect(C).toContain("security.fc_setting_num_v1(''priority_floor_course_search'', 0)")
  expect(C).toContain("when v_left < 2 and coalesce(security.fc_priority_room_v1(), 2) < 2 then")
  expect(C).not.toMatch(/insert into|cron\.schedule|\b(drop|delete|truncate)\b/i)
})

test('neither function is in the frozen consumer API', () => {
  for (const n of ['link_search_block_v1', 'admin_course_search_queue']) expect(n).not.toMatch(/^(website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1)/)
  expect(C).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./)
})

test('the PostgreSQL fixture shows the live wording BEFORE and proves the share case, the floor case, the no-floor case and the guard', () => {
  for (const t of ['loaded definitions = live (8 Nov 2026)', "PASS before: with the floor holding, the live message says", 'PASS migration applied twice: already applied', 'PASS the md5 guard refuses a definition that is not the live one']) expect(run).toContain(t)
  for (const t of ['PASS daily share used, floor not binding', 'PASS floor holds', 'PASS under the floor, and no floor in force']) expect(fx).toContain(t)
})
