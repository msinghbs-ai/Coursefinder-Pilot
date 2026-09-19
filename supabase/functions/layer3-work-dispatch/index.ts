import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL") || "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || (() => { try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default || ""; } catch { return ""; } })();
  if (!url || !serviceKey) return json({ error: "server configuration unavailable" }, 500);
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const svc = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const nonce = String(req.headers.get("x-cf-run-nonce") || "").trim();
  let authorised = Boolean(token && token === serviceKey);
  if (!authorised && nonce) {
    const { data: consumed, error: nonceError } = await svc.rpc("svc_pilot_consume_nonce", { p_function: "layer3-work-dispatch", p_nonce: nonce });
    authorised = !nonceError && consumed === true;
  }
  if (!authorised) return json({ error: "service role or valid one-time service nonce required" }, 403);

  try {
    const body = await req.json().catch(() => ({}));
    const worker = String(body?.worker || "cf247-layer3-dispatch").trim();
    const limit = Math.min(Math.max(Number(body?.limit || 10), 1), 25);
    const taskClass = "provider_current_tuition_validation";
    const { data: headroom, error: headroomError } = await svc.rpc("layer3_dispatch_headroom_service", { p_task_class: taskClass });
    if (headroomError) throw new Error(`dispatch headroom check failed: ${headroomError.message}`);
    const dispatchHeadroom = Math.max(Number(headroom?.dispatch_headroom || 0), 0);
    if (!headroom?.ok || dispatchHeadroom <= 0) {
      return json({ ok: true, worker, task_class: taskClass, quota_blocked: true, reserved_count: 0, dispatched_count: 0, headroom, results: [] });
    }
    const boundedLimit = Math.min(limit, dispatchHeadroom);
    const { data: reserved, error } = await svc.rpc("layer3_reserve_work_service", { p_worker: worker, p_limit: boundedLimit });
    if (error) throw new Error(`work reservation failed: ${error.message}`);
    const items = Array.isArray(reserved) ? reserved : [];
    const results: unknown[] = [];
    for (const item of items) {
      const workItemId = String(item?.id || "");
      if (!workItemId) continue;
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 110000);
        let response: Response;
        try {
          response = await fetch(`${url}/functions/v1/layer3-work-interpret`, {
            method: "POST",
            signal: controller.signal,
            headers: { Authorization: `Bearer ${serviceKey}`, apikey: serviceKey, "Content-Type": "application/json" },
            body: JSON.stringify({ work_item_id: workItemId, worker }),
          });
        } finally { clearTimeout(timeout); }
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) {
          await svc.rpc("layer3_work_item_transition_service", { p_work_item_id: workItemId, p_from_status: "reserved", p_to_status: "failed", p_interpretation_id: null, p_error: `interpreter HTTP ${response.status}: ${JSON.stringify(payload).slice(0, 1500)}`, p_retry_after_seconds: 60 }).catch(() => undefined);
        }
        results.push({ work_item_id: workItemId, http_status: response.status, result: payload });
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        await svc.rpc("layer3_work_item_transition_service", { p_work_item_id: workItemId, p_from_status: "reserved", p_to_status: "failed", p_interpretation_id: null, p_error: `dispatcher invocation failed: ${message}`.slice(0, 1900), p_retry_after_seconds: 60 }).catch(() => undefined);
        results.push({ work_item_id: workItemId, http_status: null, error: message });
      }
    }
    return json({ ok: true, worker, task_class: taskClass, quota_blocked: false, headroom, reserved_count: items.length, dispatched_count: results.length, results });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
