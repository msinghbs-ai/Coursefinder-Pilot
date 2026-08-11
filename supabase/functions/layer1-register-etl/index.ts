import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "layer1-edge-v1.4.0";
const RPC_CHUNK = 250;
const DEFAULT_BATCH = 2500;
const MAX_BATCH = 5000;
const SUPPORTED = ["AU", "GB", "DE", "CA", "IE", "NZ", "US"];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const clean = (v: unknown) => String(v ?? "").trim();
const slug = (v: string) => clean(v).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 100);

function parseCSV(text: string) {
  const rows: string[][] = [];
  let row: string[] = [], field = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else quoted = false;
      } else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') { row.push(field); field = ""; }
    else if (ch === '\n') { row.push(field); rows.push(row); row = []; field = ""; }
    else if (ch !== '\r') field += ch;
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  return rows;
}

function mapLevel(raw: string) {
  const s = clean(raw).toLowerCase();
  if (/doctor|phd/.test(s)) return "doctorate";
  if (/master|m\.sc|m\.a\.|mba|ll\.m/.test(s)) return "masters";
  if (/graduate certificate/.test(s)) return "graduate_certificate";
  if (/graduate diploma/.test(s)) return "graduate_diploma";
  if (/bachelor|b\.sc|b\.a\.|b\.eng/.test(s)) return "bachelor";
  if (/associate/.test(s)) return "associate_degree";
  if (/diploma/.test(s)) return "diploma";
  if (/certificate/.test(s)) return "certificate";
  if (/foundation/.test(s)) return "foundation";
  return "";
}

async function fetchT(url: string, ms = 30000, init: RequestInit = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal,
      redirect: "follow",
      headers: { "user-agent": "coursefinder-pilot/1.4", ...(init.headers || {}) },
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
  return { user, token };
}

async function evidence(service: any, sourceId: string, jobId: string, sourceUrl: string, path: string, bytes: Uint8Array, mime: string, metadata: unknown) {
  const hash = await hashBytes(bytes);
  const upload = await service.storage.from("evidence").upload(path, bytes, { contentType: mime, upsert: true });
  if (upload.error) throw new Error(`evidence upload: ${upload.error.message}`);
  const id = await rpc(service, "svc_layer1_record_evidence", {
    p_source_id: sourceId,
    p_job_id: jobId,
    p_source_url: sourceUrl,
    p_storage_path: path,
    p_content_hash: hash,
    p_mime_type: mime,
    p_metadata: metadata,
  });
  return { id, hash };
}

async function sources(service: any, country: string) {
  return await rpc(service, "svc_layer1_resolve_sources", { p_country_code: country }) || [];
}

async function startJob(service: any, country: string, sourceId: string, payload: unknown) {
  return await rpc(service, "svc_layer1_start_job", { p_country_code: country, p_source_id: sourceId, p_payload: payload });
}

async function finishJob(service: any, id: string, status: string, result: unknown, error: string | null = null) {
  try { await rpc(service, "svc_layer1_finish_job", { p_job_id: id, p_status: status, p_result: result, p_error: error }); } catch {}
}

async function health(service: any, id: string, ok: boolean, error: string | null, metadata: unknown) {
  try { await rpc(service, "svc_layer1_source_health", { p_source_id: id, p_success: ok, p_error: error, p_metadata: metadata }); } catch {}
}

async function applyRecords(service: any, country: string, sourceId: string, evidenceId: string | null, scheme: string, records: any[], apply: boolean, offset: number, batchSize: number) {
  const selected = records.slice(offset, offset + batchSize);
  const total: any = {
    records: selected.length,
    provider_created: 0,
    provider_linked: 0,
    provider_existing: 0,
    course_created: 0,
    course_linked: 0,
    course_existing: 0,
    conflicts: 0,
  };
  if (!apply) return { selected, reconciliation: total };
  for (let i = 0; i < selected.length; i += RPC_CHUNK) {
    const result = await rpc(service, "svc_layer1_apply_register_records", {
      p_country_code: country,
      p_source_id: sourceId,
      p_evidence_id: evidenceId,
      p_registration_scheme: scheme,
      p_records: selected.slice(i, i + RPC_CHUNK),
    });
    for (const key of Object.keys(total)) if (key !== "records") total[key] += Number(result?.[key] || 0);
  }
  return { selected, reconciliation: total };
}

