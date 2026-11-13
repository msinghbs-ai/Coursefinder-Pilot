// CF-247 (13 Nov 2026, Platform Admin 19:14 "Service based Model with cascading"): one rule for every OpenRouter call that has a cascade.
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
export type Cascade = { models: unknown; deadline?: number } | null | undefined;

export async function cascadeFetch(doFetch: FetchFn, cascade: Cascade, url: string, init: RequestInit): Promise<Response> {
  const models = cascade?.models, deadline = Number(cascade?.deadline) || 0;
  // deno-lint-ignore no-explicit-any
  let body: any; try { body = JSON.parse(String(init.body)) } catch { return doFetch(url, init) }
  const list = cascadeModels(String(body?.model || ""), models);
  if (list.length < 2) return doFetch(url, init);  // one model: exactly the call as it was
  const wantsJson = !!body.response_format, tried: { model: string; why: string }[] = [];
  let spent = 0, lastError: unknown = null;
  for (let i = 0; i < list.length; i++) {
    const model = list[i], left = deadline ? deadline - Date.now() : Infinity;
    // no time for another attempt after this one: this is the last
    const last = i === list.length - 1 || (deadline > 0 && left < 2 * MIN_ATTEMPT_MS);
    try {
      const r = await doFetch(url, { ...init, body: JSON.stringify({ ...body, model }), signal: i === 0 ? init.signal : AbortSignal.timeout(Math.max(1000, Math.min(RETRY_TIMEOUT_MS, left))) });
      // deno-lint-ignore no-explicit-any
      const d: any = await r.json().catch((e) => ({ unreadable: e instanceof Error ? e.message : String(e) }));
      const cost = Number(d?.usage?.cost || 0), why = technicalFailure(r.status, d, wantsJson);
      if (why && !last) { spent += cost; tried.push({ model, why }); continue }
      const out = { ...d, cf_model_sent: model, cf_cascade_tried: tried, usage: { ...(d?.usage || {}), cost: cost + spent } };
      return new Response(JSON.stringify(out), { status: r.status, headers: { "content-type": "application/json" } });
    } catch (e) {
      lastError = e; tried.push({ model, why: e instanceof Error ? e.message.slice(0, 120) : String(e).slice(0, 120) });
      if (last) throw (spent > 0 && e && typeof e === "object" ? Object.assign(e, { cost: spent }) : e);
    }
    if (last) break;
  }
  throw lastError ?? Error("no model in the cascade");
}
