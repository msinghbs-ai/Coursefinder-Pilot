// CF-247 Scholarship Coverage Recovery (Platform Admin mandate 2 Nov 2026 17:41; overnight direction 2 Nov 2026 23:24 §1 Scholarships, §3).
// Pure helpers for scholarship catalogues, kept apart from the worker so the central guard (s226) runs them directly:
//   F3 mapOutcome      a refused or failed site map is "deferred" (tried again later), never a final "empty";
//   F5 awardSections   an umbrella page that lists several awards (UNSW "Scholarships for International Students Commencing Term 1,
//                      2027": ten awards, most without their own page) becomes one item per award, keyed by the award code;
//      sectionHtml     the copy of an umbrella page the reader keeps for one award: the page with the other awards' rows removed, so
//                      the shared eligibility text (Residency: International) stays and no other award's value is read;
//   F5b labelSections  (s1037) an umbrella page whose awards carry no code and sit under group headings: awards named by a heading, by a bold label
//                      under a group heading (Charles Darwin) or by tier blocks under one heading (Lincoln flagship); finer than the heading split (s1035),
//                      so it comes first; items keyed S-<slug>, read as award sections like a coded award;
//   F6 nextPage        the next page of a paginated catalogue (rel="next", a "Next" link, page=N, or startRank/numRanks in the query or
//                      in the fragment of a script catalogue such as UNSW's HDR finder); statedTotal reads a printed result total;
//                      pagingState says complete only when the pagination ended (no next page, the stated total reached, or an empty page);
//   F7 redirectOutcome a page that now opens somewhere else: "moved" (another detail page) or "redirected_away" (the site or catalogue home,
//                      a listing, a search page): the old address is not a scholarship page any more.
// Nothing here fetches, spends or decides admission.
import { htmlToText } from "./extract.ts";
import { headingAwardSections, headingSectionHtml, headingSlug, HEADING_AWARD_PREFIX } from "./scholarship.ts";  // s1035: heading-based awards

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

export function awardSections(html: string, baseUrl: string, opts?: { labels?: boolean }): AwardSection[] {
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
  // s1035: no coded awards on the page: an umbrella that prints its awards under headings is split by heading (scholarship.ts)
  // s1037: with the setting on, awards named by a heading, a bold label or a tier block come first (they are finer than the heading split below)
  if (seen.size < 2 && opts?.labels) { const l = labelSections(html, baseUrl); if (l.length) return l }
  if (seen.size < 2) return headingAwardSections(html).map((h) => ({ key: h.key, codes: h.codes, name: h.name, value_text: h.value_text, url: null }));
  return [...seen.values()];
}

