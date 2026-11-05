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

// The official host alone does not prove which institution a page describes. Use the current
// catalogue names, never a shortened shared label such as "Monash" for Monash University.
// A missing proof is held before any paid AI call; it does not change the catalogue identity.
export function descriptionSourceIdentity(html: string, page: string, names: string[]): { ok: boolean; rule: string; matched_name?: string } {
  const words = (s: string) => String(s || "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/&/g, " and ").replace(/[^a-z0-9]+/g, " ").replace(/^the\s+/, "").trim();
  const labels = [...new Set((names || []).map(words).filter((s) => s.split(" ").length > 1))];
  const contains = (text: string, label: string) => (` ${words(text)} `).includes(` ${label} `);
  const headings = Array.from(String(html || "").matchAll(/<(title|h1)\b[^>]*>([\s\S]*?)<\/\1>/gi), (m) => ({ tag: m[1].toLowerCase(), text: htmlToText(m[2]) }));
  const matched = labels.find((name) => contains(page, name) || headings.some((h) => contains(h.text, name)));
  if (!matched) return { ok: false, rule: "provider_name_not_proved" };
  const subunits = /\b(campus|campuses|faculty|faculties|school|schools)\b/g;
  if (headings.some((h) => h.tag === "h1" && (words(h.text).match(subunits) || []).some((unit) => !(` ${matched} `).includes(` ${unit} `)))) {
    return { ok: false, rule: "provider_subunit_source" };
  }
  // A heading identifying a different university or college is stronger evidence of a conflict
  // than a passing mention of the requested name in the body (partnerships, history, offshore sites).
  const institutionalHeadings = headings.filter((h) => /\b(university|college|polytechnic|institute)\b/.test(words(h.text))
    && words(h.text).replace(/\b(about|us|the|our|who|we|are|overview|profile|welcome|to|at|university|college|polytechnic|institute)\b/g, "").trim());
  const subjectHeadings = institutionalHeadings.some((h) => h.tag === "h1") ? institutionalHeadings.filter((h) => h.tag === "h1") : institutionalHeadings;
  if (subjectHeadings.length && !subjectHeadings.some((h) => labels.some((name) => contains(h.text, name)))) {
    return { ok: false, rule: "provider_name_conflict" };
  }
  // An offshore branch can include its parent's complete name ("X University Malaysia").
  // A named institutional h1 must identify this catalogue institution without an extra entity suffix.
  // When h1 is generic, the institutional title must provide that same exact identity proof.
  const namedH1 = headings.filter((h) => h.tag === "h1" && labels.some((name) => contains(h.text, name)));
  const framing = /\b(about|us|the|our|who|we|are|overview|profile|welcome|to|at|a|glance|facts|and|figures)\b/g;
  const proofHeadings = namedH1.length ? namedH1 : headings.filter((h) => h.tag === "title");
  if (!proofHeadings.some((h) => labels.some((name) => contains(h.text, name) && !words(h.text).replace(name, " ").replace(framing, " ").trim()))) {
    return { ok: false, rule: "provider_name_conflict" };
  }
  return { ok: true, rule: "current_provider_name", matched_name: matched };
}

// Word-overlap support must never turn an unquoted numerical fact into a supported claim.
// Keep the whole answer and quotes; hold it rather than rewriting any sentence to make it pass.
export function descriptionClaimCheck(answer: any, maxVerbatimChars?: number): { ok: boolean; rule?: string; reason?: string } {
  if (!Array.isArray(answer?.sentences)) return { ok: false, rule: "invalid_answer", reason: "The answer has no sentence array." };
  const numbers = (s: unknown) => String(s || "").match(/\b\d+(?:[,.]\d+)*%?/g) || [];
  if (maxVerbatimChars !== undefined && (!Number.isInteger(maxVerbatimChars) || maxVerbatimChars < 1)) return { ok: false, rule: "invalid_verbatim_limit", reason: "The governed quotation-copy limit is unavailable." };
  for (const s of answer.sentences) {
    const quoted = new Set(numbers(s?.quote));
    if (numbers(s?.text).some((n) => !quoted.has(n))) return { ok: false, rule: "unsupported_numeric_claim", reason: "A numerical fact is absent from its supporting quote." };
    if (/\b(former|formerly|previously|was known as|became|renamed|closed|merged|ceased)\b/i.test(String(s?.quote || ""))
      && /\b(is|are|operates|offers)\b/i.test(String(s?.text || ""))
      && !/\b(former|formerly|previously|was|were|became|renamed|closed|merged|ceased|history|founded|established|origin|since)\b/i.test(String(s?.text || ""))) {
      return { ok: false, rule: "historic_claim_context", reason: "A historical institutional statement was presented as current without its source conditions." };
    }
    if (maxVerbatimChars !== undefined) {
      const normalized = (value: unknown) => String(value || "").replace(/\s+/g, " ").trim().toLowerCase();
      const text = Array.from(normalized(s?.text)), quote = normalized(s?.quote), span = maxVerbatimChars;
      for (let i = 0; i + span <= text.length; i++) {
        if (quote.includes(text.slice(i, i + span).join(""))) return { ok: false, rule: "verbatim_passage", reason: "A long official passage was copied; a concise source-grounded paraphrase is required." };
      }
    }
  }
  return { ok: true };
}

// OpenRouter's model catalogue quotes USD per token/request. A UTF-8 byte per prompt token
// bounds the byte-token vocabulary, including the JSON schema; the extra envelope covers
// provider message framing. Missing or unfamiliar charge components fail closed.
export function descriptionCostQuote(request: any, catalogue: any): { ok: false; reason: string } | { ok: true; model: string; max_cost_usd: number; input_tokens_bound: number; output_tokens_bound: number; pricing: Record<string, number>; provider_max_price: { prompt: number; completion: number; request: number } } {
  const model = String(request?.model || ""), output = Number(request?.max_tokens);
  if (!model || !Number.isInteger(output) || output <= 0 || !Array.isArray(catalogue?.data)) return { ok: false, reason: "model_pricing_unavailable" };
  const entry = catalogue.data.find((m: any) => m?.id === model), price = entry?.pricing;
  if (!price || typeof price !== "object") return { ok: false, reason: "model_pricing_unavailable" };
  const allowed = new Set(["prompt", "completion", "request", "image", "web_search", "internal_reasoning", "input_cache_read", "input_cache_write", "audio", "audio_output"]);
  const rates: Record<string, number> = {};
  for (const [key, value] of Object.entries(price)) {
    if ((typeof value !== "string" && typeof value !== "number") || String(value).trim() === "" || !Number.isFinite(Number(value)) || Number(value) < 0) return { ok: false, reason: "invalid_model_pricing" };
    if (!allowed.has(key) && Number(value) !== 0) return { ok: false, reason: "unrecognised_pricing_component" };
    rates[key] = Number(value);
  }
  if (rates.prompt == null || rates.completion == null) return { ok: false, reason: "model_pricing_unavailable" };
  // The catalogue may quote the cheapest provider. OpenRouter's enforced max_price filter
  // prevents same-model provider routing from charging above the rates used to reserve.
  // API contract: https://openrouter.ai/docs/guides/routing/provider-selection#max-price
  const precision = 1e9; // fixed: round price caps and USD reservations upwards to nanodollar precision.
  const maxPrice = { prompt: Math.ceil(rates.prompt * 1e6 * precision) / precision, completion: Math.ceil(rates.completion * 1e6 * precision) / precision, request: rates.request || 0 }; // fixed: API uses USD per million tokens.
  const pricedRequest = { ...request, provider: { ...request.provider, max_price: maxPrice } };
  const envelope = 4096; // fixed: conservative technical allowance for provider/schema/message framing, not a spending setting.
  const input = new TextEncoder().encode(JSON.stringify(pricedRequest)).length + envelope;
  const maximum = input * (maxPrice.prompt / 1e6 + (rates.input_cache_read || 0) + (rates.input_cache_write || 0))
    + output * (maxPrice.completion / 1e6 + (rates.internal_reasoning || 0)) + maxPrice.request;
  if (!Number.isFinite(maximum) || maximum < 0) return { ok: false, reason: "invalid_model_pricing" };
  return { ok: true, model, max_cost_usd: Math.ceil(maximum * precision) / precision, input_tokens_bound: input, output_tokens_bound: output, pricing: rates, provider_max_price: maxPrice };
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
// Shared with the course-description reader (course-text.ts); its matching is unchanged by the provider-description source guard.
export function descriptionSentences(a: any, page: string, minQuoteChars = 20): { about_page: boolean; sentences: { text: string; quote: string; on_page: boolean }[] } {
  const fp = flatText(page);
  // v0.58.0 (Platform Admin 2 Nov 2026 23:24, "avoid cutting essential conditions or publishing fragments"): nothing is cut here. Every
  // sentence and quote is kept whole and every sentence the model gave is passed on; the database holds a description that is too long,
  // has too many sentences or a sentence that is not complete (rules length, sentence_count, incomplete_sentence). It was cut at 600
  // characters and 12 sentences.
  const sentences = ((a?.sentences || []) as any[]).map((s) => {
    const text = String(s?.text || "").replace(/\s+/g, " ").trim(), quote = String(s?.quote || "").replace(/\s+/g, " ").trim();
    const fq = flatText(quote);
    return { text, quote, on_page: fq.length >= minQuoteChars && fp.includes(fq) };
  }).filter((s) => s.text);
  return { about_page: a?.about_page === true, sentences };
}

// Provider descriptions only (provider-description-source-guard-v1): the quote must be on the page exactly.
// Only canonical Unicode form and layout whitespace may differ. Punctuation, decimal points,
// signs, percentages, words and case remain evidence: "1.2%" must never prove "12%".
export function providerDescriptionSentences(a: any, page: string, minQuoteChars = 20): { about_page: boolean; sentences: { text: string; quote: string; on_page: boolean }[] } {
  const sourceText = (value: string) => String(value || "").normalize("NFC").replace(/\s+/g, " ").trim();
  const fp = sourceText(page);
  const onPage = (quote: string) => {
    const needle = sourceText(quote), ends = Array.from(needle), first = ends[0] || "", last = ends[ends.length - 1] || "";
    const word = (c: string) => /[\p{L}\p{N}_]/u.test(c);
    const numeric = (c: string) => /[0-9.,+\-$€£%]/u.test(c);
    for (let at = fp.indexOf(needle); at >= 0 && needle; at = fp.indexOf(needle, at + 1)) {
      const before = Array.from(fp.slice(0, at)).at(-1) || "", after = Array.from(fp.slice(at + needle.length))[0] || "";
      if (word(first) && word(before) || word(last) && word(after)) continue;
      if (numeric(first) && numeric(before) || numeric(last) && numeric(after)) continue;
      return true;
    }
    return false;
  };
  // As descriptionSentences: nothing is cut; every sentence and its whole quote is passed on for the database checks.
  const sentences = (Array.isArray(a?.sentences) ? a.sentences : []).map((s: any) => {
    const text = String(s?.text || "").replace(/\s+/g, " ").trim(), quote = String(s?.quote || "");
    const fq = flatText(quote);
    return { text, quote, on_page: fq.length >= minQuoteChars && onPage(quote) };
  }).filter((s: any) => s.text);
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
