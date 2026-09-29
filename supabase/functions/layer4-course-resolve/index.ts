import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "method not allowed" }), { status: 405, headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return new Response(JSON.stringify({ error: "authentication required" }), { status: 401, headers: cors });

    const svc = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: userData, error: userError } = await svc.auth.getUser(token);
    if (userError || !userData?.user?.id) return new Response(JSON.stringify({ error: "invalid user token" }), { status: 401, headers: cors });

    const body = await req.json();
    const courseId = String(body?.course_id || "");
    const fieldCode = String(body?.field_code || "");
    const reason = String(body?.reason || "");
    if (!courseId || !fieldCode || body?.value === undefined) return new Response(JSON.stringify({ error: "course_id, field_code and value are required" }), { status: 400, headers: cors });

    const { data, error } = await svc.rpc("layer4_course_scalar_resolve_service", {
      p_actor: userData.user.id,
      p_course_id: courseId,
      p_field_code: fieldCode,
      p_value: body.value,
      p_reason: reason,
    });
    if (error) {
      const status = /role required|actor required|permission/i.test(error.message || "") ? 403 : 400;
      return new Response(JSON.stringify({ error: error.message }), { status, headers: cors });
    }
    return new Response(JSON.stringify(data), { status: 200, headers: cors });
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }), { status: 500, headers: cors });
  }
});
