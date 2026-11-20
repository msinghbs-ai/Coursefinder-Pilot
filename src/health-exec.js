// CF-247 s817 (Platform Admin 20 Nov 2026 10:07): Platform Health as a plain-English executive view. Pure functions over the existing payload of
// admin_read('platform_health') (no new read): the top summary (overall health, AI spend in the last 24 hours against the daily cap, blockers, the
// Layer 4 waiting count) and Needs attention (failed scheduled jobs, stuck work, and connections that are down), each in plain words. Everything
// technical (every check, raw job names, schedules, error text, versions) stays under Technical details on the page.
const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : null)
const detailOf = (c) => (c && c.detail && typeof c.detail === 'object' && !Array.isArray(c.detail) ? c.detail : {})
export const OVERALL_WORDS = { ok: 'Healthy', warning: 'Needs attention', critical: 'Something is broken', unknown: 'Not checked yet' }

export function execSummary(h) {
  const checks = Array.isArray(h?.checks) ? h.checks : [], issues = Array.isArray(h?.issues) ? h.issues : []
  const budget = detailOf(checks.find((c) => c.area === 'budgets'))
  const l4 = detailOf(checks.find((c) => c.area === 'Layer 4'))
  const spend = num(budget.openrouter_spend_24h_usd), cap = num(budget.ai_daily_ceiling_usd ?? budget.openrouter_daily_ceiling_usd)
  return {
    overall: ['ok', 'warning', 'critical'].includes(h?.overall) ? h.overall : 'unknown',
    spend, cap, spendShare: spend != null && cap ? Math.min(1, spend / cap) : null,
    blockers: issues.filter((i) => i.severity === 'critical').length,
    layer4: num(l4.pending), layer4Oldest: l4.oldest || null,
  }
}

const JOB_WORDS = {
  'scholarship-coverage-classify': 'The hourly scholarship classifier', 'scholarship-course-attribute-full': 'The nightly scholarship course loader',
  'no-page-propose': 'The hourly "no course page" proposer', 'admission-rule-runner': 'The admission rule runner', 'admission-rule-runner-b': 'The admission rule runner (B)',
  'admission-rule-runner-c': 'The admission rule runner (C)',
}
const jobWords = (j) => JOB_WORDS[j] || `The scheduled job "${String(j || 'unknown').replace(/[-_]/g, ' ')}"`
const timedOut = (e) => /statement timeout|canceling statement/i.test(String(e || ''))
const CONNECTIONS = [[/zoho/i, 'Zoho'], [/wix/i, 'Wix'], [/firecrawl/i, 'Firecrawl'], [/openrouter|(^|_)ai(_|$)/i, 'AI (OpenRouter)'], [/consumer|website|search_probe|search\/api/i, 'Website API']]

// failed jobs, stuck work and connections down: what a Platform Admin acts on. Each item: { kind, tone, title, why, fix? }
export function needsAttention(h) {
  const out = [], issues = Array.isArray(h?.issues) ? h.issues : []
  for (const i of issues) {
    const k = String(i.check_key || ''), d = typeof i.detail === 'object' && i.detail ? i.detail : {}
    if (/(^|:)layer3_/.test(k)) continue      // Layer 3 retired on 12 Oct 2026: the page leaves its sub-checks out, and so does this list
    if (k.startsWith('cron:failed:')) {
      const fails = /(\d+) failure\(s\) in the last 24 hours/.exec(String(i.title || ''))?.[1], lastFailed = /the last run failed/.test(String(i.title || ''))
      if (i.severity !== 'critical' && !lastFailed) continue      // a job that failed now and then but whose last run worked is a detail, not an action
      out.push({ kind: 'job', tone: i.severity === 'critical' ? 'critical' : 'warning', title: `${jobWords(d.job || k.slice(12))} ${lastFailed ? 'failed on its last run' : 'is failing'}`,
        why: `${timedOut(d.last_error) ? 'It ran out of time' : 'It stopped with an error'}${fails ? `; ${fails} failure${fails === '1' ? '' : 's'} in the last 24 hours` : ''}.` })
    } else if (k.startsWith('queue_watch:')) {
      out.push({ kind: 'stuck', tone: i.severity === 'critical' ? 'critical' : 'warning', title: `${String(i.title || '').replace(/:\s*stuck$/i, '')} is stuck`,
        why: d.reason ? `${String(d.reason).replace(/^\d+ waiting and nothing finished since/, 'Waiting work has not moved since')}.` : 'Work is waiting and not moving.', fix: d.resolve || null })
    } else {
      const conn = CONNECTIONS.find(([re]) => re.test(k) || re.test(String(i.area || '')))
      if (conn && (i.severity === 'critical' || /fail|down|not answer|unreachable/i.test(String(i.title || '')))) {
        out.push({ kind: 'connection', tone: i.severity === 'critical' ? 'critical' : 'warning', title: `${conn[1]}: a check is failing`, why: String(i.title || '').replace(/\s*\([^)]*\)\s*$/, '') + '.' })
      }
    }
  }
  const order = { critical: 0, warning: 1 }
  return out.sort((a, b) => (order[a.tone] ?? 9) - (order[b.tone] ?? 9))
}
