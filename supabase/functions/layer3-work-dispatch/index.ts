import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL") || "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || (() => { try { return JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default || ""; } catch { return ""; } })();
  if (!url || !serviceKey) return json({ error: "server configuration unavailable" }, 500);
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token || token !== serviceKey) return json({ error: "service role required" }, 403);

  const svc = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  try {
    const body = await req.json().catch(() => ({}));
    const worker = String(body?.worker || "cf247-layer3-dispatch").trim();
    const limit = Math.min(Math.max(Number(body?.limit || 10), 1), 25);
    const { data: reserved, error } = await svc.rpc("layer3_reserve_work_service", { p_worker: worker, p_limit: limit });
    if (error) throw new Error(`work reservation failed: ${error.message}`);
    const items = Array.isArray(reserved) ? reserved : [];
    const results: unknown[] = [];
    for (const item of items) {
      const workItemId = String(item?.id || "");
      if (!workItemId) continue;
      try {
        const response = await fetch(`${url}/functions/v1/layer3-work-interpret`, {
          method: "POST",
          headers: { Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" },
          body: JSON.stringify({ work_item_id: workItemId, worker }),
        });
        const payload = await response.json().catch(() => ({}));
        results.push({ work_item_id: workItemId, http_status: response.status, result: payload });
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        await svc.rpc("layer3_work_item_transition_service", { p_work_item_id: workItemId, p_from_status: "reserved", p_to_status: "failed", p_interpretation_id: null, p_error: `dispatcher invocation failed: ${message}`.slice(0, 1900), p_retry_after_seconds: 60 }).catch(() => undefined);
        results.push({ work_item_id: workItemId, http_status: null, error: message });
      }
    }
    return json({ ok: true, worker, reserved_count: items.length, dispatched_count: results.length, results });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
