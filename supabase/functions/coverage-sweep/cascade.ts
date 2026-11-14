// CF-247 (13 Nov 2026, Platform Admin 19:14 "Service based Model with cascading"): one rule for every OpenRouter call that has a cascade.
// v1.0.0: a model in cooldown for the service (database health check) is asked after the healthy ones; every attempt's time is noted (ms).
// The database hands out each service's models in order (pipeline.ai_service_routes through security.ai_route_v1: `model` is the first, `models`
// the whole cascade). A call tries them in that order and moves to the next ONLY on a technical failure or a provider refusal:
//   an HTTP error, a time-out or network failure, an unreadable body, an error object, no answer, a cut answer (finish_reason length) or, when
//   JSON was asked for, an answer that is not JSON.
// It never moves on because of what a model answered ("not stated", no value, a low confidence): that answer is the answer.
// A later model is asked only while the caller's time budget lasts (deadline): with too little time left the last failure is returned as it came,
// so a cascade can never outlive the worker call or the lease of the item.
// The answer that is returned names the model that gave it (cf_model_sent) and carries the cost of every attempt, so the caller's pinned-model
// check compares with the model that was actually asked and the cost of a failed first attempt is not lost.

export type RouteModel = { code?: string; model_identifier?: string } | string;
type FetchFn = (url: string, init: RequestInit) => Promise<Response>;

// the cascade for a call whose request names `first`: the handed-out list from `first` on (a list that does not hold `first` is not this call's)
export function cascadeModels(first: string, models: unknown): string[] {
  const ids = (Array.isArray(models) ? models : []).map((m: RouteModel) => typeof m === "string" ? m : String(m?.model_identifier || "")).filter(Boolean);
  const i = ids.indexOf(first);
  const out = i < 0 ? [first] : ids.slice(i);
  return out.filter((m, k) => m && out.indexOf(m) === k);
}

// why this answer is a technical failure (the next model may be asked), or null when the model answered
// deno-lint-ignore no-explicit-any
export function technicalFailure(status: number, d: any, wantsJson: boolean): string | null {
  if (status < 200 || status >= 300) return `HTTP ${status}`;
  if (!d || typeof d !== "object" || d.unreadable) return "unreadable body";
  if (d.error) return `error: ${String(d.error?.message || JSON.stringify(d.error)).slice(0, 120)}`;
  const ch = d.choices?.[0];
  if (!ch) return "no choices";
  if (ch.error) return `error: ${String(ch.error?.message || "choice error").slice(0, 120)}`;
  if (ch.finish_reason === "length") return "cut answer";
  const content = String(ch.message?.content ?? "");
  if (!content.trim()) return "empty answer";
  if (wantsJson) { try { JSON.parse(content) } catch { return "answer is not JSON" } }
  return null;
}

// deno-lint-ignore no-explicit-any
export const sentModel = (d: any, asked: string): string => String(d?.cf_model_sent || asked || "");

const RETRY_TIMEOUT_MS = 90000; // fixed: API time-out of one later attempt (the first attempt keeps the caller's own time-out)
const MIN_ATTEMPT_MS = 15000;   // fixed: a later attempt is not started with less time than this left in the caller's budget
export type Cascade = { models?: unknown; deadline?: number; service?: string; source?: string; source_id?: unknown } | null | undefined;

// Round 4 (Platform Admin review 13 Nov 2026 22:10): every model call attempt is kept, the failed ones too: which service asked which model, on
// which attempt, whether it answered, why not, and the tokens and cost. The worker sends the rows to public.svc_ai_model_answered_v1 at the end of
// its call (pipeline.ai_invocations). The trace never changes a call: a failure to note an attempt is ignored.
export type Attempt = { service: string | null; model: string; attempt_no: number; outcome: "answered" | "failed"; failure_kind: string | null;
  input_tokens: number | null; output_tokens: number | null; cost: number | null; source: string | null; source_id: string | null; ms: number | null };

