// v0.59.5 (3 Nov 2026, CF-247 P0 autonomous operations; workstream A interface request, Integration Controller 18:20): mode ops_diagnose. An
// integration issue the deterministic classifier diagnosed with low confidence is read by the pinned model (ops.ai_diagnosis_model, given with
// each leased request by public.svc_ops_diagnosis_next) with the context the database gave it: the issue, its signals, the deterministic
// diagnosis and the registered root causes. The answer names one registered root cause, a confidence and quotes copied from the context. The
// database (public.svc_ops_diagnosis_record) refuses an answer whose cause is not registered or whose quotes are not in the context, and applies
// one only above ops.ai_min_confidence and the deterministic confidence. It never chooses a remedy or an authority.
// Pure functions only (no network): tests/uat/cf-247-s254-worker-ops-requests-contract.spec.mjs runs them.
import { callCost } from "./answer.ts";

export const OPS_DIAGNOSE_PROMPT_VERSION = "ops-diagnose-v1";
// the answer limit is a setting (pipeline reading.answer_tokens.ops_diagnosis, returned by svc_worker_settings_v1); this value is used only
// when the setting cannot be read
export const OPS_DIAGNOSE_TOKENS_KEY = "reading.answer_tokens.ops_diagnosis";
export const OPS_DIAGNOSE_TOKENS_DEFAULT = 800;
export function opsDiagnoseLimit(ws: Record<string, unknown> | null | undefined): number {
  const n = Number((ws || {})[OPS_DIAGNOSE_TOKENS_KEY]);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : OPS_DIAGNOSE_TOKENS_DEFAULT;
}

export const OPS_DIAGNOSE_SYSTEM = "You diagnose one operational issue of a data platform. You get the issue as JSON: what failed, what was expected, the evidence and signals the platform recorded, the platform's own rule-based diagnosis with its confidence, and the list of registered root causes (code, class, title, description). Choose the one registered root cause that best explains the evidence; use only a code from the list. Give your confidence from 0 to 1: high only when the evidence shows the cause directly. Support the choice with one to five short quotes copied exactly, character for character, from the values in the JSON you were given (words from a value, never a key, never text you wrote yourself, never text with a double quote or backslash in it). If the evidence does not support any cause better than the rule-based diagnosis, choose that diagnosis's cause with a low confidence. Explain your reasoning in at most three sentences.";

// the root-cause codes the context offers (the answer's code must be one of them)
export function opsDiagnoseCodes(context: any): string[] {
  return [...new Set((Array.isArray(context?.root_causes) ? context.root_causes : []).map((c: any) => String(c?.code || "")).filter(Boolean))] as string[];
}

export function opsDiagnoseSchema(codes: string[]) {
  return {
    type: "object", additionalProperties: false, required: ["root_cause", "confidence", "evidence", "reasoning"],
    properties: {
      root_cause: codes.length ? { type: "string", enum: codes } : { type: "string" },
      confidence: { type: "number" },
      evidence: { type: "array", items: { type: "string" } },
      reasoning: { type: "string" },
    },
  };
}

// the chat request: pinned model, temperature 0, structured answer, parameters required of the provider (no silent model or schema fallback)
export function opsDiagnoseRequest(model: string, context: any, maxTokens: number) {
  return {
    model, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "ops_diagnosis", strict: true, schema: opsDiagnoseSchema(opsDiagnoseCodes(context)) } },
    messages: [{ role: "system", content: OPS_DIAGNOSE_SYSTEM }, { role: "user", content: `Issue (JSON):\n${JSON.stringify(context ?? {})}` }],
  };
}

export type OpsDiagnoseAnswer = { ok: true; answer: { root_cause: string; confidence: number; evidence: string[]; reasoning: string; prompt_version: string; dropped_quotes: number }; cost: number }
  | { ok: false; error: string; cut: boolean; cost: number };

// one answer as OpenRouter returns it. A cut answer (finish_reason length, or unreadable while it used the whole limit) is never parsed. A quote
// is kept only when it is in the context's text and holds no double quote or backslash (the database looks for it in the stored JSON's text,
// where those characters are escaped). The confidence is kept between 0 and 1 only when given as a number.
export function opsDiagnoseAnswer(d: any, context: any, maxTokens: number, returnedModelOk: boolean): OpsDiagnoseAnswer {
  const cost = callCost(d), ch = d?.choices?.[0] || {}, content = String(ch?.message?.content ?? "");
  if (!returnedModelOk) return { ok: false, cut: false, cost, error: `returned model ${d?.model}, not the pinned model` };
  if (ch?.finish_reason === "length") return { ok: false, cut: true, cost, error: `held_partial: output_truncated: ops_diagnosis reached ${OPS_DIAGNOSE_TOKENS_KEY} (${maxTokens})` };
  if (!content.trim()) return { ok: false, cut: false, cost, error: `no_answer: ops_diagnosis (${String(ch?.error?.message || d?.error?.message || ch?.finish_reason || "no choices").slice(0, 120)})` };
  let a: any;
  try { a = JSON.parse(content) } catch (e) {
    const out = Number(d?.usage?.completion_tokens);
    if (Number.isFinite(out) && out >= maxTokens) return { ok: false, cut: true, cost, error: `held_partial: output_truncated: ops_diagnosis used all of ${OPS_DIAGNOSE_TOKENS_KEY} (${maxTokens})` };
    return { ok: false, cut: false, cost, error: `unreadable_answer: ops_diagnosis (${e instanceof Error ? e.message : String(e)})`.slice(0, 300) };
  }
  const text = JSON.stringify(context ?? {});
  const quotes = (Array.isArray(a?.evidence) ? a.evidence : []).map((q: unknown) => String(q ?? "").trim());
  const kept = quotes.filter((q: string) => q.length >= 3 && !/["\\]/.test(q) && text.includes(q)).slice(0, 5);
  const conf = typeof a?.confidence === "number" && Number.isFinite(a.confidence) ? Math.max(0, Math.min(1, a.confidence)) : null;
  return { ok: true, cost, answer: { root_cause: String(a?.root_cause ?? ""), confidence: conf as number, evidence: kept, reasoning: String(a?.reasoning ?? "").slice(0, 600),
                                     prompt_version: OPS_DIAGNOSE_PROMPT_VERSION, dropped_quotes: quotes.length - kept.length } };
}
