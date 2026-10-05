// CF-247 Decision 253 (4 Oct 2026): university adapters. Platform Admin, 15:51: "keep setting ui based uni adapters for
// field mappings". An adapter is one university's own settings, kept in pipeline.uni_adapters and changed on the
// Firecrawl panel. Nothing in it is code: it says how that university names its pages (what to take off a page title
// or a catalogue title before they are compared), where a page keeps its data as JSON (for example the __NEXT_DATA__
// script of a handbook built in the browser) and where on the page each field is (a heading pattern or a JSON path).
// An adapter only proposes: a page it confirms gets the identity basis "adapter_code" or "adapter_title", and the
// existing country admission rules decide whether that basis may be admitted (Platform settings, by country and field).
import { currencyFor, english, fee, h1Of, htmlToText, identity, intakeEvidence, intakes, titleOf } from "./extract.ts";

export type Adapter = {
  title_strip?: string | null;          // pattern taken off the page title and heading, e.g. "^[A-Z]{2,8}\\s+" or "\\s+degree program guide$"
  course_title_strip?: string | null;   // pattern taken off the catalogue title, e.g. "\\s*\\(level \\d+\\)$"
  json_source?: string | null;          // id of a <script> holding the page's data as JSON, e.g. "__NEXT_DATA__"
  json_paths?: Record<string, string>;  // field -> dotted path in that JSON: title, code, intakes, english, fee, duration
  sections?: Record<string, string>;    // field -> heading pattern; the field is read from the text after it
  section_chars?: number | null;        // how much text after a heading belongs to it (default 2,000)
  // v0.16.0: field -> pattern on the page text with one bracketed part, the value. Several matches are kept in order and
  // "pick" chooses one: intakes, fee, ielts_overall, campus, mode, duration, study_level, student_type, not_admitting.
  patterns?: Record<string, string>;
  pick?: Record<string, string>;        // field -> "first" (default), "last" or "all"
  term_months?: Record<string, string>; // v0.17.3: term name -> month name(s), the university's published mapping ("Semester 1": "February")
  // v0.17.4 (Platform Admin 5 Oct 11:48 and 13:02): the international student view of the course page. Many course pages
  // show the domestic view unless the address says otherwise (La Trobe "#/fees?location=BU&studentType=int&year=2027",
  // Adelaide "?student=future" with an international path, Curtin "?region=int"). render: read the page through Firecrawl
  // with the view applied (a plain fetch cannot run the page's script); suffix: added to each bound address; wait_ms: time
  // for the page's script to show the view (at most 8,000).
  page_view?: { render?: boolean; suffix?: string; wait_ms?: number } | null;
};

// v0.17.4: the bound address with the university's international view applied. A suffix starting with "#" replaces the
// address's fragment; one starting with "?" or "&" sets those query parameters (existing parameters are kept).
// "{campus}" in the suffix is left as printed unless the address already carries a location parameter.
export function withView(url: string, pv?: Adapter["page_view"]): string {
  const sfx = String(pv?.suffix || "").trim();
  if (!sfx) return url;
  let u: URL; try { u = new URL(url) } catch { return url }
  if (sfx.startsWith("#")) { u.hash = sfx.slice(1); return u.toString() }
  if (sfx.startsWith("?") || sfx.startsWith("&")) {
    for (const [k, v] of new URLSearchParams(sfx.slice(1))) u.searchParams.set(k, v);
    return u.toString();
  }
  return url;
}

// Fields an adapter may give besides intakes, English and fee. They are shown for testing only and never admitted.
export const EXTRA_FIELDS = ["campus", "mode", "duration", "study_level", "student_type", "not_admitting", "aqf_level", "location"];

const clean = (s: string) => String(s || "").replace(/\s+/g, " ").trim();
const norm = (s: string) => clean(s).toLowerCase().replace(/&/g, " and ").replace(/[^a-z0-9]+/g, " ").trim();
const re = (p?: string | null) => { if (!p) return null; try { return new RegExp(p, "i") } catch { return null } };
const strip = (s: string, p?: string | null) => { const r = re(p); return r ? clean(s.replace(new RegExp(r.source, "gi"), " ")) : clean(s) };

