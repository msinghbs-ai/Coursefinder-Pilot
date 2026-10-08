// CF-247 Phase 2 (8 Oct 2026, Platform Admin: "Do nzqa then prism and qilt"): register adapters for statistics published as Excel
// workbooks (PRISMS SA4 enrolments and the four QILT national report tables). The spec in pipeline.register_adapters says which
// sheet, which rows and columns, how a cell is read and what the record key is. `xlsxAdapterRecords` reads a stored workbook using
// only the spec (and the reference lists the database already holds: states, PRISMS fields of education). The reference readers are
// verbatim copies of what Layer 1 does today (prisms-au-etl v0.2.0 parseWorkbook; qilt-au-etl v0.3.0 RES, val and extract), so the
// replay can compare record by record. Read only: nothing here writes observations.
import * as XLSX from "npm:xlsx@0.18.5";

type Rec = { k: string; x: Record<string, string> };
const asText = (r: Record<string, unknown>) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, v == null ? "" : String(v)]));

export type XlsxSpec = {
  format: "xlsx_tables";
  edition_from_path?: string;                       // regex on the stored path; group 1 is the edition year
  checks?: { row: number; col: number; regex: string; sheet?: string }[];
  period?: { row: number; col: number; regex: string; sheet?: string };  // "Year-to-date <Month> <Year>"
  reported_rows?: { row: number; col: number; regex: string; sheet?: string };
  label_norm?: "qilt";
  value: "count_lt5" | "estimate_ci";
  key: string;                                      // {period} {sheet} {row} {metric}
  lookups?: { state_code?: string; study_area?: boolean };
  tables: {
    sheet: string; header?: string[]; first_row?: number;
    dims?: Record<string, number>; blank_when_empty?: string[]; label_col?: number; skip_labels?: string[]; skip_regex?: string[];
    cohort?: string; year_from_offset?: number; year_to_offset?: number;
    metrics: [number, string][];
  }[];
};

const tx = (v: unknown) => String(v ?? "").replace(/\u00a0/g, " ").replace(/\s+/g, " ").trim();
const nm = (v: unknown) => tx(v).normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
const sl = (v: unknown) => nm(v).replace(/&/g, " and ").replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
const qn = (x: unknown) => String(x ?? "").trim().normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/[\*†‡]+$/g, "").toLowerCase().replace(/&/g, " and ").replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ");
const MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];

function readCount(v: unknown) {
  if (typeof v === "number" && Number.isFinite(v) && v >= 0) return { value: String(Math.trunc(v)), suppressed: "false", code: "", raw: String(v) };
  const raw = tx(v);
  if (/^<\s*5$/i.test(raw)) return { value: "", suppressed: "true", code: "<5", raw };
  if (/^\d[\d,]*$/.test(raw)) return { value: String(Number(raw.replace(/,/g, ""))), suppressed: "false", code: "", raw };
  throw new Error(`unexpected count cell: ${JSON.stringify(v)}`);
}
function readEstimate(v: unknown) {
  const s = String(v ?? "").trim().replace(/\u00a0/g, " ");
  if (!s || /^n\/?a$/i.test(s)) return null;
  const m = s.match(/^(-?[\d,]+(?:\.\d+)?)\s*(?:\(\s*(-?[\d,]+(?:\.\d+)?)\s*,\s*(-?[\d,]+(?:\.\d+)?)\s*\))?/);
  if (!m) return null;
  const n = (x?: string) => x ? String(Number(x.replace(/,/g, ""))) : "";
  return { value: n(m[1]), low: n(m[2]), high: n(m[3]), raw: s };
}

