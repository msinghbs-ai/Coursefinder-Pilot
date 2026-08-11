import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "layer1-edge-v0.2.0";
const CHUNK = 250;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const service = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!token) return json({ error: "authentication required" }, 401);
  const { data: userData, error: userError } = await service.auth.getUser(token);
  if (userError || !userData.user?.id) return json({ error: "invalid session" }, 401);
  const { data: allowed, error: allowError } = await service.rpc("svc_layer1_authorize_platform_admin", { p_user_id: userData.user.id });
  if (allowError || allowed !== true) return json({ error: "platform_admin required" }, 403);

  let body: any = {};
  try { body = await req.json(); } catch {}
  const country = String(body.country || "AU").toUpperCase();
  const apply = body.apply === true;
  const maxRecords = Math.max(0, Math.min(50000, Math.trunc(Number(body.maxRecords || 0))));
  if (country !== "AU") return json({ error: `No Edge adapter implemented yet for ${country}` }, 400);

  const { data: sources, error: sourceError } = await service.rpc("svc_layer1_resolve_sources", { p_country_code: country });
  if (sourceError) return json({ error: sourceError.message }, 500);
  if (!Array.isArray(sources) || !sources.length) return json({ error: `No active Layer 1 source configured for ${country}` }, 400);
  const source = sources[0];

  const { data: jobId, error: jobError } = await service.rpc("svc_layer1_start_job", {
    p_country_code: country,
    p_source_id: source.source_id,
    p_payload: { version: VERSION, apply, max_records: maxRecords || null, source_system: source.system_code, requested_by: userData.user.id, runtime: "supabase_edge" },
  });
  if (jobError) return json({ error: jobError.message }, 500);

  try {
    const discoveryUrl = source?.source_metadata?.discovery_url;
    if (!discoveryUrl) throw new Error("CRICOS discovery_url is not configured");
    const metaResp = await fetch(discoveryUrl, { headers: { "user-agent": "Coursefinder-Layer1-Edge/0.2" } });
    if (!metaResp.ok) throw new Error(`CRICOS metadata HTTP ${metaResp.status}`);
    const meta = await metaResp.json();
    if (!meta?.success || !meta?.result) throw new Error("CRICOS package metadata invalid");
    const resources = meta.result.resources || [];
    const inst = findCsv(resources, "institutions");
    const courses = findCsv(resources, "courses");
    if (!inst || !courses) throw new Error("Required CRICOS Institutions/Courses CSV resources not found");

    const [instSnap, courseSnap] = await Promise.all([
      fetchEvidence(service, source, jobId, inst, "institutions"),
      fetchEvidence(service, source, jobId, courses, "courses"),
    ]);

    const records = extractRecords(instSnap.text, courseSnap.text);
    const selected = maxRecords > 0 ? records.slice(0, maxRecords) : records;
    const reconciliation = apply ? await applyBatches(service, source.source_id, courseSnap.evidenceId, selected) : summary(selected.length);
    const catalogueStats = apply ? await rpc(service, "svc_layer1_finalize_catalogue", {}) : null;
    const sourceHealth = { institution_hash: instSnap.hash, course_hash: courseSnap.hash, parsed_records: records.length, resource_updated: courseSnap.updated };

    await rpc(service, "svc_layer1_source_health", { p_source_id: source.source_id, p_success: true, p_metadata: { worker_version: VERSION, latest_job_id: jobId, runtime: "supabase_edge", ...sourceHealth } });
    const result = { adapter: "au_cricos", runtime: "supabase_edge", workerVersion: VERSION, mode: apply ? "apply" : "dry-run", resources: [instSnap.resourceSummary, courseSnap.resourceSummary], evidenceIds: [instSnap.evidenceId, courseSnap.evidenceId], parsedRecords: records.length, selectedRecords: selected.length, reconciliation, catalogueStats, sourceHealth };
    await rpc(service, "svc_layer1_finish_job", { p_job_id: jobId, p_status: "completed", p_result: result, p_error: null });
    return json({ ok: true, country, jobId, ...result });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    await safeRpc(service, "svc_layer1_source_health", { p_source_id: source.source_id, p_success: false, p_error: message, p_metadata: { worker_version: VERSION, latest_job_id: jobId, runtime: "supabase_edge" } });
    await safeRpc(service, "svc_layer1_finish_job", { p_job_id: jobId, p_status: "failed", p_result: { worker_version: VERSION, runtime: "supabase_edge" }, p_error: message });
    return json({ error: message, country, jobId, version: VERSION }, 500);
  }
});

async function rpc(client: any, name: string, args: any) { const { data, error } = await client.rpc(name, args); if (error) throw new Error(`${name}: ${error.message}`); return data; }
async function safeRpc(client: any, name: string, args: any) { try { return await rpc(client, name, args); } catch { return null; } }

