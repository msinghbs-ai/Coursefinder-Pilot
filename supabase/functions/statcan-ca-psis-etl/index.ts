import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import JSZip from "npm:jszip@3.10.1";
import Papa from "npm:papaparse@5.4.1";

const VERSION = "statcan-ca-psis-etl-v0.2.1";
const PID = "37100278";
const TABLE = "37-10-0278-01";
const WDS = "https://www150.statcan.gc.ca/t1/wds/rest";
const MAX_SAMPLE_ROWS = 5000;

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
async function fetchOk(url: string, ms = 120000, init: RequestInit = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    const r = await fetch(url, {
      ...init,
      signal: controller.signal,
      redirect: "follow",
      headers: {
        "user-agent": "coursefinder-pilot/statcan-ca-psis-0.2.1",
        accept: "application/json,application/zip,text/csv,*/*",
        ...(init.headers || {}),
      },
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}: ${url}`);
    return r;
  } finally { clearTimeout(timer); }
}
async function sha256(bytes: Uint8Array) {
  const h = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(h)].map(x => x.toString(16).padStart(2, "0")).join("");
}
const clean = (v: unknown) => String(v ?? "").replace(/\s+/g, " ").trim();
const lowerKeys = (row: Record<string, unknown>) => Object.fromEntries(Object.entries(row).map(([k,v]) => [k.toLowerCase(), v]));
const pick = (row: Record<string, unknown>, names: string[]) => {
  const l = lowerKeys(row);
  for (const n of names) if (l[n.toLowerCase()] !== undefined) return clean(l[n.toLowerCase()]);
  return "";
};

function classifyGeographyInstitution(label: string) {
  const x = clean(label);
  if (!x) return "unknown";
  if (/^Canada$/i.test(x)) return "aggregate";
  if (/^(Newfoundland and Labrador|Prince Edward Island|Nova Scotia|New Brunswick|Quebec|Ontario|Manitoba|Saskatchewan|Alberta|British Columbia|Yukon|Northwest Territories|Nunavut)$/i.test(x)) return "aggregate";
  return "institution";
}

function parseCoordinateKey(coord: string) {
  const first = clean(coord).split(".")[0];
  return /^\d+$/.test(first) ? `statcan:${PID}:geo-member:${first}` : null;
}

function parseSampleCsv(csv: string, maxRows: number) {
  const parsed = Papa.parse<Record<string, unknown>>(csv, { header: true, skipEmptyLines: true, dynamicTyping: false, preview: maxRows });
  const fields = parsed.meta.fields || [];
  const rows = parsed.data || [];
  const institutions = new Map<string, any>();
  const fieldSamples = new Set<string>();
  const credentialSamples = new Set<string>();
  const statusSamples = new Set<string>();
  for (const row of rows) {
    const geo = pick(row, ["Geography and institutions", "GEO"]);
    if (!geo || classifyGeographyInstitution(geo) !== "institution") continue;
    const coord = pick(row, ["COORDINATE"]);
    const sourceKey = parseCoordinateKey(coord) || `statcan:${PID}:label-candidate:${geo}`;
    const field = pick(row, ["Field of study"]);
    const credential = pick(row, ["Credential type"]);
    const studentStatus = pick(row, ["Status of student in Canada"]);
    if (field) fieldSamples.add(field);
    if (credential) credentialSamples.add(credential);
    if (studentStatus) statusSamples.add(studentStatus);
    if (!institutions.has(sourceKey)) institutions.set(sourceKey, {
      source_entity_key: sourceKey,
      source_entity_name: geo,
      coordinate: coord || null,
      match_status: "unmatched",
      identity_write_allowed: false,
      mapping_target: "catalogue.providers (verified IRCC DLI Provider only)",
    });
  }
  return {
    headers: fields,
    sampledRows: rows.length,
    institutions: [...institutions.values()].slice(0, 500),
    institutionCountInSample: institutions.size,
    fieldSamples: [...fieldSamples].slice(0, 50),
    credentialSamples: [...credentialSamples].slice(0, 50),
    studentStatusSamples: [...statusSamples].slice(0, 20),
    parseErrors: parsed.errors.slice(0, 20),
  };
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
    const sampleRows = Math.max(1, Math.min(Number(body.sampleRows ?? 1000), MAX_SAMPLE_ROWS));
    if (apply) return json({ error: "PSIS canonical outcomes APPLY is not enabled until parser/mapping UAT passes", workerVersion: VERSION }, 409);

    const sources = await rpc(service, "svc_layer2a_resolve_sources", { p_country_code: "CA" }) || [];
    const source = sources.find((x: any) => x.system_code === "statcan_wds" && x.source_metadata?.pid === PID) || sources.find((x: any) => x.system_code === "statcan_wds");
    if (!source) throw new Error("Statistics Canada PSIS source configuration missing");

    const jobId = await rpc(service, "svc_layer2a_start_job", { p_country_code: "CA", p_source_id: source.source_id, p_payload: { country: "CA", layer: "2A", source: "Statistics Canada PSIS", pid: PID, table: TABLE, apply: false, sample_rows: sampleRows, requested_by: user.id, version: VERSION } });
    try {
      const metadataUrl = `${WDS}/getCubeMetadata`;
      const downloadApiUrl = `${WDS}/getFullTableDownloadCSV/${PID}/en`;
      const metadataResponse = await fetchOk(metadataUrl, 45000, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify([{ productId: Number(PID) }]),
      });
      const metadata = await metadataResponse.json();
      const downloadResponse = await (await fetchOk(downloadApiUrl, 45000)).json();
      const zipUrl = downloadResponse?.object;
      if (!zipUrl || typeof zipUrl !== "string") throw new Error("Statistics Canada WDS did not return a full-table CSV download URL");
      const zipResponse = await fetchOk(zipUrl, 120000);
      const contentLength = Number(zipResponse.headers.get("content-length") || 0);
      const bytes = new Uint8Array(await zipResponse.arrayBuffer());
      if (bytes.length < 1000) throw new Error(`Statistics Canada PSIS download implausibly small: ${bytes.length} bytes`);
      const hash = await sha256(bytes);
      const stamp = new Date().toISOString().replace(/[:.]/g, "-");
      const path = `layer2a/CA/statcan/psis/${PID}/${stamp}.zip`;
      const upload = await service.storage.from("evidence").upload(path, bytes, { contentType: "application/zip", upsert: true });
      if (upload.error) throw new Error(`evidence upload: ${upload.error.message}`);
      const evidenceId = await rpc(service, "svc_layer2a_record_evidence", { p_source_id: source.source_id, p_job_id: jobId, p_source_url: zipUrl, p_storage_path: path, p_content_hash: hash, p_mime_type: "application/zip", p_metadata: { pid: PID, table: TABLE, bytes: bytes.length, metadata_url: metadataUrl, metadata_method: "POST", download_api_url: downloadApiUrl, worker_version: VERSION } });

      const zip = await JSZip.loadAsync(bytes);
      const csvEntry = Object.values(zip.files).find((f: any) => !f.dir && /\.csv$/i.test(f.name) && !/MetaData/i.test(f.name));
      if (!csvEntry) throw new Error("Statistics Canada ZIP did not contain a data CSV entry");
      const csvText = await (csvEntry as any).async("string");
      const diagnostics = parseSampleCsv(csvText, sampleRows);
      const required = ["REF_DATE", "VALUE"];
      const missingRequired = required.filter(x => !diagnostics.headers.some((h: string) => h.toUpperCase() === x));
      const geoHeader = diagnostics.headers.find((h: string) => /geography and institutions/i.test(h)) || diagnostics.headers.find((h: string) => h.toUpperCase() === "GEO");
      if (!geoHeader) missingRequired.push("Geography and institutions/GEO");

      const result = {
        ok: missingRequired.length === 0,
        status: missingRequired.length === 0 ? "parser-dry-run-pass" : "parser-schema-blocked",
        country: "CA",
        layer: "2A",
        source: "Statistics Canada PSIS",
        pid: PID,
        table: TABLE,
        metadata,
        downloadUrl: zipUrl,
        downloadedBytes: bytes.length,
        contentLengthHeader: contentLength || null,
        evidenceId,
        evidenceHash: hash,
        csvEntry: (csvEntry as any).name,
        sampleRowsRequested: sampleRows,
        diagnostics,
        missingRequiredHeaders: missingRequired,
        providerMappingRequired: true,
        canonicalIdentityWrite: false,
        applyEnabled: false,
        identityBoundary: {
          provider: "IRCC DLI only",
          course: "DLI + stable local source key; title excluded",
          provincialRegistration: "optional validation metadata",
        },
        nextGate: "persist candidate source-provider mappings; validate exact IRCC DLI matches; validate CIP/study-level/audience transforms; then bounded provider_outcomes APPLY",
        workerVersion: VERSION,
      };
      await rpc(service, "svc_layer2a_source_health", { p_source_id: source.source_id, p_success: missingRequired.length === 0, p_error: missingRequired.length ? `missing required headers: ${missingRequired.join(", ")}` : null, p_metadata: { worker_version: VERSION, pid: PID, evidence_hash: hash, downloaded_bytes: bytes.length, parser_dry_run_pass: missingRequired.length === 0, sampled_rows: diagnostics.sampledRows, institution_count_in_sample: diagnostics.institutionCountInSample } });
      await rpc(service, "svc_layer2a_finish_job", { p_job_id: jobId, p_status: missingRequired.length === 0 ? "completed" : "blocked", p_result: result, p_error: missingRequired.length ? `missing required headers: ${missingRequired.join(", ")}` : null });
      return json(result, missingRequired.length === 0 ? 200 : 409);
    } catch (error) {
      const message = String(error).slice(0, 1800);
      try { await rpc(service, "svc_layer2a_source_health", { p_source_id: source.source_id, p_success: false, p_error: message, p_metadata: { worker_version: VERSION, pid: PID } }); } catch {}
      try { await rpc(service, "svc_layer2a_finish_job", { p_job_id: jobId, p_status: "failed", p_result: { workerVersion: VERSION, pid: PID }, p_error: message }); } catch {}
      throw error;
    }
  } catch (error) {
    console.error(error);
    return json({ error: String(error), workerVersion: VERSION }, 500);
  }
});
