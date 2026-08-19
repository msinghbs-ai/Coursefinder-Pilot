import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "layer1-au-cricos-facts-v1.0.3";
const FUNCTION_NAME = "layer1-au-cricos-facts";
const RESOURCE_META = "https://data.gov.au/data/api/3/action/resource_show?id=48cacf69-2082-415e-9595-f17d0c3a4af0";
const RPC_CHUNK = 250;
const DEFAULT_BATCH = 1000;
const MAX_BATCH = 1000;

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
const numericText = (v: unknown) => clean(v).replace(/,/g, "");
const nk = (v: unknown) => clean(v).replace(/^\uFEFF/, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

function parse(text: string) {
  const rows: string[][] = [];
  let row: string[] = [], field = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else quoted = false;
      } else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n") { row.push(field); rows.push(row); row = []; field = ""; }
    else if (c !== "\r") field += c;
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  return rows;
}
function objs(text: string) {
  const rows = parse(text);
  if (!rows.length) return [];
  const header = rows[0].map(nk);
  return rows.slice(1)
    .filter((r) => r.some(clean))
    .map((r) => Object.fromEntries(header.map((h, i) => [h, clean(r[i])])));
}
function val(row: Record<string, string>, names: string[]) {
  for (const name of names) {
    const v = row[nk(name)];
    if (clean(v)) return clean(v);
  }
  return "";
}
function fieldParts(raw: string) {
  const s = clean(raw);
  const m = s.match(/^\s*(\d{4})\b\s*(?:[-–—:]\s*)?(.*)$/);
  return m ? { code: m[1], name: clean(m[2]) || s.replace(/^\s*\d{4}\b\s*/, "") } : { code: "", name: s };
}
async function rpc(client: any, name: string, args: Record<string, unknown> = {}) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}
async function fetchT(url: string, ms = 90000) {
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
  } finally { clearTimeout(timer); }
}
async function sha(bytes: Uint8Array) {
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
  if (!await rpc(service, "svc_layer1_authorize_platform_admin", { p_user_id: result.data.user.id })) {
    throw new Error("platform_admin required");
  }
  return { id: result.data.user.id, mode: "user" };
}
async function recordEvidence(
  service: any, sourceId: string, jobId: string, sourceUrl: string,
  bytes: Uint8Array, metadata: Record<string, unknown>,
) {
  const hash = await sha(bytes);
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
  return { id, hash, path };
}
async function applyFacts(
  service: any,
  sourceId: string,
  evidenceId: string,
  snapshotAt: string,
  rows: any[],
  apply: boolean,
) {
  const total: any = {
    records: rows.length,
    matched: 0,
    course_missing: 0,
    fact_created: 0,
    fact_updated: 0,
    fact_unchanged: 0,
    fact_superseded: 0,
    fee_observations: 0,
    fee_created: 0,
    fee_updated: 0,
    fee_unchanged: 0,
    fee_superseded: 0,
    secondary_field_mapped: 0,
    secondary_field_unmapped: 0,
    invalid_boolean_values: 0,
    invalid_numeric_values: 0,
    invalid_fee_values: 0,
  };
  for (let i = 0; i < rows.length; i += RPC_CHUNK) {
    const result = await rpc(service, "svc_layer1_apply_course_regulatory_facts", {
      p_country_code: "AU",
      p_source_id: sourceId,
      p_evidence_id: evidenceId,
      p_registration_scheme: "cricos",
      p_source_snapshot_at: snapshotAt,
      p_records: rows.slice(i, i + RPC_CHUNK),
      p_apply: apply,
    });
    for (const key of Object.keys(total)) {
      if (key !== "records") total[key] += Number(result?.[key] || 0);
    }
  }
  return total;
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

    const resourceResponse = await fetchT(RESOURCE_META, 30000);
    const resourceData = await resourceResponse.json();
    const courseResource = resourceData?.result;
    if (!courseResource?.url) throw new Error("current CRICOS Courses CSV resource missing");
    if (!/^CRICOS Courses\.csv$/i.test(String(courseResource.name || "").trim())) {
      throw new Error("CRICOS Courses resource identity changed");
    }
    if (!courseResource.last_modified) throw new Error("CRICOS Courses resource last_modified missing");

    const courseResponse = await fetchT(courseResource.url, 120000);
    const bytes = new Uint8Array(await courseResponse.arrayBuffer());
    const hash = await sha(bytes);
    if (body.expectedHash && clean(body.expectedHash) !== hash) {
      throw new Error("CRICOS Courses source changed since approved evidence capture");
    }

    const text = new TextDecoder().decode(bytes);
    const parsedRows = parse(text);
    const columns = (parsedRows[0] || []).map((x) => clean(x).replace(/^\uFEFF/, ""));
    const rows = objs(text);
    const activeSourceRows = rows.filter((r: any) => {
      const expired = val(r, ["Expired"]);
      return !expired || /^(no|false|n|0)$/i.test(expired);
    });
    const expiredRows = rows.length - activeSourceRows.length;

    const normalized = activeSourceRows.map((r: any) => {
      const f2 = fieldParts(val(r, ["Field of Education 2 Narrow Field"]));
      return {
        provider_code: val(r, ["CRICOS Provider Code"]),
        course_code: val(r, ["CRICOS Course Code"]),
        vet_national_code: val(r, ["VET National Code"]),
        dual_qualification: val(r, ["Dual Qualification"]),
        secondary_field_code: f2.code,
        secondary_field_name: f2.name,
        foundation_studies: val(r, ["Foundation Studies"]),
        work_component: val(r, ["Work Component"]),
        work_component_hours_per_week: numericText(val(r, ["Work Component Hours/Week"])),
        work_component_weeks: numericText(val(r, ["Work Component Weeks"])),
        work_component_total_hours: numericText(val(r, ["Work Component Total Hours"])),
        course_language: val(r, ["Course Language"]),
        tuition_fee: val(r, ["Tuition Fee"]),
        non_tuition_fee: val(r, ["Non Tuition Fee"]),
        estimated_total_course_cost: val(r, ["Estimated Total Course Cost"]),
      };
    }).filter((r: any) => r.provider_code && r.course_code);

    if (normalized.length !== 26648) {
      throw new Error(`active CRICOS course count drift: expected 26648, got ${normalized.length}`);
    }

    const population = columns.map((name) => {
      const key = nk(name);
      let populated = 0;
      for (const r of activeSourceRows as any[]) if (clean(r[key])) populated++;
      return { field: name, active_rows: activeSourceRows.length, populated_rows: populated };
    });

    let evidenceId = clean(body.evidenceId);
    let evidencePath: string | null = null;
    if (!evidenceId) {
      const ev = await recordEvidence(service, source.source_id, jobId, courseResource.url, bytes, {
        resource_id: courseResource.id,
        resource_name: courseResource.name,
        last_modified: courseResource.last_modified,
        byte_size: bytes.length,
        columns,
        field_classification_version: "M1-L1-AU-CRICOS-FACTS-v1",
      });
      evidenceId = ev.id;
      evidencePath = ev.path;
    }

    const selected = normalized.slice(offset, offset + batchSize);
    const reconciliation = await applyFacts(
      service,
      source.source_id,
      evidenceId,
      courseResource.last_modified,
      selected,
      apply,
    );
    const nextOffset = offset + selected.length;
    const hasMore = nextOffset < normalized.length;
    const result = {
      country: "AU",
      mode: apply ? "apply" : "dry-run",
      adapter: "cricos_direct_courses_regulatory_facts",
      workerVersion: VERSION,
      offset,
      batchSize,
      totalRecords: normalized.length,
      selectedRecords: selected.length,
      nextOffset,
      hasMore,
      sourceRows: rows.length,
      expiredRows,
      reconciliation,
      evidenceId,
      evidencePath,
      courseHash: hash,
      resource: {
        id: courseResource.id,
        name: courseResource.name,
        last_modified: courseResource.last_modified,
        byte_size: bytes.length,
      },
      sourceSchema: columns,
      population,
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
        cricos_facts_snapshot: courseResource.last_modified,
        cricos_facts_last_run_mode: result.mode,
        cricos_facts_last_offset: offset,
        cricos_facts_last_batch_size: batchSize,
        cricos_facts_next_offset: nextOffset,
        cricos_facts_has_more: hasMore,
      },
    });
    await rpc(service, "svc_layer1_finish_job", {
      p_job_id: jobId,
      p_status: "completed",
      p_result: result,
      p_error: null,
    });
    return json({ ok: true, jobId, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (jobId) {
      try {
        await rpc(service, "svc_layer1_finish_job", {
          p_job_id: jobId,
          p_status: "failed",
          p_result: { workerVersion: VERSION },
          p_error: message,
        });
      } catch {}
    }
    if (source) {
      try {
        await rpc(service, "svc_layer1_source_health", {
          p_source_id: source.source_id,
          p_success: false,
          p_error: message,
          p_metadata: { cricos_facts_worker_version: VERSION },
        });
      } catch {}
    }
    return json({ error: message, jobId, workerVersion: VERSION }, 500);
  }
});