export function xlsxAdapterRecords(spec: XlsxSpec, bytes: Uint8Array, path: string, ctx: any = {}): Rec[] {
  const wb = XLSX.read(bytes, { type: "array", cellFormula: false, cellHTML: false, cellDates: false });
  const grids = new Map<string, unknown[][]>();
  const grid = (name: string, raw: boolean) => {
    const id = `${name}|${raw}`; if (grids.has(id)) return grids.get(id)!;
    const ws = wb.Sheets[name]; if (!ws) throw new Error(`sheet missing: ${name}`);
    const g = XLSX.utils.sheet_to_json(ws, { header: 1, raw, defval: null }) as unknown[][]; grids.set(id, g); return g;
  };
  const raw = spec.value === "count_lt5", first = spec.tables[0].sheet;
  const cell = (c: { row: number; col: number; sheet?: string }) => tx(grid(c.sheet || first, raw)[c.row]?.[c.col]);
  for (const c of spec.checks || []) if (!new RegExp(c.regex, "i").test(cell(c))) throw new Error(`workbook check failed at row ${c.row + 1}`);
  let period = "", pStart = "", pEnd = "";
  if (spec.period) {
    const m = cell(spec.period).match(new RegExp(spec.period.regex, "i")); if (!m) throw new Error("period line not found");
    const mo = MONTHS.indexOf(m[1].toLowerCase()) + 1, yr = Number(m[2]); if (!mo || !Number.isInteger(yr)) throw new Error("period not readable");
    period = `${yr}-${String(mo).padStart(2, "0")}`; pStart = `${yr}-01-01`; pEnd = `${period}-${String(new Date(Date.UTC(yr, mo, 0)).getUTCDate()).padStart(2, "0")}`;
  }
  const edition = spec.edition_from_path ? Number(path.match(new RegExp(spec.edition_from_path))?.[1] || NaN) : NaN;
  if (spec.edition_from_path && !Number.isInteger(edition)) throw new Error("edition year not found in the stored path");
  const states = new Set<string>((ctx.subdivisions || []).map((s: any) => tx(s.code)));
  const areas = new Map<string, string>((ctx.external_study_areas || []).map((a: any) => [nm(a.name), tx(a.external_code)]));
  const out: Rec[] = []; let dataRows = 0;
  for (const t of spec.tables) {
    const g = grid(t.sheet, raw);
    let start = t.first_row ?? 0;
    if (t.header) {
      const h = g.findIndex((r) => t.header!.every((name, i) => nm(r?.[i]) === name));
      if (h < 0) throw new Error(`headers not found on ${t.sheet}`); start = h + 1;
    }
    const skip = new Set(t.skip_labels || []), skipRe = (t.skip_regex || []).map((r) => new RegExp(r, "i"));
    for (let r = start; r < g.length; r++) {
      const row = g[r] || [], base: Record<string, unknown> = {};
      if (t.dims) {
        for (const [f, c] of Object.entries(t.dims)) base[f] = tx(row[c]);
        const vals = Object.values(t.dims).map((c) => tx(row[c]));
        if ((t.blank_when_empty || Object.keys(t.dims)).every((f) => !base[f])) continue;
        if (vals.some((v) => !v)) throw new Error(`incomplete dimensions at worksheet row ${r + 1}`);
        dataRows++;
      }
      if (t.label_col != null) {
        const label = String(row[t.label_col] ?? "").trim(), l = qn(label);
        if (!label || skip.has(l) || skipRe.some((re) => re.test(label))) continue;
        base.label = label; base.key = "qilt-inst:" + qn(label);
      }
      if (spec.lookups?.state_code) {
        const code = spec.lookups.state_code.replace("{STATE}", String(base.state).toUpperCase());
        if (!states.has(code)) throw new Error(`unmapped state ${base.state} at worksheet row ${r + 1}`); base.state = code;
      }
      if (spec.lookups?.study_area) {
        const a = areas.get(nm(base.broad_field)); if (!a) throw new Error(`unregistered field ${base.broad_field} at worksheet row ${r + 1}`); base.study_area = a;
      }
      if (base.sector != null) base.sector = sl(String(base.sector).replace(/^Non-Award$/i, "Non award"));
      if (t.cohort) { base.cohort = t.cohort; base.year_from = edition + (t.year_from_offset || 0); base.year_to = edition + (t.year_to_offset || 0) }
      if (period) { base.period_start = pStart; base.period_end = pEnd }
      for (const [col, metric] of t.metrics) {
        const key = spec.key.replace("{period}", period).replace("{sheet}", t.sheet).replace("{row}", String(r + 1)).replace("{metric}", metric);
        if (spec.value === "count_lt5") { const c = readCount(row[col]); out.push({ k: key, x: asText({ ...base, metric, ...c }) }) }
        else { const c = readEstimate(row[col]); if (c) out.push({ k: key, x: asText({ ...base, metric, ...c }) }) }
      }
    }
  }
  if (spec.reported_rows) {
    const m = cell(spec.reported_rows).match(new RegExp(spec.reported_rows.regex, "i"));
    if (m && Number(m[1].replace(/,/g, "")) !== dataRows) throw new Error(`row count differs: workbook ${m[1]}, read ${dataRows}`);
  }
  return out;
}