function progress(totalRecords: number, offset: number, selectedRecords: number, batchSize: number) {
  const nextOffset = offset + selectedRecords;
  return {
    offset,
    batchSize,
    totalRecords,
    selectedRecords,
    nextOffset,
    hasMore: nextOffset < totalRecords,
  };
}

async function runAU(url: string, anon: string, token: string, apply: boolean, offset: number, batchSize: number) {
  const response = await fetchT(`${url}/functions/v1/layer1-au-depth`, 120000, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, apikey: anon, "content-type": "application/json" },
    body: JSON.stringify({ apply, offset, batchSize }),
  });
  const text = await response.text();
  let out: any;
  try { out = JSON.parse(text); } catch { out = { raw: text }; }
  if (!response.ok || out?.error) throw new Error(`layer1-au-depth: ${out?.error || `HTTP ${response.status}`}`);
  return out;
}

async function runSeed(service: any, country: string, sourceRows: any[], apply: boolean, offset: number, batchSize: number, userId: string) {
  const source = sourceRows[0];
  if (!source) throw new Error(`${country}: source missing`);
  const snapshot = await rpc(service, "svc_layer1_get_seed_snapshot", { p_country_code: country });
  if (!Array.isArray(snapshot) || !snapshot.length) throw new Error(`${country}: Layer 1 seed snapshot missing`);

  const records: any[] = [];
  for (const provider of snapshot) {
    for (const course of provider.q || []) records.push({
      provider_code: provider.p,
      provider_name: provider.n,
      website: provider.w,
      city: provider.c,
      course_name: course[0],
      course_level: course[1],
      course_code: course[2],
      duration_weeks: course[3],
      field_of_study: course[4],
    });
    if (!(provider.q || []).length) records.push({ provider_code: provider.p, provider_name: provider.n, website: provider.w, city: provider.c });
  }

  const scheme = clean(snapshot[0]?.s || source.system_code || country).toLowerCase();
  const jobId = await startJob(service, country, source.source_id, {
    country_code: country,
    apply,
    offset,
    batch_size: batchSize,
    runtime: "supabase_edge",
    version: VERSION,
    mode: "seed_snapshot_bounded",
    requested_by: userId,
  });

  try {
    let reachable = false, httpStatus: number | null = null, liveError: string | null = null;
    try {
      const response = await fetchT(source.source_url || source.system_base_url, 12000);
      httpStatus = response.status;
      reachable = response.ok;
      await response.body?.cancel();
    } catch (error) { liveError = String(error).slice(0, 300); }

    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    const bytes = new TextEncoder().encode(JSON.stringify(snapshot));
    const ev = await evidence(service, source.source_id, jobId, source.source_url || source.system_base_url,
      `regulatory/${country}/seed/${stamp}.json`, bytes, "application/json",
      { country, mode: "seed_snapshot", live_reachable: reachable, http_status: httpStatus, offset, batch_size: batchSize });

    const applied = await applyRecords(service, country, source.source_id, ev.id, scheme, records, apply, offset, batchSize);
    const p = progress(records.length, offset, applied.selected.length, batchSize);
    const result = {
      country,
      mode: apply ? "apply" : "dry-run",
      adapter: "seed_snapshot_bounded",
      ...p,
      parsedRecords: records.length,
      reconciliation: applied.reconciliation,
      evidenceIds: [ev.id],
      freshness: { reachable, httpStatus, error: liveError },
      workerVersion: VERSION,
    };
    await health(service, source.source_id, reachable, liveError, { worker_version: VERSION, last_run_mode: result.mode, last_run_offset: offset, last_run_batch_size: batchSize, next_offset: p.nextOffset, has_more: p.hasMore, seed_snapshot: true });
    await finishJob(service, jobId, "completed", result);
    return { ...result, jobId };
  } catch (error) {
    const message = String(error).slice(0, 1800);
    await health(service, source.source_id, false, message, { worker_version: VERSION });
    await finishJob(service, jobId, "failed", { workerVersion: VERSION }, message);
    throw error;
  }
}

