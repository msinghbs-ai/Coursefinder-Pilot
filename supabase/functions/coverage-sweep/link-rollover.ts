// s891 (20 Nov 2026, CF-247 session S1-CourseLink-2027-CRICOS, Platform Admin 22:58 AEDT): rule course_link_year_rollover_v1.
// A held official course page whose address carries a past curriculum year (/2023/, -2023, ?year=2023) is tried at the upcoming year, then
// the current year, then the year before, then at the address held. The first address that answers a plain read (no Firecrawl, no AI) on the
// same host, without a "not found" or "no longer offered" page, and is proved to be this course's page by the platform's own identity rule
// (the exact CRICOS code for Australia) is the one the database may admit. Pure functions only: the worker mode link_year_rollover fetches,
// and security.link_rollover_record_v1 decides.
export const LINK_ROLLOVER_VERSION = "link-year-rollover-v1";

export type RolloverCandidate = { url: string; year: number | null; held: boolean };

const YEAR = "(?:19|20)[0-9]{2}";

/** Where the curriculum year sits in a course page address: a whole path segment, a path segment's -YYYY end, or a query value. */
export function addressYear(url: string): { year: number; at: "segment" | "suffix" | "query" } | null {
  let u: URL;
  try { u = new URL(url) } catch { return null }
  const seg = u.pathname.match(new RegExp(`/(${YEAR})(?=/|$)`));
  if (seg) return { year: Number(seg[1]), at: "segment" };
  const suf = u.pathname.match(new RegExp(`[-_](${YEAR})(?=/|$)`));
  if (suf) return { year: Number(suf[1]), at: "suffix" };
  for (const [, v] of u.searchParams) if (new RegExp(`^${YEAR}$`).test(v)) return { year: Number(v), at: "query" };
  return null;
}

function withYear(url: string, at: "segment" | "suffix" | "query", from: number, to: number): string {
  const u = new URL(url);
  if (at === "query") {
    for (const [k, v] of [...u.searchParams]) if (v === String(from)) { u.searchParams.set(k, String(to)); break }
    return u.toString();
  }
  const re = at === "segment" ? new RegExp(`/${from}(?=/|$)`) : new RegExp(`([-_])${from}(?=/|$)`);
  u.pathname = u.pathname.replace(re, at === "segment" ? `/${to}` : `$1${to}`);
  return u.toString();
}

/**
 * The addresses to try, newest first: the upcoming year, the current year, the year before (each only when later than the held year), then
 * the held address itself. An archived handbook address (a path segment "archive") is never offered as the held fallback.
 */
export function yearCandidates(url: string, currentYear: number): RolloverCandidate[] {
  const y = addressYear(url);
  if (!y || y.year >= currentYear + 1) return [];
  const out: RolloverCandidate[] = [];
  for (const to of [currentYear + 1, currentYear, currentYear - 1]) {
    if (to <= y.year) continue;
    const c = withYear(url, y.at, y.year, to);
    if (!out.some((o) => o.url === c)) out.push({ url: c, year: to, held: false });
  }
  if (!/\/archive(?=\/|$)/i.test(new URL(url).pathname)) out.push({ url, year: y.year, held: true });
  return out;
}

const hostOf = (u: string) => { try { return new URL(u).hostname.toLowerCase().replace(/^www\./, "") } catch { return "" } };

/** Whether a plain read of a candidate is a live page for it (the identity proof is checked by the caller with the platform's rule). */
export function pageAnswer(p: { http: number | null; requested: string; finalUrl: string; year: number | null; text: string; minChars: number; markers: string[]; jsonIdentity: boolean }): { ok: boolean; reason: string } {
  if (p.http !== 200) return { ok: false, reason: p.http === null ? "no_answer" : `http_${p.http}` };
  if (hostOf(p.finalUrl) !== hostOf(p.requested)) return { ok: false, reason: "moved_to_another_host" };
  let path = "/";
  try { path = new URL(p.finalUrl).pathname } catch { return { ok: false, reason: "bad_final_address" } }
  if (path === "/" || /(^|\/)(search|404|not-?found|error|page-not-found)(\/|$|\.)/i.test(path)) return { ok: false, reason: "moved_to_a_general_page" };
  if (p.year !== null && !String(p.finalUrl).includes(String(p.year))) return { ok: false, reason: "moved_to_another_year" };
  const low = p.text.toLowerCase();
  const hit = p.markers.map((m) => String(m || "").toLowerCase().trim()).filter(Boolean).find((m) => low.includes(m.replace("{year}", String(p.year ?? ""))));
  if (hit) return { ok: false, reason: `page_says: ${hit}` };
  if (p.text.length < p.minChars && !p.jsonIdentity) return { ok: false, reason: "page_needs_a_browser" };
  return { ok: true, reason: "live" };
}

/** The identity proofs strong enough for this rule: Australia's exact CRICOS code, New Zealand's own programme code, a university adapter's code. */
export function strongIdentity(basis: string | null | undefined, country: string): boolean {
  const b = String(basis || "");
  if (country.toUpperCase() === "AU") return b === "cricos_code" || b === "adapter_code";
  return b === "nzqa_code" || b === "adapter_code";
}
