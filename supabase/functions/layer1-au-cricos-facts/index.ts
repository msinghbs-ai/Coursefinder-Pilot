import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "layer1-au-cricos-facts-v1.0.4";
const FUNCTION_NAME = "layer1-au-cricos-facts";
const RESOURCE_META = "https://data.gov.au/data/api/3/action/resource_show?id=48cacf69-2082-415e-9595-f17d0c3a4af0";
const DEFAULT_BATCH = 500;
const MAX_BATCH = 500;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cf-run-nonce",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "content-type": "application/json", "cache-control": "no-store" },
});
const clean = (v: unknown) => String(v ?? "").trim();
const nk = (v: unknown) => clean(v).replace(/^\uFEFF/, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
const numericText = (v: unknown) => clean(v).replace(/,/g, "");

async function rpc(client: any, name: string, args: Record<string, unknown> = {}) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

async function fetchT(url: string, ms: number) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      redirect: "follow",
      headers: { "user-agent": "coursefinder-au-cricos-facts/1.0" },
    });
    if (!response.ok) throw new Error(`${url} HTTP ${response.status}`);
    return response;
  } finally {
    clearTimeout(timer);
  }
}

async function sha256(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

async function authorize(req: Request, service: any, url: string, anon: string) {
  const nonce = clean(req.headers.get("x-cf-run-nonce"));
  if (nonce) {
    const ok = await rpc(service, "svc_pilot_consume_nonce", { p_function: FUNCTION_NAME, p_nonce: nonce });
    if (!ok) throw new Error("valid one-time Pilot nonce required");
    return { id: null, mode: "nonce" };
  }
  const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("authentication required");
  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });
  const result = await userClient.auth.getUser(token);
  if (result.error || !result.data.user) throw new Error("invalid session");
  const ok = await rpc(service, "svc_layer1_authorize_platform_admin", { p_user_id: result.data.user.id });
  if (!ok) throw new Error("platform_admin required");
  return { id: result.data.user.id, mode: "user" };
}

function scanCsv(text: string, offset: number, batchSize: number) {
  let header: string[] | null = null;
  let index: Record<string, number> = {};
  let row: string[] = [];
  let field = "";
  let quoted = false;
  let sourceRows = 0;
  let activeRows = 0;
  let expiredRows = 0;
  const selected: Record<string, string>[] = [];

  const pushRow = () => {
    row.push(field);
    field = "";
    if (!header) {
      header = row.map((x) => clean(x).replace(/^\uFEFF/, ""));
      index = Object.fromEntries(header.map((h, i) => [nk(h), i]));
      row = [];
      return;
    }
    if (!row.some((x) => clean(x))) { row = []; return; }
    sourceRows++;
    const get = (name: string) => clean(row[index[nk(name)]]);
    const expired = get("Expired");
    const active = !expired || /^(no|false|n|0)$/i.test(expired);
    if (!active) {
      expiredRows++;
      row = [];
      return;
    }
    const activeIndex = activeRows++;
    if (activeIndex >= offset && selected.length < batchSize) {
      const f2 = get("Field of Education 2 Narrow Field");
      const m = f2.match(/^\s*(\d{4})\b\s*(?:[-–—:]\s*)?(.*)$/);
      selected.push({
        provider_code: get("CRICOS Provider Code"),
        course_code: get("CRICOS Course Code"),
        vet_national_code: get("VET National Code"),
        dual_qualification: get("Dual Qualification"),
        secondary_field_code: m?.[1] || "",
        secondary_field_name: m ? (clean(m[2]) || f2.replace(/^\s*\d{4}\b\s*/, "")) : f2,
        foundation_studies: get("Foundation Studies"),
        work_component: get("Work Component"),
        work_component_hours_per_week: numericText(get("Work Component Hours/Week")),
        work_component_weeks: numericText(get("Work Component Weeks")),
        work_component_total_hours: numericText(get("Work Component Total Hours")),
        course_language: get("Course Language"),
        tuition_fee: get("Tuition Fee"),
        non_tuition_fee: get("Non Tuition Fee"),
        estimated_total_course_cost: get("Estimated Total Course Cost"),
      });
    }
    row = [];
  };

  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else quoted = false;
      } else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n") pushRow();
    else if (c !== "\r") field += c;
  }
  if (field.length || row.length) pushRow();
  return { sourceSchema: header || [], sourceRows, activeRows, expiredRows, selected };
}

