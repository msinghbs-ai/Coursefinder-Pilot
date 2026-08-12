import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "layer1-ca-live-v1.0.0";
const IRCC_DLI_URL = "https://www.canada.ca/en/immigration-refugees-citizenship/services/study-canada/study-permit/prepare/designated-learning-institutions-list.html";
const DEFAULT_BATCH = 100;
const MAX_BATCH = 500;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const clean = (v: unknown) => String(v ?? "").replace(/\s+/g, " ").trim();
const decode = (v: string) => clean(v
  .replace(/&nbsp;/g, " ")
  .replace(/&amp;/g, "&")
  .replace(/&quot;/g, '"')
  .replace(/&#39;|&apos;/g, "'")
  .replace(/&ndash;|&#8211;/g, "–")
  .replace(/&mdash;|&#8212;/g, "—")
  .replace(/<[^>]*>/g, " "));

async function fetchT(url: string, ms = 45000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    return await fetch(url, {
      signal: controller.signal,
      redirect: "follow",
      headers: { "user-agent": "coursefinder-pilot/ca-live-1.0.0", accept: "text/html,application/xhtml+xml" },
    });
  } finally { clearTimeout(timer); }
}

async function hashBytes(bytes: Uint8Array) {
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map(x => x.toString(16).padStart(2, "0")).join("");
}

async function rpc(client: any, name: string, args: Record<string, unknown> = {}) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

async function authAdmin(req: Request, service: any, url: string, anon: string) {
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("authentication required");
  const client = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });
  const { data: { user }, error } = await client.auth.getUser(token);
  if (error || !user) throw new Error("invalid user session");
  if (!await rpc(service, "svc_layer1_authorize_platform_admin", { p_user_id: user.id })) throw new Error("platform_admin required");
  return user;
}