// ---- reference: prisms-au-etl v0.2.0 parseWorkbook (copied, not changed; only the record shape for the replay is added) ------
const SHEET = "Data";
const text = (value: unknown) => String(value ?? "").replace(/\u00a0/g, " ").replace(/\s+/g, " ").trim();
const norm = (value: unknown) => text(value).normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
const slug = (value: unknown) => norm(value).replace(/&/g, " and ").replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
function isoDate(year: number, month: number, day: number) { return `${year.toString().padStart(4, "0")}-${month.toString().padStart(2, "0")}-${day.toString().padStart(2, "0")}` }
function parsePeriod(line: string) {
  const months: Record<string, number> = { january: 1, february: 2, march: 3, april: 4, may: 5, june: 6, july: 7, august: 8, september: 9, october: 10, november: 11, december: 12 };
  const m = line.match(/Year-to-date\s+([A-Za-z]+)\s+(\d{4})/i);
  if (!m) throw new Error(`unable to parse PRISMS period line: ${line}`);
  const month = months[m[1].toLowerCase()]; const year = Number(m[2]);
  if (!month || !Number.isInteger(year)) throw new Error("invalid PRISMS period");
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return { year, month, monthName: m[1], collectionVersion: `${year}-${String(month).padStart(2, "0")}`, periodStart: isoDate(year, 1, 1), periodEnd: isoDate(year, month, lastDay), periodType: "ytd" };
}
function parseReportedSummary(line: string) {
  const m = line.match(/Row Count:\s*([\d,]+).*Total Enrolments:\s*([\d,]+).*Total Commencements:\s*([\d,]+)/i);
  if (!m) return null;
  return { rows: Number(m[1].replace(/,/g, "")), enrolments: Number(m[2].replace(/,/g, "")), commencements: Number(m[3].replace(/,/g, "")) };
}
function parseCount(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value) && value >= 0) return { value: Math.trunc(value), suppressed: false, suppressionCode: null, raw: String(value) };
  const raw = text(value);
  if (/^<\s*5$/i.test(raw)) return { value: null, suppressed: true, suppressionCode: "<5", raw };
  if (/^\d[\d,]*$/.test(raw)) return { value: Number(raw.replace(/,/g, "")), suppressed: false, suppressionCode: null, raw };
  throw new Error(`unexpected PRISMS count cell: ${JSON.stringify(value)}`);
}
function sectorCode(value: unknown) { return slug(text(value).replace(/^Non-Award$/i, "Non award")) }

export function prismsReferenceRecords(bytes: Uint8Array, ctx: any): Rec[] {
  const wb = XLSX.read(bytes, { type: "array", cellFormula: false, cellHTML: false, cellDates: false });
  const ws = wb.Sheets[SHEET];
  if (!ws) throw new Error(`required PRISMS sheet missing: ${SHEET}`);
  const rows = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: null }) as unknown[][];
  if (!rows.length || !/International Student Enrolments and Commencements by SA4/i.test(text(rows[0]?.[0]))) throw new Error("unexpected PRISMS workbook title");
  const periodLine = text(rows[1]?.[0]);
  if (!/\bPRISMS\b/i.test(periodLine)) throw new Error("PRISMS source marker missing");
  const period = parsePeriod(periodLine);
  const reported = parseReportedSummary(text(rows[4]?.[0]));
  const headerIndex = rows.findIndex((r) => norm(r?.[0]) === "state" && norm(r?.[1]) === "sa4 name" && norm(r?.[2]) === "abs remoteness area" && norm(r?.[3]) === "sector" && norm(r?.[4]) === "broad field of education" && norm(r?.[5]) === "enrolments" && norm(r?.[6]) === "commencements");
  if (headerIndex < 0) throw new Error("required PRISMS headers missing");
  const subdivisionByCode = new Map<string, any>((ctx.subdivisions || []).map((x: any) => [text(x.code), x]));
  const areaByName = new Map<string, any>((ctx.external_study_areas || []).map((x: any) => [norm(x.name), x]));
  const out: Rec[] = []; let parsedRows = 0;
  for (let i = headerIndex + 1; i < rows.length; i++) {
    const row = rows[i] || [];
    const state = text(row[0]); const sa4 = text(row[1]); const remoteness = text(row[2]); const sector = text(row[3]); const broadField = text(row[4]);
    if (!state && !sa4 && !sector && !broadField) continue;
    if (!state || !sa4 || !remoteness || !sector || !broadField) throw new Error(`incomplete PRISMS source dimensions at worksheet row ${i + 1}`);
    const subdivisionCode = `AU-${state.toUpperCase()}`;
    const subdivision = subdivisionByCode.get(subdivisionCode);
    if (!subdivision) throw new Error(`unmapped AU subdivision ${state} at worksheet row ${i + 1}`);
    const area = areaByName.get(norm(broadField));
    if (!area) throw new Error(`unregistered PRISMS broad field ${broadField} at worksheet row ${i + 1}`);
    const enrolments = parseCount(row[5]); const commencements = parseCount(row[6]);
    for (const [metricCode, count] of [["enrolments", enrolments], ["commencements", commencements]] as const) {
      const r = { state: subdivisionCode, sa4, remoteness, sector: sectorCode(sector), broad_field: broadField, study_area: area.external_code, period_start: period.periodStart, period_end: period.periodEnd,
                  metric: metricCode, value: count.value, suppressed: count.suppressed, code: count.suppressionCode, raw: count.raw };
      out.push({ k: `prisms-sa4:${period.collectionVersion}:row:${i + 1}:${metricCode}`, x: asText(r) });
    }
    parsedRows++;
  }
  if (reported?.rows && parsedRows !== reported.rows) throw new Error(`PRISMS row-count mismatch: workbook reports ${reported.rows}, parser found ${parsedRows}`);
  return out;
}

