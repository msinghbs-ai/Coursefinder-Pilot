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

// v1.0.3 (15 Nov 2026, Platform Admin 12:53): an OpenRouter key or budget limit refusal is an ACCOUNT stop, not a failure of the model or the item.
// OpenRouter answers 402 or 403 with "Key limit exceeded" (or error.metadata.limit_source openrouter_key_limit) once the key's own limit or a budget
// over it is used up; every model of every cascade goes through the same key, so asking the next model only repeats the refusal. On the first one:
// the attempt is noted with failure kind key_limit (left out of the model health counts), no other model is asked, the worker call stops asking
// (every later call of this worker call is refused here without being sent), the caller gets a KeyLimitStop error and gives its items back to the
// queue (svc_ai_key_limit_release_v1), and the refusal is recorded (svc_openrouter_key_record_v1), so security.ai_route_v1 holds AI work until the
// key has room again.
const KEY_LIMIT_TEXT = /key limit exceeded/i;
export const KEY_LIMIT_MARK = "OpenRouter key limit";
// deno-lint-ignore no-explicit-any
export function keyLimitRefusal(status: number, d: any): string | null {
  if (status !== 402 && status !== 403) return null;
  const msg = String(d?.error?.message ?? d?.message ?? "");
  const source = String(d?.error?.metadata?.limit_source ?? d?.metadata?.limit_source ?? "");
  if (!KEY_LIMIT_TEXT.test(msg) && source !== "openrouter_key_limit") return null;
  // the key's own words (they name the limit and what is used); the key management address in them is left out
  return `${KEY_LIMIT_MARK} (HTTP ${status}): ${msg.replace(/https?:\/\/\S+/g, "").replace(/\s+/g, " ").trim() || source}`.slice(0, 300);
}
export class KeyLimitStop extends Error {
  constructor(why: string) { super(why.startsWith(KEY_LIMIT_MARK) ? why : `${KEY_LIMIT_MARK}: ${why}`); this.name = "KeyLimitStop" }
}
// an error, or a text a lane made from one ("held_partial: ... slice 1 of 2: OpenRouter key limit ..."), that a key limit refusal caused
export function isKeyLimit(e: unknown): boolean {
  if (e instanceof KeyLimitStop) return true;
  const t = e instanceof Error ? e.message : typeof e === "string" ? e : "";
  return !!t && (t.includes(KEY_LIMIT_MARK) || KEY_LIMIT_TEXT.test(t));
}
let keyStop: { why: string; status: number; at: string } | null = null;
export const keyStopped = () => keyStop;
export const resetKeyStop = () => { keyStop = null };
// "$70.01 of $70.00 used": what the refusal says of the limit, for the record
export function keyLimitFigures(why: string): { used_usd: number | null; limit_usd: number | null } {
  const m = /\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s+of\s+\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s+used/i.exec(why);
  const n = (s?: string) => s == null ? null : Number(s.replace(/,/g, ""));
  return { used_usd: n(m?.[1]), limit_usd: n(m?.[2]) };
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
// v1.0.5 (16 Nov 2026, Platform Admin 12:36, "per-attempt ledger flush"): each attempt is written to pipeline.ai_invocations as soon as it is noted,
// through the writer the worker sets for its call (public.svc_ai_model_answered_v1), so a call the platform stops part-way (HTTP 546, worker
// resource limit) no longer loses the attempts it had already paid for. Rows the writer could not hand over (an error answer) stay in the trace and go
// with the end-of-call write as before. A write that timed out is not sent again (it may have been kept), so an attempt is never counted twice.
type TraceWriter = (rows: Attempt[]) => Promise<void>;
let traceWriter: TraceWriter | null = null;
const TRACE_WRITE_MS = 5000; // fixed: API time-out of one attempt write; a slower write is left to the end-of-call write path
export const setTraceWriter = (w: TraceWriter | null): void => { traceWriter = w };
export const traceStats = { written: 0, kept_for_end: 0, uncertain: 0 };
export async function flushAiTrace(): Promise<void> {
  if (!traceWriter || !trace.length) return;
  const rows = trace.splice(0, trace.length);
  let timer: number | undefined;
  try {
    const timedOut = new Promise<"timeout">((res) => { timer = setTimeout(() => res("timeout"), TRACE_WRITE_MS) });
    const r = await Promise.race([traceWriter(rows).then(() => "ok" as const), timedOut]);
    if (r === "timeout") traceStats.uncertain += rows.length; else traceStats.written += rows.length;
  } catch {
    trace.unshift(...rows); traceStats.kept_for_end += rows.length;  // refused: kept for the end-of-call write
  } finally { if (timer !== undefined) clearTimeout(timer) }
}
export function failureKind(why: string): string {
  if (why.startsWith(KEY_LIMIT_MARK)) return "key_limit";  // v1.0.3: an account stop; job ai-model-health leaves it out of the model's counts
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
  if (keyStop) throw new KeyLimitStop(keyStop.why);  // v1.0.3: the key refused earlier in this worker call: nothing more is sent
  if (list.length < 2) {  // one model: exactly the call as it was; the attempt is noted from a copy of the answer
    const t1 = Date.now();
    let r: Response;
    try {
      r = await doFetch(url, init);
    } catch (e) { note(cascade, list[0], 1, thrown(e), null, Date.now() - t1); await flushAiTrace(); throw e }
    // deno-lint-ignore no-explicit-any
    const d: any = await r.clone().json().catch(() => ({ unreadable: true }));
    const kl = keyLimitRefusal(r.status, d);
    note(cascade, list[0], 1, kl ?? technicalFailure(r.status, d, wantsJson), d, Date.now() - t1);
    await flushAiTrace();  // v1.0.5: written as it completes
    if (kl) { keyStop = { why: kl, status: r.status, at: new Date().toISOString() }; throw new KeyLimitStop(kl) }
    return r;
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
      const kl = keyLimitRefusal(r.status, d);
      const cost = Number(d?.usage?.cost || 0), why = kl ?? technicalFailure(r.status, d, wantsJson);
      note(cascade, model, i + 1, why, d, Date.now() - t1);
      await flushAiTrace();  // v1.0.5: written as it completes, the paid failures too
      if (kl) {  // v1.0.3: every model goes through the same key: no other model is asked; the cost of earlier failed attempts stays with the error
        keyStop = { why: kl, status: r.status, at: new Date().toISOString() };
        throw Object.assign(new KeyLimitStop(kl), { cost: cost + spent });
      }
      if (why && !last) { spent += cost; tried.push({ model, why }); continue }
      const out = { ...d, cf_model_sent: model, cf_cascade_tried: tried, usage: { ...(d?.usage || {}), cost: cost + spent } };
      return new Response(JSON.stringify(out), { status: r.status, headers: { "content-type": "application/json" } });
    } catch (e) {
      if (e instanceof KeyLimitStop) throw e;  // v1.0.3: noted above; no other model is asked
      lastError = e; note(cascade, model, i + 1, thrown(e), null, Date.now() - t1); await flushAiTrace(); tried.push({ model, why: e instanceof Error ? e.message.slice(0, 120) : String(e).slice(0, 120) });
      if (last) throw (spent > 0 && e && typeof e === "object" ? Object.assign(e, { cost: spent }) : e);
    }
    if (last) break;
  }
  throw lastError ?? Error("no model in the cascade");
}
