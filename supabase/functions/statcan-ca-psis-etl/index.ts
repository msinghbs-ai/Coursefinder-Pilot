import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "statcan-ca-psis-etl-v0.3.1";
const PID = 37100278;
const TABLE = "37-10-0278-01";
const WDS = "https://www150.statcan.gc.ca/t1/wds/rest";
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
  if (!await rpc(service, "svc_layer1_authorize_platform_admin", { p_user_id: user.id })) {
    throw new Error("platform_admin required");
  }
  return user;
}

async function fetchJson(url: string, init: RequestInit = {}, ms = 45000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    const response = await fetch(url, {
      ...init,
      signal: controller.signal,
      redirect: "follow",
      headers: {
        accept: "application/json",
        "user-agent": "coursefinder-pilot/statcan-ca-psis-0.3.1",
        ...(init.headers || {}),
      },
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}: ${url}`);
    return await response.json();
  } finally {
    clearTimeout(timer);
  }
}

async function sha256(bytes: Uint8Array) {
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map(x => x.toString(16).padStart(2, "0")).join("");
}

function metadataObject(raw: any) {
  return Array.isArray(raw) ? raw?.[0]?.object : raw?.object;
}

function isAggregateName(name: string) {
  return /^(Canada|Newfoundland and Labrador|Prince Edward Island|Nova Scotia|New Brunswick|Quebec|Ontario|Manitoba|Saskatchewan|Alberta|British Columbia|Yukon|Northwest Territories|Nunavut)$/i.test(clean(name));
}

function activeMembers(dimension: any) {
  return (dimension?.member || []).filter((m: any) => m.terminated === 0 || m.terminated === undefined || m.terminated === null);
}

function buildDiagnostics(meta: any) {
  const dims = Array.isArray(meta?.dimension) ? meta.dimension : [];
  const dimensions = dims.map((d: any) => ({
    position: Number(d.dimensionPositionId),
    name: d.dimensionNameEn,
    memberCount: Array.isArray(d.member) ? d.member.length : 0,
    members: (d.member || []).slice(0, 20).map((m: any) => ({
      memberId: m.memberId,
      name: m.memberNameEn,
      parentMemberId: m.parentMemberId,
      classificationCode: m.classificationCode ?? null,
      geoLevel: m.geoLevel ?? null,
      terminated: m.terminated ?? null,
    })),
  }));
  const geo = dims.find((d: any) => /geography|institution/i.test(d.dimensionNameEn || ""));
  const institutionCandidates = activeMembers(geo)
    .filter((m: any) => {
      const name = clean(m.memberNameEn);
      return name && !isAggregateName(name);
    })
    .slice(0, 500)
    .map((m: any) => ({
      source_entity_key: `statcan:${PID}:dim${geo.dimensionPositionId}:member:${m.memberId}`,
      source_entity_name: m.memberNameEn,
      member_id: m.memberId,
      parent_member_id: m.parentMemberId ?? null,
      classification_code: m.classificationCode ?? null,
      geo_level: m.geoLevel ?? null,
      match_status: "unmatched",
      identity_write_allowed: false,
      mapping_target: "existing canonical CA Provider with verified IRCC DLI",
    }));
  return {
    headers: dimensions.map((d: any) => d.name),
    dimensions,
    institutions: institutionCandidates,
    institutionCountInSample: institutionCandidates.length,
    sampledRows: 0,
    parseErrors: [],
  };
}

function fixedCoordinate(values: number[]) {
  const slots = values.slice(0, 10);
  while (slots.length < 10) slots.push(0);
  return slots.join(".");
}

function sampleCoordinates(meta: any, limit = 5) {
  const dims = Array.isArray(meta?.dimension) ? meta.dimension : [];
  if (!dims.length) return [];

  const base = dims.map((d: any) => Number(activeMembers(d)?.[0]?.memberId ?? 0));
  const geoIndex = dims.findIndex((d: any) => /geography|institution/i.test(d.dimensionNameEn || ""));
  if (geoIndex < 0) return [fixedCoordinate(base)];

  const institutionMembers = activeMembers(dims[geoIndex])
    .filter((m: any) => {
      const name = clean(m.memberNameEn);
      return name && !isAggregateName(name);
    })
    .slice(0, limit);

  const coordinates = institutionMembers.map((member: any) => {
    const values = [...base];
    values[geoIndex] = Number(member.memberId);
    return fixedCoordinate(values);
  });

  return [...new Set(coordinates)].filter(Boolean);
}

function normaliseSeriesSamples(raw: any) {
  return (Array.isArray(raw) ? raw : []).map((x: any) => ({
    status: x?.status ?? null,
    coordinate: x?.object?.coordinate ?? null,
    vectorId: x?.object?.vectorId ?? null,
    responseStatusCode: x?.object?.responseStatusCode ?? null,
    latest: Array.isArray(x?.object?.vectorDataPoint) ? x.object.vectorDataPoint[0] ?? null : null,
  }));
}

function seriesProbePassed(samples: any[]) {
  return samples.some((sample: any) =>
    String(sample?.status || "").toUpperCase() === "SUCCESS" &&
    Number(sample?.responseStatusCode) === 0 &&
    Number.isFinite(Number(sample?.vectorId)) &&
    sample?.latest !== null && sample?.latest !== undefined
  );
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
    if (Boolean(body.apply)) {
      return json({
        error: "PSIS canonical outcomes APPLY remains disabled until mapping/crosswalk UAT passes",
        workerVersion: VERSION,
      }, 409);
    }

    const sources = await rpc(service, "svc_layer2a_resolve_sources", { p_country_code: "CA" }) || [];
    const source = sources.find((x: any) => x.system_code === "statcan_wds");
    if (!source) throw new Error("Statistics Canada PSIS source configuration missing");

    const jobId = await rpc(service, "svc_layer2a_start_job", {
      p_country_code: "CA",
      p_source_id: source.source_id,
      p_payload: {
        country: "CA",
        layer: "2A",
        pid: PID,
        table: TABLE,
        apply: false,
        mode: "bounded_metadata_series_uat",
        requested_by: user.id,
        version: VERSION,
      },
    });

    try {
      const metadataRaw = await fetchJson(`${WDS}/getCubeMetadata`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify([{ productId: PID }]),
      });
      const meta = metadataObject(metadataRaw);
      if (!meta || Number(meta.productId) !== PID) throw new Error("StatsCan metadata response missing expected product");

      const metadataBytes = new TextEncoder().encode(JSON.stringify(metadataRaw));
      const metadataHash = await sha256(metadataBytes);
      const stamp = new Date().toISOString().replace(/[:.]/g, "-");
      const path = `layer2a/CA/statcan/psis/${PID}/${stamp}-metadata.json`;
      const upload = await service.storage.from("evidence").upload(path, metadataBytes, {
        contentType: "application/json",
        upsert: true,
      });
      if (upload.error) throw new Error(`evidence upload: ${upload.error.message}`);

      const evidenceId = await rpc(service, "svc_layer2a_record_evidence", {
        p_source_id: source.source_id,
        p_job_id: jobId,
        p_source_url: `${WDS}/getCubeMetadata`,
        p_storage_path: path,
        p_content_hash: metadataHash,
        p_mime_type: "application/json",
        p_metadata: {
          pid: PID,
          table: TABLE,
          worker_version: VERSION,
          evidence_role: "bounded_metadata_uat",
        },
      });

      const diagnostics = buildDiagnostics(meta);
      const coordinates = sampleCoordinates(meta, 5);
      let seriesSamples: any[] = [];
      let seriesProbeError: string | null = null;

      if (coordinates.length) {
        const requestBody = coordinates.map(coordinate => ({ productId: PID, coordinate, latestN: 1 }));
        try {
          const seriesRaw = await fetchJson(`${WDS}/getDataFromCubePidCoordAndLatestNPeriods`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(requestBody),
          }, 30000);
          seriesSamples = normaliseSeriesSamples(seriesRaw);
        } catch (error) {
          seriesProbeError = String(error);
          seriesSamples = [{ status: "sample_unavailable", error: seriesProbeError }];
        }
      } else {
        seriesProbeError = "no valid source coordinates generated";
      }

      const dimensionNames = diagnostics.dimensions.map((d: any) => String(d.name || "").toLowerCase());
      const requiredDimensions = ["institution", "field", "credential", "status"].map(token => ({
        token,
        present: dimensionNames.some((name: string) => name.includes(token)),
      }));
      const missingRequiredDimensions = requiredDimensions.filter(x => !x.present).map(x => x.token);
      const metadataPass = diagnostics.dimensions.length > 0 && missingRequiredDimensions.length === 0;
      const seriesPass = seriesProbePassed(seriesSamples);
      const ok = metadataPass && seriesPass;
      const status = ok ? "parser-dry-run-pass" : metadataPass ? "series-probe-blocked" : "parser-schema-blocked";
      const gateError = !metadataPass
        ? `missing required dimensions: ${missingRequiredDimensions.join(", ")}`
        : !seriesPass
          ? `StatsCan bounded data-series probe did not return a successful vector${seriesProbeError ? `: ${seriesProbeError}` : ""}`
          : null;

      const result = {
        ok,
        status,
        country: "CA",
        layer: "2A",
        source: "Statistics Canada PSIS",
        pid: PID,
        table: TABLE,
        metadataSummary: {
          cubeTitleEn: meta.cubeTitleEn,
          cubeStartDate: meta.cubeStartDate,
          cubeEndDate: meta.cubeEndDate,
          nbSeriesCube: meta.nbSeriesCube,
          nbDatapointsCube: meta.nbDatapointsCube,
          releaseTime: meta.releaseTime,
          issueDate: meta.issueDate,
        },
        diagnostics,
        coordinatesProbed: coordinates,
        seriesSamples,
        metadataPass,
        seriesProbePass: seriesPass,
        evidenceId,
        evidenceHash: metadataHash,
        missingRequiredDimensions,
        providerMappingRequired: true,
        canonicalIdentityWrite: false,
        applyEnabled: false,
        identityBoundary: {
          provider: "IRCC DLI only",
          course: "DLI + namespaced stable local programme key; title excluded",
          provincialRegistration: "optional validation metadata",
        },
        nextGate: ok
          ? "persist candidate source-provider mappings; verify source institutions to existing IRCC-DLI Providers; establish CIP/study-level/audience transforms"
          : "repair bounded StatsCan series probe before source-provider mapping UAT",
        workerVersion: VERSION,
      };

      await rpc(service, "svc_layer2a_source_health", {
        p_source_id: source.source_id,
        p_success: ok,
        p_error: gateError,
        p_metadata: {
          worker_version: VERSION,
          pid: PID,
          parser_dry_run_pass: ok,
          metadata_pass: metadataPass,
          series_probe_pass: seriesPass,
          metadata_hash: metadataHash,
          institution_candidates: diagnostics.institutionCountInSample,
          mode: "bounded_metadata_series_uat",
        },
      });
      await rpc(service, "svc_layer2a_finish_job", {
        p_job_id: jobId,
        p_status: ok ? "completed" : "blocked",
        p_result: result,
        p_error: gateError,
      });

      return json(result, ok ? 200 : 409);
    } catch (error) {
      const message = String(error).slice(0, 1800);
      try {
        await rpc(service, "svc_layer2a_source_health", {
          p_source_id: source.source_id,
          p_success: false,
          p_error: message,
          p_metadata: { worker_version: VERSION, pid: PID },
        });
      } catch {}
      try {
        await rpc(service, "svc_layer2a_finish_job", {
          p_job_id: jobId,
          p_status: "failed",
          p_result: { workerVersion: VERSION, pid: PID },
          p_error: message,
        });
      } catch {}
      throw error;
    }
  } catch (error) {
    console.error(error);
    return json({ error: String(error), workerVersion: VERSION }, 500);
  }
});