function parseDliProviders(html: string) {
  const providers = new Map<string, any>();
  const rows = html.match(/<tr\b[\s\S]*?<\/tr>/gi) || [];
  for (const row of rows) {
    const cells = [...row.matchAll(/<t[dh]\b[^>]*>([\s\S]*?)<\/t[dh]>/gi)].map(m => decode(m[1]));
    if (cells.length < 3) continue;
    const joined = cells.join(" | ");
    const dli = joined.match(/\bO\d{10,15}\b/)?.[0];
    if (!dli) continue;
    const dliIndex = cells.findIndex(c => c.includes(dli));
    const providerName = dliIndex > 0 ? clean(cells[dliIndex - 1]) : "";
    if (!providerName || /DLI name|Institution/i.test(providerName)) continue;
    const province = dliIndex > 1 ? clean(cells[dliIndex - 2]) : null;
    const city = dliIndex >= 0 && cells[dliIndex + 1] ? clean(cells[dliIndex + 1]) : null;
    const campus = dliIndex >= 0 && cells[dliIndex + 2] ? clean(cells[dliIndex + 2]) : null;
    const publicPrivate = cells.find(c => /Public institution|Private institution/i.test(c)) || null;
    const current = providers.get(dli) || {
      provider_code: dli,
      provider_name: providerName,
      province,
      cities: new Set<string>(),
      campuses: new Set<string>(),
      public_private: publicPrivate,
    };
    if (city) current.cities.add(city);
    if (campus) current.campuses.add(campus);
    providers.set(dli, current);
  }
  return [...providers.values()].map(p => ({
    provider_code: p.provider_code,
    provider_name: p.provider_name,
    province: p.province,
    cities: [...p.cities],
    campuses: [...p.campuses],
    public_private: p.public_private,
  })).sort((a, b) => a.provider_code.localeCompare(b.provider_code));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY") || serviceKey;
  const service = createClient(url, serviceKey, { auth: { persistSession: false } });

  try {
    const user = await authAdmin(req, service, url, anon);
    const body = await req.json().catch(() => ({}));
    const apply = Boolean(body.apply);
    const offset = Math.max(0, Number(body.offset ?? 0));
    const batchSize = Math.max(1, Math.min(Number(body.batchSize ?? DEFAULT_BATCH), MAX_BATCH));

    const sourceRows = await rpc(service, "svc_layer1_resolve_sources", { p_country_code: "CA" }) || [];
    const source = sourceRows.find((x: any) => x.system_code === "ca_ircc_dli") || sourceRows[0];
    if (!source) throw new Error("CA IRCC DLI source missing");

    const sourceUrl = source.source_url || source.system_base_url || IRCC_DLI_URL;
    const jobId = await rpc(service, "svc_layer1_start_job", {
      p_country_code: "CA",
      p_source_id: source.source_id,
      p_payload: { country_code: "CA", apply, offset, batch_size: batchSize, runtime: "supabase_edge", version: VERSION, mode: "ircc_dli_live_gate", requested_by: user.id },
    });

    try {
      const response = await fetchT(sourceUrl);
      if (!response.ok) throw new Error(`IRCC DLI HTTP ${response.status}`);
      const html = await response.text();
      const bytes = new TextEncoder().encode(html);
      const hash = await hashBytes(bytes);
      const providers = parseDliProviders(html);
      if (providers.length < 100) throw new Error(`IRCC DLI parse returned implausible provider count ${providers.length}`);

      const selected = providers.slice(offset, offset + batchSize);
      const nextOffset = offset + selected.length;
      const hasMore = nextOffset < providers.length;
      const stamp = new Date().toISOString().replace(/[:.]/g, "-");
      const path = `regulatory/CA/ircc-dli/${stamp}.html`;
      const upload = await service.storage.from("evidence").upload(path, bytes, { contentType: "text/html", upsert: true });
      if (upload.error) throw new Error(`evidence upload: ${upload.error.message}`);
      const evidenceId = await rpc(service, "svc_layer1_record_evidence", {
        p_source_id: source.source_id,
        p_job_id: jobId,
        p_source_url: sourceUrl,
        p_storage_path: path,
        p_content_hash: hash,
        p_mime_type: "text/html",
        p_metadata: { country: "CA", mode: "ircc_dli_live_gate", provider_rows: providers.length, offset, batch_size: batchSize, stable_provider_identifier: "IRCC DLI number", full_course_catalogue: false },
      });

      const blocker = {
        code: "CA_COURSE_IDENTITY_SOURCE_BLOCKER",
        summary: "IRCC DLI provides stable Provider identity but no Canada-wide authoritative course catalogue with stable regulator/source programme identifiers.",
        providerIdentity: "CA + ircc_dli + DLI number",
        courseIdentityRequired: "Provider + authoritative registration scheme + stable regulator/source course code",
        applyAllowed: false,
        architectureChangeRequired: false,
        remediation: "Adopt and validate a complete federated provincial/territorial programme-source model with stable programme identifiers, or identify a Canada-wide authoritative programme register before canonical APPLY.",
      };

      const result = {
        country: "CA",
        mode: apply ? "blocked-apply" : "dry-run",
        adapter: "ircc_dli_live_gate",
        offset,
        batchSize,
        totalRecords: providers.length,
        selectedRecords: selected.length,
        nextOffset,
        hasMore,
        parsedProviders: providers.length,
        selectedProviders: selected,
        evidenceIds: [evidenceId],
        evidenceHash: hash,
        providerIdentityStable: true,
        courseIdentityStable: false,
        courseCatalogueAuthoritativeCoverage: false,
        blocker,
        workerVersion: VERSION,
      };

      await rpc(service, "svc_layer1_source_health", {
        p_source_id: source.source_id,
        p_success: true,
        p_error: null,
        p_metadata: { worker_version: VERSION, parsed_providers: providers.length, evidence_hash: hash, live_authoritative: true, seed_snapshot: false, course_gate_blocked: true, last_run_offset: offset, last_run_batch_size: batchSize },
      });
      await rpc(service, "svc_layer1_finish_job", { p_job_id: jobId, p_status: apply ? "blocked" : "completed", p_result: result, p_error: apply ? blocker.summary : null });

      if (apply) return json({ error: blocker.summary, ...result }, 409);
      return json({ ok: true, status: "completed_with_blocker", requestedCountry: "CA", ...result });
    } catch (error) {
      const message = String(error).slice(0, 1800);
      try { await rpc(service, "svc_layer1_source_health", { p_source_id: source.source_id, p_success: false, p_error: message, p_metadata: { worker_version: VERSION } }); } catch {}
      try { await rpc(service, "svc_layer1_finish_job", { p_job_id: jobId, p_status: "failed", p_result: { workerVersion: VERSION }, p_error: message }); } catch {}
      throw error;
    }
  } catch (error) {
    return json({ error: String(error), workerVersion: VERSION }, 500);
  }
});
