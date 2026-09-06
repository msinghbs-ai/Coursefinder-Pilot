import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const VERSION = "ranking-publisher-url-import-v2.0.0";
const ORIGIN = "https://coursefinder-pilot.techm.workers.dev";
const LOCAL = new Set(["http://localhost:5173", "http://127.0.0.1:5173"]);

const cors = (req: Request) => {
  const origin = req.headers.get("origin") || "";
  const allow = origin === ORIGIN || LOCAL.has(origin) ? origin : ORIGIN;
  return {
    "access-control-allow-origin": allow,
    "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
    "access-control-allow-methods": "POST, OPTIONS",
    "cache-control": "no-store",
    "vary": "origin",
  };
};

const reply = (req: Request, status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(req), "content-type": "application/json; charset=utf-8" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return reply(req, 405, { error: "method_not_allowed", worker_version: VERSION });

  const auth = req.headers.get("authorization") || "";
  if (!auth.toLowerCase().startsWith("bearer ")) {
    return reply(req, 401, { error: "authentication_required", worker_version: VERSION });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anon) return reply(req, 500, { error: "service_configuration_error", worker_version: VERSION });

  const user = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data: ctx, error: ctxErr } = await user.rpc("admin_read", { p_operation: "context", p_args: {} });
  if (ctxErr || !ctx?.authenticated) {
    return reply(req, 401, { error: "authentication_required", worker_version: VERSION });
  }
  if (Number(ctx.role_rank || 0) < 4) {
    return reply(req, 403, { error: "pipeline_operator_role_required", worker_version: VERSION });
  }

  const body = await req.json().catch(() => ({}));
  const systemCode = String(body?.system_code || "").trim().toLowerCase();
  const editionYear = Number(body?.edition_year);

  return reply(req, 410, {
    ok: false,
    error: "ranking_url_acquisition_retired",
    detail: "CourseFinder ranking ingestion is Evidence-first Layer 1 ETL. Upload authorised publisher Evidence and run the ranking Layer 1 ETL. Parse.bot is excluded from ranking acquisition.",
    system_code: systemCode || null,
    edition_year: Number.isInteger(editionYear) ? editionYear : null,
    supported_layer1_workers: {
      qs_wur: "ranking-qs-official-etl",
      the_wur: "ranking-the-official-etl",
      arwu: "ranking-layer1-etl",
    },
    historical_parsebot_evidence_retained: true,
    worker_version: VERSION,
  });
});
