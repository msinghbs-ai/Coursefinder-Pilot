// CF-247 Scholarship Coverage Recovery (Platform Admin mandate 2 Nov 2026 17:41; overnight direction 2 Nov 2026 23:24 §1 Scholarships, §3).
// Pure helpers for scholarship catalogues, kept apart from the worker so the central guard (s224) runs them directly:
//   F3 mapOutcome      a refused or failed site map is "deferred" (tried again later), never a final "empty";
//   F5 awardSections   an umbrella page that lists several awards (UNSW "Scholarships for International Students Commencing Term 1,
//                      2027": ten awards, most without their own page) becomes one item per award, keyed by the award code;
//      sectionHtml     the copy of an umbrella page the reader keeps for one award: the page with the other awards' rows removed, so
//                      the shared eligibility text (Residency: International) stays and no other award's value is read;
//   F6 nextPage        the next page of a paginated catalogue (rel="next", a "Next" link, page=N, or startRank/numRanks in the query or
//                      in the fragment of a script catalogue such as UNSW's HDR finder); statedTotal reads a printed result total;
//                      pagingState says complete only when the pagination ended (no next page, the stated total reached, or an empty page);
//   F7 redirectOutcome a page that now opens somewhere else: "moved" (another detail page) or "redirected_away" (the site or catalogue home,
//                      a listing, a search page): the old address is not a scholarship page any more.
// Nothing here fetches, spends or decides admission.
import { htmlToText } from "./extract.ts";

export type MapOutcome = "mapped" | "empty" | "deferred";
// methods as the worker records them: "map_search(72)", "map:403", "map:scholarship_share", "map:credits_refused", ...
export function mapOutcome(methods: string[], kept: number): MapOutcome {
  if (kept > 0) return "mapped";
  const ran = methods.some((m) => /^map_search\(\d+\)$/.test(m));
  // a map that ran and found nothing is empty; a refusal (budget, share, cap, key) or a failed call (429, 5xx, timeout) is not evidence of zero
  if (ran && !methods.some((m) => /^map:/.test(m))) return "empty";
  return "deferred";
}

// award codes as universities print them (UNSW PUCA1025, UGCA1603, PGCA1107): four capitals and four digits
const CODE = /\b([A-Z]{4}\d{4})\b/g;
const mainOf = (html: string) => { const m = html.match(/<main[\s\S]*?<\/main>/i); return m && m[0].length > 400 ? m[0] : html };
export type AwardSection = { key: string; codes: string[]; name: string; value_text: string; url: string | null };

// One block per award: a table row (or list item) naming at least one code, or a heading with a code and the text under it.
function blocks(main: string): { html: string; start: number }[] {
  const out: { html: string; start: number }[] = [];
  for (const m of main.matchAll(/<(tr|li)\b[\s\S]*?<\/\1>/gi)) if (CODE.test(m[0].replace(/<[^>]+>/g, " "))) out.push({ html: m[0], start: m.index || 0 }), CODE.lastIndex = 0;
  CODE.lastIndex = 0;
  if (out.length) return out;
  const hs = [...main.matchAll(/<h([2-4])\b[^>]*>[\s\S]*?<\/h\1>/gi)];
  hs.forEach((h, i) => {
    const end = i + 1 < hs.length ? hs[i + 1].index! : main.length;
    const html = main.slice(h.index!, end);
    if (new RegExp(CODE.source).test(h[0].replace(/<[^>]+>/g, " "))) out.push({ html, start: h.index! });
  });
  return out;
}

