// CF-247 Decision 252 (4 Oct 2026): trial runs of Serper (web search) and ScrapingBee (browser rendering) against samples
// of the real backlog in each country. Started and continued from Platform settings › Models & services › Toolsets and
// limits by the Platform Admin. Every limit (cases, credits, time per call, parallel calls, query wording, rendering
// options, match threshold) comes from the run's settings snapshot, which the Platform Admin set in the UI.
// Nothing found here is admitted or written to a course, provider or page: results are recorded for review only.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "toolset-trial-v1.0.0";
const ORIGIN = "https://coursefinder-pilot.techm.workers.dev";
const hdrs = (req: Request) => { const o = req.headers.get("origin") || ""; return { "access-control-allow-origin": o === ORIGIN || o.startsWith("http://localhost") ? o : ORIGIN, "access-control-allow-headers": "authorization, x-client-info, apikey, content-type", "access-control-allow-methods": "POST, OPTIONS", "content-type": "application/json", "cache-control": "no-store", vary: "origin" } };
const reply = (req: Request, s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: hdrs(req) });

const STOP = new Set(["of", "and", "the", "in", "for", "with", "to", "a", "an", "at", "on", "by", "de", "des", "du", "la", "le", "et", "en"]);
export const words = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "").replace(/\([^)]*\)/g, " ").split(/[^a-z0-9]+/).filter((w) => w.length > 1 && !STOP.has(w));
export function titleScore(name: string, title: string) { const a = [...new Set(words(name))]; if (!a.length) return 0; const b = new Set(words(title)); return a.filter((w) => b.has(w)).length / a.length }
export const hostOf = (u: string) => { try { return new URL(u).hostname.toLowerCase().replace(/^www\./, "") } catch { return "" } };
export const onSite = (u: string, domain: string) => { const h = hostOf(u); return !!domain && (h === domain || h.endsWith("." + domain)) };
export const fill = (t: string, v: Record<string, string>) => String(t || "").replace(/\{(\w+)\}/g, (_, k) => v[k] ?? "").replace(/\s+/g, " ").trim();
const norm = (u: string) => String(u || "").toLowerCase().replace(/^https?:\/\/(www\.)?/, "").replace(/[?#].*$/, "").replace(/\/+$/, "");

// Classify one search for a course page.
export function classifyCourseSearch(input: any, organic: any[], min: number) {
  const top = organic.slice(0, 10).map((r: any) => ({ title: String(r.title || ""), link: String(r.link || ""), position: r.position, on_site: onSite(String(r.link || ""), input.domain), score: Math.round(titleScore(input.course, String(r.title || "")) * 100) / 100 }));
  const match = top.find((r) => r.on_site && r.score >= min);
  const outcome = !top.length ? "no_results" : match ? "found_on_provider_site" : top.some((r) => r.on_site) ? "provider_site_no_title_match" : "other_sites_only";
  return { outcome, found_url: match?.link || null, found_title: match?.title || null, same_as_earlier_candidate: !!(match && input.earlier_candidate && norm(match.link) === norm(input.earlier_candidate)), top: top.slice(0, 3) };
}
// Classify one search for a provider's website.
export function classifyProviderSearch(input: any, organic: any[], min: number, directories: string[]) {
  const top = organic.slice(0, 10).map((r: any) => ({ title: String(r.title || ""), link: String(r.link || ""), position: r.position, score: Math.round(titleScore(input.provider, String(r.title || "")) * 100) / 100, directory: directories.some((d) => hostOf(String(r.link || "")).includes(String(d).toLowerCase())) }));
  const own = top.find((r) => !r.directory && r.score >= min);
  const outcome = !top.length ? "no_results" : own ? "likely_official_site" : top.every((r) => r.directory) ? "directories_only" : "no_confident_match";
  return { outcome, suggested_site: own ? "https://" + hostOf(own.link) : null, found_title: own?.title || null, top: top.slice(0, 3) };
}
// Classify one rendered page.
const tag = (html: string, t: string) => (html.match(new RegExp(`<${t}[^>]*>([\\s\\S]*?)</${t}>`, "i"))?.[1] || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
export function classifyRender(input: any, status: number, html: string, min: number) {
  const text = html.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/gi, " ").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");
  const h1 = tag(html, "h1"), title = tag(html, "title");
  const blocked = status === 403 || status === 429 || status === 503 || /captcha|cf-chl|access denied|are you a robot|verify you are human/i.test(html.slice(0, 20000)) && text.length < 4000;
  const score = Math.max(titleScore(input.course, h1), titleScore(input.course, title));
  const code = !!(input.code && text.includes(String(input.code)));
  const markers = { intake: /\b(intakes?|commenc\w*|start dates?)\b[^.]{0,80}\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*/i.test(text), english: /\b(IELTS|TOEFL|PTE Academic|Duolingo English)\b/i.test(text), tuition: /(A\$|NZ\$|C\$|CA\$|\$|AUD|NZD|CAD)\s?\d{1,3}(,\d{3})+/.test(text) };
  const outcome = status >= 400 || !html ? (blocked ? "blocked" : "error") : blocked ? "blocked" : score >= min || code ? "rendered_course_page" : "rendered_other_page";
  return { outcome, title_score: Math.round(score * 100) / 100, code_found: code, h1: h1.slice(0, 160), title: title.slice(0, 160), text_chars: text.length, markers };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: hdrs(req) });
  if (req.method !== "POST") return reply(req, 405, { error: "method_not_allowed" });
  const auth = req.headers.get("authorization") || "";
  if (!auth.toLowerCase().startsWith("bearer ")) return reply(req, 401, { error: "authentication_required" });
  const url = Deno.env.get("SUPABASE_URL"), anon = Deno.env.get("SUPABASE_ANON_KEY"), service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return reply(req, 500, { error: "service_configuration_error" });
  const user = createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: ctx, error: ctxErr } = await user.rpc("admin_read", { p_operation: "context", p_args: {} });
  if (ctxErr || !ctx?.authenticated) return reply(req, 401, { error: "authentication_required" });
  if (Number(ctx?.role_rank || 0) < 6) return reply(req, 403, { error: "platform_admin_role_required" });
  let body: any; try { body = await req.json() } catch { return reply(req, 400, { error: "invalid_json" }) }
  const runId = String(body?.run_id || "");
  if (body?.action !== "run" || !/^[0-9a-f-]{36}$/i.test(runId)) return reply(req, 400, { error: "run_id_required" });
  const svc = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const rpc = async (n: string, a: Record<string, unknown>) => { const { data, error } = await svc.rpc(n, a); if (error) throw new Error(`${n}: ${error.message}`); return data };

  const work = async () => {
    const t0 = Date.now(); let timedOut = false, go = true;
    try {
      while (go) {
        const batch = await rpc("svc_toolset_trial_next", { p_run_id: runId, p_limit: 10 });
        const items: any[] = batch?.items || []; if (!items.length) break;
        const s = batch.settings || {}, prov = batch.provider || {}, purpose = String(batch.purpose);
        const budgetMs = Number(s.trial_seconds_per_call) * 1000, conc = Math.max(1, Number(s.trial_concurrency) || 1), min = Number(s.title_match_min);
        if (!prov.secret) { for (const it of items) await rpc("svc_toolset_trial_record", { p_item_id: it.id, p_result: { outcome: "vendor_limit", message: "no key saved" } }); break }
        let i = 0;
        await Promise.all(Array.from({ length: Math.min(conc, items.length) }, async () => {
          while (go && i < items.length) {
            const it = items[i++]; const inp = it.input || {};
            if (Date.now() - t0 > budgetMs) { timedOut = true; go = false; break }
            const started = Date.now(); let res: any;
            try {
              if (purpose === "render_page") {
                const q = new URLSearchParams({ api_key: prov.secret, url: String(inp.url), render_js: String(!!s.render_js), premium_proxy: String(!!s.premium_proxy), block_resources: "false" });
                if (s.render_js && Number(s.wait_ms) > 0) q.set("wait", String(Number(s.wait_ms)));
                const r = await fetch(`${prov.base_url}?${q}`, { signal: AbortSignal.timeout(Number(prov.timeout_seconds || 90) * 1000) });
                const credits = Number(r.headers.get("spb-cost") || 0); const html = await r.text();
                if (r.status === 401 || r.status === 402 || (r.status === 429 && /credit|limit|plan/i.test(html.slice(0, 400)))) res = { outcome: "vendor_limit", message: `ScrapingBee ${r.status}: ${html.slice(0, 200)}` };
                else res = { ...classifyRender(inp, r.status, html, min), http_status: r.status, credits, final_url: r.headers.get("spb-resolved-url") || null, html_bytes: html.length };
              } else {
                const q = purpose === "find_course_page"
                  ? fill(String(s.course_query), { course: inp.course, provider: inp.provider, code: inp.code || "", country: inp.country }) + (s.course_site_filter && inp.domain ? ` site:${inp.domain}` : "")
                  : fill(String(s.provider_query), { provider: inp.provider, city: inp.city || "", country: inp.country });
                const r = await fetch(String(prov.base_url), { method: "POST", headers: { "X-API-KEY": prov.secret, "content-type": "application/json" }, body: JSON.stringify({ q, gl: String(it.country).toLowerCase(), num: Number(s.results_per_query) || 10 }), signal: AbortSignal.timeout(Number(prov.timeout_seconds || 30) * 1000) });
                const txt = await r.text(); let d: any = {}; try { d = JSON.parse(txt) } catch { /* not json */ }
                if (r.status === 401 || r.status === 402 || r.status === 403 || (r.status === 400 && /credit|key/i.test(txt))) res = { outcome: "vendor_limit", message: `Serper ${r.status}: ${txt.slice(0, 200)}` };
                else if (!r.ok) res = { outcome: "error", http_status: r.status, credits: 0, query: q, message: txt.slice(0, 200) };
                else {
                  const organic = Array.isArray(d.organic) ? d.organic : [];
                  res = { ...(purpose === "find_course_page" ? classifyCourseSearch(inp, organic, min) : classifyProviderSearch(inp, organic, min, Array.isArray(s.directory_hosts) ? s.directory_hosts : [])), http_status: r.status, credits: Number(d.credits ?? 1), query: q };
                }
              }
            } catch (e) { res = { outcome: "error", credits: 0, message: String((e as Error)?.message || e).slice(0, 200) } }
            res.latency_ms = Date.now() - started; res.worker_version = VERSION;
            const rec = await rpc("svc_toolset_trial_record", { p_item_id: it.id, p_result: res });
            if (!rec?.continue) go = false;
          }
        }));
        if (Date.now() - t0 > budgetMs) { timedOut = true; break }
      }
    } catch (e) { console.error("toolset-trial", runId, String((e as Error)?.message || e)) }
    try { await rpc("svc_toolset_trial_close", { p_run_id: runId, p_timed_out: timedOut }) } catch (e) { console.error("close", String(e)) }
  };
  // @ts-ignore EdgeRuntime is provided by Supabase
  EdgeRuntime.waitUntil(work());
  return reply(req, 202, { ok: true, run_id: runId, worker_version: VERSION });
});
