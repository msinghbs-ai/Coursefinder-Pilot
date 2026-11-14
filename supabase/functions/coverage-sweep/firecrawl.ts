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
  const formats = (Array.isArray(s.read_formats) ? s.read_formats : ["rawHtml"]).map(String).filter((f) => ["rawHtml", "html", "markdown"].includes(f));
  const b: Record<string, unknown> = { url, formats: formats.length ? formats : ["rawHtml"], onlyMainContent: false };
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
// The page a read returned: the raw page (with its <title>) when asked for, otherwise Firecrawl's cleaned HTML.
export const pageHtml = (d: any) => String(d?.data?.rawHtml || d?.data?.html || "");
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
// R7 (CF-247 ingestion validation report, 14 Nov 2026): a page Firecrawl rendered with its own 4xx or 5xx status is a soft error, never a read:
// "server_error" for 5xx, "page_error" for any other 4xx not named above.
export function readOutcome(rec: { success: boolean; error: string | null; page_status: number | null; http: number | null }, html: string, textLen: number) {
  if (rec.error && /time(d)? ?out|timeout|aborted/i.test(rec.error) && !html) return "timeout";
  if (!rec.success && !html) return rec.http === 429 ? "rate_limited" : "fc_error";
  const ps = rec.page_status;
  if (ps === 404 || ps === 410) return "not_found";
  if (ps !== null && [401, 403, 406, 429].includes(ps)) return "blocked";
  if (ps !== null && ps >= 500) return "server_error";
  if (ps !== null && ps >= 400) return "page_error";
  if (!html) return "no_content";
  if (/captcha|cf-chl|access denied|are you a robot|verify you are human|request unsuccessful|incapsula/i.test(html.slice(0, 20000)) && textLen < 4000) return "blocked";
  if (textLen < 300) return "thin";
  return "read";
}

// R7 (CF-247 ingestion validation report, 14 Nov 2026, recommendations 4 and 8): one Firecrawl client. Every call the worker makes to Firecrawl
// (scrape, map, search; v1 search kept where a lane used it) goes through fcClient, so each call is:
//   - described by callRecord and written to pipeline.firecrawl_calls (svc_fc_call_log) with its lane (use_case) and outcome;
//   - for a scrape, judged by readOutcome, and its page accepted only when the page's own status (data.metadata.statusCode) is not 4xx or 5xx.
//     A rendered error page comes back with no html or markdown (accepted false, soft_error true), so it is never stored as a read; page_status
//     is returned for the lane to record with its evidence.
// The client does not decide spending: each lane still asks useFc / svc_fc_spend before calling. It never throws; a network failure or
// time-out comes back as rec.http null with rec.error set (fcFailed). Logging failures never stop the lane.
export type FcCtx = { use_case: string; provider_id?: string | null; course_id?: string | null; run_id?: string | null; item_id?: string | null; url?: string | null };
// timeoutMs: API time-out only (technical safety value). defer: the lane writes the call log itself (with \`log\` and its own final outcome), as
// fc_run does after the identity check; every other lane lets the client write it.
export type FcOpts = { timeoutMs: number; version?: "v1" | "v2"; estimate?: number; defer?: boolean };
export type FcRec = ReturnType<typeof callRecord>;
// A page status Firecrawl reported that can be a page: unknown (not reported) or below 400.
export const pageOk = (ps: number | null) => ps === null || ps < 400;
// The call never reached Firecrawl or never answered (network error or time-out).
export const fcFailed = (r: { rec: FcRec }) => r.rec.http === null;
const plainLen = (h: string) => h.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/gi, " ").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim().length;
const callOutcome = (rec: FcRec, okOutcome: string) => rec.error && rec.http === null && /time(d)? ?out|timeout|aborted/i.test(rec.error) ? "timeout" : rec.http === 429 ? "rate_limited" : !rec.success || rec.http === null || rec.http >= 400 ? "fc_error" : okOutcome;

