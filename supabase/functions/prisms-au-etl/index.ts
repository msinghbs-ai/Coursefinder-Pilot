import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import * as XLSX from "npm:xlsx@0.18.5";

const VERSION = "prisms-au-etl-v0.1.1";
const SOURCE_URL = "https://www.education.gov.au/download/15221/international-student-enrolment-and-commencement-data-abs-sa4-publication/44345/document/xlsx";
const SOURCE_PAGE = "https://www.education.gov.au/international-education-data-and-research/resources/international-student-enrolment-and-commencement-data-abs-sa4";
const SHEET = "Data";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });

const text = (value: unknown) =>
  String(value ?? "").replace(/\u00a0/g, " ").replace(/\s+/g, " ").trim();

const norm = (value: unknown) =>
  text(value)
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();

const slug = (value: unknown) =>
  norm(value)
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");

async function rpc(client: any, name: string, args: Record<string, unknown> = {}) {
  const { data, error } = await client.rpc(name, args);
  if (error) throw new Error(`${name}: ${error.message}`);
  return data;
}

async function sha256(bytes: Uint8Array) {
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)]
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}

function isoDate(year: number, month: number, day: number) {
  return `${year.toString().padStart(4, "0")}-${month
    .toString()
    .padStart(2, "0")}-${day.toString().padStart(2, "0")}`;
}

function parsePeriod(line: string) {
  const months: Record<string, number> = {
    january: 1,
    february: 2,
    march: 3,
    april: 4,
    may: 5,
    june: 6,
    july: 7,
    august: 8,
    september: 9,
    october: 10,
    november: 11,
    december: 12,
  };
  const m = line.match(/Year-to-date\s+([A-Za-z]+)\s+(\d{4})/i);
  if (!m) throw new Error(`unable to parse PRISMS period line: ${line}`);
  const month = months[m[1].toLowerCase()];
  const year = Number(m[2]);
  if (!month || !Number.isInteger(year)) throw new Error("invalid PRISMS period");
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return {
    year,
    month,
    monthName: m[1],
    collectionVersion: `${year}-${String(month).padStart(2, "0")}`,
    periodStart: isoDate(year, 1, 1),
    periodEnd: isoDate(year, month, lastDay),
    periodType: "ytd",
  };
}

function parseReportedSummary(line: string) {
  const m = line.match(
    /Row Count:\s*([\d,]+).*Total Enrolments:\s*([\d,]+).*Total Commencements:\s*([\d,]+)/i,
  );
  if (!m) return null;
  return {
    rows: Number(m[1].replace(/,/g, "")),
    enrolments: Number(m[2].replace(/,/g, "")),
    commencements: Number(m[3].replace(/,/g, "")),
  };
}

function parseCount(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value) && value >= 0) {
    return { value: Math.trunc(value), suppressed: false, suppressionCode: null, raw: String(value) };
  }
  const raw = text(value);
  if (/^<\s*5$/i.test(raw)) {
    return { value: null, suppressed: true, suppressionCode: "<5", raw };
  }
  if (/^\d[\d,]*$/.test(raw)) {
    return {
      value: Number(raw.replace(/,/g, "")),
      suppressed: false,
      suppressionCode: null,
      raw,
    };
  }
  throw new Error(`unexpected PRISMS count cell: ${JSON.stringify(value)}`);
}

function sectorCode(value: unknown) {
  return slug(text(value).replace(/^Non-Award$/i, "Non award"));
}

