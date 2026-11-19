// CF-247 S747 (19 Nov 2026, session S2-BOOST-AER, Platform Admin 10:48 AEDT): the AER v2 matrix reader on the row chunker (entry-chunks.ts, S744 to S746).
// One table of a stored entry-requirements page is sent as its own row chunks ([R#] lines with the headings over them and the table header), at most
// rows_per_call rows a call, with a prompt version kept as data (pipeline.ai_instruction_versions, answer contract aer-matrix-chunk-answer-v1). The
// answer gives one record per row; the checks below are deterministic:
//   row completeness: every row of the group answered exactly once, no row number that was not sent;
//   quote fidelity: each quote is text of its own row (whitespace collapsed, NFKC), and a minimum given is printed inside its quote.
// Nothing here admits, proposes or records a reading: mode aer_chunk_smoke returns the figures and the caller records them as evidence.
import type { EntryChunk } from "./entry-chunks.ts";

export const AER_CHUNK_MODE = "aer_chunk_smoke";
export const AER_CHUNK_CONTRACT = "aer-matrix-chunk-answer-v1";
export const AER_CHUNK_INPUT = "entry-chunks-v1";

const strOrNull = { type: ["string", "null"] };
export const AER_CHUNK_SCHEMA = {
  type: "object", additionalProperties: false, required: ["rows"],
  properties: {
    rows: { type: "array", items: { type: "object", additionalProperties: false,
      required: ["r", "no_requirement", "country", "qualification", "study_level", "minimum", "quote"],
      properties: { r: { type: "integer" }, no_requirement: { type: "boolean" }, country: strOrNull, qualification: strOrNull, study_level: strOrNull, minimum: strOrNull, quote: { type: "string" } } } } } };

// the version's pinned provider routing and extra fields as aerV3Request takes them; require_parameters is always set so no provider ignores the schema
export function aerChunkRequest(model: string, system: string, user: string, maxTokens: number, routing?: Record<string, unknown> | null, params?: Record<string, unknown> | null) {
  const extra: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(params || {})) if (!["model", "messages", "response_format", "provider", "max_tokens", "temperature"].includes(k)) extra[k] = v;
  return { ...extra, model, temperature: 0, max_tokens: maxTokens, usage: { include: true }, provider: { ...(routing || {}), require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "aer_matrix_chunk_v1", strict: true, schema: AER_CHUNK_SCHEMA } },
    messages: [{ role: "system", content: system }, { role: "user", content: user }] };
}

// one canonical form for comparing a quote with its row: NFKC, every run of white space one space, trimmed
export const chunkFlat = (s: unknown) => String(s ?? "").normalize("NFKC").replace(/\s+/g, " ").trim();

export type ChunkRowCheck = { r: number; answered: boolean; no_requirement: boolean; quote_in_row: boolean | null; minimum_in_quote: boolean | null };
export type ChunkVerified = { rows: number; answered: number; missing: number[]; doubled: number[]; invented: number[]; quotes: number; quotes_in_row: number;
  minimums: number; minimums_in_quote: number; checks: ChunkRowCheck[] };

// the group's answer against the rows that were sent (a row is "answered" when its number comes back exactly once)
export function aerChunkVerify(answer: any, group: EntryChunk[]): ChunkVerified {
  const sent = new Map(group.map((c) => [c.n, c]));
  const got: any[] = Array.isArray(answer?.rows) ? answer.rows : [];
  const seen = new Map<number, number>(); const invented = new Set<number>();
  for (const x of got) { const r = Number(x?.r); if (!sent.has(r)) { invented.add(r); continue } seen.set(r, (seen.get(r) || 0) + 1) }
  const doubled = [...seen].filter(([, k]) => k > 1).map(([r]) => r);
  const missing = group.map((c) => c.n).filter((n) => !seen.has(n));
  const checks: ChunkRowCheck[] = [];
  let quotes = 0, inRow = 0, mins = 0, minIn = 0;
  for (const c of group) {
    const xs = got.filter((x) => Number(x?.r) === c.n);
    if (xs.length !== 1) { checks.push({ r: c.n, answered: false, no_requirement: false, quote_in_row: null, minimum_in_quote: null }); continue }
    const x = xs[0], row = chunkFlat(c.quote), q = chunkFlat(x.quote), m = chunkFlat(x.minimum);
    const none = x.no_requirement === true;
    const qOk = q ? row.includes(q) : (none ? null : false);
    const mOk = m && !none ? q.includes(m) : null;
    if (q || !none) { quotes++; if (qOk) inRow++ }
    if (mOk !== null) { mins++; if (mOk) minIn++ }
    checks.push({ r: c.n, answered: true, no_requirement: none, quote_in_row: qOk, minimum_in_quote: mOk });
  }
  return { rows: group.length, answered: group.length - missing.length - doubled.length, missing, doubled, invented: [...invented], quotes, quotes_in_row: inRow,
    minimums: mins, minimums_in_quote: minIn, checks };
}

// the bar a smoke run must meet before the chunked reader is recommended as an AER v2 record source (a recommendation only: nothing switches on)
export const AER_CHUNK_BAR = { row_completeness_pct: 100, quote_fidelity_pct: 100, minimum_in_quote_pct: 100, invented: 0 } as const;

export type ChunkTotals = { rows: number; answered: number; doubled: number; invented: number; quotes: number; quotes_in_row: number; minimums: number; minimums_in_quote: number;
  row_completeness_pct: number; quote_fidelity_pct: number; minimum_in_quote_pct: number; meets_bar: boolean };

export function aerChunkTotals(vs: ChunkVerified[]): ChunkTotals {
  const s = (k: keyof ChunkVerified) => vs.reduce((t, v) => t + (Array.isArray(v[k]) ? (v[k] as unknown[]).length : Number(v[k]) || 0), 0);
  const rows = s("rows"), answered = s("answered"), quotes = s("quotes"), inRow = s("quotes_in_row"), mins = s("minimums"), minIn = s("minimums_in_quote"), invented = s("invented");
  const pct = (a: number, b: number) => (b ? Math.round((a / b) * 1000) / 10 : 100);
  const t = { rows, answered, doubled: s("doubled"), invented, quotes, quotes_in_row: inRow, minimums: mins, minimums_in_quote: minIn,
    row_completeness_pct: pct(answered, rows), quote_fidelity_pct: pct(inRow, quotes), minimum_in_quote_pct: pct(minIn, mins), meets_bar: false };
  t.meets_bar = rows > 0 && t.row_completeness_pct >= AER_CHUNK_BAR.row_completeness_pct && t.quote_fidelity_pct >= AER_CHUNK_BAR.quote_fidelity_pct &&
    t.minimum_in_quote_pct >= AER_CHUNK_BAR.minimum_in_quote_pct && invented <= AER_CHUNK_BAR.invented;
  return t;
}