async function recordEvidence(service: any, sourceId: string, jobId: string, sourceUrl: string, bytes: Uint8Array, hash: string, metadata: Record<string, unknown>) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const path = `regulatory/AU/cricos/${stamp}-courses.csv`;
  const upload = await service.storage.from("evidence").upload(path, bytes, { contentType: "text/csv", upsert: true });
  if (upload.error) throw new Error(upload.error.message);
  const id = await rpc(service, "svc_layer1_record_evidence", {
    p_source_id: sourceId,
    p_job_id: jobId,
    p_source_url: sourceUrl,
    p_storage_path: path,
    p_content_hash: hash,
    p_mime_type: "text/csv",
    p_metadata: metadata,
  });
  return { id, path };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || serviceKey;
  const service = createClient(url, serviceKey, { auth: { persistSession: false } });
  let jobId: string | null = null;
  let source: any = null;

  try {
    const actor = await authorize(req, service, url, anon);
    const body = await req.json().catch(() => ({}));
    const apply = body.apply === true;
    const offset = Math.max(0, Number(body.offset ?? 0));
    const batchSize = Math.max(1, Math.min(Number(body.batchSize ?? DEFAULT_BATCH), MAX_BATCH));

    const sources = await rpc(service, "svc_layer1_resolve_sources", { p_country_code: "AU" });
    source = (sources || []).find((x: any) => x.system_code === "au_cricos") || (sources || [])[0];
    if (!source) throw new Error("AU CRICOS source missing");

    jobId = await rpc(service, "svc_layer1_start_job", {
      p_country_code: "AU",
      p_source_id: source.source_id,
      p_payload: {
        apply,
        offset,
        batch_size: batchSize,
        runtime: "supabase_edge",
        version: VERSION,
        mode: "cricos_regulatory_course_facts",
        requested_by: actor.id,
        authorization_mode: actor.mode,
      },
    });

    const metaResponse = await fetchT(RESOURCE_META, 30000);
    const resource = (await metaResponse.json())?.result;
    if (!resource?.url || !resource?.last_modified) throw new Error("current CRICOS Courses resource metadata missing");
    if (!/^CRICOS Courses\.csv$/i.test(String(resource.name || "").trim())) throw new Error("CRICOS Courses resource identity changed");

    const fileResponse = await fetchT(resource.url, 120000);
    const bytes = new Uint8Array(await fileResponse.arrayBuffer());
    const hash = await sha256(bytes);
    if (body.expectedHash && clean(body.expectedHash) !== hash) throw new Error("CRICOS Courses source changed since approved evidence capture");

    const scan = scanCsv(new TextDecoder().decode(bytes), offset, batchSize);
    if (scan.activeRows !== 26648) throw new Error(`active CRICOS course count drift: expected 26648, got ${scan.activeRows}`);
    if (scan.selected.some((r) => !r.provider_code || !r.course_code)) throw new Error("selected CRICOS identity row missing Provider/Course code");

    let evidenceId = clean(body.evidenceId);
    let evidencePath: string | null = null;
    if (!evidenceId) {
      const ev = await recordEvidence(service, source.source_id, jobId, resource.url, bytes, hash, {
        resource_id: resource.id,
        resource_name: resource.name,
        last_modified: resource.last_modified,
        byte_size: bytes.length,
        columns: scan.sourceSchema,
        field_classification_version: "M1-L1-AU-CRICOS-FACTS-v1",
      });
      evidenceId = ev.id;
      evidencePath = ev.path;
    }

    const reconciliation = await rpc(service, "svc_layer1_apply_course_regulatory_facts", {
      p_country_code: "AU",
      p_source_id: source.source_id,
      p_evidence_id: evidenceId,
      p_registration_scheme: "cricos",
      p_source_snapshot_at: resource.last_modified,
      p_records: scan.selected,
      p_apply: apply,
    });

    const nextOffset = offset + scan.selected.length;
    const hasMore = nextOffset < scan.activeRows;
    const result = {
      country: "AU",
      mode: apply ? "apply" : "dry-run",
      adapter: "cricos_direct_courses_regulatory_facts",
      workerVersion: VERSION,
      offset,
      batchSize,
      totalRecords: scan.activeRows,
      selectedRecords: scan.selected.length,
      nextOffset,
      hasMore,
      sourceRows: scan.sourceRows,
      expiredRows: scan.expiredRows,
      reconciliation,
      evidenceId,
      evidencePath,
      courseHash: hash,
      resource: { id: resource.id, name: resource.name, last_modified: resource.last_modified, byte_size: bytes.length },
      sourceSchema: scan.sourceSchema,
      feeSemantics: {
        currency: "AUD",
        audience: "international",
        fee_year: null,
        basis: "registered_total_course",
        annualised: false,
        types: ["tuition", "non_tuition", "estimated_total_course_cost"],
      },
      searchAdmission: "blocked_by_search.enrichment_gates.course_fee",
    };

    await rpc(service, "svc_layer1_source_health", {
      p_source_id: source.source_id,
      p_success: true,
      p_error: null,
      p_metadata: {
        cricos_facts_worker_version: VERSION,
        cricos_facts_hash: hash,
        cricos_facts_snapshot: resource.last_modified,
        cricos_facts_last_run_mode: result.mode,
        cricos_facts_last_offset: offset,
        cricos_facts_last_batch_size: batchSize,
        cricos_facts_next_offset: nextOffset,
        cricos_facts_has_more: hasMore,
      },
    });
    await rpc(service, "svc_layer1_finish_job", { p_job_id: jobId, p_status: "completed", p_result: result, p_error: null });
    return json({ ok: true, jobId, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (jobId) {
      try { await rpc(service, "svc_layer1_finish_job", { p_job_id: jobId, p_status: "failed", p_result: { workerVersion: VERSION }, p_error: message }); } catch {}
    }
    if (source) {
      try { await rpc(service, "svc_layer1_source_health", { p_source_id: source.source_id, p_success: false, p_error: message, p_metadata: { cricos_facts_worker_version: VERSION } }); } catch {}
    }
    return json({ error: message, jobId, workerVersion: VERSION }, 500);
  }
});