// ---- reference: qilt-au-etl v0.3.0 RES, norm, sourceKey, val, extract (copied, not changed) --------------------------------
const RES:any={
 gos:{year:2025,surveyCode:"qilt_gos",url:"https://www.qilt.edu.au/docs/default-source/default-document-library/gos_2025_national_report_tables.zip?sfvrsn=643ae941_1",label:"QILT GOS 2025 National Report Tables",sheets:[["LF_UG_UNI_1Y_INST_CI","UG",2025,2025,[2,"fte",3,"oe",4,"lf",5,"salary"]],["LF_PGC_UNI_1Y_INST_CI","PGC",2025,2025,[2,"fte",3,"oe",4,"lf",5,"salary"]],["LF_PGR_UNI_3YP_INST_CI","PGR",2023,2025,[2,"fte",3,"oe",4,"lf",5,"salary"]],["LF_UG_NUHEI_3YP_INST_CI","UG",2023,2025,[2,"fte",3,"oe",4,"lf",5,"salary"]],["LF_PGC_NUHEI_3YP_INST_CI","PGC",2023,2025,[2,"fte",3,"oe",4,"lf",5,"salary"]]]},
 ses:{year:2024,surveyCode:"qilt_ses",url:"https://www.qilt.edu.au/docs/default-source/default-document-library/ses_2024_national_report_tables.zip?sfvrsn=f1ce2f6e_1",label:"QILT SES 2024 National Report Tables",sheets:[["FOCUS_UG_UNI_1Y_INST_CI","UG",2024,2024,[2,"skills_development",3,"peer_engagement",4,"teaching_quality_engagement",5,"student_support_services",6,"learning_resources",7,"overall_educational_experience"]],["FOCUS_PGC_UNI_1Y_INST_CI","PGC",2024,2024,[2,"skills_development",3,"peer_engagement",4,"teaching_quality_engagement",5,"student_support_services",6,"learning_resources",7,"overall_educational_experience"]],["FOCUS_UG_NUHEI_1Y_INST_CI","UG",2024,2024,[2,"skills_development",3,"peer_engagement",4,"teaching_quality_engagement",5,"student_support_services",6,"learning_resources",7,"overall_educational_experience"]],["FOCUS_PGC_NUHEI_1Y_INST_CI","PGC",2024,2024,[2,"skills_development",3,"peer_engagement",4,"teaching_quality_engagement",5,"student_support_services",6,"learning_resources",7,"overall_educational_experience"]]]},
 gosl:{year:2025,surveyCode:"qilt_gosl",url:"https://www.qilt.edu.au/docs/default-source/default-document-library/gosl_2025_national_report_tables.zip?sfvrsn=91c4a3c0_2",label:"QILT GOS-L 2025 National Report Tables",sheets:[["STMT2_UG_UNI_1Y_INST_CI","UG",2025,2025,[3,"medium_fte",5,"medium_oe"]],["STMT2_PGC_UNI_1Y_INST_CI","PGC",2025,2025,[3,"medium_fte",5,"medium_oe"]],["SAL_UG_UNI_1Y_INST_FIG","UG",2025,2025,[2,"medium_salary"]],["SAL_PGC_UNI_1Y_INST_FIG","PGC",2025,2025,[2,"medium_salary"]]]},
 ess:{year:2025,surveyCode:"qilt_ess",url:"https://www.qilt.edu.au/docs/default-source/default-document-library/ess_2025_national_report_tables.zip",label:"QILT ESS 2025 National Report Tables",sheets:[["EMPSAT_ALL_UNI_3YP","ALL",2023,2025,[2,"foundation_skills",3,"adaptive_skills",4,"collaborative_skills",5,"technical_skills",6,"employability_skills",7,"overall_satisfaction"]]]}
};
const t=(x:any)=>String(x??"").trim();
const qnorm=(x:any)=>t(x).normalize("NFKD").replace(/[\u0300-\u036f]/g,"").replace(/[\*†‡]+$/g,"").toLowerCase().replace(/&/g," and ").replace(/[^a-z0-9]+/g," ").trim().replace(/\s+/g," ");const sourceKey=(x:string)=>"qilt-inst:"+qnorm(x);
function val(x:any){const s=t(x).replace(/\u00a0/g," ");if(!s||/^n\/?a$/i.test(s))return null;const m=s.match(/^(-?[\d,]+(?:\.\d+)?)\s*(?:\(\s*(-?[\d,]+(?:\.\d+)?)\s*,\s*(-?[\d,]+(?:\.\d+)?)\s*\))?/);if(!m)return null;return{v:Number(m[1].replace(/,/g,"")),lo:m[2]?Number(m[2].replace(/,/g,"")):null,hi:m[3]?Number(m[3].replace(/,/g,"")):null,raw:s};}
function extract(wb:any,cfg:any){const missing=cfg.sheets.map((x:any)=>x[0]).filter((n:string)=>!wb.Sheets[n]);if(missing.length)throw Error(`configured QILT sheets missing: ${missing.join(', ')}`);const labels=new Set<string>(),rows:any[]=[];const skip=new Set(["standard deviation","mean","median","minimum","maximum","national","all institutions","all universities","all nuheis"]);for(const spec of cfg.sheets){const[name,cohort,yf,yt,cols]=spec,ws=wb.Sheets[name],a=XLSX.utils.sheet_to_json(ws,{header:1,raw:false,defval:null}) as any[][];for(let r=4;r<a.length;r++){const label=t(a[r]?.[1]),nl=qnorm(label);if(!label||skip.has(nl)||/^all (universities|nuheis|institutions)$/i.test(label)||/^back to index$/i.test(label))continue;labels.add(label);for(let k=0;k<cols.length;k+=2){const cell=val(a[r]?.[cols[k]]);if(!cell)continue;rows.push({label,key:sourceKey(label),cohort,yearFrom:yf,yearTo:yt,metricCode:cols[k+1],value:cell.v,low:cell.lo,high:cell.h,sheet:name,row:r+1,raw:cell.raw});}}}return{labels:[...labels],rows};}

