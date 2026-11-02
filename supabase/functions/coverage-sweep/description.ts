// v0.57.0 (2 Nov 2026, CF-247 missing-field enrichment Priority 1, Platform Admin 2 Nov 2026 10:28): the provider description reader.
// Mode provider_description: the database (public.svc_provider_description_next) gives each provider's verified website hosts, a stored
// About / Overview copy when one is held, the page-name patterns, the pinned model and the limits. The worker uses the stored copy first;
// otherwise it reads the provider's home page directly (robots.txt respected), picks the About / Overview link on the provider's own hosts and
// reads that page (directly; Firecrawl only when the site refuses a direct read, within the existing Firecrawl budget). The pinned model then
// writes 2 to 5 student-facing sentences, each with the exact words of the page that support it. Every sentence's quote is checked against the
// page here; the database repeats the remaining checks (host, length, superlatives, claims, support, duplicates) and proposes the description
// to Layer 4. Nothing here writes a description.
// Pure functions only (no network), so the contract spec can read them.
import { htmlToText } from "./extract.ts";
import { callCost } from "./answer.ts";

export const DESCRIPTION_PROMPT_VERSION = "provider-description-v2";  // v2 (v0.58.0): the length limits are stated to the model

const flatText = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");
const bare = (h: string) => String(h || "").toLowerCase().replace(/^www\./, "").replace(/\.$/, "");

// a host belongs to the provider when it is one of its hosts or a sub-domain of one
export function ownHost(hostname: string, hosts: string[]): boolean {
  const h = bare(hostname);
  return (hosts || []).map(bare).filter(Boolean).some((x) => h === x || h.endsWith("." + x));
}

// v0.58.0 (pilot 2 Nov 2026 16:16): the page rule, the same as security.provider_description_page_v1. The lists are settings sent by the lease
// (page_rule: pdesc.about_prefixes, pdesc.refused_path_words, pdesc.refused_host_labels, pdesc.about_max_segments).
export type PageRule = { about_prefixes?: string[]; refused_path_words?: string[]; refused_host_labels?: string[]; about_max_segments?: number };
export function aboutPageCheck(url: string, hosts: string[], patterns: string[], rule: PageRule = {}): { ok: boolean; rule: string; main: boolean } {
  let u: URL; try { u = new URL(url) } catch { return { ok: false, rule: "wrong_host", main: false } }
  const host = bare(u.hostname);
  if (!/^https?:$/.test(u.protocol) || !ownHost(host, hosts)) return { ok: false, rule: "wrong_host", main: false };
  const main = (hosts || []).map(bare).includes(host);
  const low = (xs?: string[]) => (xs || []).map((x) => String(x).toLowerCase()).filter(Boolean);
  if (!main && low(rule.refused_host_labels).includes(host.split(".")[0])) return { ok: false, rule: "refused_host", main };
  let segs = decodeURIComponent(u.pathname).toLowerCase().replace(/\/+$/, "").split("/").filter(Boolean);
  if (segs.length && /^[a-z]{2}(-[a-z]{2})?$/.test(segs[0])) segs = segs.slice(1);  // a language part (/en/) is not a path part
  const refused = low(rule.refused_path_words);
  if (segs.some((s) => refused.includes(s) || s.split(/[-_.]+/).some((t) => refused.includes(t)))) return { ok: false, rule: "refused_word", main };
  const first = segs[0] || "", max = Number(rule.about_max_segments) > 0 ? Number(rule.about_max_segments) : 2;
  const named = low(patterns).includes(first) || low(rule.about_prefixes).some((x) => first.startsWith(x) && first.length > x.length);
  if (!segs.length || segs.length > max || !named) return { ok: false, rule: "not_about_page", main };
  return { ok: true, rule: "about_page", main };
}

// About / Overview links on the provider's own hosts that pass the page rule, best first: the main site host first, then a link whose text
// names an About page, then the shorter address.
export function aboutLinks(html: string, baseUrl: string, hosts: string[], patterns: string[], rule: PageRule = {}): { url: string; text: string; score: number }[] {
  const res = new Map<string, { url: string; text: string; score: number }>();
  const pats = (patterns || []).map((p) => String(p).toLowerCase().replace(/[-_]/g, " ")).filter((p) => p.length >= 3);
  const re = /<a\b[^>]*href\s*=\s*["']([^"'#]+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html || ""))) {
    let u: URL; try { u = new URL(m[1], baseUrl) } catch { continue }
    const key = u.origin.toLowerCase() + u.pathname.toLowerCase().replace(/\/+$/, "");
    const c = aboutPageCheck(key, hosts, patterns, rule);
    if (!c.ok) continue;
    const text = htmlToText(m[2]).toLowerCase().slice(0, 80);
    const score = (c.main ? 20 : 0) + (pats.some((p) => text === p || text.startsWith(p + " ") || text.startsWith("about")) ? 5 : 0) - key.length / 100;
    if (!res.has(key) || res.get(key)!.score < score) res.set(key, { url: key, text, score });
  }
  return [...res.values()].sort((a, b) => b.score - a.score || a.url.length - b.url.length);
}

