// CF-247 (S51): Platform Admin 16 Oct 2026 15:25: "Platform health: CRITICAL, with 5 critical issues and 1 warning. Most are stale or
// mis-labelled. The real one is scholarships: none published or read for two days." "Dashboard should display Icons" "Platform Users -
// can't be deleted, only disabled (only Platform admin should be able to delete the user from UI, Platform admins roles user can't be
// deleted form the UI".
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const health = fs.readFileSync('supabase/migrations/20261016070000_cf247_health_and_scholarship_reads.sql', 'utf8')
const del = fs.readFileSync('supabase/migrations/20261016080000_cf247_user_delete.sql', 'utf8')
const fn = fs.readFileSync('supabase/functions/admin-user-management/index.ts', 'utf8')
const ui = fs.readFileSync('src/access-roles-entry.jsx', 'utf8')
const dash = fs.readFileSync('src/Dashboard.jsx', 'utf8')
const deploy = fs.readFileSync('.github/workflows/deploy-edge-functions.yml', 'utf8')

test('scholarship reads asked for are not held by the per-university cap; the paused reader is switched on again', () => {
  expect(health).toContain("and (p.requested_at is not null or not security.fc_sch_held_v1(s.provider_id, false))  -- v2.15.265")
  expect(health).toContain("perform security.flag_release_v1(f.id, 'cf247-20261016070000', 'auto'")
})

test('health checks: claimable work only, tuition hand-off retired, trial runs, allowance and limits from settings', () => {
  expect(health).toContain("'queue','coverage_queues:tuition_handoff','status','retired'")
  expect(health).not.toContain("'Tuition hand-off to Layer 3','coverage-tuition-handoff'")
  expect(health).toContain("v_ts:=greatest(coalesce(r.last_run, r.created_before), (select max(f.released_at) from pipeline.enrichment_flags f where f.entity='job'")
  expect(health).toContain("'queue','scholarship_queues:held','status','held'")
  expect(health).toContain("v_n3:=coalesce((select s.value from pipeline.scholarship_layer_settings s where s.key='firecrawl_cap'),0);")
  expect(health).not.toContain('falls back to direct reads only')
  expect(health).toContain("v_num2:=current_setting('max_connections')::numeric;")
  expect(health).toContain("set compute_size = 'Medium'")
  expect(health).toContain('database_critical_bytes = 7516192768')
})

test('user delete: Platform Admin only, never a Platform Admin, yourself or the system account; history kept', () => {
  expect(del).toContain("raise exception 'a platform admin cannot be deleted from the screen'")
  expect(del).toContain("raise exception 'you cannot delete your own account'")
  expect(del).toContain("raise exception 'active platform admin actor required'")
  expect(del).toContain("like '%.invalid'")
  expect(del).toContain("update security.user_roles set expires_at = now() where user_id = p_target_user_id")
  expect(del).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(fn).toContain('if (Number(context?.role_rank || 0) < 6) return reply(req, 403, { error: "platform_admin_role_required" });')
  expect(fn).toContain('serviceClient.rpc("svc_admin_access_guard_delete"')
  expect(fn).toContain('serviceClient.auth.admin.deleteUser(targetUserId, guard.soft === true)')
  expect(fn).toContain('const authUsers = authUsersAll.filter((u: any) => !u.deleted_at && !deletedIds.has(String(u.id)));')
  expect(deploy).toContain('[admin-user-management]=true')
  expect(ui).toContain("if((user.roles||[]).some(r=>r.role_code==='platform_admin'))return'A Platform Admin cannot be deleted from here'")
})

test('dashboard: an icon for every queue in Waiting for you', () => {
  for (const k of ['review', 'onboarding_admit', 'onboarding_stopped', 'scholarship_links', 'scholarships_ready', 'reference', 'dates', 'failed_jobs', 'failed_automations'])
    expect(dash).toMatch(new RegExp(`\\b${k}:[A-Z]`))
  expect(dash).toContain('<span className="db-queue-icon" aria-hidden="true"><Icon size={16}/></span>')
})

test.describe('mocked browser', () => {
  test('Waiting for you rows show their icons', async ({ page }) => {
    const { mockAdmin } = await import('./support/admin-mock.mjs')
    await mockAdmin(page)
    await page.goto('/#dashboard')
    const rows = page.locator('[data-waiting] li')
    await expect(rows.first()).toBeVisible()
    const n = await rows.count()
    for (let i = 0; i < n; i++) await expect(rows.nth(i).locator('.db-queue-icon svg')).toHaveCount(1)
  })
})
