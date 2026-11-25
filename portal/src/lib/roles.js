// Portal access (design decisions, 25 Nov 2026): Counsellor (rank 2) and above use the portal; a Viewer (rank 1) can browse
// courses, providers and scholarships only. Anyone else, including a signed-in user with no role, sees a plain "no access" page.
// The database enforces the same rule; this only decides what the screen shows.
export const VIEWER_RANK = 1
export const COUNSELLOR_RANK = 2

export function portalAccess(context) {
  const rank = Number(context?.role_rank || 0)
  if (!context?.authenticated || rank < VIEWER_RANK) return { allowed: false, kind: 'none', label: 'No access', rank }
  if (rank >= COUNSELLOR_RANK) return { allowed: true, kind: 'counsellor', label: roleLabel(context.role, 'Counsellor'), rank }
  return { allowed: true, kind: 'viewer', label: 'Viewer', rank }
}

function roleLabel(code, fallback) {
  const text = String(code || '').replace(/[_-]+/g, ' ').trim()
  if (!text || text === 'unassigned') return fallback
  return text.charAt(0).toUpperCase() + text.slice(1)
}

// First name for the greeting: the saved full name if there is one, otherwise the part of the email before the dot, dash or @.
export function firstName(user, context) {
  const full = String(user?.user_metadata?.full_name || user?.user_metadata?.name || '').trim()
  if (full) return full.split(/\s+/)[0]
  const local = String(context?.email || user?.email || '').split('@')[0]
  const part = local.split(/[._-]/)[0]
  return part ? part.charAt(0).toUpperCase() + part.slice(1).toLowerCase() : ''
}

// Melbourne time, so the greeting matches the counsellors' morning.
export function greeting(date = new Date()) {
  const hour = Number(new Intl.DateTimeFormat('en-AU', { hour: 'numeric', hour12: false, timeZone: 'Australia/Melbourne' }).format(date)) % 24
  return hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening'
}
