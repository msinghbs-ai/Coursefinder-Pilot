// Provider Description autonomy mandate (4 November 2026): navigation in the
// existing Inbox only. Its authoritative key order is (order, kind, time, ref).
export function layer4DeepLinkCursor(kinds, kind, ref, createdAt) {
  const rawOrder = kinds?.[kind]?.order, order = Number(rawOrder)
  if (rawOrder == null || rawOrder === '' || !Number.isInteger(order) || typeof kind !== 'string' || typeof ref !== 'string' || typeof createdAt !== 'string' || !createdAt || Number.isNaN(Date.parse(createdAt)) || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(ref)) return null
  // Canonical UUIDs have a fixed textual width. Their immediate predecessor
  // includes this item first even when a bulk arrival shares its microsecond.
  const n = BigInt(`0x${ref.replaceAll('-', '')}`)
  const hex = n ? (n - 1n).toString(16).padStart(32, '0') : ''
  const before = hex ? `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}` : ''
  return { after_o: order, after_kind: kind, after_at: createdAt, after_ref: before }
}
