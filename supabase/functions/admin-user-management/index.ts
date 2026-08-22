import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const WORKER_ORIGIN = "https://coursefinder-pilot.techm.workers.dev";
const LOCAL_ORIGINS = new Set(["http://localhost:5173", "http://127.0.0.1:5173"]);
const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function cors(req: Request) {
  const origin = req.headers.get("origin") || "";
  const allowOrigin = origin === WORKER_ORIGIN || LOCAL_ORIGINS.has(origin) ? origin : WORKER_ORIGIN;
  return {
    "access-control-allow-origin": allowOrigin,
    "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
    "access-control-allow-methods": "POST, OPTIONS",
    "cache-control": "no-store",
    "referrer-policy": "no-referrer",
    "vary": "origin",
  };
}

function reply(req: Request, status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(req), "content-type": "application/json; charset=utf-8" },
  });
}

function cleanRoles(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map(v => String(v || "").trim()).filter(Boolean))].slice(0, 6);
}

function parseExpiry(value: unknown): string | null {
  if (value === null || value === undefined || value === "") return null;
  const raw = String(value);
  const date = new Date(raw);
  if (Number.isNaN(date.getTime()) || date.getTime() <= Date.now()) throw new Error("expiry_must_be_future");
  return date.toISOString();
}

async function listAuthUsers(serviceClient: any) {
  const users: any[] = [];
  for (let page = 1; page <= 10; page += 1) {
    const { data, error } = await serviceClient.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw new Error("auth_user_list_failed");
    const batch = data?.users || [];
    users.push(...batch);
    if (batch.length < 200) break;
  }
  return users;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
  if (req.method !== "POST") return reply(req, 405, { error: "method_not_allowed" });

  const authHeader = req.headers.get("authorization") || "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) return reply(req, 401, { error: "authentication_required" });

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return reply(req, 500, { error: "service_configuration_error" });

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const { data: context, error: contextError } = await userClient.rpc("admin_read", { p_operation: "context", p_args: {} });
  if (contextError || !context?.authenticated) return reply(req, 401, { error: "authentication_required" });
  if (Number(context?.role_rank || 0) < 6) return reply(req, 403, { error: "platform_admin_role_required" });

  const actorUserId = String(context?.user_id || "");
  if (!uuidRe.test(actorUserId)) return reply(req, 403, { error: "platform_admin_context_invalid" });

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { return reply(req, 400, { error: "invalid_json" }); }
  const action = String(body?.action || "list").trim().toLowerCase();

  const serviceClient = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

  try {
    if (action === "list") {
      const [authUsers, snapshotResult] = await Promise.all([
        listAuthUsers(serviceClient),
        serviceClient.rpc("svc_admin_access_snapshot"),
      ]);
      if (snapshotResult.error) throw new Error("access_snapshot_failed");
      const snapshot = snapshotResult.data || {};
      const roles = Array.isArray(snapshot.roles) ? snapshot.roles : [];
      const roleRank = new Map(roles.map((r: any) => [r.code, Number(r.rank || 0)]));
      const assignments = Array.isArray(snapshot.assignments) ? snapshot.assignments : [];
      const byUser = new Map<string, any[]>();
      for (const assignment of assignments) {
        const key = String(assignment.user_id || "");
        if (!byUser.has(key)) byUser.set(key, []);
        byUser.get(key)!.push(assignment);
      }
      const now = Date.now();
      const users = authUsers.map((u: any) => {
        const userAssignments = (byUser.get(u.id) || []).map((a: any) => ({
          ...a,
          active: !a.expires_at || new Date(a.expires_at).getTime() > now,
        }));
        const effective = userAssignments.filter((a: any) => a.active).sort((a: any, b: any) => (roleRank.get(b.role_code) || 0) - (roleRank.get(a.role_code) || 0))[0] || null;
        const disabled = Boolean(u.banned_until && new Date(u.banned_until).getTime() > now);
        return {
          id: u.id,
          email: u.email || null,
          created_at: u.created_at || null,
          last_sign_in_at: u.last_sign_in_at || null,
          email_confirmed_at: u.email_confirmed_at || null,
          banned_until: u.banned_until || null,
          disabled,
          roles: userAssignments,
          effective_role: effective ? { code: effective.role_code, name: effective.role_name, rank: roleRank.get(effective.role_code) || effective.rank || 0 } : null,
        };
      }).sort((a: any, b: any) => String(a.email || "").localeCompare(String(b.email || "")));
      const emailById = new Map(users.map((u: any) => [u.id, u.email]));
      const events = (Array.isArray(snapshot.events) ? snapshot.events : []).map((event: any) => ({
        ...event,
        actor_email: emailById.get(String(event.actor_user_id || "")) || null,
        target_email: emailById.get(String(event.target_user_id || "")) || null,
      }));
      return reply(req, 200, { users, roles, events, total: users.length, actor_user_id: actorUserId });
    }

    if (action === "create") {
      const email = String(body?.email || "").trim().toLowerCase();
      const roles = cleanRoles(body?.roles);
      const mode = String(body?.mode || "invite").toLowerCase() === "password" ? "password" : "invite";
      const expiresAt = parseExpiry(body?.expires_at);
      if (!emailRe.test(email)) return reply(req, 400, { error: "valid_email_required" });
      if (!roles.length) return reply(req, 400, { error: "at_least_one_role_required" });

      let createdUser: any = null;
      if (mode === "password") {
        const password = String(body?.password || "");
        if (password.length < 12) return reply(req, 400, { error: "password_minimum_12_characters" });
        const { data, error } = await serviceClient.auth.admin.createUser({
          email,
          password,
          email_confirm: true,
          user_metadata: { created_via: "coursefinder_admin", account_purpose: "managed" },
        });
        if (error || !data?.user) return reply(req, 409, { error: error?.message || "user_create_failed" });
        createdUser = data.user;
      } else {
        const { data, error } = await serviceClient.auth.admin.inviteUserByEmail(email, {
          data: { created_via: "coursefinder_admin", account_purpose: "staff" },
        });
        if (error || !data?.user) return reply(req, 409, { error: error?.message || "user_invite_failed" });
        createdUser = data.user;
      }

      const { data: roleState, error: roleError } = await serviceClient.rpc("svc_admin_access_replace_roles", {
        p_actor_user_id: actorUserId,
        p_target_user_id: createdUser.id,
        p_role_codes: roles,
        p_expires_at: expiresAt,
      });
      if (roleError) {
        await serviceClient.auth.admin.deleteUser(createdUser.id).catch(() => undefined);
        return reply(req, 400, { error: roleError.message || "role_assignment_failed" });
      }

      const eventAction = mode === "password" ? "user_created" : "user_invited";
      await serviceClient.rpc("svc_admin_access_log_event", {
        p_actor_user_id: actorUserId,
        p_target_user_id: createdUser.id,
        p_action: eventAction,
        p_before_state: {},
        p_after_state: { email, roles: roleState?.roles || [], confirmed: mode === "password" },
        p_metadata: { mode },
      });
      return reply(req, 201, { ok: true, user: { id: createdUser.id, email: createdUser.email || email, mode, roles: roleState?.roles || [] } });
    }

    if (action === "roles") {
      const targetUserId = String(body?.user_id || "");
      const roles = cleanRoles(body?.roles);
      const expiresAt = parseExpiry(body?.expires_at);
      if (!uuidRe.test(targetUserId)) return reply(req, 400, { error: "valid_user_id_required" });
      if (!roles.length) return reply(req, 400, { error: "at_least_one_role_required" });
      const { data, error } = await serviceClient.rpc("svc_admin_access_replace_roles", {
        p_actor_user_id: actorUserId,
        p_target_user_id: targetUserId,
        p_role_codes: roles,
        p_expires_at: expiresAt,
      });
      if (error) return reply(req, error.code === "42501" ? 409 : 400, { error: error.message || "role_update_failed" });
      return reply(req, 200, { ok: true, user_id: targetUserId, role_state: data });
    }

    if (action === "disable" || action === "enable") {
      const targetUserId = String(body?.user_id || "");
      if (!uuidRe.test(targetUserId)) return reply(req, 400, { error: "valid_user_id_required" });
      const { data: beforeData, error: beforeError } = await serviceClient.auth.admin.getUserById(targetUserId);
      if (beforeError || !beforeData?.user) return reply(req, 404, { error: "target_user_not_found" });
      const beforeDisabled = Boolean(beforeData.user.banned_until && new Date(beforeData.user.banned_until).getTime() > Date.now());

      if (action === "disable") {
        const { error: guardError } = await serviceClient.rpc("svc_admin_access_guard_disable", {
          p_actor_user_id: actorUserId,
          p_target_user_id: targetUserId,
        });
        if (guardError) return reply(req, 409, { error: guardError.message || "disable_not_allowed" });
      }

      const { data: updated, error: updateError } = await serviceClient.auth.admin.updateUserById(targetUserId, { ban_duration: action === "disable" ? "876000h" : "none" });
      if (updateError || !updated?.user) return reply(req, 400, { error: updateError?.message || `user_${action}_failed` });

      await serviceClient.rpc("svc_admin_access_log_event", {
        p_actor_user_id: actorUserId,
        p_target_user_id: targetUserId,
        p_action: action === "disable" ? "user_disabled" : "user_enabled",
        p_before_state: { disabled: beforeDisabled, banned_until: beforeData.user.banned_until || null },
        p_after_state: { disabled: action === "disable", banned_until: updated.user.banned_until || null },
        p_metadata: {},
      });
      return reply(req, 200, { ok: true, user_id: targetUserId, disabled: action === "disable" });
    }

    return reply(req, 400, { error: "unsupported_action" });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    const status = message === "expiry_must_be_future" ? 400 : 500;
    return reply(req, status, { error: message });
  }
});