// the page text the model reads: main text without navigation, header, footer and asides, at most pageChars characters
export function descriptionPageText(html: string, pageChars: number): string {
  let h = String(html || "");
  const main = h.match(/<main[\s\S]*?<\/main>/i);
  if (main && main[0].length > 1500) h = main[0];
  h = h.replace(/<(nav|header|footer|aside)\b[\s\S]*?<\/\1>/gi, " ");
  return htmlToText(h).slice(0, Math.max(1000, pageChars));
}

export const DESCRIPTION_SYSTEM =
  "You write a short description of one university or education provider for prospective students, using only what the provider's own official page states. " +
  "Give 2 to 5 sentences. Each sentence is a plain, factual paraphrase of one passage of the page, and for each sentence you give that passage's exact words as its quote, copied character for character from the page text. " +
  "Do not state rankings, ratings, awards, facilities, employment or graduate outcomes, accreditations, student or staff numbers, or comparisons with other institutions unless the quoted words state them. " +
  "Do not use superlatives or marketing words (best, leading, world-class, top, renowned, prestigious, excellent) unless they are inside the quote. " +
  "Do not use anything you know about the provider from elsewhere. Write in Australian English, third person, present tense. " +
  "Set about_page to false and give no sentences when the page does not describe the institution itself (what it is, where it is, what it teaches, its history).";

export const DESCRIPTION_SCHEMA = {
  type: "object", additionalProperties: false, required: ["about_page", "sentences"],
  properties: {
    about_page: { type: "boolean" },
    sentences: { type: "array", items: { type: "object", additionalProperties: false, required: ["text", "quote"], properties: { text: { type: "string" }, quote: { type: "string" } } } },
  },
} as const;

export type DescriptionLength = { min_sentences?: number; max_sentences?: number; min_chars?: number; max_chars?: number };
// the limits the database validation applies (settings pdesc.min_sentences, max_sentences, min_chars, max_chars), stated to the model
export function lengthNote(l: DescriptionLength | null | undefined): string {
  const n = (x: unknown) => (Number.isFinite(Number(x)) && Number(x) > 0 ? Math.floor(Number(x)) : null);
  const s1 = n(l?.min_sentences), s2 = n(l?.max_sentences), c1 = n(l?.min_chars), c2 = n(l?.max_chars);
  if (!s2 && !c2) return "";
  return `Length: ${s1 && s2 ? `${s1} to ${s2} sentences` : s2 ? `at most ${s2} sentences` : ""}${s2 && c2 ? ", " : ""}${c1 && c2 ? `${c1} to ${c2} characters in all (the sentences, not the quotes)` : c2 ? `at most ${c2} characters in all` : ""}.\n`;
}
export function descriptionRequest(model: string, provider: string, url: string, page: string, maxTokens: number, length?: DescriptionLength) {
  return {
    model, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },  // pinned: one model, never a router
    response_format: { type: "json_schema", json_schema: { name: "provider_description", strict: true, schema: DESCRIPTION_SCHEMA } },
    messages: [{ role: "system", content: DESCRIPTION_SYSTEM }, { role: "user", content: `Provider: ${provider}\nPage: ${url}\n${lengthNote(length)}\nPage text:\n${page}` }],
  };
}

// every sentence keeps its quote and whether the quote is on the page (at least minQuoteChars letters and digits, found in the page text)
export function descriptionSentences(a: any, page: string, minQuoteChars = 20): { about_page: boolean; sentences: { text: string; quote: string; on_page: boolean }[] } {
  const fp = flatText(page);
  const sentences = ((a?.sentences || []) as any[]).slice(0, 12).map((s) => {
    const text = String(s?.text || "").replace(/\s+/g, " ").trim().slice(0, 600), quote = String(s?.quote || "").replace(/\s+/g, " ").trim().slice(0, 600);
    const fq = flatText(quote);
    return { text, quote, on_page: fq.length >= minQuoteChars && fp.includes(fq) };
  }).filter((s) => s.text);
  return { about_page: a?.about_page === true, sentences };
}

// the setting that limits the answer (pipeline toolset, read through svc_worker_settings_v1 like every reading.answer_tokens.* limit)
export const DESCRIPTION_ANSWER_KEY = "reading.answer_tokens.provider_description";

// one answer as OpenRouter returns it, read by the same rules as answer.ts readAnswer (W32): a cut answer is never parsed and is held
// (held_partial: output_truncated), an empty or unreadable answer fails, named; the cost is always kept
export function descriptionAnswer(d: any, maxTokens: number): { ok: true; a: any; cost: number } | { ok: false; error: string; cost: number } {
  const cost = callCost(d), ch = d?.choices?.[0] || {}, content = String(ch?.message?.content ?? ""), out = Number(d?.usage?.completion_tokens);
  const cut = (why: string) => ({ ok: false as const, cost, error: `held_partial: output_truncated: provider_description ${why} ${DESCRIPTION_ANSWER_KEY} (${maxTokens})` });
  if (ch?.finish_reason === "length") return cut("reached");
  if (!content.trim()) return { ok: false, cost, error: `no_answer: provider_description (${String(ch?.error?.message || d?.error?.message || ch?.finish_reason || "no choices").slice(0, 120)})` };
  try { return { ok: true, a: JSON.parse(content), cost } }
  catch (e) {
    if (Number.isFinite(out) && maxTokens > 0 && out >= maxTokens) return cut("used all of");
    return { ok: false, cost, error: `unreadable_answer: provider_description (${e instanceof Error ? e.message : String(e)})`.slice(0, 300) };
  }
}