async function runGB(service: any, sourceRows: any[], apply: boolean, offset: number, batchSize: number, userId: string) {
  const live = sourceRows.find((x: any) => x.system_code === "gb_ukvi_student_sponsors");
  let liveProviderRegister: any = null;

  if (live) {
    const jobId = await startJob(service, "GB", live.source_id, {
      country_code: "GB", apply, offset, batch_size: batchSize,
      runtime: "supabase_edge", version: VERSION, mode: "live_provider_register_bounded", requested_by: userId,
    });
    try {
      const page = await fetchT(live.source_url || live.system_base_url, 20000);
      const html = await page.text();
      const csvUrl = html.match(/https:\/\/assets\.publishing\.service\.gov\.uk[^"']+?\.csv/)?.[0];
      if (!csvUrl) throw new Error("UKVI CSV asset not found");
      const csvResponse = await fetchT(csvUrl, 60000);
      if (!csvResponse.ok) throw new Error(`UKVI CSV HTTP ${csvResponse.status}`);
      const text = await csvResponse.text();
      const rows = parseCSV(text), head = rows[0] || [], hx = (name: string) => head.indexOf(name);
      const records: any[] = [];
      for (const row of rows.slice(1)) {
        if (!clean(row[hx("Sponsor Type")]).includes("Higher Education")) continue;
        if (clean(row[hx("Route")]) !== "Student") continue;
        const name = clean(row[hx("Sponsor Name")]);
        if (name) records.push({ provider_code: slug(name), provider_name: name, city: clean(row[hx("Town/City")]) || null });
      }
      const stamp = new Date().toISOString().replace(/[:.]/g, "-");
      const ev = await evidence(service, live.source_id, jobId, csvUrl, `regulatory/GB/ukvi/${stamp}.csv`, new TextEncoder().encode(text), "text/csv", { provider_rows: records.length, offset, batch_size: batchSize });
      const applied = await applyRecords(service, "GB", live.source_id, ev.id, "uk_sponsor", records, apply, offset, batchSize);
      liveProviderRegister = { adapter: "ukvi_live_bounded", ...progress(records.length, offset, applied.selected.length, batchSize), parsedRecords: records.length, reconciliation: applied.reconciliation, evidenceIds: [ev.id] };
      await health(service, live.source_id, true, null, { worker_version: VERSION, parsed_records: records.length, last_run_offset: offset, last_run_batch_size: batchSize });
      await finishJob(service, jobId, "completed", liveProviderRegister);
    } catch (error) {
      const message = String(error).slice(0, 1500);
      liveProviderRegister = { adapter: "ukvi_live_bounded", error: message };
      await health(service, live.source_id, false, message, { worker_version: VERSION });
      await finishJob(service, jobId, "failed", liveProviderRegister, message);
    }
  }

  const seedSources = sourceRows.filter((x: any) => x.system_code !== "gb_ukvi_student_sponsors");
  const seed = await runSeed(service, "GB", seedSources, apply, offset, batchSize, userId);
  return { ...seed, liveProviderRegister };
}

async function runDE(service: any, sourceRows: any[], apply: boolean, offset: number, batchSize: number, userId: string) {
  const source = sourceRows.find((x: any) => x.system_code === "de_daad_programmes") || sourceRows[0];
  if (!source) throw new Error("DE source missing");
  const jobId = await startJob(service, "DE", source.source_id, {
    country_code: "DE", apply, offset, batch_size: batchSize,
    runtime: "supabase_edge", version: VERSION, mode: "daad_live_bounded", requested_by: userId,
  });

  try {
    const apiUrl = source.system_config?.api_url || "https://www2.daad.de/deutschland/studienangebote/international-programmes/api/solr";
    const endpoint = `${apiUrl}/en/search.json?q=&sort=4&page=1`;
    const response = await fetchT(endpoint, 45000, { headers: { accept: "application/json" } });
    if (!response.ok) throw new Error(`DAAD HTTP ${response.status}`);
    const data = await response.json();
    const courses = data.courses || [];
    const records = courses.filter((c: any) => c.courseName && c.academy).map((c: any) => ({
      provider_code: slug(c.academy),
      provider_name: c.academy,
      city: c.city || null,
      course_code: String(c.id),
      course_name: c.courseName,
      course_level: mapLevel(c.courseName),
      field_of_study: c.subject || null,
    }));
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    const ev = await evidence(service, source.source_id, jobId, endpoint, `regulatory/DE/daad/${stamp}.json`, new TextEncoder().encode(JSON.stringify({ numResults: data.numResults, courses })), "application/json", { num_results: data.numResults, offset, batch_size: batchSize });
    const applied = await applyRecords(service, "DE", source.source_id, ev.id, "daad", records, apply, offset, batchSize);
    const p = progress(records.length, offset, applied.selected.length, batchSize);
    const result = {
      country: "DE",
      mode: apply ? "apply" : "dry-run",
      adapter: "daad_live_bounded",
      ...p,
      parsedRecords: records.length,
      availableRecords: data.numResults,
      reconciliation: applied.reconciliation,
      evidenceIds: [ev.id],
      workerVersion: VERSION,
    };
    await health(service, source.source_id, true, null, { worker_version: VERSION, parsed_records: records.length, available_records: data.numResults, last_run_offset: offset, last_run_batch_size: batchSize });
    await finishJob(service, jobId, "completed", result);
    return { ...result, jobId };
  } catch (error) {
    const message = String(error).slice(0, 1800);
    await health(service, source.source_id, false, message, { worker_version: VERSION });
    await finishJob(service, jobId, "failed", { workerVersion: VERSION }, message);
    throw error;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY") || serviceKey;
  const service = createClient(url, serviceKey, { auth: { persistSession: false } });

  try {
    const { user, token } = await authAdmin(req, service, url, anon);
    const body = await req.json().catch(() => ({}));
    const requested = String(body.country || "AU").toUpperCase();
    if (requested !== "ALL" && !SUPPORTED.includes(requested)) throw new Error(`No Layer 1 adapter for ${requested}`);

    const apply = Boolean(body.apply);
    const offset = Math.max(0, Number(body.offset ?? 0));
    const requestedBatch = Number(body.batchSize ?? body.maxRecords ?? DEFAULT_BATCH);
    const batchSize = Math.max(1, Math.min(requestedBatch, MAX_BATCH));
    const countries = requested === "ALL" ? SUPPORTED : [requested];
    const results: any[] = [], failures: any[] = [];

    for (const country of countries) {
      try {
        let result: any;
        if (country === "AU") result = await runAU(url, anon, token, apply, offset, batchSize);
        else {
          const sourceRows = await sources(service, country);
          if (country === "GB") result = await runGB(service, sourceRows, apply, offset, batchSize, user.id);
          else if (country === "DE") result = await runDE(service, sourceRows, apply, offset, batchSize, user.id);
          else result = await runSeed(service, country, sourceRows, apply, offset, batchSize, user.id);
        }
        results.push(result);
      } catch (error) {
        failures.push({ country, error: String(error).slice(0, 1200) });
      }
    }

    let catalogueStats = null;
    if (apply && results.length) catalogueStats = await rpc(service, "svc_layer1_finalize_catalogue");
    const depthStats = await rpc(service, "svc_layer1_depth_stats");
    const seedStatus = await rpc(service, "svc_layer1_seed_status");
    const single = results.length === 1 ? results[0] : null;

    return json({
      ok: failures.length === 0,
      status: failures.length ? "completed_with_errors" : "completed",
      mode: apply ? "apply" : "dry-run",
      requestedCountry: requested,
      offset,
      batchSize,
      nextOffset: single?.nextOffset ?? null,
      hasMore: single?.hasMore ?? null,
      totalRecords: single?.totalRecords ?? single?.parsedRecords ?? null,
      countries: results,
      failures,
      catalogueStats: {
        ...(catalogueStats || {}),
        campuses: depthStats?.campuses || 0,
        course_campus_links: depthStats?.course_campus_links || 0,
      },
      depthStats,
      seedStatus,
      workerVersion: VERSION,
      runtime: "supabase_edge",
    }, failures.length && results.length === 0 ? 500 : 200);
  } catch (error) {
    return json({ error: String(error), workerVersion: VERSION }, 500);
  }
});