async function fetchEvidence(client: any, source: any, jobId: string, resource: any, kind: string) {
  const response = await fetch(resource.url, { headers: { "user-agent": "Coursefinder-Layer1-Edge/0.2" } });
  if (!response.ok) throw new Error(`CRICOS ${kind} download HTTP ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  const text = new TextDecoder("utf-8").decode(bytes);
  const hash = await sha256Hex(bytes);
  const updated = resource.last_modified || resource.created || new Date().toISOString();
  const path = `regulatory/AU/cricos/${String(updated).slice(0,10)}/${kind}-${hash}.csv`;
  const { error } = await client.storage.from("evidence").upload(path, bytes, { contentType: "text/csv", upsert: true, cacheControl: "3600" });
  if (error) throw new Error(`Evidence upload failed: ${error.message}`);
  const evidenceId = await rpc(client, "svc_layer1_record_evidence", { p_source_id: source.source_id, p_job_id: jobId, p_source_url: resource.url, p_storage_path: path, p_content_hash: hash, p_mime_type: "text/csv", p_metadata: { dataset: "CRICOS", resource_kind: kind, resource_id: resource.id, resource_name: resource.name, resource_updated: updated, byte_size: bytes.byteLength, runtime: "supabase_edge" } });
  return { text, hash, updated, evidenceId, resourceSummary: { id: resource.id, name: resource.name, url: resource.url, updated } };
}

function findCsv(resources: any[], token: string) { return resources.filter(r => String(r.format || "").toUpperCase() === "CSV" && r.url && String(r.name || "").toLowerCase().includes(token)).sort((a,b) => resourceTime(b) - resourceTime(a))[0] || null; }
function resourceTime(r: any) { const n = Date.parse(r.last_modified || r.created || r.metadata_modified || ""); return Number.isFinite(n) ? n : 0; }

function parseCsv(text: string) {
  const rows: string[][] = []; let row: string[] = [], field = "", quoted = false;
  for (let i=0;i<text.length;i++) { const ch=text[i]; if (quoted) { if (ch==='"' && text[i+1]==='"') { field+='"'; i++; } else if (ch==='"') quoted=false; else field+=ch; } else { if (ch==='"') quoted=true; else if (ch===',') { row.push(field); field=''; } else if (ch==='\n') { row.push(field.replace(/\r$/, '')); rows.push(row); row=[]; field=''; } else field+=ch; } }
  if (field.length || row.length) { row.push(field.replace(/\r$/, '')); rows.push(row); }
  if (rows.length < 2) return [];
  const headers = rows[0].map(v => v.replace(/^\uFEFF/, '').trim());
  return rows.slice(1).filter(r => r.some(v => v.trim())).map(values => Object.fromEntries(headers.map((h,i)=>[h, values[i] ?? ''])));
}
function normaliseRow(row: any) { return Object.fromEntries(Object.entries(row).map(([k,v]) => [String(k).toLowerCase().replace(/[_-]+/g,' ').replace(/\s+/g,' ').trim(), String(v ?? '').trim()])); }
function pick(row: any, aliases: string[]) { for (const a of aliases) { const k=a.toLowerCase().replace(/[_-]+/g,' ').replace(/\s+/g,' ').trim(); if (row[k]) return row[k]; } return ''; }
function cleanCode(v: any) { return String(v || '').trim().toUpperCase(); }
function numericText(v: any) { const m=String(v || '').replace(/,/g,'').match(/\d+(?:\.\d+)?/); return m ? m[0] : ''; }

function extractRecords(institutionText: string, courseText: string) {
  const providers = new Map<string,string>();
  for (const raw of parseCsv(institutionText)) { const row=normaliseRow(raw); const code=pick(row,['provider code','cricos provider code','institution code']); const name=pick(row,['provider name','institution name','institution trading name']); if (code && name) providers.set(cleanCode(code), name.trim()); }
  const out: any[] = [], seen = new Set<string>();
  for (const raw of parseCsv(courseText)) { const row=normaliseRow(raw); const courseCode=pick(row,['course code','cricos course code']); const courseName=pick(row,['course name','course title']); const providerCodeRaw=pick(row,['provider code','cricos provider code','institution code']); if (!courseCode || !courseName || !providerCodeRaw) continue; const courseKey=cleanCode(courseCode), providerCode=cleanCode(providerCodeRaw); if (seen.has(courseKey)) continue; const providerName=pick(row,['provider name','institution name','institution trading name']) || providers.get(providerCode); if (!providerName) continue; seen.add(courseKey); out.push({ provider_code: providerCode, provider_name: String(providerName).trim(), course_code: courseKey, course_name: courseName.trim(), course_level: pick(row,['course level','qualification type','course type']) || null, duration_weeks: numericText(pick(row,['duration weeks','duration (weeks)','course duration weeks','duration'])) || null }); }
  if (!out.length) throw new Error('CRICOS CSV parsing produced zero course records');
  return out;
}

async function applyBatches(client: any, sourceId: string, evidenceId: string, records: any[]) {
  const total = summary(0);
  for (let i=0;i<records.length;i+=CHUNK) { const r=await rpc(client,'svc_layer1_apply_cricos_records',{ p_source_id: sourceId, p_evidence_id: evidenceId, p_records: records.slice(i,i+CHUNK) }); for (const k of Object.keys(total)) total[k] += Number(r?.[k] || 0); }
  return total;
}
function summary(records: number) { return { provider_created:0, provider_linked:0, course_created:0, course_linked:0, conflicts:0, records }; }
async function sha256Hex(bytes: Uint8Array) { const digest=await crypto.subtle.digest('SHA-256', bytes); return [...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join(''); }
