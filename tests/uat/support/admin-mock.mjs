// Mocked Supabase for local admin UAT: a signed-in Platform Admin and live-shaped reads.
// Only for the local dev server (VITE_SUPABASE_URL=https://example.supabase.co); nothing reaches a real backend.
import * as F from './admin-fixtures.mjs'

export async function mockAdmin(page, { rank = 6, healthMissing = false, courseDiffers = false } = {}) {
  const context = { ...F.context, role_rank: rank, role: rank >= 6 ? 'platform_admin' : 'viewer' }
  const session = { access_token: 'mock-token', refresh_token: 'mock-refresh', token_type: 'bearer', expires_in: 360000, expires_at: Math.floor(Date.now() / 1000) + 360000, user: { id: context.user_id, email: 'admin@example.test', aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {} } }
  const adminRead = {
    context, dashboard: F.dashboard, layer_status_summary: F.layerStatus, platform_health: F.platformHealth,
    course_coverage: F.courseCoverage, data_quality_overview: F.dataQualityOverview,
    courses_page: F.coursesPage, course_detail: F.courseDetail, scholarships_page: F.scholarshipsPage, scholarship_detail: F.scholarshipDetail,
    layer3_queue_status: { by_task_class: [] }, layer2_acquisition_providers: F.environmentRead.layer2_providers, layer2_provider_routes: [],
  }
  const calls = []; page.l3calls = calls
  const rpc = {
    admin_layer3_operations: F.layer3Operations,
    admin_layer3_control_read: F.layer3Control,
    admin_layer3_control: b => { calls.push(b); return F.layer3Control },
    admin_source_comparison: b => b.p_entity_type === 'course' ? (courseDiffers ? F.courseComparisonDiffers : F.courseComparison) : F.scholarshipComparison,
  }
  await page.addInitScript(s => { try { localStorage.setItem('sb-example-auth-token', JSON.stringify(s)) } catch {} }, session)
  await page.route('https://example.supabase.co/**', async route => {
    const u = new URL(route.request().url())
    let body = {}
    try { body = route.request().postDataJSON() || {} } catch {}
    const json = (data, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(data) })
    if (u.pathname.startsWith('/auth/v1/user')) return json(session.user)
    if (u.pathname.startsWith('/auth/v1/')) return json(session)
    if (u.pathname === '/rest/v1/rpc/admin_read') {
      const op = body.p_operation
      if (op === 'platform_health' && healthMissing) return json({ code: 'P0001', message: 'unknown admin_read operation platform_health' }, 400)
      return json(op in adminRead ? adminRead[op] : {})
    }
    if (u.pathname.startsWith('/rest/v1/rpc/')) { const v = rpc[u.pathname.split('/').pop()]; return json(typeof v === 'function' ? v(body) : (v ?? [])) }
    if (u.pathname.startsWith('/functions/v1/')) return json(u.pathname.endsWith('platform-environment-control') ? F.environmentRead : {})
    return json([])
  })
}