// ---- Format profiles (Platform Admin 14 Nov 2026; worker v0.98.0): what every scrape asks Firecrawl for, set in Platform settings ›
// Models & services › Toolsets and limits › Firecrawl › Format profiles (settings scrape_profiles, scrape_profile_lanes,
// scrape_profile_overrides, scrape_profiles_version). A lane keeps its own request (address, proxy, location, and its wait and time
// allowed unless the profile sets them); the profile decides the formats and the content filters. The server checks the same rules
// (security.fc_scrape_profiles_check_v1) before anything is saved; the worker checks again before anything is sent.
// Only these formats can be asked for: the others add credits per page or run an AI pass with no pinned model (json, summary, question,
// highlights, changeTracking, branding, ...), and onlyCleanContent is an AI pass too. A format Firecrawl adds later is refused as well.
export const FC_FORMATS = ["markdown", "rawHtml", "html", "links", "screenshot"];
export const FC_ACTION_TYPES = ["click", "wait", "scroll", "press", "write"];
export const LANE_OWN = "lane_own";  // a lane mapped here sends its own request unchanged (AER v1 lanes: Decision 276)
const PROFILE_KEYS = new Set(["name", "about", "formats", "onlyMainContent", "includeTags", "excludeTags", "maxAgeMs", "waitFor", "timeout", "actions", "screenshotFullPage", "crawl"]);
const CRAWL_KEYS = new Set(["limit", "maxDiscoveryDepth", "includePaths", "excludePaths", "sitemap"]);
const tagOk = (t: unknown) => typeof t === "string" && /^[a-zA-Z][a-zA-Z0-9-]{0,40}$|^[.#][A-Za-z0-9_-]{1,60}$/.test(t);
const intIn = (v: unknown, lo: number, hi: number) => typeof v === "number" && Number.isInteger(v) && v >= lo && v <= hi;
export type ScrapeProfile = { name?: string; about?: string; formats: string[]; onlyMainContent?: boolean; includeTags?: string[]; excludeTags?: string[];
  maxAgeMs?: number | null; waitFor?: number | null; timeout?: number | null; actions?: Record<string, unknown>[] | null; screenshotFullPage?: boolean;
  crawl?: { limit?: number; maxDiscoveryDepth?: number; includePaths?: string[]; excludePaths?: string[]; sitemap?: string } };
export type FcProfiles = { version: number; profiles: Record<string, ScrapeProfile>; lanes: Record<string, string>; overrides: { provider_id: string; lane: string; profile: string; why?: string }[] };
/** Every problem with one profile, in words; [] when it can be saved and sent. */
export function checkProfile(p: any, name = "profile"): string[] {
  const e: string[] = [];
  if (!p || typeof p !== "object" || Array.isArray(p)) return [`${name}: not a profile`];
  for (const k of Object.keys(p)) if (!PROFILE_KEYS.has(k)) e.push(k === "onlyCleanContent" ? `${name}: onlyCleanContent is never sent (an AI pass over the page)` : `${name}: ${k} is not a profile setting`);
  if (!Array.isArray(p.formats) || !p.formats.length) e.push(`${name}: choose at least one format`);
  else {
    for (const f of p.formats) if (!FC_FORMATS.includes(String(f))) e.push(`${name}: format ${typeof f === "string" ? f : JSON.stringify(f)} is never sent (only ${FC_FORMATS.join(", ")})`);
    if (new Set(p.formats).size !== p.formats.length) e.push(`${name}: a format is named twice`);
    if (!p.formats.some((f: string) => ["markdown", "rawHtml", "html", "links"].includes(f))) e.push(`${name}: a screenshot alone is not a page read; add markdown, rawHtml, html or links`);
  }
  if (p.onlyMainContent !== undefined && typeof p.onlyMainContent !== "boolean") e.push(`${name}: onlyMainContent is yes or no`);
  for (const k of ["includeTags", "excludeTags"]) if (p[k] !== undefined && (!Array.isArray(p[k]) || p[k].length > 40 || !p[k].every(tagOk))) e.push(`${name}: ${k} is a list of tag names or .class/#id selectors`);
  if (p.maxAgeMs != null && !intIn(p.maxAgeMs, 0, 30 * 86400000)) e.push(`${name}: the Firecrawl copy age is 0 to 30 days`);
  if (p.waitFor != null && !intIn(p.waitFor, 0, 60000)) e.push(`${name}: wait after load is 0 to 60,000 ms`);
  if (p.timeout != null && !intIn(p.timeout, 1000, 300000)) e.push(`${name}: time allowed is 1,000 to 300,000 ms`);
  if (p.waitFor != null && p.timeout != null && p.waitFor >= p.timeout) e.push(`${name}: wait after load must be shorter than the time allowed`);
  if (p.actions != null) {
    if (!Array.isArray(p.actions) || p.actions.length > 20) e.push(`${name}: actions are a list of at most 20 steps`);
    else for (const a of p.actions) if (!a || typeof a !== "object" || !FC_ACTION_TYPES.includes(String((a as any).type))) e.push(`${name}: action ${JSON.stringify((a as any)?.type ?? a)} is not allowed (only ${FC_ACTION_TYPES.join(", ")})`);
  }
  if (p.screenshotFullPage !== undefined && typeof p.screenshotFullPage !== "boolean") e.push(`${name}: full-page screenshot is yes or no`);
  if (p.crawl !== undefined) {
    const c = p.crawl;
    if (!c || typeof c !== "object" || Array.isArray(c)) e.push(`${name}: crawl options are a set of values`);
    else {
      for (const k of Object.keys(c)) if (!CRAWL_KEYS.has(k)) e.push(`${name}: crawl ${k} is not a crawl option (maxDiscoveryDepth, not maxDepth)`);
      if (c.limit !== undefined && !intIn(c.limit, 1, 1000)) e.push(`${name}: crawl pages at most is 1 to 1,000`);
      if (c.maxDiscoveryDepth !== undefined && !intIn(c.maxDiscoveryDepth, 0, 10)) e.push(`${name}: crawl link depth is 0 to 10`);
      for (const k of ["includePaths", "excludePaths"]) if (c[k] !== undefined && (!Array.isArray(c[k]) || c[k].length > 50 || !c[k].every((x: unknown) => typeof x === "string" && x.length > 0 && x.length <= 200))) e.push(`${name}: crawl ${k} is a list of path patterns`);
      if (c.sitemap !== undefined && !["include", "skip", "only"].includes(c.sitemap)) e.push(`${name}: crawl site map is include, skip or only`);
    }
  }
  return e;
}
/** Every problem with the whole set (profiles, lane map, overrides); [] when it can be saved and sent. */
export function checkProfiles(all: any): string[] {
  if (!all || typeof all !== "object") return ["profiles: not set"];
  const e: string[] = [], P = all.profiles || {};
  if (typeof P !== "object" || Array.isArray(P) || !Object.keys(P).length) e.push("profiles: at least one profile");
  for (const [k, p] of Object.entries(P)) { if (!/^[a-z][a-z0-9_]{0,40}$/.test(k) || k === LANE_OWN) e.push(`profile name ${k} is not allowed`); e.push(...checkProfile(p, k)) }
  for (const [lane, prof] of Object.entries(all.lanes || {})) if (prof !== LANE_OWN && !P[prof as string]) e.push(`lane ${lane}: profile ${prof} does not exist`);
  for (const o of Array.isArray(all.overrides) ? all.overrides : []) if (!o?.provider_id || !o?.lane || !(o.profile === LANE_OWN || P[o.profile])) e.push(`override for ${o?.provider_id ?? "?"}: needs a university, a lane and an existing profile`);
  return e;
}
/** The profile a call uses: a provider override for this lane, else the lane's profile, else default. null: the lane's own request. */
export function resolveProfile(all: FcProfiles | null, lane: string, providerId?: string | null): { key: string; profile: ScrapeProfile } | null {
  if (!all?.profiles) return null;
  const ov = providerId ? (all.overrides || []).find((o) => o.provider_id === providerId && o.lane === lane) : null;
  const key = ov?.profile ?? all.lanes?.[lane] ?? LANE_OWN;  // a lane not in the map sends its own request
  if (key === LANE_OWN || !all.profiles[key]) return null;
  return { key, profile: all.profiles[key] };
}
/** The request a lane sends, with its profile applied. Without a profile the lane's own request goes as it is, minus anything never sent. */
export function applyProfile(body: Record<string, unknown>, prof: ScrapeProfile | null, fresh: boolean): Record<string, unknown> {
  const b: Record<string, unknown> = { ...body };
  if (prof) {
    b.formats = prof.formats.map((f) => (f === "screenshot" ? { type: "screenshot", fullPage: prof.screenshotFullPage ?? false } : f));
    if (prof.onlyMainContent !== undefined) b.onlyMainContent = prof.onlyMainContent;
    if (prof.includeTags?.length) b.includeTags = prof.includeTags; else delete b.includeTags;
    if (prof.excludeTags?.length) b.excludeTags = prof.excludeTags; else delete b.excludeTags;
    if (prof.maxAgeMs != null) b.maxAge = prof.maxAgeMs;
    if (prof.waitFor != null) b.waitFor = prof.waitFor;
    if (prof.timeout != null) b.timeout = prof.timeout;
    if (prof.actions?.length) b.actions = prof.actions;
  }
  if (fresh && prof) b.maxAge = 0;  // on demand: always a fresh page, never Firecrawl's stored copy (a lane sending its own request keeps it)
  // never sent, whoever asked: a format outside the allow-list (string or object) and onlyCleanContent
  if (Array.isArray(b.formats)) b.formats = (b.formats as unknown[]).filter((f) => (typeof f === "string" ? FC_FORMATS.includes(f) : !!f && typeof f === "object" && (f as any).type === "screenshot"));
  delete b.onlyCleanContent;
  return b;
}
/** The formats a request asks for, as names. */
export const formatNames = (b: Record<string, unknown>) => (Array.isArray(b.formats) ? b.formats : []).map((f: any) => (typeof f === "string" ? f : String(f?.type || "")));

export function fcClient(o: { headers: Record<string, string>; log: (p: Record<string, unknown>) => Promise<unknown>; textLen?: (html: string) => number;
                              profiles?: FcProfiles | null; fresh?: (ctx: FcCtx) => boolean | Promise<boolean> }) {
  const textLen = o.textLen ?? plainLen;
  const call = async (endpoint: "scrape" | "map" | "search", body: Record<string, unknown>, opts: FcOpts) => {
    const started = Date.now(); let http: number | null = null, d: any = null, hdrs: Headers | null = null, err: string | null = null;
    try {
      const r = await fetch(`https://api.firecrawl.dev/${opts.version ?? "v2"}/${endpoint}`, { method: "POST", headers: o.headers, body: JSON.stringify(body), signal: AbortSignal.timeout(opts.timeoutMs) });
      http = r.status; hdrs = r.headers; d = await r.json().catch(() => null);
    } catch (e) { err = e instanceof Error ? `${e.name}: ${e.message}` : String(e) }
    const rec = callRecord(http, d, hdrs, Date.now() - started, err);
    // the credits Firecrawl reported; otherwise the lane's estimate for a call Firecrawl answered (the fc_run rule)
    const credits = rec.credits_used ?? (http !== null && http < 500 && http !== 429 ? (opts.estimate ?? 1) : 0);
    return { http, d: (d ?? {}) as any, rec: { ...rec, credits_used: credits } };
  };
  // the pipeline.firecrawl_calls row (svc_fc_call_log): the request without its address or query text (kept in url, or in request.query for a search)
  const row = (endpoint: string, body: Record<string, unknown>, ctx: FcCtx, rec: FcRec, outcome: string) => {
    const { url: _u, query: _q, ...request } = body;
    return { run_id: ctx.run_id ?? null, item_id: ctx.item_id ?? null, use_case: ctx.use_case, endpoint, provider_id: ctx.provider_id ?? null, course_id: ctx.course_id ?? null,
             url: ctx.url ?? (typeof body.url === "string" ? body.url : null), request: { ...request, ...(endpoint === "search" ? { query: body.query } : {}) }, ...rec, outcome } as Record<string, unknown>;
  };
  const write = async (endpoint: string, body: Record<string, unknown>, ctx: FcCtx, rec: FcRec, outcome: string, opts: FcOpts) => {
    const log = row(endpoint, body, ctx, rec, outcome);
    if (!opts.defer) await o.log(log).catch(() => null);
    return log;
  };
  // POST /scrape: html (rawHtml, else html), markdown and links only for a page Firecrawl answered whose own status is not 4xx or 5xx.
  const scrape = async (laneBody: Record<string, unknown>, ctx: FcCtx & { fresh?: boolean }, opts: FcOpts) => {
    // v0.98.0: the lane's request with its format profile applied (lane, then a provider override); on demand asks for a fresh page
    const rp = resolveProfile(o.profiles ?? null, ctx.use_case, ctx.provider_id);
    const fresh = !!rp && (ctx.fresh === true || (o.fresh ? await Promise.resolve(o.fresh(ctx)).catch(() => false) : false));
    const body = applyProfile(laneBody, rp?.profile ?? null, fresh);
    // a profile's time allowed never outlasts the lane's API time-out: Firecrawl is given 5 s less, so it answers before the call is cut
    const askT = body.timeout, askW = body.waitFor;
    if (rp?.profile.timeout != null && typeof askT === "number" && typeof opts.timeoutMs === "number") {
      const t = Math.max(1000, Math.min(askT, opts.timeoutMs - 5000));  // fixed: API time-out margin
      body.timeout = t;
      if (typeof askW === "number" && askW >= t) body.waitFor = Math.max(0, t - 1000);
    }
    const profile = { key: rp?.key ?? LANE_OWN, version: o.profiles?.version ?? null, formats: formatNames(body), max_age_ms: typeof body.maxAge === "number" ? body.maxAge : null, fresh };
    const { http, d, rec } = await call("scrape", body, opts);
    const ps = rec.page_status;
    const raw = pageHtml(d), md = String(d?.data?.markdown || "");
    const outcome = readOutcome(rec, raw || md, raw ? textLen(raw) : md.trim().length);
    const accepted = rec.success && pageOk(ps) && !!(raw || md || (Array.isArray(d?.data?.links) && d.data.links.length));
    const log = await write("scrape", body, ctx, rec, outcome, opts);
    return {
      d, rec, http, outcome, log, accepted, page_status: ps, soft_error: rec.success && !pageOk(ps), profile, body,
      // the screenshot Firecrawl returned (a link it keeps for 24 hours), only for an accepted page that asked for one
      screenshot: accepted && typeof d?.data?.screenshot === "string" ? String(d.data.screenshot) : null,
      code: ps ?? http,  // the page's own status when Firecrawl reported it, otherwise the API's
      html: accepted ? raw : "", markdown: accepted ? md : "", links: accepted && Array.isArray(d?.data?.links) ? (d.data.links as unknown[]).map(String) : [] as string[],
      finalUrl: String(d?.data?.metadata?.url || d?.data?.metadata?.sourceURL || body.url || ""),
    };
  };
  // POST /map: the addresses as Firecrawl returned them (strings or { url, title }); each lane keeps its own filter.
  const map = async (body: Record<string, unknown>, ctx: FcCtx, opts: FcOpts) => {
    const { http, d, rec } = await call("map", body, opts);
    const raw: any[] = Array.isArray(d?.links) ? d.links : Array.isArray(d?.data?.links) ? d.data.links : [];
    const ok = rec.success && http !== null && http < 400;
    const outcome = callOutcome(rec, raw.length ? "mapped" : "no_links");
    const log = await write("map", body, ctx, rec, outcome, opts);
    return { d, rec, http, ok, outcome, raw, log };
  };
  // POST /search: the results as Firecrawl returned them (v2 data.web, v1 data).
  const search = async (body: Record<string, unknown>, ctx: FcCtx, opts: FcOpts) => {
    opts = { estimate: 2, ...opts };
    const { http, d, rec } = await call("search", body, opts);
    const raw: any[] = Array.isArray(d?.data?.web) ? d.data.web : Array.isArray(d?.data) ? d.data : [];
    const ok = rec.success && http !== null && http < 400;
    const outcome = callOutcome(rec, raw.length ? "results" : "no_results");
    const log = await write("search", body, ctx, rec, outcome, opts);
    return { d, rec, http, ok, outcome, raw, log };
  };
  return { scrape, map, search };
}
export type FcClient = ReturnType<typeof fcClient>;