function parseWorkbook(bytes: Uint8Array, ctx: any) {
  const wb = XLSX.read(bytes, {
    type: "array",
    cellFormula: false,
    cellHTML: false,
    cellDates: false,
  });
  const ws = wb.Sheets[SHEET];
  if (!ws) throw new Error(`required PRISMS sheet missing: ${SHEET}`);

  const rows = XLSX.utils.sheet_to_json(ws, {
    header: 1,
    raw: true,
    defval: null,
  }) as unknown[][];

  if (!rows.length || !/International Student Enrolments and Commencements by SA4/i.test(text(rows[0]?.[0]))) {
    throw new Error("unexpected PRISMS workbook title");
  }

  const periodLine = text(rows[1]?.[0]);
  if (!/\bPRISMS\b/i.test(periodLine)) throw new Error("PRISMS source marker missing");
  const period = parsePeriod(periodLine);
  const reported = parseReportedSummary(text(rows[4]?.[0]));

  const headerIndex = rows.findIndex((r) =>
    norm(r?.[0]) === "state" &&
    norm(r?.[1]) === "sa4 name" &&
    norm(r?.[2]) === "abs remoteness area" &&
    norm(r?.[3]) === "sector" &&
    norm(r?.[4]) === "broad field of education" &&
    norm(r?.[5]) === "enrolments" &&
    norm(r?.[6]) === "commencements"
  );
  if (headerIndex < 0) throw new Error("required PRISMS headers missing");

  const subdivisionByCode = new Map<string, any>(
    (ctx.subdivisions || []).map((x: any) => [text(x.code), x]),
  );
  const areaByName = new Map<string, any>(
    (ctx.external_study_areas || []).map((x: any) => [norm(x.name), x]),
  );

  const parsedRows: any[] = [];
  const observations: any[] = [];
  const stateCodes = new Set<string>();
  const sectors = new Set<string>();
  const sourceFields = new Set<string>();
  const duplicateDimensionCounter = new Map<string, number>();
  let exactNumeric = 0;
  let suppressed = 0;
  let mappedCanonicalFieldObservations = 0;
  let visibleEnrolments = 0;
  let visibleCommencements = 0;

  for (let i = headerIndex + 1; i < rows.length; i++) {
    const row = rows[i] || [];
    const state = text(row[0]);
    const sa4 = text(row[1]);
    const remoteness = text(row[2]);
    const sector = text(row[3]);
    const broadField = text(row[4]);
    if (!state && !sa4 && !sector && !broadField) continue;
    if (!state || !sa4 || !remoteness || !sector || !broadField) {
      throw new Error(`incomplete PRISMS source dimensions at worksheet row ${i + 1}`);
    }

    const subdivisionCode = `AU-${state.toUpperCase()}`;
    const subdivision = subdivisionByCode.get(subdivisionCode);
    if (!subdivision) {
      throw new Error(`unmapped AU subdivision ${state} at worksheet row ${i + 1}`);
    }

    const area = areaByName.get(norm(broadField));
    if (!area) {
      throw new Error(`unregistered PRISMS broad field ${broadField} at worksheet row ${i + 1}`);
    }

    const enrolments = parseCount(row[5]);
    const commencements = parseCount(row[6]);
    const sourceSectorCode = sectorCode(sector);
    const geographyKey = `sa4:${state.toLowerCase()}:${slug(sa4)}`;
    const dimKey = [
      state.toUpperCase(),
      norm(sa4),
      norm(remoteness),
      sourceSectorCode,
      area.external_code,
    ].join("|");
    duplicateDimensionCounter.set(dimKey, (duplicateDimensionCounter.get(dimKey) || 0) + 1);

    stateCodes.add(subdivisionCode);
    sectors.add(sourceSectorCode);
    sourceFields.add(area.external_code);

    const base = {
      host_country_id: ctx.country_id,
      provider_id: null,
      course_id: null,
      subdivision_id: subdivision.id,
      external_study_area_id: area.id,
      field_of_study_id: area.field_of_study_id || null,
      study_level_id: null,
      survey_id: ctx.survey_id,
      audience: "international",
      period_start: period.periodStart,
      period_end: period.periodEnd,
      period_type: period.periodType,
      source_geography_type: "ABS_SA4",
      source_geography_key: geographyKey,
      source_geography_name: sa4,
      source_remoteness_area: remoteness,
      source_sector_code: sourceSectorCode,
      source_provider_type: null,
      source_nationality_code: null,
      source_nationality_name: null,
      source_study_area_code: area.external_code,
      source_study_area_name: broadField,
    };

    const metricDefs = [
      ["enrolments", enrolments],
      ["commencements", commencements],
    ] as const;

    for (const [metricCode, count] of metricDefs) {
      const metricId = ctx.metric_ids?.[metricCode];
      if (!metricId) throw new Error(`PRISMS metric missing from context: ${metricCode}`);
      if (count.suppressed) suppressed++;
      else {
        exactNumeric++;
        if (metricCode === "enrolments") visibleEnrolments += Number(count.value);
        else visibleCommencements += Number(count.value);
      }
      if (area.field_of_study_id) mappedCanonicalFieldObservations++;

      observations.push({
        ...base,
        metric_id: metricId,
        source_observation_key:
          `prisms-sa4:${period.collectionVersion}:row:${i + 1}:${metricCode}`,
        metric_value: count.value,
        is_suppressed: count.suppressed,
        suppression_code: count.suppressionCode,
        status: "current",
        metadata: {
          layer: "2A",
          publisher: "Department of Education",
          source_system: "PRISMS",
          source_page: SOURCE_PAGE,
          source_sheet: SHEET,
          source_row: i + 1,
          source_raw_value: count.raw,
          privacy_suppressed: count.suppressed,
          source_period_line: periodLine,
          source_workbook_hash: null,
          worker_version: VERSION,
          published_provider_dimension: false,
          published_course_dimension: false,
          identity_authority: false,
          subdivision_mapping: "exact_published_state_to_existing_au_iso_subdivision",
          canonical_field_mapping: area.field_of_study_id
            ? "exact_existing_canonical_label"
            : "source_only_unmapped",
        },
      });
    }

    parsedRows.push({
      worksheetRow: i + 1,
      state,
      sa4,
      remoteness,
      sector,
      sourceSectorCode,
      broadField,
      externalStudyAreaCode: area.external_code,
      canonicalFieldCode: area.canonical_field_code || null,
      enrolments,
      commencements,
    });
  }

  if (reported?.rows && parsedRows.length !== reported.rows) {
    throw new Error(
      `PRISMS row-count mismatch: workbook reports ${reported.rows}, parser found ${parsedRows.length}`,
    );
  }

  const duplicateDimensionGroups = [...duplicateDimensionCounter.values()].filter((n) => n > 1).length;

  return {
    period,
    periodLine,
    reported,
    parsedRows,
    observations,
    exactNumeric,
    suppressed,
    mappedCanonicalFieldObservations,
    stateCodes: [...stateCodes].sort(),
    sectors: [...sectors].sort(),
    sourceFields: [...sourceFields].sort(),
    duplicateDimensionGroups,
    visibleNumericTotals: {
      enrolments: visibleEnrolments,
      commencements: visibleCommencements,
    },
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "POST required" }, 405);

  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  let sourceId: string | null = null;
  try {
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const internal = text(req.headers.get("x-cf-layer1-service-key"));
    const internalOk = Boolean(internal) && internal === serviceKey;
    const nonce = text(req.headers.get("x-cf-run-nonce"));
    const nonceOk = Boolean(nonce) &&
      (await rpc(client, "svc_pilot_consume_nonce", {
        p_function: "prisms-au-etl",
        p_nonce: nonce,
      }));
    if (!internalOk && !nonceOk) {
      return json({ error: "valid one-time Pilot nonce or governed Layer 1 service authority required" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const mode = text(body?.mode || "dry_run").toLowerCase();
    if (!["dry_run", "apply"].includes(mode)) {
      throw new Error("mode must be dry_run or apply");
    }

    const ctx = await rpc(client, "svc_prisms_context");
    if (!ctx?.country_id || !ctx?.survey_id) {
      throw new Error("PRISMS context unavailable");
    }

    const response = await fetch(SOURCE_URL, {
      redirect: "follow",
      headers: { "user-agent": "CourseFinder-Pilot/PRISMS-0.1" },
    });
    if (!response.ok) throw new Error(`PRISMS source HTTP ${response.status}`);

    const bytes = new Uint8Array(await response.arrayBuffer());
    const workbookHash = await sha256(bytes);
    const parsed = parseWorkbook(bytes, ctx);

    for (const observation of parsed.observations) {
      observation.metadata.source_workbook_hash = workbookHash;
    }

    const base = {
      ok: true,
      workerVersion: VERSION,
      mode,
      sourceUrl: SOURCE_URL,
      sourcePage: SOURCE_PAGE,
      workbookBytes: bytes.length,
      workbookSha256: workbookHash,
      sourceSheet: SHEET,
      collectionVersion: parsed.period.collectionVersion,
      periodStart: parsed.period.periodStart,
      periodEnd: parsed.period.periodEnd,
      periodType: parsed.period.periodType,
      parsedRows: parsed.parsedRows.length,
      candidateObservations: parsed.observations.length,
      exactNumericObservations: parsed.exactNumeric,
      suppressedObservations: parsed.suppressed,
      canonicalFieldMappedObservations: parsed.mappedCanonicalFieldObservations,
      mappedSubdivisions: parsed.stateCodes,
      sourceSectors: parsed.sectors,
      sourceBroadFields: parsed.sourceFields,
      duplicatePublishedDimensionGroups: parsed.duplicateDimensionGroups,
      reportedSummary: parsed.reported,
      visibleNumericTotals: parsed.visibleNumericTotals,
      providerDimensionPublished: false,
      courseDimensionPublished: false,
      identityAuthority: false,
      sample: parsed.parsedRows.slice(0, 12),
    };

    if (mode === "dry_run") return json(base);

    const label =
      `Department of Education PRISMS SA4 ${parsed.period.monthName} ${parsed.period.year}`;
    sourceId = await rpc(client, "svc_prisms_prepare_source", {
      p_label: label,
      p_url: SOURCE_URL,
      p_collection_version: parsed.period.collectionVersion,
      p_period_start: parsed.period.periodStart,
      p_period_end: parsed.period.periodEnd,
    });

    const storagePath =
      `layer2a/AU/prisms/sa4/${parsed.period.collectionVersion}/${workbookHash}.xlsx`;
    const upload = await client.storage.from("evidence").upload(storagePath, bytes, {
      contentType:
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      upsert: true,
    });
    if (upload.error) throw upload.error;

    const evidenceId = await rpc(client, "svc_prisms_register_evidence", {
      p_source_id: sourceId,
      p_source_url: SOURCE_URL,
      p_storage_path: storagePath,
      p_content_hash: workbookHash,
      p_collection_version: parsed.period.collectionVersion,
      p_period_start: parsed.period.periodStart,
      p_period_end: parsed.period.periodEnd,
      p_worker_version: VERSION,
    });

    let observationsSeen = 0;
    let observationsChanged = 0;
    const payload = parsed.observations.map((o: any) => ({
      ...o,
      source_id: sourceId,
      evidence_id: evidenceId,
    }));

    for (let i = 0; i < payload.length; i += 1000) {
      const result = await rpc(client, "svc_prisms_apply_observations", {
        p_rows: payload.slice(i, i + 1000),
      });
      observationsSeen += Number(result?.seen || 0);
      observationsChanged += Number(result?.changed || 0);
    }

    await rpc(client, "svc_prisms_touch_source", {
      p_source_id: sourceId,
      p_ok: true,
      p_error: null,
    });

    return json({
      ...base,
      sourceId,
      evidenceId,
      evidenceStoragePath: storagePath,
      observationsSeen,
      observationsChanged,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (sourceId) {
      try {
        await rpc(client, "svc_prisms_touch_source", {
          p_source_id: sourceId,
          p_ok: false,
          p_error: message,
        });
      } catch {
        // Preserve the primary error.
      }
    }
    return json({ ok: false, workerVersion: VERSION, error: message }, 500);
  }
});
