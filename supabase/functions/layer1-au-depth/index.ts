import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { unzipSync } from "npm:fflate@0.8.2";

const VERSION = "layer1-au-depth-v1.1.0";
const PKG = "https://data.gov.au/data/api/3/action/package_show?id=cricos";
const RES = "https://data.gov.au/data/api/3/action/resource_show?id=";
const RPC_CHUNK = 250;
const DEFAULT_BATCH = 2500;
const MAX_BATCH = 5000;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "content-type": "application/json", "cache-control": "no-store" },
});
const clean = (v: unknown) => String(v ?? "").trim();
const nk = (v: unknown) => String(v ?? "").replace(/^\uFEFF/, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();

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
    else if (c === ',') { row.push(field); field = ""; }
    else if (c === '\n') { row.push(field); rows.push(row); row = []; field = ""; }
    else if (c !== '\r') field += c;
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  return rows;
}

function objs(text: string) {
  const rows = parse(text);
  if (!rows.length) return [];
  const header = rows[0].map(nk);
  return rows.slice(1)
    .filter(r => r.some(clean))
    .map(r => Object.fromEntries(header.map((h, i) => [h, clean(r[i])])));
}

function val(row: Record<string, string>, names: string[]) {
  for (const name of names) {
    const value = row[nk(name)];
    if (clean(value)) return clean(value);
  }
  return "";
}

function level(raw: string) {
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

async function rpc(client: any, name: string, args: Record<string, unknown> = {}) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

async function fetchT(url: string, ms = 90000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    return await fetch(url, {
      signal: controller.signal,
      redirect: "follow",
      headers: { "user-agent": "coursefinder-pilot-au-depth/1.1" },
    });
  } finally { clearTimeout(timer); }
}

async function sha(bytes: Uint8Array) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map(x => x.toString(16).padStart(2, "0")).join("");
}

async function auth(req: Request, service: any, url: string, anon: string) {
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
  return result.data.user;
}

