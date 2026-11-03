// v0.59.5 (3 Nov 2026, CF-247 P0 autonomous operations; workstream A interface request, Integration Controller 18:20 and 18:50): mode
// ops_diagnose, contract ops-diagnose-v1 (workstream A, migration 20261104100000). Each leased request (public.svc_ops_diagnosis_next) carries
// its pinned model, lease_until, contract, context, instructions and response_schema. The worker sends the instructions and the schema as given
// with the context, to the pinned model only, and answers every request exactly once through public.svc_ops_diagnosis_record:
//   an answer: {root_cause, confidence, evidence[], reasoning?} and nothing else; every quote is copied from a text value of the context
//              (the database checks the same text values); a quote that is not is left out, and an answer with none left is a worker error;
//   a failure: {error} with the cost spent (an HTTP failure, a cut, unreadable or empty answer, another model's answer, the call's time budget).
//              The database records it and never asks again.
// The database applies an answer only above ops.ai_min_confidence and the deterministic confidence; it never chooses a remedy or an authority.
// Pure functions only (no network): tests/uat/cf-247-s254-worker-ops-requests-contract.spec.mjs runs them.
import { callCost } from "./answer.ts";

export const OPS_DIAGNOSE_CONTRACT = "ops-diagnose-v1";
// the answer limit is a setting (pipeline reading.answer_tokens.ops_diagnosis, returned by svc_worker_settings_v1); this value is used only
// when the setting cannot be read
export const OPS_DIAGNOSE_TOKENS_KEY = "reading.answer_tokens.ops_diagnosis";
export const OPS_DIAGNOSE_TOKENS_DEFAULT = 800;
export function opsDiagnoseLimit(ws: Record<string, unknown> | null | undefined): number {
  const n = Number((ws || {})[OPS_DIAGNOSE_TOKENS_KEY]);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : OPS_DIAGNOSE_TOKENS_DEFAULT;
}

// the context's text values, as the database reads them (every string in the JSON, one per line)
export function opsContextText(context: unknown): string {
  const out: string[] = [];
  const walk = (v: unknown) => { if (typeof v === "string") out.push(v); else if (Array.isArray(v)) v.forEach(walk); else if (v && typeof v === "object") Object.values(v).forEach(walk) };
  walk(context);
  return out.join("\n");
}

// the request is usable only under this contract with its model, instructions and schema
export function opsDiagnoseUsable(it: any): string | null {
  if (String(it?.contract || "") !== OPS_DIAGNOSE_CONTRACT) return `unsupported contract ${String(it?.contract || "none")} (worker reads ${OPS_DIAGNOSE_CONTRACT})`;
  if (!String(it?.model || "")) return "no model given";
  if (!String(it?.instructions || "").trim() || !it?.response_schema || typeof it.response_schema !== "object") return "no instructions or response_schema given";
  return null;
}

// the chat request: the pinned model, temperature 0, the contract's instructions and schema as given, parameters required of the provider. Strict
// schema mode needs every property required, so it is asked only when the schema requires them all (reasoning is optional in ops-diagnose-v1).
export function opsDiagnoseRequest(it: any, maxTokens: number) {
  const schema = it.response_schema, props = Object.keys(schema?.properties || {}), req = Array.isArray(schema?.required) ? schema.required : [];
  return {
    model: String(it.model), temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "ops_diagnosis", strict: props.every((p) => req.includes(p)), schema } },
    messages: [{ role: "system", content: String(it.instructions) }, { role: "user", content: `Context (JSON):\n${JSON.stringify(it.context ?? {})}` }],
  };
}

export type OpsDiagnoseResult = { answer: { root_cause: string; confidence: number; evidence: string[]; reasoning?: string } | { error: string }; cost: number; dropped_quotes: number };
const fail = (error: string, cost: number, dropped = 0): OpsDiagnoseResult => ({ answer: { error: error.slice(0, 300) }, cost, dropped_quotes: dropped });

// one reply as OpenRouter returns it (d), for request it, turned into exactly the answer the contract allows, or {error}
export function opsDiagnoseAnswer(d: any, it: any, maxTokens: number, httpOk: boolean, httpStatus = 200): OpsDiagnoseResult {
  const cost = callCost(d), ch = d?.choices?.[0] || {}, content = String(ch?.message?.content ?? ""), model = String(it?.model || "");
  if (!httpOk) return fail(`HTTP ${httpStatus}: ${JSON.stringify(d?.error || d || {}).slice(0, 200)}`, cost);
  if (d?.model && !String(d.model).startsWith(model)) return fail(`returned model ${d.model}, not ${model}`, cost);  // pinned: another model's answer is not used
  if (ch?.finish_reason === "length") return fail(`output_truncated: reached ${OPS_DIAGNOSE_TOKENS_KEY} (${maxTokens})`, cost);
  if (!content.trim()) return fail(`no_answer (${String(ch?.error?.message || d?.error?.message || ch?.finish_reason || "no choices").slice(0, 120)})`, cost);
  let a: any;
  try { a = JSON.parse(content) } catch (e) {
    const out = Number(d?.usage?.completion_tokens);
    if (Number.isFinite(out) && out >= maxTokens) return fail(`output_truncated: used all of ${OPS_DIAGNOSE_TOKENS_KEY} (${maxTokens})`, cost);
    return fail(`unreadable_answer (${e instanceof Error ? e.message : String(e)})`, cost);
  }
  const codes = (it?.response_schema?.properties?.root_cause?.enum as unknown[] | undefined)?.map(String);
  const rc = typeof a?.root_cause === "string" ? a.root_cause : "";
  if (!rc || (codes && !codes.includes(rc))) return fail(`root_cause ${JSON.stringify(a?.root_cause ?? null).slice(0, 80)} is not a registered cause`, cost);
  if (typeof a?.confidence !== "number" || !Number.isFinite(a.confidence) || a.confidence < 0 || a.confidence > 1) return fail("confidence is not a number from 0 to 1", cost);
  const text = opsContextText(it?.context);
  const quotes = (Array.isArray(a?.evidence) ? a.evidence : []).filter((q: unknown) => typeof q === "string").map((q: string) => q.trim());
  const kept = [...new Set(quotes.filter((q: string) => q.length >= 3 && text.includes(q)))] as string[];
  if (!kept.length) return fail("no quote of the answer is in the context's text", cost, quotes.length);
  const answer: { root_cause: string; confidence: number; evidence: string[]; reasoning?: string } = { root_cause: rc, confidence: a.confidence, evidence: kept };
  if (typeof a?.reasoning === "string" && a.reasoning.trim()) answer.reasoning = a.reasoning.trim().slice(0, 600);
  return { answer, cost, dropped_quotes: quotes.length - kept.length };
}
