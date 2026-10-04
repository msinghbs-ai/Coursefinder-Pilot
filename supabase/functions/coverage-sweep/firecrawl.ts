// CF-247 Decision 253 (4 Oct 2026): Firecrawl use cases for target universities. Every option sent to Firecrawl comes
// from the run's settings (Platform settings › Models & services › Toolsets and limits › Firecrawl). Every call is
// described by callRecord() for the support report: what was asked, what came back, the scrape id, credits and proxy.

const STOP = new Set(["of", "and", "the", "in", "for", "with", "to", "a", "an", "at", "on", "by", "de", "des", "du", "la", "le", "et", "en"]);
export const words = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "").replace(/\([^)]*\)/g, " ").split(/[^a-z0-9]+/).filter((w) => w.length > 1 && !STOP.has(w));
export function titleScore(name: string, title: string) { const a = [...new Set(words(name))]; if (!a.length) return 0; const b = new Set(words(title)); return a.filter((w) => b.has(w)).length / a.length }
export const hostOf = (u: string) => { try { return new URL(u).hostname.toLowerCase().replace(/^www\./, "") } catch { return "" } };
export const onDomain = (u: string, domain: string) => { const h = hostOf(u); const d = String(domain || "").toLowerCase().replace(/^www\./, ""); return !!d && (h === d || h.endsWith("." + d)) };
export const fill = (t: string, v: Record<string, string>) => String(t || "").replace(/\{(\w+)\}/g, (_, k) => v[k] ?? "").replace(/\s+/g, " ").trim();
const num = (v: unknown) => { const n = Number(v); return v === null || v === undefined || v === "" || !Number.isFinite(n) ? null : n };
const PROXIES = new Set(["basic", "auto", "stealth", "enhanced"]);

// The body of a page read (POST /v2/scrape).
export function scrapeBody(url: string, s: Record<string, unknown>, country: string) {
  const b: Record<string, unknown> = { url, formats: ["html"], onlyMainContent: false };
  const proxy = String(s.read_proxy ?? "auto").toLowerCase(); if (PROXIES.has(proxy)) b.proxy = proxy;
  const wait = num(s.read_wait_ms); if (wait && wait > 0) b.waitFor = Math.min(wait, 30000);
  const to = num(s.read_timeout_ms); if (to && to > 0) b.timeout = Math.min(Math.max(to, 10000), 120000);
  if (s.read_location !== false && /^[A-Z]{2}$/.test(String(country || ""))) b.location = { country };
  return b;
}
// The body of a search on the university's own site (POST /v2/search).
export function searchBody(input: Record<string, unknown>, s: Record<string, unknown>, country: string) {
  const query = fill(String(s.find_query ?? "{course} site:{domain}"), { course: String(input.course || ""), code: String(input.code || ""), provider: String(input.provider || ""), domain: String(input.domain || "") });
  const limit = Math.min(Math.max(num(s.find_results) ?? 5, 1), 20);
  return { query, limit, ...(/^[A-Z]{2}$/.test(String(country || "")) ? { country } : {}) };
}
// Search results: those on the university's own site whose title matches the course, best first.
export function searchCandidates(input: Record<string, unknown>, results: { url?: string; title?: string }[], min: number) {
  const rows = results.slice(0, 20).map((r) => ({ url: String(r.url || "").replace(/#.*$/, ""), title: String(r.title || ""), on_site: onDomain(String(r.url || ""), String(input.domain || "")), score: Math.round(titleScore(String(input.course || ""), String(r.title || "")) * 100) / 100 }));
  const candidates = [...new Set(rows.filter((r) => r.on_site && r.score >= min).sort((a, b) => b.score - a.score).map((r) => r.url))];
  const outcome = !rows.length ? "no_results" : candidates.length ? "found_on_provider_site" : rows.some((r) => r.on_site) ? "provider_site_no_title_match" : "other_sites_only";
  return { outcome, candidates, top: rows.slice(0, 5) };
}
// The search results in a Firecrawl v2 (data.web) or v1 (data) reply.
export const searchResults = (d: any) => ((Array.isArray(d?.data?.web) ? d.data.web : Array.isArray(d?.data) ? d.data : []) as any[]).filter((x) => typeof x?.url === "string").map((x) => ({ url: String(x.url), title: String(x.title || x.metadata?.title || "") }));

// What a reply says, for the call log and the support report. Page content is never kept here.
const KEEP = ["statusCode", "scrapeId", "creditsUsed", "proxyUsed", "sourceURL", "url", "contentType", "cacheState", "cachedAt", "error", "numPages", "concurrencyLimited", "concurrencyQueueDurationMs", "timezone"];
export function callRecord(http: number | null, d: any, headers: Headers | null, ms: number, error: string | null) {
  const m = d?.data?.metadata || {};
  const meta: Record<string, unknown> = {};
  for (const k of KEEP) if (m[k] !== undefined && m[k] !== null && String(m[k]).length <= 300) meta[k] = m[k];
  for (const k of ["warning", "id", "creditsUsed"]) if (d?.[k] !== undefined && d?.[k] !== null && String(d[k]).length <= 300) meta["reply_" + k] = d[k];
  if (d?.data?.warning) meta.warning = String(d.data.warning).slice(0, 300);
  for (const h of ["x-request-id", "cf-ray", "x-ratelimit-remaining", "retry-after"]) { const v = headers?.get(h); if (v) meta["header_" + h] = v.slice(0, 120) }
  const pageStatus = num(m.statusCode);
  const apiError = error || (d && d.success === false ? String(d.error || d.message || "success false") : null) || (http !== null && http >= 400 ? `HTTP ${http}` : null);
  const pageError = m.error ? String(m.error) : null;
  return {
    http, success: !apiError && d?.success !== false, error: (apiError || pageError || null)?.slice(0, 1000) ?? null,
    scrape_id: String(m.scrapeId || d?.data?.scrapeId || d?.id || "") || null, credits_used: num(m.creditsUsed ?? d?.creditsUsed), proxy_used: m.proxyUsed ? String(m.proxyUsed) : null,
    page_status: pageStatus, duration_ms: Math.round(ms), meta,
  };
}

// The result of one page read through Firecrawl, before the identity check.
export function readOutcome(rec: { success: boolean; error: string | null; page_status: number | null; http: number | null }, html: string, textLen: number) {
  if (rec.error && /time(d)? ?out|timeout|aborted/i.test(rec.error) && !html) return "timeout";
  if (!rec.success && !html) return rec.http === 429 ? "rate_limited" : "fc_error";
  const ps = rec.page_status;
  if (ps === 404 || ps === 410) return "not_found";
  if (ps !== null && [401, 403, 406, 429].includes(ps)) return "blocked";
  if (!html) return "no_content";
  if (/captcha|cf-chl|access denied|are you a robot|verify you are human|request unsuccessful|incapsula/i.test(html.slice(0, 20000)) && textLen < 4000) return "blocked";
  if (textLen < 300) return "thin";
  return "read";
}