export function awardSections(html: string, baseUrl: string): AwardSection[] {
  const main = mainOf(html);
  const seen = new Map<string, AwardSection>();
  for (const b of blocks(main)) {
    const text = htmlToText(b.html).replace(/\s+/g, " ").trim();
    const codes = [...new Set([...text.matchAll(new RegExp(CODE.source, "g"))].map((m) => m[1]))];
    if (!codes.length) continue;
    // the name is the text before the first code ("International Scientia Coursework Scholarship (PUCA1025)")
    const before = text.slice(0, text.indexOf(codes[0])).replace(/[\s(\[–—:-]+$/, "").trim();
    const name = before.split(/\s{2,}|\|/).pop()!.trim().slice(0, 200);
    if (name.length < 6) continue;
    const after = text.slice(text.indexOf(codes[codes.length - 1]) + codes[codes.length - 1].length).replace(/^[\s)\]:,–—-]+/, "").slice(0, 300);
    let url: string | null = null;
    for (const a of b.html.matchAll(/<a\b[^>]*href\s*=\s*["']([^"'#][^"']*)["']/gi)) {
      try { const u = new URL(a[1].replace(/&amp;/g, "&"), baseUrl); if (/^https?:$/.test(u.protocol) && !/\.(pdf|docx?)(\?|$)/i.test(u.pathname) && !/login|apply|sc_search/i.test(u.href)) { url = u.href; break } } catch { /* */ }
    }
    const key = codes[0];
    if (!seen.has(key)) seen.set(key, { key, codes, name, value_text: after, url });
  }
  // an umbrella lists several awards; one coded award on a page is that award's own page
  return seen.size >= 2 ? [...seen.values()] : [];
}

// The copy kept for one award of an umbrella page: the other awards' blocks removed, the shared text kept. Null when the award is not there.
export function sectionHtml(html: string, code: string): string | null {
  const main = mainOf(html);
  const bs = blocks(main);
  const mine = bs.filter((b) => new RegExp(`\\b${code}\\b`).test(htmlToText(b.html)));
  if (!mine.length) return null;
  let out = main;
  for (const b of bs) if (!mine.includes(b)) out = out.replace(b.html, " ");
  const name = awardSections(html, "https://x.invalid/").find((s) => s.codes.includes(code))?.name;
  return `<html><head><title>${name ? name + " | " : ""}${code}</title></head><body>${name ? `<h1>${name}</h1>` : ""}${out}</body></html>`;
}
// "#award-puca1025" on a candidate or page address names the award section of an umbrella page
export function sectionCode(url: string): string | null {
  const m = url.match(/#award-([a-z]{4}\d{4})$/i);
  return m ? m[1].toUpperCase() : null;
}

// ---- F6 pagination ---------------------------------------------------------------------------------------------------------------------
function withParam(qs: string, key: string, value: string) {
  const re = new RegExp(`([?&#]|^)(${key}=)([^&]*)`);
  return re.test(qs) ? qs.replace(re, `$1$2${value}`) : qs;
}
export function nextPage(url: string, html: string): string | null {
  let u: URL; try { u = new URL(url) } catch { return null }
  const rel = html.match(/<link\b[^>]*rel=["']next["'][^>]*href=["']([^"']+)["']/i) || html.match(/<a\b[^>]*rel=["']next["'][^>]*href=["']([^"']+)["']/i);
  if (rel) { try { return new URL(rel[1].replace(/&amp;/g, "&"), url).href } catch { /* */ } }
  for (const a of html.matchAll(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]{0,80}?)<\/a>/gi)) {
    const t = a[2].replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
    if (/^(next|next page|›|»|>)$/i.test(t) || /aria-label=["']next/i.test(a[0])) { try { const n = new URL(a[1].replace(/&amp;/g, "&"), url).href; if (n !== url) return n } catch { /* */ } }
  }
  // a script catalogue keeps its state in the query or the fragment: startRank=1&numRanks=10 -> startRank=11
  for (const part of ["search", "hash"] as const) {
    const s = u[part];
    const sr = s.match(/[?&#]startRank=(\d+)/), nr = s.match(/[?&#]numRanks=(\d+)/);
    if (sr && nr) { const v = new URL(url); v[part] = withParam(s, "startRank", String(Number(sr[1]) + Number(nr[1]))); return v.href }
    const pg = s.match(/[?&#]page=(\d+)/);
    if (pg) { const v = new URL(url); v[part] = withParam(s, "page", String(Number(pg[1]) + 1)); return v.href }
  }
  return null;
}
export function statedTotal(text: string): number | null {
  const m = text.match(/\b(?:of|showing \d+\s*[-–]\s*\d+ of)\s+([\d,]+)\s+(?:results|scholarships|opportunities|awards|projects)\b/i)
    || text.match(/\b([\d,]+)\s+(?:results|scholarships|opportunities|awards|projects)\s+(?:found|available|match)/i)
    || text.match(/\bshowing\s+([\d,]+)\s+(?:results|scholarships|opportunities|awards|projects)\b/i);
  return m ? Number(m[1].replace(/,/g, "")) : null;
}
export type PagingState = { state: "complete" | "partial" | "failed"; reason: string; pages_read: number; items: number; total_stated: number | null; next_url: string | null };
// complete only when the pagination ended by itself; a page limit or a failed page leaves the catalogue partial with its continuation
export function pagingState(p: { pages_read: number; items: number; total_stated: number | null; next_url: string | null; last_page_new: number; failed: boolean; page_limit_hit: boolean }): PagingState {
  const base = { pages_read: p.pages_read, items: p.items, total_stated: p.total_stated, next_url: p.next_url };
  if (p.failed && p.pages_read === 0) return { ...base, state: "failed", reason: "first_page_failed" };
  if (p.failed) return { ...base, state: "partial", reason: "page_failed" };
  if (p.total_stated !== null && p.items >= p.total_stated) return { ...base, state: "complete", reason: "total_reached", next_url: null };
  if (p.total_stated !== null && p.items < p.total_stated && !p.next_url) return { ...base, state: "partial", reason: "total_not_reached" };
  if (!p.next_url) return { ...base, state: "complete", reason: "no_next_page" };
  if (p.pages_read > 1 && p.last_page_new === 0) return { ...base, state: "complete", reason: "empty_page", next_url: null };
  if (p.page_limit_hit) return { ...base, state: "partial", reason: "page_limit" };
  return { ...base, state: "partial", reason: "continuation" };
}

// ---- F7 moved and redirected sources ---------------------------------------------------------------------------------------------------
const AWAY = /^\/?$|^\/(home|index(\.html?)?|scholarships?|scholarships?\/search|search|find-a-scholarship|scholarship-search|study|research\/hdr\/scholarships)\/?$/i;
export function redirectOutcome(requested: string, finalUrl: string | null | undefined): "same" | "moved" | "redirected_away" {
  if (!finalUrl) return "same";
  let a: URL, b: URL; try { a = new URL(requested); b = new URL(finalUrl) } catch { return "same" }
  const norm = (u: URL) => (u.hostname.replace(/^www\./, "") + u.pathname.replace(/\/+$/, "")).toLowerCase();
  if (norm(a) === norm(b)) return "same";
  return AWAY.test(b.pathname) ? "redirected_away" : "moved";
}
