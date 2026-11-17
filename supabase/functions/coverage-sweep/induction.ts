// CF-247 Wave 2 (S2-Build, 17 Nov 2026; Platform Admin 20:30: the AI mapper calls its model through this worker): the request for the Layer 1
// induction field mapping (service layer1_induction_map, route pipeline.ai_service_routes). The edge function layer1-ai-induction-mapper sends the
// wizard's sample and the allowed names; the worker asks the route's one model and returns the answer. The answer is a suggestion a person
// reviews; the parser spec built from it is checked by security.layer1_parser_spec_validate_v1 before it is shown.
// Pure functions only (no network). Its system message is exported to docs/platform/ai-prompts.json by scripts/ai-prompts-export.mjs.

export const INDUCTION_PROMPT_VERSION = "induction-map-v1";
export const INDUCTION_ANSWER_KEY = "reading.answer_tokens.induction_map";
export const INDUCTION_ANSWER_DEFAULT = 4000; // used only when the setting cannot be read

export const INDUCTION_SYSTEM = [
  "You map the columns of a sample from an official education data source to a platform's fields. Answer with one JSON object only.",
  "Use only the field names, category keys and parser targets you are given. Never invent a name. If nothing fits, use null.",
  "Base every choice on the column name and the sample values, and give one short reason a person can check against the sample.",
  "Shape: {\"suggestions\":[{\"source_field\":\"<column>\",\"target_field\":\"<platform field or null>\",\"category_key\":\"<category key or null>\",\"confidence\":0.0,\"reason\":\"...\"}],",
  "\"spec_fields\":[{\"source\":\"<column>\",\"target\":\"<parser target>\",\"transforms\":[{\"op\":\"trim\"}]}],\"unique_key\":[\"<parser target>\"],\"header_row\":1}.",
  "Give at most one suggestion per column. Map a parser target only from a column whose values fit its type.",
  "Transforms allowed: trim, upper, lower, strip_currency, first_token, default (arg: text), map_values (arg: object of text to text),",
  "date_format (arg: one of YYYY-MM-DD, DD/MM/YYYY, MM/DD/YYYY, D MMM YYYY, DD-MM-YYYY, YYYY/MM/DD).",
].join("\n");

export type InductionInput = {
  target_record_type: string; country_code: string; connector_type: string;
  sample: { columns: string[]; rows: string[][] };
  platform_fields: { field: string; label: string; category_key: string }[];
  categories: { key: string; label: string; description: string }[];
  parser_targets: { target: string; type: string; required: boolean }[];
  parser_key: string[];
  previous_spec?: unknown;
};

const cut = (v: unknown, n: number) => String(v ?? "").replace(/\s+/g, " ").trim().slice(0, n);

// the input is bounded here as well as in the edge function (20 rows, 300 columns, short values)
export function inductionInput(raw: any): InductionInput {
  const columns = (Array.isArray(raw?.sample?.columns) ? raw.sample.columns : []).slice(0, 300).map((c: unknown) => cut(c, 200));
  return {
    target_record_type: cut(raw?.target_record_type, 40), country_code: cut(raw?.country_code, 2), connector_type: cut(raw?.connector_type, 40),
    sample: { columns, rows: (Array.isArray(raw?.sample?.rows) ? raw.sample.rows : []).slice(0, 20).map((r: unknown) => (Array.isArray(r) ? r : []).slice(0, columns.length).map((v) => cut(v, 300))) },
    platform_fields: (Array.isArray(raw?.platform_fields) ? raw.platform_fields : []).slice(0, 200).map((f: any) => ({ field: cut(f?.field, 80), label: cut(f?.label, 120), category_key: cut(f?.category_key, 40) })),
    categories: (Array.isArray(raw?.categories) ? raw.categories : []).slice(0, 40).map((c: any) => ({ key: cut(c?.key, 40), label: cut(c?.label, 120), description: cut(c?.description, 300) })),
    parser_targets: (Array.isArray(raw?.parser_targets) ? raw.parser_targets : []).slice(0, 100).map((t: any) => ({ target: cut(t?.target, 80), type: cut(t?.type, 30), required: !!t?.required })),
    parser_key: (Array.isArray(raw?.parser_key) ? raw.parser_key : []).slice(0, 10).map((k: unknown) => cut(k, 80)),
    ...(raw?.previous_spec && typeof raw.previous_spec === "object" ? { previous_spec: raw.previous_spec } : {}),
  };
}

export function inductionRequest(model: string, input: InductionInput, maxTokens: number) {
  return {
    model, temperature: 0, max_tokens: maxTokens, response_format: { type: "json_object" },
    provider: { require_parameters: true, allow_fallbacks: false },
    messages: [{ role: "system", content: INDUCTION_SYSTEM }, { role: "user", content: JSON.stringify(input) }],
  };
}

export function inductionAnswerLimit(ws: Record<string, unknown> | null | undefined) {
  const n = Number((ws || {})[INDUCTION_ANSWER_KEY]);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : INDUCTION_ANSWER_DEFAULT;
}

// one answer: whole and readable, or failed with the reason named; a cut answer is never parsed
export function readInductionAnswer(d: any, maxTokens: number): { ok: true; a: any; cost: number } | { ok: false; error: string; cost: number } {
  const cost = Number(d?.usage?.cost || 0) > 0 ? Number(d.usage.cost) : 0;
  const ch = d?.choices?.[0] || {}, content = String(ch?.message?.content ?? "");
  if (ch?.finish_reason === "length") return { ok: false, cost, error: `the answer was cut off at ${maxTokens} tokens (${INDUCTION_ANSWER_KEY})` };
  if (!content.trim()) return { ok: false, cost, error: `no answer (${cut(ch?.error?.message || d?.error?.message || ch?.finish_reason || "no choices", 120)})` };
  try { return { ok: true, a: JSON.parse(content.replace(/^```(json)?\s*|\s*```$/g, "")), cost } }
  catch { return { ok: false, cost, error: "the answer was not JSON" } }
}