// The copy kept for one award of an umbrella page: the other awards' blocks removed, the shared text kept. Null when the award is not there.
export function sectionHtml(html: string, code: string, opts?: { labels?: boolean }): string | null {
  if (/^S-/i.test(code)) return (opts?.labels ? labelSectionHtml(html, code) : null) ?? headingSectionHtml(html, code);  // s1037: with the setting on the label section first, then the s1035 heading section
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
  const m = url.match(/#award-([a-z]{4}\d{4}|s-[a-z0-9-]{3,60})$/i);
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

// ---- F5b label-and-tier award sections (s1032, Platform Admin 24 Nov 2026) ---------------------------------------------------------------
// Pages that print their awards without codes. Three shapes, one rule: a page is cut into blocks (a heading, a label printed wholly in bold, or
// a paragraph / list item / table cell of text); an award label is a heading of level 2 or lower, or a bold label, that names an award
// (scholarship, award, bursary, grant, fellowship, prize, rebate, waiver) and is not a call to action or a bare category ("Other Scholarships");
// a label with a deeper label directly under it is a group, not an award (Charles Darwin: the h2 "CDU Scholarships" over bold award labels;
// Lincoln: the h3 "Other Scholarships" over h4 awards). An award's section runs to the next label or the next heading that closes it. Inside
// one award, two or more blocks that begin with an amount, a percentage or "Automatic" are tiers (Lincoln flagship: NZ$2,500, NZ$3,000, ...),
// and each tier is its own award named "<award> - <tier>". The page must give at least two awards, two of them with a stated value.
// Nothing here fetches, spends or decides admission; the extractor and the admission rules read each section as they read any award.
const LABEL_AWARD = /\b(scholarships?|awards?|bursar(?:y|ies)|grants?|fellowships?|prizes?|rebates?|waivers?)\b/i;
const LABEL_NOUN = "(?:scholarships?|awards?|bursar(?:y|ies)|grants?|prizes?)";
const LABEL_GENERIC = new RegExp(`^(?:(?:other|general|international|domestic|university|all|our|current|available|new|existing|key|major|more|further|additional|government|external|research|equity|merit)\\s+)*${LABEL_NOUN}(?:\\s+(?:and|&)\\s+${LABEL_NOUN})?$`, "i");
const LABEL_CTA = /^(?:apply|how to|how do|tips|find|search|view|see|read|contact|terms|conditions|frequently|faq|important|key dates|about|why|do you|what|who |when |where |ready to|have you|looking for|check|scholarship application|\d+ tips)/i;
const LABEL_VALUE = /(?:[A-Z]{0,3}\$\s?\d|\d\s?%|\b(?:AUD|NZD|USD)\b|\btuition\b|\bfees?\b|\bfull\b|\bhalf\b|\bup to\b)/;
const LABEL_TIER = /^(?:up to\s+|a\s+|an\s+)?(?:[A-Z]{0,3}\$|(?:NZD|AUD|USD|CAD|GBP)\s?)\s?\d|^\d{1,3}(?:\.\d+)?\s?%|^automatic\b/i;
const BLOCK_TAGS = new Set(["p", "div", "li", "ul", "ol", "tr", "td", "th", "dt", "dd", "br", "section", "article", "table", "thead", "tbody", "header", "footer", "aside", "form", "blockquote", "hr", "figure", "figcaption", "details", "summary"]);
type Seg = { k: "h" | "b" | "t" | "s"; level: number; text: string; links: string[] };
export type LabelSection = AwardSection & { group: string; body: string[]; intro: string };

const decodeEntities = (t: string) => t
  .replace(/&nbsp;|&#160;|&#xa0;/gi, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;|&#39;|&#x27;/g, "'")
  .replace(/&#8217;|&rsquo;/g, "\u2019").replace(/&#8211;|&ndash;/g, "\u2013").replace(/&#8212;|&mdash;/g, "\u2014")
  .replace(/&#(\d+);/g, (_, n) => { try { return String.fromCodePoint(Number(n)) } catch { return " " } });

// the page as an ordered list of blocks: a heading (with its level), a block printed wholly in bold (a label), or text; links stay with their block
function segments(main: string): Seg[] {
  const out: Seg[] = [];
  const src = main.replace(/<!--[\s\S]*?-->/g, " ").replace(/<(script|style|noscript|svg|template)\b[\s\S]*?<\/\1>/gi, " ");
  let buf = "", bold = 0, plain = 0, boldDepth = 0, head = 0, sum = 0, links: string[] = [];
  const flush = () => {
    const text = buf.replace(/\s+/g, " ").trim();
    if (text) out.push({ k: head ? "h" : sum ? "s" : (bold > 0 && bold >= 0.9 * (bold + plain) && text.length <= 160 ? "b" : "t"), level: head, text, links });
    buf = ""; bold = 0; plain = 0; links = [];
  };
  for (const m of src.matchAll(/<(\/?)([a-z][a-z0-9]*)\b([^>]*)>|([^<]+)/gi)) {
    if (m[4] !== undefined) {
      const t = decodeEntities(m[4]);
      buf += t;
      const n = t.replace(/\s+/g, "").length;
      if (boldDepth > 0 || head || sum) bold += n; else plain += n;
      continue;
    }
    const close = m[1] === "/", tag = m[2].toLowerCase();
    if (/^h[1-6]$/.test(tag)) { flush(); head = close ? 0 : Number(tag[1]); continue }
    if (tag === "summary") { flush(); sum = close ? 0 : 1; continue }  // s1051: an expandable section's toggle (<details><summary>) names the award it holds (Charles Darwin: eight awards)
    if (tag === "strong" || tag === "b") { boldDepth = Math.max(0, boldDepth + (close ? -1 : 1)); continue }
    if (tag === "a" && !close) { const h = m[3].match(/href\s*=\s*["']([^"']+)["']/i); if (h) links.push(decodeEntities(h[1])); continue }
    if (BLOCK_TAGS.has(tag)) flush();
  }
  flush();
  return out;
}

const cleanLabel = (t: string) => t.replace(/[\s*:\u2013\u2014-]+$/g, "").replace(/\s+/g, " ").trim();
const labelOk = (t: string) => t.length >= 6 && t.length <= 160 && LABEL_AWARD.test(t) && !LABEL_CTA.test(t) && !/\?$/.test(t) && !LABEL_GENERIC.test(cleanLabel(t));
// a stable section key: "S-" and the award's name as an upper-case slug (the key scheme of the heading splitter, s1035, which the database already
// accepts in the listing-member and admit functions); a name seen twice on one page gets "-2", "-3" ...
function sectionKey(name: string, taken: Set<string>): string {
  const base = (HEADING_AWARD_PREFIX + (headingSlug(name) || "award").toUpperCase()).slice(0, 56).replace(/-+$/, "");
  let key = base, n = 2;
  while (taken.has(key)) key = `${base}-${n++}`;
  taken.add(key);
  return key;
}
const pickUrl = (links: string[], baseUrl: string): string | null => {
  for (const href of links) {
    try { const u = new URL(href.replace(/&amp;/g, "&"), baseUrl); u.hash = "";
      if (/^https?:$/.test(u.protocol) && !/\.(pdf|docx?)(\?|$)/i.test(u.pathname) && !/login|apply|sc_search|mailto/i.test(u.href) && !/\/scholarships?\/?$/i.test(u.pathname) && u.href.replace(/\/$/, "") !== baseUrl.split("#")[0].replace(/\/$/, "")) return u.href } catch { /* */ }
  }
  return null;
};

// Programme-specific scholarship tables: the source names the programme and its own benefit in adjacent cells.
// Keep this in the existing label reader. The strict heading/header/shared-eligibility shape is required;
// an arbitrary fees table, ambiguous duplicate title, unavailable award or pending qualification is not an award.
function programmeTableSections(html: string): LabelSection[] {
  const main = mainOf(html).replace(/<!--[\s\S]*?-->/g, " ").replace(/<(script|style|noscript|svg|template)\b[\s\S]*?<\/\1>/gi, " ");
  const plain = (s: string) => decodeEntities(s.replace(/<[^>]*>/g, " ")).replace(/\s+/g, " ").trim();
  const heading = /<h[1-4]\b[^>]*>\s*International Scholarships\s*<\/h[1-4]>/i.exec(main);
  const details = /<h[2-5]\b[^>]*>\s*Scholarship details per programme\s*<\/h[2-5]>/i.exec(main);
  const disclaimer = /<h[2-5]\b[^>]*>\s*Scholarship Disclaimer\s*<\/h[2-5]>/i.exec(main);
  if (!heading || !details || !disclaimer || heading.index >= details.index || details.index >= disclaimer.index) return [];
  const intro = plain(main.slice(heading.index + heading[0].length, details.index));
  const after = main.slice(disclaimer.index + disclaimer[0].length);
  const end = after.search(/<h[1-4]\b/i);
  const terms = plain(end < 0 ? after : after.slice(0, end));
  // These are source assertions, not fabricated defaults. Do not split a table without common international tuition eligibility.
  if (intro.length > 1200 || terms.length > 3000 ||
      !/\binternational students\b/i.test(intro) || !/\btuition fees\b/i.test(intro) ||
      !/\bnew\b.{0,80}\binternational students\b/i.test(terms) ||
      !/\b(?:eligible|offer)\b/i.test(terms) || !/\b20\d{2}\b/.test(terms)) return [];
  const tableRegion = main.slice(details.index + details[0].length, disclaimer.index);
  const tables = [...tableRegion.matchAll(/<table\b[^>]*>[\s\S]*?<\/table>/gi)];
  const rowsOf = (table: string) => [...table.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/gi)]
    .map(row => [...row[1].matchAll(/<(th|td)\b[^>]*>([\s\S]*?)<\/\1>/gi)].map(cell => plain(cell[2])));
  const candidates = tables.map(t => rowsOf(t[0])).filter(rows => rows.some(r => r.length === 2 &&
    /^programme name$/i.test(r[0]) && /^scholarship$/i.test(r[1])));
  if (candidates.length !== 1) return [];
  const rows = candidates[0];
  const at = rows.findIndex(r => r.length === 2 && /^programme name$/i.test(r[0]) && /^scholarship$/i.test(r[1]));
  const byName = new Map<string, { title: string; amount: string; count: number }>();
  for (const r of rows.slice(at + 1)) {
    if (r.length !== 2 || !r[0] || !r[1]) continue; // category/header rows have no monetary value
    const title = r[0], amount = r[1];
    if (title.length < 8 || title.length > 180 || /\bpending\b|course page coming soon|subject to approval/i.test(title)) continue;
    if (!/^(?:NZ\s*)?\$\s*[1-9]\d{0,2}(?:,\d{3})*(?:\.\d{2})?$|^NZD\s+[1-9]\d{0,2}(?:,\d{3})*(?:\.\d{2})?$/i.test(amount)) continue;
    const identity = headingSlug(title);
    if (!identity) continue;
    const old = byName.get(identity);
    if (old) { old.count++; continue } // even equal amounts cannot establish two distinct programme identities
    byName.set(identity, { title, amount, count: 1 });
  }
  const out: LabelSection[] = [], used = new Set<string>();
  for (const r of byName.values()) {
    if (r.count !== 1) continue;
    const name = r.title + " - International Scholarship";
    const key = sectionKey(name, used);
    // Ordinal keys are ambiguous when a table is reordered. Fail closed on slug truncation collisions.
    if (key !== (HEADING_AWARD_PREFIX + headingSlug(name).toUpperCase()).slice(0, 56).replace(/-+$/, "")) return [];
    out.push({ key, codes: [key], name, value_text: r.amount, url: null,
      group: "International Scholarships", intro, body: ["Programme: " + r.title, "Scholarship: " + r.amount, terms] });
  }
  return out.length >= 2 ? out : [];
}

export function labelSections(html: string, baseUrl: string): LabelSection[] {
  const programmeTable = programmeTableSections(html);
  if (programmeTable.length) return programmeTable;
  const segs = segments(mainOf(html));
  type Cand = { i: number; rank: number; name: string };
  const cands: Cand[] = [];
  // s1051: when the page gives two or more expandable-section toggles that name awards, the toggles are the award labels and a bold label inside
  // a section ("Type of Award:") is part of that award, not a new one
  const toggles = segs.filter((s) => s.k === "s" && labelOk(s.text)).length >= 2;
  segs.forEach((s, i) => { if (((s.k === "h" && s.level >= 2) || (s.k === "s") || (s.k === "b" && !toggles)) && labelOk(s.text)) cands.push({ i, rank: s.k === "h" ? s.level : 7, name: cleanLabel(s.text) }) });
  const isCand = new Set(cands.map((c) => c.i));
  const intro = segs.slice(0, cands.length ? cands[0].i : 0).filter((x) => x.k === "t").map((x) => x.text).join(" ").slice(0, 1500);  // the text ahead of the first award is shared by every award
  const taken = new Set<string>(), out: LabelSection[] = [];
  cands.forEach((c) => {
    // a group: a deeper award label sits under it before the next heading at its own level or above (a bare category such as "Other
    // Scholarships" is never an award itself, so only headings, not award labels, close the scan)
    if (c.rank < 7) {
      let group = false;
      for (let k = c.i + 1; k < segs.length; k++) {
        if (segs[k].k === "h" && segs[k].level <= c.rank) break;
        if (isCand.has(k) && cands.find((x) => x.i === k)!.rank > c.rank) { group = true; break }
      }
      if (group) return;
    }
    let end = segs.length;
    for (let k = c.i + 1; k < segs.length; k++) {
      if (isCand.has(k) || (segs[k].k === "h" && (c.rank === 7 || segs[k].level <= c.rank))) { end = k; break }
    }
    // the nearest heading above that is not this award (the group the award sits under)
    let group = "";
    for (let k = c.i - 1; k >= 0; k--) if (segs[k].k === "h" && segs[k].level >= 1 && (c.rank === 7 || segs[k].level < c.rank)) { group = cleanLabel(segs[k].text); break }
    const body = segs.slice(c.i + 1, end), links = [...segs[c.i].links, ...body.flatMap((b) => b.links)];
    const tierAt = body.map((b, i) => (b.k === "t" && LABEL_TIER.test(b.text) ? i : -1)).filter((i) => i >= 0);
    if (tierAt.length >= 2) {
      const lead = body.slice(0, tierAt[0]);
      tierAt.forEach((at, ti) => {
        const blk = body.slice(at, ti + 1 < tierAt.length ? tierAt[ti + 1] : body.length);
        const first = blk[0].text.split(/\.\s|\.$/)[0];  // the tier's own label: its first sentence
        const tier = first.length > 90 ? first.slice(0, 90).replace(/\s+\S*$/, "") : first;
        const name = `${c.name} - ${cleanLabel(tier)}`;
        out.push({ key: sectionKey(name, taken), codes: [], name, value_text: blk[0].text.slice(0, 300), url: pickUrl(blk.flatMap((b) => b.links), baseUrl), group: group || c.name, body: [...lead, ...blk].map((b) => b.text), intro });
      });
      return;
    }
    const valueSeg = body.find((b) => LABEL_VALUE.test(b.text)) || body[0];
    out.push({ key: sectionKey(c.name, taken), codes: [], name: c.name, value_text: (valueSeg?.text || "").slice(0, 300), url: pickUrl(links, baseUrl), group, body: body.map((b) => b.text), intro });
  });
  // s1052: a link two or more awards share (Charles Darwin: the terms page two awards point to) names no single award, so it is not an award address: those awards keep their section keys
  const used = new Map<string, number>();
  for (const s of out) if (s.url) used.set(s.url, (used.get(s.url) || 0) + 1);
  for (const s of out) if (s.url && (used.get(s.url) || 0) > 1) s.url = null;
  for (const s of out) s.codes = [s.key];
  // an umbrella lists several awards, at least two of them with a stated value; anything less is a page about one award or a list of links
  const valued = out.filter((s) => LABEL_VALUE.test(s.name) || LABEL_VALUE.test(s.body.join(" ")));
  return out.length >= 2 && valued.length >= 2 ? out : [];
}

// the copy kept for one label section: the award's name, the group it sits under and its own text; the other awards are left out
function labelSectionHtml(html: string, code: string): string | null {
  const s = labelSections(html, "https://x.invalid/").find((x) => x.key === code);
  if (!s) return null;
  const esc = (t: string) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const h1 = (html.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1] || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
  return `<html><head><title>${esc(s.name)} | ${code}</title></head><body><h1>${esc(s.name)}</h1>${h1 ? `<p>${esc(decodeEntities(h1))}</p>` : ""}${s.group && s.group !== s.name ? `<h2>${esc(s.group)}</h2>` : ""}<main>${s.intro ? `<p>${esc(s.intro)}</p>` : ""}${s.body.map((t) => `<p>${esc(t)}</p>`).join("")}</main></body></html>`;
}