// The edition is read from the stored path (layer2a/AU/qilt/<survey code>/<year>/<hash>.xlsx); sheet cohort years move with the
// edition year exactly as qilt-au-etl v0.3.0 does for an edition found by the discovery job.
export function qiltReferenceRecords(bytes: Uint8Array, path: string): Rec[] {
  const m = path.match(/\/qilt_([a-z]+)\/(\d{4})\/[0-9a-f]{64}\.xlsx$/);
  if (!m) throw new Error("stored QILT path does not name the survey and year");
  const base0 = RES[m[1]], yr = Number(m[2]); if (!base0) throw new Error(`no QILT reader for ${m[1]}`);
  const d = yr - base0.year, cfg = { ...base0, year: yr, sheets: base0.sheets.map((x: any) => [x[0], x[1], x[2] + d, x[3] + d, x[4]]) };
  const wb = XLSX.read(bytes, { type: "array", cellFormula: false, cellHTML: false });
  return extract(wb, cfg).rows.map((r: any) => ({ k: `${r.sheet}|${r.row}|${r.metricCode}`,
    x: asText({ label: r.label, key: r.key, cohort: r.cohort, year_from: r.yearFrom, year_to: r.yearTo, metric: r.metricCode, value: r.value, low: r.low, high: r.high, raw: r.raw }) }));
}
