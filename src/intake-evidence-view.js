// CF-247 F-INT.04: a readable view of one stored intake evidence record.
// Reads only fields the server already returns; a field that is absent shows "Not held", never a guess.
const text = x => (typeof x === 'string' && x.trim()) ? x.trim() : (typeof x === 'number' || typeof x === 'boolean') ? String(x) : null

export function summariseEvidence(e) {
  const r = e && typeof e === 'object' ? e : {}
  const year = text(r.evidence_year) ?? text(r.planned?.year)
  const rows = [
    ['Source quote', text(r.page_quote)],
    ['Evidence year', year],
    ['Reason', text(r.reason)],
    ['Locked', text(r.locked)],
    ['Decided by', text(r.decided_by) ?? text(r.actor)],
    ['Next scheduled attempt', text(r.next_attempt_at)],
  ]
  return rows.map(([label, v]) => ({ label, value: v ?? 'Not held', held: v != null }))
}
