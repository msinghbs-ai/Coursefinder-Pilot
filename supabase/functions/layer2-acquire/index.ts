import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const ORIGIN = "https://coursefinder-pilot.techm.workers.dev";
const cors = (req: Request) => {
  const origin = req.headers.get("origin") || "";
  return {
    "access-control-allow-origin": origin === ORIGIN || origin.startsWith("http://localhost") ? origin : ORIGIN,
    "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
    "access-control-allow-methods": "POST, OPTIONS",
    "content-type": "application/json",
    "cache-control": "no-store",
    "vary": "origin",
  };
};
const json = (req: Request, status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: cors(req) });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return json(req, 405, { error: "method_not_allowed" });

  const auth = req.headers.get("authorization") || "";
  if (!/^Bearer /i.test(auth)) return json(req, 401, { error: "authentication_required" });

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anon) return json(req, 500, { error: "service_configuration_error" });

  const user = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: ctx, error: contextError } = await user.rpc("admin_read", { p_operation: "context", p_args: {} });
  if (contextError || !ctx?.authenticated) return json(req, 401, { error: "authentication_required" });
  if (Number(ctx.role_rank || 0) < 4) return json(req, 403, { error: "pipeline_operator_role_required" });

  let body: unknown;
  try { body = await req.json(); } catch { return json(req, 400, { error: "invalid_json" }); }

  const upstream = await fetch(`${url}/functions/v1/layer2-acquire-v2`, {
    method: "POST",
    headers: {
      "authorization": auth,
      "apikey": anon,
      "content-type": "application/json",
      "x-client-info": "coursefinder-layer2-acquire-compat/2.0",
    },
    body: JSON.stringify(body),
  });

  const text = await upstream.text();
  let payload: any;
  try { payload = text ? JSON.parse(text) : {}; } catch { payload = { error: "invalid_upstream_response", detail: text.slice(0, 500) }; }

  return json(req, upstream.status, {
    ...payload,
    compatibility_endpoint: "layer2-acquire",
    runtime_endpoint: "layer2-acquire-v2",
  });
});
