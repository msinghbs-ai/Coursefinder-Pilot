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
};

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
  for (const k of path.split(".")) {
    const next: unknown[] = [];
    for (const c of cur) {
      if (c === null || c === undefined) continue;
      if (k === "*" && Array.isArray(c)) next.push(...c);
      else if (typeof c === "object") next.push((c as Record<string, unknown>)[k]);
    }
    cur = next;
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
  const candidates = basis ? { final_url: null, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), fee: fee(part("fee"), currencyFor(course.country)), english: english(part("english")), intakes: intakes(part("intakes")), intake_context: intakeEvidence(part("intakes")), extractor, adapter: true } : null;
  return { identity: basis, how, json_found: !!data, page_title: titleOf(html).slice(0, 160), h1: h1Of(html).slice(0, 160), course_title_seen: ct, candidates };
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