// v1.0.0 (Platform Admin 15 Nov 2026 00:23, self-improving cascade): models the database has put in cooldown for a service (pipeline.ai_model_health,
// refreshed by job ai-model-health from the attempts in pipeline.ai_invocations) are asked LAST in that service's cascade, after the healthy ones,
// until their cooldown ends. Only the order changes: the list is still exactly the service's allowed and qualified models, nothing is added or
// removed, and a cascade whose models are all cooling keeps its own order. Empty unless ai.health_reorder_on is 1 (svc_ai_model_health_v1).
const COOLING = new Map<string, Set<string>>();
export function setCooling(byService: unknown): void {
  COOLING.clear();
  if (!byService || typeof byService !== "object") return;
  for (const [svc, models] of Object.entries(byService as Record<string, unknown>)) if (Array.isArray(models) && models.length) COOLING.set(svc, new Set(models.map(String)));
}
export function healthOrder(service: string | null | undefined, list: string[]): string[] {
  const cool = service ? COOLING.get(service) : undefined;
  if (!cool || list.length < 2) return list;
  const ok = list.filter((m) => !cool.has(m)), cooling = list.filter((m) => cool.has(m));
  return ok.length ? [...ok, ...cooling] : list;
}
const trace: Attempt[] = [];
const TRACE_MAX = 2000; // fixed: memory guard of one worker call's attempt list
export const takeAiTrace = (): Attempt[] => trace.splice(0, trace.length);
export function failureKind(why: string): string {
  if (/^HTTP /.test(why)) return "http";
  if (/timed? ?out|timeout|abort/i.test(why)) return "timeout";
  if (why === "cut answer") return "cut";
  if (why === "answer is not JSON") return "non_json";
  if (/^error: /.test(why)) return "refused";
  if (why === "empty answer" || why === "no choices" || why === "unreadable body") return "empty";
  return "http";  // a network failure
}
// deno-lint-ignore no-explicit-any
function note(c: Cascade, model: string, attemptNo: number, why: string | null, d: any, ms: number | null = null) {
  try {
    if (!model || trace.length >= TRACE_MAX) return;
    const n = (v: unknown) => v == null || !Number.isFinite(Number(v)) ? null : Number(v);
    trace.push({ service: c?.service ? String(c.service) : null, model, attempt_no: attemptNo, outcome: why ? "failed" : "answered", failure_kind: why ? failureKind(why) : null,
      input_tokens: n(d?.usage?.prompt_tokens), output_tokens: n(d?.usage?.completion_tokens), cost: n(d?.usage?.cost), source: c?.source ? String(c.source) : null,
      source_id: c?.source_id == null ? null : String(c.source_id), ms: ms == null || !Number.isFinite(ms) ? null : Math.round(ms) });
  } catch { /* the trace never fails a call */ }
}
const thrown = (e: unknown): string => e instanceof Error ? (e.name === "TimeoutError" || e.name === "AbortError" ? "timeout" : e.message.slice(0, 120)) : String(e).slice(0, 120);

export async function cascadeFetch(doFetch: FetchFn, cascade: Cascade, url: string, init: RequestInit): Promise<Response> {
  const models = cascade?.models, deadline = Number(cascade?.deadline) || 0;
  // deno-lint-ignore no-explicit-any
  let body: any; try { body = JSON.parse(String(init.body)) } catch { return doFetch(url, init) }
  const list = healthOrder(cascade?.service, cascadeModels(String(body?.model || ""), models));
  const wantsJson = !!body.response_format;
  if (list.length < 2) {  // one model: exactly the call as it was; the attempt is noted from a copy of the answer
    const t1 = Date.now();
    try {
      const r = await doFetch(url, init);
      // deno-lint-ignore no-explicit-any
      const d: any = await r.clone().json().catch(() => ({ unreadable: true }));
      note(cascade, list[0], 1, technicalFailure(r.status, d, wantsJson), d, Date.now() - t1);
      return r;
    } catch (e) { note(cascade, list[0], 1, thrown(e), null, Date.now() - t1); throw e }
  }
  const tried: { model: string; why: string }[] = [];
  let spent = 0, lastError: unknown = null;
  for (let i = 0; i < list.length; i++) {
    const model = list[i], left = deadline ? deadline - Date.now() : Infinity;
    // no time for another attempt after this one: this is the last
    const last = i === list.length - 1 || (deadline > 0 && left < 2 * MIN_ATTEMPT_MS);
    const t1 = Date.now();
    try {
      const r = await doFetch(url, { ...init, body: JSON.stringify({ ...body, model }), signal: i === 0 ? init.signal : AbortSignal.timeout(Math.max(1000, Math.min(RETRY_TIMEOUT_MS, left))) });
      // deno-lint-ignore no-explicit-any
      const d: any = await r.json().catch((e) => ({ unreadable: e instanceof Error ? e.message : String(e) }));
      const cost = Number(d?.usage?.cost || 0), why = technicalFailure(r.status, d, wantsJson);
      note(cascade, model, i + 1, why, d, Date.now() - t1);
      if (why && !last) { spent += cost; tried.push({ model, why }); continue }
      const out = { ...d, cf_model_sent: model, cf_cascade_tried: tried, usage: { ...(d?.usage || {}), cost: cost + spent } };
      return new Response(JSON.stringify(out), { status: r.status, headers: { "content-type": "application/json" } });
    } catch (e) {
      lastError = e; note(cascade, model, i + 1, thrown(e), null, Date.now() - t1); tried.push({ model, why: e instanceof Error ? e.message.slice(0, 120) : String(e).slice(0, 120) });
      if (last) throw (spent > 0 && e && typeof e === "object" ? Object.assign(e, { cost: spent }) : e);
    }
    if (last) break;
  }
  throw lastError ?? Error("no model in the cascade");
}
