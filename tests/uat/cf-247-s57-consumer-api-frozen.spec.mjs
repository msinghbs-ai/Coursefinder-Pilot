// Guards: G3 (CLAUDE.md, Decision 266): the consumer API is frozen
// CF-247 (S57) Decision 266: the consumer API is frozen. Platform Admin 18 Oct 2026 11:58: "From here on, make sure the consumer api are not
// affected by any decision or design"; choice "Frozen-surface guard (Recommended)".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import crypto from 'node:crypto'

const APPROVED = /^-- Consumer API change approved: .{10,}$/m
const base = JSON.parse(fs.readFileSync('tests/uat/consumer-api-baseline.json', 'utf8'))
const FROM = '20261018050000'
const migs = fs.readdirSync('supabase/migrations').filter(f => f.endsWith('.sql') && f.slice(0, 14) > FROM).sort()
const API_FN = /create\s+or\s+replace\s+function\s+(public\.)?(website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1)|create\s+or\s+replace\s+function\s+api\.|drop\s+function\s+(if\s+exists\s+)?(public\.)?(website_v2_|website_edge_|website_api_v2_|zoho_edge_)|drop\s+function\s+(if\s+exists\s+)?api\./i
const CONSUMER_TABLES = /alter\s+table\s+(if\s+exists\s+)?(only\s+)?(catalogue|ref|ranking|scholarship|search|api)\.\S+\s+(drop|rename|alter\s+column)|drop\s+(table|view|materialized\s+view)\s+(if\s+exists\s+)?(catalogue|ref|ranking|scholarship|search|api)\./i

test('the consumer edge functions match the frozen baseline (or the change is approved)', () => {
  for (const [p, sha] of Object.entries(base.edge_files)) {
    const now = crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex')
    expect(now, `${p} changed: a consumer API change needs the Platform Admin's approval and a new baseline`).toBe(sha)
  }
})

test('no migration after the baseline changes a consumer API function or the tables it reads, unless approved', () => {
  for (const f of migs) {
    const sql = fs.readFileSync(`supabase/migrations/${f}`, 'utf8')
    if (APPROVED.test(sql)) continue
    expect(API_FN.test(sql), `${f} touches a consumer API function`).toBe(false)
    expect(CONSUMER_TABLES.test(sql), `${f} drops, renames or retypes something the consumer API reads`).toBe(false)
    expect(/consumer_api_rebaseline_v1\(/.test(sql), `${f} re-takes the baseline without approval`).toBe(false)
  }
})

const mig = fs.readFileSync('supabase/migrations/20261018050000_cf247_consumer_api_guard.sql', 'utf8')
test('the guard: baseline from live, daily check, hard flag on drift, nothing changed or dropped', () => {
  expect(mig).toContain("select security.consumer_api_rebaseline_v1('Decision 266, 18 Oct 2026: first baseline, taken from live as found');")
  expect(mig).toContain("if current_user <> 'postgres' then raise exception 'consumer API baseline is re-taken only by a migration'")
  expect(mig).toContain("'consumer_api_drift'")
  expect(mig.indexOf("('consumer-api-guard', 'Search and API'")).toBeLessThan(mig.indexOf("cron.schedule('consumer-api-guard'"))
  expect(mig).not.toMatch(/^(delete|drop|truncate)\b/im)
  expect(API_FN.test(mig)).toBe(false)
})