// The JSON a page keeps in <script id="...">.
export function pageJson(html: string, id?: string | null): unknown {
  if (!id) return null;
  const m = html.match(new RegExp(`<script[^>]*id=["']${id.replace(/[^A-Za-z0-9_-]/g, "")}["'][^>]*>([\\s\\S]*?)</script>`, "i"));
  if (!m) return null;
  try { return JSON.parse(m[1]) } catch { return null }
}
// A dotted path ("props.pageProps.pageContent.code"); "*" takes every item of a list.
export function jsonAt(data: unknown, path?: string | null): unknown {
  if (!path) return undefined;
  let cur: unknown[] = [data];
  for (const seg of path.split(".")) {
    // v0.17.2: "fees[fee_type=international_fee_paying]" keeps only the list items whose field has that value
    const f = seg.match(/^([^\[]+)\[([^=\]]+)=([^\]]*)\]$/);
    const k = f ? f[1] : seg;
    const next: unknown[] = [];
    for (const c of cur) {
      if (c === null || c === undefined) continue;
      if (k === "*" && Array.isArray(c)) next.push(...c);
      else if (typeof c === "object") next.push((c as Record<string, unknown>)[k]);
    }
    cur = f ? next.flatMap((x) => Array.isArray(x) ? x : [x]).filter((x) => x && typeof x === "object" && String((x as Record<string, unknown>)[f[2]] ?? "") === f[3]) : next;
  }
  const vals = cur.filter((v) => v !== undefined && v !== null);
  return vals.length === 0 ? undefined : vals.length === 1 ? vals[0] : vals;
}
// Text of a JSON value (strings joined, markup taken out).
export const jsonText = (v: unknown): string => v === undefined || v === null ? "" : typeof v === "string" ? htmlToText(v) : Array.isArray(v) ? v.map(jsonText).join(" \n ") : typeof v === "object" ? Object.values(v as Record<string, unknown>).map(jsonText).join(" \n ") : String(v);
// The text after the first heading that matches, up to n characters.
export function sectionText(text: string, pattern?: string | null, n = 2000) {
  const r = re(pattern); if (!r) return null;
  const m = r.exec(text); return m ? text.slice(m.index, m.index + Math.max(200, Math.min(n, 10000))) : null;
}

