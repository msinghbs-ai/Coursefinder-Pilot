import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL") || "";
  const serviceKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ||
    (() => {
      try {
        return (
          JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}").default || ""
        );
      } catch {
        return "";
      }
    })();
  if (!url || !serviceKey)
    return json({ error: "server configuration unavailable" }, 500);
  const token = (req.headers.get("Authorization") || "").replace(
    /^Bearer\s+/i,
    "",
  );
  const svc = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const nonce = String(req.headers.get("x-cf-run-nonce") || "").trim();
  let authorised = Boolean(token && token === serviceKey);
  if (!authorised && nonce) {
    const { data: consumed, error: nonceError } = await svc.rpc(
      "svc_pilot_consume_nonce",
      { p_function: "layer3-work-dispatch", p_nonce: nonce },
    );
    authorised = !nonceError && consumed === true;
  }
  if (!authorised)
    return json(
      { error: "service role or valid one-time service nonce required" },
      403,
    );

  try {
    const body = await req.json().catch(() => ({}));
    const worker = String(body?.worker || "cf247-layer3-dispatch").trim();
    const limit = Math.min(Math.max(Number(body?.limit || 10), 1), 25);
    const taskClass = "provider_current_tuition_validation";
    const { data: headroom, error: headroomError } = await svc.rpc(
      "layer3_dispatch_headroom_service",
      { p_task_class: taskClass },
    );
    if (headroomError)
      throw new Error(
        `dispatch headroom check failed: ${headroomError.message}`,
      );
    const dispatchHeadroom = Math.max(
      Number(headroom?.dispatch_headroom || 0),
      0,
    );
    if (!headroom?.ok || dispatchHeadroom <= 0) {
      return json({
        ok: true,
        worker,
        task_class: taskClass,
        quota_blocked: true,
        reserved_count: 0,
        dispatched_count: 0,
        headroom,
        results: [],
      });
    }
    const profileId = String(headroom?.profile_id || "");
    if (!profileId)
      return json({ error: "resolved model profile id unavailable" }, 500);
    const boundedLimit = Math.min(limit, dispatchHeadroom);
    const budgetMs = 240000;
    const startedAt = Date.now();
    const interpreterTimeoutMs = 110000;
    const dbTransitionSafetyMarginMs = 5000;
    const requiredRemainingMs =
      interpreterTimeoutMs + dbTransitionSafetyMarginMs;
    const items: unknown[] = [];
    const results: unknown[] = [];
    for (let reservedCount = 0; reservedCount < boundedLimit; reservedCount++) {
      if (budgetMs - (Date.now() - startedAt) < requiredRemainingMs) break;
      const { data: reserved, error } = await svc.rpc(
        "layer3_reserve_scoped_work_service",
        {
          p_worker: worker,
          p_task_class: taskClass,
          p_profile_id: profileId,
          p_limit: 1,
        },
      );
      if (error) throw new Error(`work reservation failed: ${error.message}`);
      const batch = Array.isArray(reserved) ? reserved : [];
      if (batch.length === 0) break;
      const item = batch[0];
      items.push(item);
      const workItemId = String(item?.id || "");
      if (!workItemId) continue;
      const failWorkItem = async (err: string) => {
        // CF-247 WP2b: supabase-js rpc() returns a query builder, not a Promise,
        // so it has no .catch(); chaining one threw and aborted the whole batch
        // whenever a single item failed. rpc() reports errors in its result, so
        // a plain try/catch keeps this best-effort backstop from ever throwing.
        try {
        const first = await svc
          .rpc("layer3_work_item_transition_service", {
            p_work_item_id: workItemId,
            p_from_status: "reserved",
            p_to_status: "failed",
            p_interpretation_id: null,
            p_error: err.slice(0, 1900),
            p_retry_after_seconds: 60,
          });
        if (!(first as any)?.data?.ok) {
          await svc
            .rpc("layer3_work_item_transition_service", {
              p_work_item_id: workItemId,
              p_from_status: "interpreting",
              p_to_status: "failed",
              p_interpretation_id: null,
              p_error: err.slice(0, 1900),
              p_retry_after_seconds: 60,
            });
        }
        } catch {
          /* best effort: the interpreter records its own failure state */
        }
      };
      try {
        const controller = new AbortController();
        const timeout = setTimeout(
          () => controller.abort(),
          interpreterTimeoutMs,
        );
        let response: Response;
        try {
          response = await fetch(`${url}/functions/v1/layer3-work-interpret`, {
            method: "POST",
            signal: controller.signal,
            headers: {
              Authorization: `Bearer ${serviceKey}`,
              apikey: serviceKey,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ work_item_id: workItemId, worker }),
          });
        } finally {
          clearTimeout(timeout);
        }
        const payload = await response.json().catch(() => ({}));
        if (!response.ok) {
          await failWorkItem(
            `interpreter HTTP ${response.status}: ${JSON.stringify(payload).slice(0, 1500)}`,
          );
        }
        results.push({
          work_item_id: workItemId,
          http_status: response.status,
          result: payload,
        });
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        await failWorkItem(`dispatcher invocation failed: ${message}`);
        results.push({
          work_item_id: workItemId,
          http_status: null,
          error: message,
        });
      }
    }
    return json({
      ok: true,
      worker,
      task_class: taskClass,
      quota_blocked: false,
      headroom,
      reserved_count: items.length,
      dispatched_count: results.length,
      results,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
