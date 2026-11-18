// CF-247 S1-RM-Design (Platform Admin 18 Nov 2026 21:23, s696): which fields each role sees in the record drawers.
// Two audiences. Student-facing fields are what a Counsellor can read to a student; internal fields are provenance,
// audit and diagnostics. Viewer and Counsellor see student-facing fields only; Editor (Curator, Pipeline Operator and
// PIM Operator, ranks 3 to 5) and Platform Admin (rank 6) see both. This decides what the screen shows; the server's
// role checks stay the access control. "Preview as" lets an Editor or Platform Admin see a lower role's view; it can
// only lower what is shown, never raise it.

export const ROLE_TIERS = [
  { key: 'viewer', label: 'Viewer', ranks: [1], audience: 'student' },
  { key: 'counsellor', label: 'Counsellor', ranks: [2], audience: 'student' },
  { key: 'editor', label: 'Editor', ranks: [3, 4, 5], audience: 'internal', note: 'Curator, Pipeline Operator and PIM Operator' },
  { key: 'platform_admin', label: 'Platform Admin', ranks: [6], audience: 'internal' },
]

// Each field (or on-screen marker) and who sees it. `selector` is the element on the drawer that carries it, so one
// rule both documents and hides it.
export const FIELD_VISIBILITY = [
  { field: 'change_tag', label: 'Automated or entered-by-hand tag', audience: 'internal', selector: '.re-auto, .re-lock-wrap' },
  { field: 'edit_actions', label: 'Change and Remove buttons', audience: 'internal', selector: '.re-actions' },
  { field: 'rule_id', label: 'Study rule id', audience: 'internal', selector: '[data-vis="rule_id"]' },
  { field: 'confidence', label: 'Match confidence and locality match share', audience: 'internal', selector: '[data-vis="confidence"]' },
  { field: 'hook_detail', label: 'Layer 4 hook detail', audience: 'internal', selector: '[data-vis="hook_detail"]' },
  { field: 'prompt_version', label: 'AI prompt version and read cost', audience: 'internal', selector: '[data-vis="prompt_version"], [data-course-entry-reads]' },
  { field: 'layer4_queue_state', label: 'Layer 4 queue state and corrections', audience: 'internal', selector: '.cf-layer4-override, [data-vis="layer4_queue_state"]' },
  { field: 'raw_quote', label: 'Raw quote diagnostics', audience: 'internal', selector: '[data-vis="raw_quote"]' },
  { field: 'approval_status', label: 'Approval and edition status', audience: 'internal', selector: '[data-vis="approval_status"]' },
  { field: 'dataset_edition', label: 'Dataset edition', audience: 'internal', selector: '[data-vis="dataset_edition"]' },
  { field: 'identifiers', label: 'Record id and stable key', audience: 'internal', selector: '[data-identifiers]' },
  { field: 'fill_actions', label: 'Fill, extract and re-read actions', audience: 'internal', selector: '[data-fill-fields-card], [data-vis="fill_actions"]' },
  { field: 'value', label: 'The value itself (fee, intake, figure, rank)', audience: 'student' },
  { field: 'source_link', label: 'Source page link', audience: 'student' },
  { field: 'attribution_text', label: 'Attribution the licence requires beside a figure', audience: 'student' },
  { field: 'reference_period', label: 'Period the figure covers', audience: 'student' },
  { field: 'climate_icon', label: 'Climate icon (long-term average)', audience: 'student' },
]

export const PREVIEW_ROLES = [
  { key: 'admin', label: 'Admin', tier: null },
  { key: 'counsellor', label: 'Counsellor', tier: 'counsellor' },
  { key: 'viewer', label: 'Viewer', tier: 'viewer' },
]

export function tierOfRank(rank) {
  const r = Number(rank) || 0
  return ROLE_TIERS.find(t => t.ranks.includes(r))?.key || (r >= 6 ? 'platform_admin' : 'viewer')
}
const ORDER = ROLE_TIERS.map(t => t.key)
// the tier the screen uses: the person's own, or the preview when it is lower (a preview never raises)
export function effectiveTier(rank, preview = 'admin') {
  const own = tierOfRank(rank), p = PREVIEW_ROLES.find(x => x.key === preview)?.tier
  return p && ORDER.indexOf(p) < ORDER.indexOf(own) ? p : own
}
export const audienceOf = tier => ROLE_TIERS.find(t => t.key === tier)?.audience || 'student'
export function canSee(field, tier) {
  const f = FIELD_VISIBILITY.find(x => x.field === field)
  if (!f) return audienceOf(tier) === 'internal' // an unlisted field is internal until it is listed
  return f.audience === 'student' || audienceOf(tier) === 'internal'
}
export const canPreview = rank => audienceOf(tierOfRank(rank)) === 'internal'
// the matrix the Guide and the admin spec print: one row per field, one column per role
export function visibilityMatrix() {
  return FIELD_VISIBILITY.map(f => ({ field: f.field, label: f.label, ...Object.fromEntries(ROLE_TIERS.map(t => [t.key, canSee(f.field, t.key)])) }))
}
// CSS that hides every internal marker inside a drawer showing a student-facing tier
export function studentHideCss(scope = '[data-view-audience="student"]') {
  return FIELD_VISIBILITY.filter(f => f.audience === 'internal' && f.selector)
    .map(f => f.selector.split(',').map(s => `${scope} ${s.trim()}`).join(',')).join(',') + '{display:none!important}'
}