// Apply one adapter to one stored page. Returns the identity it finds (if any) and the field candidates, in the shape
// the reader records, so the existing admission rules can read them.
export function applyAdapter(a: Adapter, html: string, course: { title: string; code: string; country: string; status?: string }, extractor: string) {
  const text = htmlToText(html);
  const base = identity(html, text, course.title, course.code, course.status === "ambiguous", course.country);
  const data = pageJson(html, a.json_source);
  const paths = a.json_paths || {};
  const ct = norm(strip(course.title, a.course_title_strip));
  let basis: string | null = base, how = base ? "existing rule" : "";
  if (!basis && data) {
    const jc = clean(String(jsonAt(data, paths.code) ?? "")).toUpperCase(), jt = norm(strip(jsonText(jsonAt(data, paths.title)), a.title_strip));
    const code = clean(course.code).toUpperCase();
    if (code.length >= 5 && jc && (jc === code || jc.split(/[^A-Z0-9]+/).includes(code))) { basis = "adapter_code"; how = `code in page data (${paths.code})` }
    else if (ct && jt && jt === ct) { basis = "adapter_title"; how = `title in page data (${paths.title})` }
  }
  if (!basis && (a.title_strip || a.course_title_strip)) {
    const heads = [h1Of(html), titleOf(html), (clean(titleOf(html)).split(/\s+[|–—]\s+|\s+-\s+/)[0] || "")].map((h) => norm(strip(h, a.title_strip)));
    if (ct && ct.split(" ").length >= 2 && heads.includes(ct)) { basis = "adapter_title"; how = "title after the adapter's patterns" }
  }
  const part = (f: string) => {
    if (data && paths[f]) { const t = jsonText(jsonAt(data, paths[f])); if (t) return t }
    return sectionText(text, a.sections?.[f], Number(a.section_chars || 2000)) ?? text;
  };
  // an IELTS score kept as a number in the page data (json_paths.ielts_overall, json_paths.ielts_min_band)
  const num = (k: string) => { const v = data && paths[k] ? Number(jsonText(jsonAt(data, paths[k]))) : NaN; return Number.isFinite(v) && v > 0 && v <= 9 ? v : null };
  const eng = (() => { const e: Record<string, unknown> = english(part("english")); const o = num("ielts_overall"), b = num("ielts_min_band"); if (o !== null && e.ielts_overall == null) { e.ielts_overall = o; e.context = `page data: IELTS ${o}${b !== null ? `, no band below ${b}` : ""}` } if (b !== null && e.ielts_min_band == null) e.ielts_min_band = b; return e })();
  const pat = patternValues(a, text, course.code);
  const extra: Record<string, string> = {};
  for (const f of EXTRA_FIELDS) {
    const v = pat[f] ?? (data && paths[f] ? clean(jsonText(jsonAt(data, paths[f]))).slice(0, 300) : "");
    if (v) extra[f] = v;
  }
  // a pattern for intakes or fee is the adapter's own reading: it replaces the general reader's and is marked as such
  // v0.17.3: term names in the intakes reading become the months the university publishes for them
  if (pat.intakes && a.term_months) {
    const add: string[] = [];
    for (const [term, months] of Object.entries(a.term_months)) {
      const t = String(term || "").trim(); if (t.length < 3) continue;
      if (new RegExp(`(?:^|[^A-Za-z0-9])${t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?![A-Za-z0-9])`, "i").test(pat.intakes)) add.push(String(months));
    }
    if (add.length) pat.intakes = `${pat.intakes} ${add.join(" ")}`;
  }
  // month names as printed, capitalised ("May" the month, not "may" the verb)
  const pIntakes = pat.intakes ? MONTH_NAMES.filter((m) => new RegExp(`\\b(?:${m}|${m.slice(0, 3)})\\b`).test(pat.intakes)) : null;
  // v0.17.2: a fee kept as a number in the page data (json_paths.fee) counts as the adapter's own reading too
  const jFeeRaw = !pat.fee && data && paths.fee ? jsonText(jsonAt(data, paths.fee)) : "";
  const pFee = pat.fee ? Number(pat.fee.replace(/[^0-9.]/g, "")) : (/^\s*\$?\s*[0-9][0-9,]*(\.[0-9]+)?\s*$/.test(jFeeRaw) ? Number(jFeeRaw.replace(/[^0-9.]/g, "")) : NaN);
  const pIelts = pat.ielts_overall ? Number(pat.ielts_overall) : NaN;
  if (Number.isFinite(pIelts) && pIelts >= 4 && pIelts <= 9) { eng.ielts_overall = pIelts; eng.context = `adapter pattern: IELTS ${pIelts}` }
  const candidates = basis ? {
    final_url: null, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200),
    fee: Number.isFinite(pFee) && pFee >= 1000 && pFee <= 500000 ? { value: pFee, safe: true, ambiguous: false, basis: "annual", fee_year: patternYear(a, text, "fee", course.code), currency: currencyFor(course.country), rejection_reason: null, candidates: [], context: pat.fee ? `adapter pattern: ${pat.fee}` : `page data: ${paths.fee} = ${jFeeRaw}` } : fee(part("fee"), currencyFor(course.country)),
    english: eng,
    intakes: pIntakes && pIntakes.length ? pIntakes : intakes(part("intakes")),
    intake_context: pIntakes && pIntakes.length ? [`adapter pattern: ${pat.intakes}`.slice(0, 200)] : intakeEvidence(part("intakes")),
    ...(pIntakes && pIntakes.length ? { intakes_by: "adapter" } : {}),
    ...(Number.isFinite(pFee) && pFee >= 1000 ? { fee_by: "adapter" } : {}),
    ...(Number.isFinite(pIelts) && pIelts >= 4 && pIelts <= 9 ? { english_by: "adapter" } : (num("ielts_overall") !== null ? { english_by: "adapter" } : {})),
    ...(Object.keys(extra).length ? { adapter_extra: extra } : {}),
    extractor, adapter: true } : null;
  return { identity: basis, how, json_found: !!data, page_title: titleOf(html).slice(0, 160), h1: h1Of(html).slice(0, 160), course_title_seen: ct, candidates, extra, patterns_found: pat };
}

const MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
// The year printed in the text a field's pattern matched (for example "Annual fee 2026: $47,300"), or null.
export function patternYear(a: Adapter, text: string, field: string, code = ""): number | null {
  const p = withCode((a.patterns || {})[field], code); if (!p) return null;
  let r: RegExp; try { r = new RegExp(p, "i") } catch { return null }
  const m = r.exec(text); const y = m ? (m[0].match(/\b(20[2-3]\d)\b/) || [])[1] : undefined;
  return y ? Number(y) : null;
}
// The value each pattern finds on the page text (its first bracketed part, or the whole match). "pick" chooses which
// match when the page has several (a page with a domestic and an international view prints some fields twice).
// v0.17.1: "{code}" in a pattern stands for the course's own code, so a page that covers several courses (each with
// its own CRICOS code and block) is read from this course's block. A pattern with {code} is skipped when there is no code.
export function withCode(p: string | undefined, code: string): string | null {
  if (!p) return null;
  if (!p.includes("{code}")) return p;
  const c = String(code || "").trim(); if (!c) return null;
  return p.split("{code}").join(c.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
}
export function patternValues(a: Adapter, text: string, code = ""): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [f, p0] of Object.entries(a.patterns || {})) {
    const p = withCode(p0, code); if (!p) continue;
    let r: RegExp; try { r = new RegExp(p, "gi") } catch { continue }
    const ms = [...text.matchAll(r)].slice(0, 20).map((m) => clean(m[1] ?? m[0])).filter(Boolean);
    if (!ms.length) continue;
    const how = (a.pick || {})[f] || "first";
    out[f] = (how === "last" ? ms[ms.length - 1] : how === "all" ? [...new Set(ms)].join(" | ") : ms[0]).slice(0, 300);
  }
  return out;
}

// What a stored page offers an adapter author: its title and heading, JSON scripts and headings.
export function inspectPage(html: string) {
  const scripts = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/gi)].map((m) => ({ id: (m[1].match(/id=["']([^"']+)/i) || [])[1] || null, type: (m[1].match(/type=["']([^"']+)/i) || [])[1] || null, chars: m[2].length }))
    .filter((x) => x.chars > 200 && (x.id || /json/i.test(x.type || ""))).slice(0, 8);
  const headings = [...html.matchAll(/<h([1-4])[^>]*>([\s\S]*?)<\/h\1>/gi)].map((m) => clean(htmlToText(m[2]))).filter(Boolean).slice(0, 30);
  return { title: titleOf(html).slice(0, 160), h1: h1Of(html).slice(0, 160), text_chars: htmlToText(html).length, scripts, headings };
}
// The top-level shape of a page's JSON (keys down to a depth), to help pick paths.
export function jsonShape(v: unknown, depth = 4, prefix = ""): string[] {
  if (depth < 0 || v === null || typeof v !== "object") return [];
  const out: string[] = [];
  for (const [k, x] of Object.entries(Array.isArray(v) ? (v.length ? { "*": v[0] } : {}) : v as Record<string, unknown>)) {
    const p = prefix ? `${prefix}.${k}` : k;
    out.push(`${p}${x !== null && typeof x === "object" ? "" : `: ${String(x).slice(0, 60)}`}`);
    if (out.length > 120) break;
    out.push(...jsonShape(x, depth - 1, p));
  }
  return out.slice(0, 160);
}
// Paths in a page's JSON whose key matches a pattern, with a short value (to pick an adapter's JSON paths).
export function jsonFind(v: unknown, pattern: string, limit = 80): string[] {
  let r: RegExp; try { r = new RegExp(pattern, "i") } catch { return [] }
  const out: string[] = [];
  const walk = (x: unknown, p: string, d: number) => {
    if (out.length >= limit || d > 12 || x === null || typeof x !== "object") return;
    for (const [k, y] of Object.entries(x as Record<string, unknown>)) {
      const q = p ? `${p}.${Array.isArray(x) ? "*" : k}` : k;
      if (!Array.isArray(x) && r.test(k)) out.push(`${q}: ${y !== null && typeof y === "object" ? (Array.isArray(y) ? `[${y.length}]` : "{…}") : String(y).replace(/\s+/g, " ").slice(0, 100)}`);
      walk(y, q, d + 1);
      if (Array.isArray(x)) break;
    }
  };
  walk(v, "", 0);
  return [...new Set(out)].slice(0, limit);
}
