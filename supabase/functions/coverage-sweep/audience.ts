// CF-247 s1298 (S1-Build; design coursefinder-admin #1271 Phase B, SS-Programme-Control 27 Nov 2026 12:08 AEDT): read-only audience and identity signals of a
// stored course page. Deterministic, no model, no fetch, no write. A signal is evidence for qualifying a provider template rule; it is never an admission by itself.

const INTL = /\binternational (students?|applicants?|student fees?|fees?|tuition)\b/gi
const DOM = /\b(domestic (students?|applicants?|fees?)|australian (citizens?|permanent residents?)|commonwealth supported|csp\b|hecs|fee-help|new zealand citizens?)\b/gi
const TOGGLE = />\s*(international|domestic)(\s+students?)?\s*</gi
const PARAM = /[?&](studenttype|student-type|student_type|audience|residency|usertype|student|location|origin|type)=([a-z0-9_-]{2,24})/gi
const DATA_ATTR = /data-(audience|student-type|studenttype|residency|location|user-type)\s*=\s*["']([^"']{1,32})["']/gi
const PATH = /\/(international|domestic|local|overseas)(-students?)?(\/|\b)/gi

function strip(html: string): string {
  return html.replace(/<script\b[\s\S]*?<\/script>/gi, " ").replace(/<style\b[\s\S]*?<\/style>/gi, " ").replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;|&#160;/g, " ").replace(/&amp;/g, "&").replace(/\s+/g, " ").trim()
}
function count(re: RegExp, s: string): number { return (s.match(re) || []).length }
function distinct(re: RegExp, s: string, f: (m: RegExpMatchArray) => string, max = 8): string[] {  // fixed: diagnostic list bound
  const out = new Set<string>(); for (const m of s.matchAll(re)) { out.add(f(m).toLowerCase()); if (out.size >= max) break } return [...out]
}

export type AudienceSignals = {
  title: string; h1: string; canonical: string | null; code_on_page: boolean; chars: number;
  intl_words: number; dom_words: number; toggle: { international: number; domestic: number }; params: string[]; data_attrs: string[]; paths: string[];
  intl_links: string[]; view: "international" | "domestic" | "toggle" | "mixed" | "none";
}

export function audienceSignals(html: string, courseCode: string | null): AudienceSignals {
  const text = strip(html)
  const pick = (re: RegExp) => strip((html.match(re) || [])[1] || "").slice(0, 160)
  const toggleHits = [...html.matchAll(TOGGLE)].map((m) => m[1].toLowerCase())
  const toggle = { international: toggleHits.filter((t) => t === "international").length, domestic: toggleHits.filter((t) => t === "domestic").length }
  const hrefs = [...html.matchAll(/href\s*=\s*["']([^"'#]{4,400})["']/gi)].map((m) => m[1])
  const intlLinks = [...new Set(hrefs.filter((h) => /international|[?&](studenttype|student-type|student_type|audience|residency)=/i.test(h)))].slice(0, 6)  // fixed: diagnostic bound
  const i = count(INTL, text), d = count(DOM, text)
  const view = toggle.international > 0 && toggle.domestic > 0 ? "toggle" : i > 0 && d > 0 ? "mixed" : i > 0 ? "international" : d > 0 ? "domestic" : "none"
  return {
    title: pick(/<title[^>]*>([\s\S]*?)<\/title>/i), h1: pick(/<h1[^>]*>([\s\S]*?)<\/h1>/i),
    canonical: (html.match(/<link[^>]+rel=["']canonical["'][^>]*href=["']([^"']+)["']/i) || html.match(/<meta[^>]+property=["']og:url["'][^>]*content=["']([^"']+)["']/i) || [])[1] || null,
    code_on_page: !!courseCode && courseCode.length >= 5 && text.toUpperCase().includes(courseCode.toUpperCase()), chars: text.length,
    intl_words: i, dom_words: d, toggle,
    params: distinct(PARAM, hrefs.join(" "), (m) => `${m[1]}=${m[2]}`), data_attrs: distinct(DATA_ATTR, html, (m) => `${m[1]}=${m[2]}`),
    paths: distinct(PATH, hrefs.join(" "), (m) => m[1] + (m[2] || "")), intl_links: intlLinks, view,
  }
}
