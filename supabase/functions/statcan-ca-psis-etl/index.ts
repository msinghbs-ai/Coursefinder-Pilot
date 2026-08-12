import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "statcan-ca-psis-etl-v0.1.0";
const PID = "37100278";
const WDS = "https://www150.statcan.gc.ca/t1/wds/rest";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

async function rpc(client: any, name: string, args: Record<string, unknown> = {}) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}
async function authAdmin(req: Request, service: any, url: string, anon: string) {
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("authentication required");
  const client = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false } });
  const { data: { user }, error } = await client.auth.getUser(token);
  if (error || !user) throw new Error("invalid user session");
  if (!await rpc(service, "svc_layer1_authorize_platform_admin", { p_user_id: user.id })) throw new Error("platform_admin required");
  return user;
}
async function fetchOk(url: string, ms = 120000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    const r = await fetch(url, { signal: controller.signal, redirect: "follow", headers: { "user-agent": "coursefinder-pilot/statcan-ca-psis-0.1.0", accept: "application/json,application/zip,*/*" } });
    if (!r.ok) throw new Error(`HTTP ${r.status}: ${url}`);
    return r;
  } finally { clearTimeout(timer); }
}
async function sha256(bytes: Uint8Array) {
  const h = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(h)].map(x => x.toString(16).padStart(2, "0")).join("");
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
    if (apply) return json({ error: "PSIS canonical outcomes APPLY is not enabled until parser/mapping UAT passes", workerVersion: VERSION }, 409);

    const sources = await rpc(service, "svc_layer2a_resolve_sources", { p_country_code: "CA" }) || [];
    const source = sources.find((x: any) => x.system_code === "statcan_wds" && x.source_metadata?.pid === PID) || sources.find((x: any) => x.system_code === "statcan_wds");
    if (!source) throw new Error("Statistics Canada PSIS source configuration missing");

    const jobId = await rpc(service, "svc_layer2a_start_job", { p_country_code: "CA", p_source_id: source.source_id, p_payload: { country: "CA", layer: "2A", source: "Statistics Canada PSIS", pid: PID, apply: false, requested_by: user.id, version: VERSION } });
    try {
      const metadataUrl = `${WDS}/getCubeMetadata/${PID}`;
      const downloadApiUrl = `${WDS}/getFullTableDownloadCSV/${PID}/en`;
      const metadata = await (await fetchOk(metadataUrl, 45000)).json();
      const downloadResponse = await (await fetchOk(downloadApiUrl, 45000)).json();
      const zipUrl = downloadResponse?.object;
      if (!zipUrl || typeof zipUrl !== "string") throw new Error("Statistics Canada WDS did not return a full-table CSV download URL");
      const zipResponse = await fetchOk(zipUrl, 120000);
      const bytes = new Uint8Array(await zipResponse.arrayBuffer());
      if (bytes.length < 1000) throw new Error(`Statistics Canada PSIS download implausibly small: ${bytes.length} bytes`);
      const hash = await sha256(bytes);
      const stamp = new Date().toISOString().replace(/[:.]/g, "-");
      const path = `layer2a/CA/statcan/psis/${PID}/${stamp}.zip`;
      const upload = await service.storage.from("evidence").upload(path, bytes, { contentType: "application/zip", upsert: true });
      if (upload.error) throw new Error(`evidence upload: ${upload.error.message}`);
      const evidenceId = await rpc(service, "svc_layer2a_record_evidence", { p_source_id: source.source_id, p_job_id: jobId, p_source_url: zipUrl, p_storage_path: path, p_content_hash: hash, p_mime_type: "application/zip", p_metadata: { pid: PID, table: "37-10-0278-01", bytes: bytes.length, metadata_url: metadataUrl, download_api_url: downloadApiUrl, worker_version: VERSION } });
      const result = { ok: true, status: "source-acquisition-pass", country: "CA", layer: "2A", source: "Statistics Canada PSIS", pid: PID, table: "37-10-0278-01", metadata, downloadUrl: zipUrl, downloadedBytes: bytes.length, evidenceId, evidenceHash: hash, applyEnabled: false, nextGate: "parse full-table CSV, establish source institution mappings to canonical IRCC DLI Providers, validate CIP/study-level dimensions, then bounded APPLY", workerVersion: VERSION };
      await rpc(service, "svc_layer2a_source_health", { p_source_id: source.source_id, p_success: true, p_error: null, p_metadata: { worker_version: VERSION, pid: PID, evidence_hash: hash, downloaded_bytes: bytes.length, source_acquisition_pass: true } });
      await rpc(service, "svc_layer2a_finish_job", { p_job_id: jobId, p_status: "completed", p_result: result, p_error: null });
      return json(result);
    } catch (error) {
      const message = String(error).slice(0, 1800);
      try { await rpc(service, "svc_layer2a_source_health", { p_source_id: source.source_id, p_success: false, p_error: message, p_metadata: { worker_version: VERSION, pid: PID } }); } catch {}
      try { await rpc(service, "svc_layer2a_finish_job", { p_job_id: jobId, p_status: "failed", p_result: { workerVersion: VERSION, pid: PID }, p_error: message }); } catch {}
      throw error;
    }
  } catch (error) {
    return json({ error: String(error), workerVersion: VERSION }, 500);
  }
});
