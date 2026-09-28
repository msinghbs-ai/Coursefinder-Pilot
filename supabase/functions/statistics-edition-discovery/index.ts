import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

// CF-247 / Decision 134: find new statistics editions from each family's stable publisher page.
// For every rule: read the listing page, find file links with the rule's pattern, and for any file newer than the
// known editions record a candidate and check it with a dry run of the dataset's worker (nothing is written to
// the catalogue). Applying a checked candidate is a separate, deliberate action on the Layer 1 card.
const VERSION = "statistics-edition-discovery-v1.0.0";
const FN = "statistics-edition-discovery";
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json", "cache-control": "no-store" } });
async function rpc(c: any, n: string, a: Record<string, unknown> = {}) { const { data, error } = await c.rpc(n, a); if (error) throw new Error(`${n}: ${error.message}`); return data; }
const bare = (u: string) => { try { const x = new URL(u); return `${x.hostname.toLowerCase()}${x.pathname.toLowerCase()}`; } catch { return u.toLowerCase(); } };

async function dryRun(url: string, serviceKey: string, worker: string, member: string | null, fileUrl: string, year: number | null) {
  const payload: Record<string, unknown> = { mode: "dry_run", url: fileUrl };
  if (member) payload.survey = member;
  if (year) payload.year = year;
  const r = await fetch(`${url}/functions/v1/${worker}`, { method: "POST", headers: { authorization: `Bearer ${serviceKey}`, apikey: serviceKey, "x-cf-layer1-service-key": serviceKey, "content-type": "application/json" }, body: JSON.stringify(payload) });
  const body = await r.json().catch(() => ({}));
  if (!r.ok || body?.ok === false || body?.error) return { ok: false, error: String(body?.error || `${worker} HTTP ${r.status}`) };
  return { ok: true, candidateObservations: body.candidateObservations ?? body.parsedMetricCells ?? null, collectionVersion: body.collectionVersion ?? null, zipSha256: body.zipSha256 ?? null, workbookSha256: body.workbookSha256 ?? null, missingSheets: body.missingSheets ?? [], workerVersion: body.workerVersion ?? null };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "POST required" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!, serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } });
  try {
    const nonce = (req.headers.get("x-cf-run-nonce") || "").trim();
    if (!nonce || !(await rpc(svc, "svc_pilot_consume_nonce", { p_function: FN, p_nonce: nonce }))) return json({ ok: false, error: "valid one-time nonce required" }, 401);
    const rules: any[] = (await rpc(svc, "svc_statistics_edition_rules")) || [];
    const out: any[] = [];
    for (const rule of rules) {
      const res: any = { member: rule.member_code, found: 0, new: 0, checked: [] as any[] };
      try {
        const page = await fetch(rule.listing_url, { redirect: "follow", headers: { "user-agent": "CourseFinder-Pilot/statistics-discovery-1.0", accept: "text/html" } });
        if (!page.ok) throw new Error(`listing HTTP ${page.status}`);
        const html = await page.text(), base = new URL(page.url || rule.listing_url);
        const seen = new Map<string, number | null>();
        for (const m of html.matchAll(/href\s*=\s*["']([^"']+)["']/gi)) {
          const href = m[1].replace(/&amp;/g, "&"); const mm = href.match(new RegExp(rule.file_pattern, "i")); if (!mm) continue;
          let abs: URL; try { abs = new URL(href, base); } catch { continue; }
          const host = abs.hostname.toLowerCase(), dom = String(rule.authority_domain).toLowerCase();
          if (abs.protocol !== "https:" || !(host === dom || host.endsWith(`.${dom}`))) continue;
          const year = rule.year_group ? Number(mm[rule.year_group]) : null;
          seen.set(abs.toString(), Number.isInteger(year) ? year : null);
        }
        res.found = seen.size;
        const known: string[] = rule.known || [], knownBare = new Set(known.map(bare));
        const knownYears = known.map((k) => { const mm = k.match(new RegExp(rule.file_pattern, "i")); return rule.year_group && mm ? Number(mm[rule.year_group]) : NaN; }).filter(Number.isInteger);
        const maxKnown = knownYears.length ? Math.max(...knownYears) : null;
        for (const [fileUrl, year] of seen) {
          if (knownBare.has(bare(fileUrl))) continue;
          if (rule.year_group && maxKnown !== null && year !== null && year <= maxKnown) continue;
          res.new++;
          const check = await dryRun(url, serviceKey, rule.worker, rule.worker_member, fileUrl, year);
          await rpc(svc, "svc_statistics_candidate_record", { p_member_code: rule.member_code, p_file_url: fileUrl, p_edition_year: year, p_status: check.ok ? "checked" : "check_failed", p_check: check });
          res.checked.push({ fileUrl, year, ok: check.ok, rows: (check as any).candidateObservations ?? null, error: (check as any).error ?? null });
        }
      } catch (e) { res.error = String((e as Error).message || e); }
      out.push(res);
    }
    return json({ ok: true, rules: out.length, results: out, workerVersion: VERSION });
  } catch (e) { return json({ ok: false, error: String((e as Error).message || e), workerVersion: VERSION }, 500); }
});