async function evidence(service: any, sourceId: string, jobId: string, sourceUrl: string, path: string, bytes: Uint8Array, mime: string, metadata: unknown) {
  const hash = await sha(bytes);
  const upload = await service.storage.from("evidence").upload(path, bytes, { contentType: mime, upsert: true });
  if (upload.error) throw new Error(upload.error.message);
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

async function applyCore(service: any, sourceId: string, evidenceId: string, rows: any[], apply: boolean) {
  const total: any = {
    records: rows.length,
    provider_created: 0,
    provider_linked: 0,
    provider_existing: 0,
    course_created: 0,
    course_linked: 0,
    course_existing: 0,
    conflicts: 0,
  };
  if (!apply) return total;
  for (let i = 0; i < rows.length; i += RPC_CHUNK) {
    const result = await rpc(service, "svc_layer1_apply_register_records", {
      p_country_code: "AU",
      p_source_id: sourceId,
      p_evidence_id: evidenceId,
      p_registration_scheme: "cricos",
      p_records: rows.slice(i, i + RPC_CHUNK),
    });
    for (const key of Object.keys(total)) if (key !== "records") total[key] += Number(result?.[key] || 0);
  }
  return total;
}

async function applyDepth(service: any, sourceId: string, evidenceId: string, rows: any[], apply: boolean) {
  const total: any = {
    location_records: 0,
    course_location_records: 0,
    campuses_created: 0,
    campuses_existing: 0,
    course_links_created: 0,
    course_links_existing: 0,
    provider_missing: 0,
    course_missing: 0,
    campus_missing: 0,
    conflicts: 0,
  };
  if (!apply) {
    for (const row of rows) row.course_code ? total.course_location_records++ : total.location_records++;
    return total;
  }
  for (let i = 0; i < rows.length; i += RPC_CHUNK) {
    const result = await rpc(service, "svc_layer1_apply_location_records", {
      p_country_code: "AU",
      p_source_id: sourceId,
      p_evidence_id: evidenceId,
      p_registration_scheme: "cricos",
      p_records: rows.slice(i, i + RPC_CHUNK),
    });
    for (const key of Object.keys(total)) total[key] += Number(result?.[key] || 0);
  }
  return total;
}

function archiveFile(zip: Record<string, Uint8Array>, kind: "i" | "c" | "l" | "cl") {
  const entry = Object.entries(zip).find(([name]) => {
    const normalized = name.toLowerCase().replace(/[_-]+/g, " ");
    if (kind === "i") return /institutions.*\.csv$/.test(normalized);
    if (kind === "c") return /courses.*\.csv$/.test(normalized) && !/course locations/.test(normalized);
    if (kind === "l") return /locations.*\.csv$/.test(normalized) && !/course locations/.test(normalized);
    return /course locations.*\.csv$/.test(normalized);
  });
  if (!entry) throw new Error(`archive missing ${kind}: ${Object.keys(zip).join(",")}`);
  return { name: entry[0], bytes: entry[1], text: new TextDecoder().decode(entry[1]) };
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || serviceKey;
  const service = createClient(url, serviceKey, { auth: { persistSession: false } });

  let jobId: string | null = null;
  let source: any = null;

  try {
    const user = await auth(req, service, url, anon);
    const body = await req.json().catch(() => ({}));
    const apply = body.apply === true;
    const offset = Math.max(0, Number(body.offset ?? 0));
    const requestedBatch = Number(body.batchSize ?? body.maxRecords ?? DEFAULT_BATCH);
    const batchSize = Math.max(1, Math.min(requestedBatch, MAX_BATCH));

    const sourceRows = await rpc(service, "svc_layer1_resolve_sources", { p_country_code: "AU" });
    source = (sourceRows || []).find((x: any) => x.system_code === "au_cricos") || (sourceRows || [])[0];
    if (!source) throw new Error("AU source missing");

    jobId = await rpc(service, "svc_layer1_start_job", {
      p_country_code: "AU",
      p_source_id: source.source_id,
      p_payload: {
        country_code: "AU",
        apply,
        offset,
        batch_size: batchSize,
        runtime: "supabase_edge",
        version: VERSION,
        mode: "live_zip_depth_bounded",
        requested_by: user.id,
      },
    });

    const packageResponse = await fetchT(source.source_metadata?.discovery_url || PKG, 30000);
    const packageData = await packageResponse.json();
    const zipResource = (packageData?.result?.resources || []).find((x: any) =>
      String(x.format || "").toUpperCase() === "ZIP" && /Providers,? Courses,? (and )?Locations/i.test(String(x.name || ""))
    ) || (packageData?.result?.resources || []).find((x: any) =>
      String(x.format || "").toUpperCase() === "ZIP" && /CRICOS/i.test(String(x.name || ""))
    );
    if (!zipResource) throw new Error("consolidated CRICOS ZIP not found");

    const resourceResponse = await fetchT(RES + zipResource.id, 30000);
    const meta = (await resourceResponse.json())?.result;
    if (!meta?.url) throw new Error("ZIP URL missing");

    const zipResponse = await fetchT(meta.url, 90000);
    if (!zipResponse.ok) throw new Error(`ZIP HTTP ${zipResponse.status}`);
    const zipBytes = new Uint8Array(await zipResponse.arrayBuffer());
    const zip = unzipSync(zipBytes);
    const institutions = archiveFile(zip, "i");
    const courses = archiveFile(zip, "c");
    const locations = archiveFile(zip, "l");
    const courseLocations = archiveFile(zip, "cl");

    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    const zipEvidence = await evidence(service, source.source_id, jobId, meta.url,
      `regulatory/AU/cricos/${stamp}-providers-courses-locations.zip`, zipBytes, "application/zip",
      { resource_id: meta.id, resource_name: meta.name, last_modified: meta.last_modified, byte_size: zipBytes.length, offset, batch_size: batchSize });
    const institutionEvidence = await evidence(service, source.source_id, jobId, meta.url,
      `regulatory/AU/cricos/${stamp}-institutions.csv`, institutions.bytes, "text/csv",
      { parent_zip_evidence_id: zipEvidence.id, archive_name: institutions.name });
    const courseEvidence = await evidence(service, source.source_id, jobId, meta.url,
      `regulatory/AU/cricos/${stamp}-courses.csv`, courses.bytes, "text/csv",
      { parent_zip_evidence_id: zipEvidence.id, archive_name: courses.name });
    const locationEvidence = await evidence(service, source.source_id, jobId, meta.url,
      `regulatory/AU/cricos/${stamp}-locations.csv`, locations.bytes, "text/csv",
      { parent_zip_evidence_id: zipEvidence.id, archive_name: locations.name });
    const courseLocationEvidence = await evidence(service, source.source_id, jobId, meta.url,
      `regulatory/AU/cricos/${stamp}-course-locations.csv`, courseLocations.bytes, "text/csv",
      { parent_zip_evidence_id: zipEvidence.id, archive_name: courseLocations.name });

    const providerMap = new Map<string, any>();
    for (const row of objs(institutions.text)) {
      const providerCode = val(row, ["CRICOS Provider Code"]);
      const providerName = val(row, ["Trading Name", "Institution Name"]);
      if (!providerCode || !providerName) continue;
      let website = val(row, ["Website"]);
      if (website && !/^https?:\/\//i.test(website)) website = "https://" + website;
      providerMap.set(providerCode, {
        name: providerName,
        website: website || null,
        city: val(row, ["Postal Address City"]) || null,
      });
    }

    const allCourses: any[] = [];
    for (const row of objs(courses.text)) {
      const expired = val(row, ["Expired"]);
      if (expired && !/^(no|false|n|0)$/i.test(expired)) continue;
      const providerCode = val(row, ["CRICOS Provider Code"]);
      const provider = providerMap.get(providerCode);
      const courseCode = val(row, ["CRICOS Course Code"]);
      const title = val(row, ["Course Name"]);
      if (!provider || !courseCode || !title) continue;
      allCourses.push({
        provider_code: providerCode,
        provider_name: provider.name,
        website: provider.website,
        city: provider.city,
        course_code: courseCode,
        course_name: title,
        course_level: level(val(row, ["Course Level"])),
        duration_weeks: val(row, ["Duration (Weeks)"]),
        field_of_study: val(row, ["Field of Education 1 Narrow Field"]).replace(/^[0-9]+ - /, ""),
      });
    }

    const selectedCourses = allCourses.slice(offset, offset + batchSize);
    const selectedCourseCodes = new Set(selectedCourses.map(x => x.course_code));
    const selectedProviderCodes = new Set(selectedCourses.map(x => x.provider_code));
    const courseProviderMap = new Map(allCourses.map(x => [x.course_code, x.provider_code]));

    const selectedLocations: any[] = [];
    for (const row of objs(locations.text)) {
      const providerCode = val(row, ["CRICOS Provider Code"]);
      const name = val(row, ["Location Name"]);
      if (!providerCode || !name || !selectedProviderCodes.has(providerCode)) continue;
      selectedLocations.push({
        provider_code: providerCode,
        location_code: name,
        location_name: name,
        address_line1: val(row, ["Address Line 1"]),
        address_line2: [val(row, ["Address Line 2"]), val(row, ["Address Line 3"]), val(row, ["Address Line 4"])].filter(Boolean).join(", "),
        city: val(row, ["City"]),
        state: val(row, ["State"]),
        postcode: val(row, ["Postcode"]),
      });
    }

    const selectedCourseLocations: any[] = [];
    const seenCourseLocations = new Set<string>();
    for (const row of objs(courseLocations.text)) {
      const courseCode = val(row, ["CRICOS Course Code"]);
      if (!courseCode || !selectedCourseCodes.has(courseCode)) continue;
      const providerCode = val(row, ["CRICOS Provider Code"]) || courseProviderMap.get(courseCode) || "";
      const locationName = val(row, ["Location Name"]);
      if (!providerCode || !locationName) continue;
      const key = `${providerCode}|${courseCode}|${locationName}`;
      if (seenCourseLocations.has(key)) continue;
      seenCourseLocations.add(key);
      selectedCourseLocations.push({
        provider_code: providerCode,
        course_code: courseCode,
        location_code: locationName,
        delivery_mode: "on_campus",
      });
    }

    const coreResult = await applyCore(service, source.source_id, courseEvidence.id, selectedCourses, apply);
    const locationResult = await applyDepth(service, source.source_id, locationEvidence.id, selectedLocations, apply);
    const courseLocationResult = await applyDepth(service, source.source_id, courseLocationEvidence.id, selectedCourseLocations, apply);

    let catalogueStats = null;
    let depthStats = null;
    if (apply) {
      catalogueStats = await rpc(service, "svc_layer1_finalize_catalogue");
      depthStats = await rpc(service, "svc_layer1_depth_stats");
    }

    const depthReconciliation = {
      location_records: locationResult.location_records,
      course_location_records: courseLocationResult.course_location_records,
      campuses_created: locationResult.campuses_created,
      campuses_existing: locationResult.campuses_existing,
      course_links_created: courseLocationResult.course_links_created,
      course_links_existing: courseLocationResult.course_links_existing,
      provider_missing: Number(locationResult.provider_missing || 0) + Number(courseLocationResult.provider_missing || 0),
      course_missing: courseLocationResult.course_missing,
      campus_missing: courseLocationResult.campus_missing,
      conflicts: Number(locationResult.conflicts || 0) + Number(courseLocationResult.conflicts || 0),
    };

    const nextOffset = offset + selectedCourses.length;
    const hasMore = nextOffset < allCourses.length;
    const result = {
      country: "AU",
      mode: apply ? "apply" : "dry-run",
      adapter: "cricos_consolidated_zip_depth_bounded",
      workerVersion: VERSION,
      offset,
      batchSize,
      totalRecords: allCourses.length,
      parsedRecords: allCourses.length,
      selectedRecords: selectedCourses.length,
      nextOffset,
      hasMore,
      parsedLocations: objs(locations.text).length,
      selectedLocations: selectedLocations.length,
      parsedCourseLocations: objs(courseLocations.text).length,
      selectedCourseLocations: selectedCourseLocations.length,
      reconciliation: coreResult,
      depthReconciliation,
      catalogueStats,
      depthStats,
      evidenceIds: [zipEvidence.id, institutionEvidence.id, courseEvidence.id, locationEvidence.id, courseLocationEvidence.id],
      resource: { id: meta.id, name: meta.name, last_modified: meta.last_modified, archiveFiles: Object.keys(zip) },
    };

    await rpc(service, "svc_layer1_source_health", {
      p_source_id: source.source_id,
      p_success: true,
      p_error: null,
      p_metadata: {
        worker_version: VERSION,
        parsed_records: allCourses.length,
        parsed_locations: result.parsedLocations,
        parsed_course_locations: result.parsedCourseLocations,
        zip_hash: zipEvidence.hash,
        last_run_mode: result.mode,
        last_run_offset: offset,
        last_run_batch_size: batchSize,
        last_run_records: result.selectedRecords,
        next_offset: nextOffset,
        has_more: hasMore,
      },
    });
    await rpc(service, "svc_layer1_finish_job", { p_job_id: jobId, p_status: "completed", p_result: result, p_error: null });
    return json({ ok: true, jobId, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (jobId) try { await rpc(service, "svc_layer1_finish_job", { p_job_id: jobId, p_status: "failed", p_result: { workerVersion: VERSION }, p_error: message }); } catch {}
    if (source) try { await rpc(service, "svc_layer1_source_health", { p_source_id: source.source_id, p_success: false, p_error: message, p_metadata: { worker_version: VERSION } }); } catch {}
    return json({ error: message, jobId, workerVersion: VERSION }, 500);
  }
});
