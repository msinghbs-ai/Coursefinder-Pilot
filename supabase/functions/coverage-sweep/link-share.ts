// v0.59.5 (3 Nov 2026, CF-247 P0 autonomous operations; workstream F finding, Integration Controller 18:20): course-page search answered once per
// query. About 70% of paid course-page searches repeated a query already searched (the same title or code for several course rows, or a course
// searched again). With the setting reading.link_search_share_on (ships off) the worker sends one paid search for each distinct query of its
// batch and records that answer for every course row with the query, and an earlier answer for the same query inside the lookback window
// (public.svc_course_link_search_prior_v1, ops_cost.repeat_search_hours) is recorded without a new search: an earlier "no result" answers again.
// The database still picks and checks each course's own page from the answer (svc_course_link_search_record), so nothing else changes.
// Pure functions only: tests/uat/cf-247-s254-worker-ops-requests-contract.spec.mjs runs them.
export function linkSearchShareOn(ws: Record<string, unknown> | null | undefined): boolean { return Number((ws || {})["reading.link_search_share_on"]) >= 1 }
export function linkQueryKey(q: string): string { return String(q || "").normalize("NFKC").toLowerCase().replace(/\s+/g, " ").trim() }
export function linkSearchGroups<T extends { query: string }>(items: T[]): { key: string; query: string; items: T[] }[] {
  const m = new Map<string, { key: string; query: string; items: T[] }>();
  for (const it of items) {
    const key = linkQueryKey(it.query);
    if (!key) continue;
    if (!m.has(key)) m.set(key, { key, query: it.query, items: [] });
    m.get(key)!.items.push(it);
  }
  return [...m.values()];
}
