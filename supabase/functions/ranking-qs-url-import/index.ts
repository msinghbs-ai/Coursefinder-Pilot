import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const VERSION = "ranking-qs-url-import-v2.0.0";
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
  new Response(JSON.stringify(body), { status, headers: { ...cors(req), "content-type": "application/json; charset=utf-8" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return reply(req, 405, { error: "method_not_allowed", worker_version: VERSION });
  const auth = req.headers.get("authorization") || "";
  if (!auth.toLowerCase().startsWith("bearer ")) return reply(req, 401, { error: "authentication_required", worker_version: VERSION });

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anon) return reply(req, 500, { error: "service_configuration_error", worker_version: VERSION });

  const user = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data: ctx, error } = await user.rpc("admin_read", { p_operation: "context", p_args: {} });
  if (error || !ctx?.authenticated) return reply(req, 401, { error: "authentication_required", worker_version: VERSION });
  if (Number(ctx.role_rank || 0) < 4) return reply(req, 403, { error: "pipeline_operator_role_required", worker_version: VERSION });

  const body = await req.json().catch(() => ({}));
  const year = Number(body?.edition_year);
  return reply(req, 410, {
    ok: false,
    error: "qs_url_acquisition_retired",
    detail: "QS ranking ingestion now uses authorised QS workbook Evidence followed by ranking-qs-official-etl. URL acquisition and Parse.bot fallback are retired.",
    edition_year: Number.isInteger(year) ? year : null,
    required_worker: "ranking-qs-official-etl",
    evidence_format: "official/generated QS XLSX",
    historical_evidence_retained: true,
    worker_version: VERSION,
  });
});
