import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const WORKER_ORIGIN = "https://coursefinder-pilot.techm.workers.dev";
const LOCAL_ORIGINS = new Set(["http://localhost:5173", "http://127.0.0.1:5173"]);
// CF-247 invite and reset links (Platform Admin 16 Nov 2026 22:12): every Supabase Auth email this function sends returns the person to the
// admin sign-in on the Cloudflare Worker, never to the Supabase project address. ADMIN_LOGIN_URL may override it (an https address that is not
// a supabase.co one); otherwise the Worker origin above. Supabase Auth honours redirectTo only if the address is in Authentication > URL
// Configuration > Redirect URLs (a dashboard setting; admin repo docs/paste/PASTE-20261117-supabase-invite-email-template.md).
function adminLoginUrl(): string {
  const raw = String(Deno.env.get("ADMIN_LOGIN_URL") || "").trim();
  try {
    const u = new URL(raw);
    if (u.protocol === "https:" && !/(^|\.)supabase\.co$/i.test(u.hostname)) return u.origin + (u.pathname.endsWith("/") ? u.pathname : u.pathname + "/");
  } catch { /* not set or not an address: the Worker origin */ }
  return WORKER_ORIGIN + "/";
}
// The in-app Platform guide (nav-map slug platform-guide), sent with an invitation as {{ .Data.guide_url }}
const guideUrl = (login: string) => login + "#platform-guide";
// v2.16.20 (Platform Admin 17 Nov 2026 14:40): Users & roles › Links & Email Templates. The saved templates use five plain tokens; Supabase Auth
// wants its own. {{guide_link}} is written in as the saved address; the others become the Auth variables the invitation and the reset already fill.
const TEMPLATE_TOKENS: Record<string, string> = { link: "{{ .ConfirmationURL }}", user_email: "{{ .Email }}", user_name: "{{ .Data.full_name }}", role: "{{ .Data.role }}" };
const escHtml = (v: string) => v.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
function toAuthTemplate(text: string, guideLink: string): string {
  return String(text || "")
    // v2.16.22 (Platform Admin 17 Nov 2026 16:13): a person with no name leaves no stray comma or space. "Welcome, {{user_name}}" reads "Welcome".
    .replace(/(,?[ ]?)\{\{\s*user_name\s*\}\}/g, (_m, lead) => `{{ if .Data.full_name }}${lead}{{ .Data.full_name }}{{ end }}`)
    .replace(/\{\{\s*(link|guide_link|user_email|role)\s*\}\}/g, (_m, t) => t === "guide_link" ? escHtml(guideLink) : TEMPLATE_TOKENS[t]);
}
// A Supabase personal access token with access to this project, kept as an Edge Function secret (a secret's name cannot begin SUPABASE_)
const managementToken = () => String(Deno.env.get("SB_MANAGEMENT_TOKEN") || "").trim();
const projectRef = (url: string) => { try { return new URL(url).hostname.split(".")[0]; } catch { return ""; } };
// v2.16.23 (Platform Admin 17 Nov 2026 16:24): email delivery provider. With Resend chosen, a from address and a key (saved on Links & Email
// Templates and kept in Vault, or the Edge Function secret RESEND_API_KEY), invitations and resets are written from the saved templates and sent
// through Resend with the saved sender name. Otherwise Supabase's built-in mail service sends them, as before. The key is never returned or logged.
type Delivery = { configured: string; effective: "resend" | "supabase"; key: string; keySource: "saved" | "edge_secret" | null; senderName: string; fromEmail: string; templates: any; guideLink: string };
async function loadDelivery(serviceClient: any): Promise<Delivery> {
  const [{ data: d }, { data: tpl }] = await Promise.all([serviceClient.rpc("svc_admin_email_delivery"), serviceClient.rpc("svc_admin_auth_template_settings")]);
  const saved = String(d?.resend_api_key || "").trim(), env = String(Deno.env.get("RESEND_API_KEY") || "").trim();
  const key = saved || env, fromEmail = String(d?.from_email || "").trim();
  const configured = d?.email_provider === "resend" ? "resend" : "supabase";
  return { configured, effective: configured === "resend" && key && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(fromEmail) ? "resend" : "supabase", key,
    keySource: saved ? "saved" : env ? "edge_secret" : null, senderName: String(d?.sender_name || "StudySearch PIM Admin"), fromEmail,
    templates: tpl?.templates || null, guideLink: String(tpl?.guide_link || "") };
}
// One saved template with a person's values written in. In the body every value is HTML-escaped; a missing name takes its comma or space with it.
function renderEmail(text: string, v: Record<string, string>, html: boolean): string {
  const out = (x: string) => html ? escHtml(x) : x;
  return String(text || "")
    .replace(/(,?[ ]?)\{\{\s*user_name\s*\}\}/g, (_m, lead) => v.user_name ? lead + out(v.user_name) : "")
    .replace(/\{\{\s*(link|guide_link|user_email|role)\s*\}\}/g, (_m, t) => out(String(v[t] || "")));
}
async function sendViaResend(d: Delivery, to: string, kind: "invite" | "recovery", v: Record<string, string>, subjectPrefix = ""): Promise<void> {
  const t = d.templates?.[kind];
  if (!t?.subject || !t?.body) throw new Error("email_template_not_found");
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${d.key}`, "content-type": "application/json" },
    body: JSON.stringify({ from: `${d.senderName} <${d.fromEmail}>`, to: [to], subject: subjectPrefix + renderEmail(t.subject, v, false), html: renderEmail(t.body, v, true) }),
    signal: AbortSignal.timeout(15000), // fixed: API time-out
  });
  if (!r.ok) {
    const j: any = await r.json().catch(() => ({}));
    throw new Error(`resend_${r.status}_${String(j?.name || j?.message || "send_failed").replace(/re_[A-Za-z0-9_-]+/g, "re_…").slice(0, 160)}`);
  }
}
const SYSTEM_EMAIL = /\.invalid$/i;
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
    // v2.16.20: Links & Email Templates. Where links return to and whether a save can be copied to Supabase Auth from here.
    if (action === "auth_templates_status") {
      const d = await loadDelivery(serviceClient);
      return reply(req, 200, { ok: true, login_url: adminLoginUrl(), management_token_configured: managementToken().length > 0,
        delivery: { configured: d.configured, effective: d.effective, key_source: d.keySource, sender_name: d.senderName, from_email: d.fromEmail } });
    }
    // Copy the saved settings to Supabase Auth (site_url, and the Invite user and Reset password subjects and bodies). The save itself, with its
    // reason, is public.admin_auth_template_settings_save; this only pushes what is saved. Without a management token nothing is changed.
    if (action === "auth_templates_sync") {
      const { data: tpl, error: tplError } = await serviceClient.rpc("svc_admin_auth_template_settings");
      if (tplError || !tpl?.templates) throw new Error("auth_template_settings_failed");
      const token = managementToken(), ref = projectRef(url);
      let synced = false, note = "management_token_not_configured";
      if (token && ref) {
        const guide = String(tpl.guide_link || "");
        const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/config/auth`, {
          method: "PATCH",
          headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
          body: JSON.stringify({
            site_url: String(tpl.site_url),
            mailer_subjects_invite: toAuthTemplate(tpl.templates.invite.subject, guide),
            mailer_templates_invite_content: toAuthTemplate(tpl.templates.invite.body, guide),
            mailer_subjects_recovery: toAuthTemplate(tpl.templates.recovery.subject, guide),
            mailer_templates_recovery_content: toAuthTemplate(tpl.templates.recovery.body, guide),
          }),
          signal: AbortSignal.timeout(15000), // fixed: API time-out
        });
        synced = r.ok; note = r.ok ? "synced" : `management_api_${r.status}`;
      }
      await serviceClient.rpc("svc_admin_auth_template_log", { p_actor: actorUserId, p_action: "auth_templates_sync", p_detail: { synced, note, site_url: tpl.site_url } });
      return reply(req, 200, { ok: true, synced, note });
    }
    // Send the Reset password email to an existing account (the signed-in admin by default), through Supabase Auth, so the real template is what
    // arrives. An invitation cannot be tested this way: Auth only sends one by creating the account.
    if (action === "auth_template_test") {
      const template = String(body?.template || "recovery");
      const { data: me } = await serviceClient.auth.admin.getUserById(actorUserId);
      const to = String(body?.to || me?.user?.email || "").trim().toLowerCase();
      if (!emailRe.test(to) || SYSTEM_EMAIL.test(to)) return reply(req, 400, { error: "valid_test_email_required" });
      // v2.16.23: through Resend either saved template can be tested, to any address, with sample values and a link that signs nobody in
      const delivery = await loadDelivery(serviceClient);
      if (delivery.effective === "resend") {
        if (template !== "invite" && template !== "recovery") return reply(req, 400, { error: "template_is_invite_or_recovery" });
        const login = adminLoginUrl();
        let note = "sent";
        try {
          await sendViaResend(delivery, to, template, { link: login + "#test-email-link-signs-nobody-in", guide_link: delivery.guideLink || guideUrl(login),
            user_email: to, user_name: String(me?.user?.user_metadata?.full_name || ""), role: "Platform Admin" }, "[Test] ");
        } catch (e) { note = e instanceof Error ? e.message : "send_failed"; }
        await serviceClient.rpc("svc_admin_auth_template_log", { p_actor: actorUserId, p_action: "auth_template_test", p_detail: { template, sent_to: to, provider: "resend", synced: note === "sent", note } });
        if (note !== "sent") return reply(req, 400, { error: note });
        return reply(req, 200, { ok: true, sent_to: to, template, provider: "resend" });
      }
      if (template !== "recovery") return reply(req, 409, { error: "an_invitation_is_tested_by_inviting_a_new_address_from_create_user" });
      const known = (await listAuthUsers(serviceClient)).some((u: any) => String(u.email || "").toLowerCase() === to && !u.deleted_at);
      if (!known) return reply(req, 409, { error: "test_address_has_no_account_a_reset_email_only_goes_to_an_existing_user" });
      const { error: testError } = await serviceClient.auth.resetPasswordForEmail(to, { redirectTo: adminLoginUrl() });
      await serviceClient.rpc("svc_admin_auth_template_log", { p_actor: actorUserId, p_action: "auth_template_test", p_detail: { template, sent_to: to, synced: !testError, note: testError ? String(testError.message || "send_failed") : "sent" } });
      if (testError) return reply(req, 400, { error: testError.message || "test_email_failed" });
      return reply(req, 200, { ok: true, sent_to: to, template });
    }
    if (action === "list") {
      const [authUsersAll, snapshotResult, deletedResult, activeResult] = await Promise.all([
        listAuthUsers(serviceClient),
        serviceClient.rpc("svc_admin_access_snapshot"),
        serviceClient.rpc("svc_admin_access_deleted"),
        // 22 Oct 2026 (Platform Admin "Sujata last login was yesterday"): sign-in only changes when a password is typed; sessions refresh
        serviceClient.rpc("svc_admin_access_last_active"),
      ]);
      const lastActive: Record<string, string> = (activeResult && !activeResult.error && activeResult.data) || {};
      // 16 Oct 2026: deleted users (removed or soft-deleted) leave the list
      const deletedIds = new Set<string>(Array.isArray(deletedResult.data?.ids) ? deletedResult.data.ids.map(String) : []);
      const authUsers = authUsersAll.filter((u: any) => !u.deleted_at && !deletedIds.has(String(u.id)));
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
          last_active_at: lastActive[String(u.id)] || u.last_sign_in_at || null,
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
      return reply(req, 200, { users, roles, events, deletions: deletedResult.data?.recent || [], total: users.length, actor_user_id: actorUserId });
    }

    if (action === "create") {
      const email = String(body?.email || "").trim().toLowerCase();
      const roles = cleanRoles(body?.roles);
      const mode = String(body?.mode || "invite").toLowerCase() === "password" ? "password" : "invite";
      const expiresAt = parseExpiry(body?.expires_at);
      const fullName = String(body?.full_name || "").replace(/\s+/g, " ").trim().slice(0, 120);
      if (!emailRe.test(email)) return reply(req, 400, { error: "valid_email_required" });
      if (!roles.length) return reply(req, 400, { error: "at_least_one_role_required" });

      let createdUser: any = null;
      let sentBy = "supabase";
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
        // the invitation's template reads {{ .Data.role }}, {{ .Data.full_name }} and {{ .Data.guide_url }}; the role is the highest selected one
        const { data: snap } = await serviceClient.rpc("svc_admin_access_snapshot");
        const known = (Array.isArray(snap?.roles) ? snap.roles : []).filter((r: any) => roles.includes(String(r.code)));
        const top = known.sort((a: any, b: any) => Number(b.rank || 0) - Number(a.rank || 0))[0] || null;
        const login = adminLoginUrl();
        const { data: savedTpl } = await serviceClient.rpc("svc_admin_auth_template_settings");
        const savedGuide = String(savedTpl?.guide_link || "");
        const inviteData = {
            created_via: "coursefinder_admin",
            account_purpose: "staff",
            role: top ? String(top.name || top.code) : roles[0],
            role_code: top ? String(top.code) : roles[0],
            guide_url: guideUrl(login),
            full_name: fullName || null,
            // v2.16.20: the Admin guide link saved on Users & roles › Links & Email Templates, when there is one
            ...(savedGuide ? { guide_url: savedGuide } : {}),
        };
        const delivery = await loadDelivery(serviceClient);
        if (delivery.effective === "resend") {
          // v2.16.23: Supabase Auth makes the account and the single-use link without sending; the email goes through Resend from the saved template
          const { data, error } = await serviceClient.auth.admin.generateLink({ type: "invite", email, options: { redirectTo: login, data: inviteData } });
          const link = String(data?.properties?.action_link || "");
          if (error || !data?.user || !link) return reply(req, 409, { error: error?.message || "user_invite_failed" });
          try {
            await sendViaResend(delivery, email, "invite", { link, guide_link: String(inviteData.guide_url), user_email: email, user_name: fullName, role: String(inviteData.role) });
          } catch (e) {
            await serviceClient.auth.admin.deleteUser(data.user.id).catch(() => undefined); // nothing was sent, so no account is left behind
            return reply(req, 502, { error: e instanceof Error ? e.message : "invitation_email_failed" });
          }
          createdUser = data.user;
          sentBy = "resend";
        } else {
        const { data, error } = await serviceClient.auth.admin.inviteUserByEmail(email, {
          redirectTo: login,
          data: inviteData,
        });
        if (error || !data?.user) return reply(req, 409, { error: error?.message || "user_invite_failed" });
        createdUser = data.user;
        }
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
        p_metadata: { mode, redirect_to: mode === "invite" ? adminLoginUrl() : null, ...(mode === "invite" ? { provider: sentBy } : {}) },
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

    // CF-247 (Platform Admin 16 Nov 2026 22:12): a Platform Admin sends a password reset email to another person's account. Not to their own
    // account (they reset it from the sign-in screen), not to another Platform Admin, not to the system account, not to a disabled account and
    // not before the invitation is accepted (the invitation link sets the first password). The link returns to the admin sign-in (redirectTo).
    if (action === "reset_password") {
      const targetUserId = String(body?.user_id || "");
      if (!uuidRe.test(targetUserId)) return reply(req, 400, { error: "valid_user_id_required" });
      if (targetUserId === actorUserId) return reply(req, 409, { error: "reset_own_password_from_sign_in" });
      const { data: target, error: targetError } = await serviceClient.auth.admin.getUserById(targetUserId);
      if (targetError || !target?.user) return reply(req, 404, { error: "target_user_not_found" });
      const email = String(target.user.email || "");
      if (!emailRe.test(email) || SYSTEM_EMAIL.test(email)) return reply(req, 409, { error: "system_account_has_no_reset" });
      if (target.user.banned_until && new Date(target.user.banned_until).getTime() > Date.now()) return reply(req, 409, { error: "account_disabled_enable_first" });
      if (!target.user.email_confirmed_at) return reply(req, 409, { error: "invitation_not_yet_accepted" });
      const { data: snap, error: snapError } = await serviceClient.rpc("svc_admin_access_snapshot");
      if (snapError) throw new Error("access_snapshot_failed");
      const now = Date.now();
      const isAdmin = (Array.isArray(snap?.assignments) ? snap.assignments : []).some((a: any) =>
        String(a.user_id) === targetUserId && a.role_code === "platform_admin" && (!a.expires_at || new Date(a.expires_at).getTime() > now));
      if (isAdmin) return reply(req, 409, { error: "platform_admin_resets_own_password" });
      const login = adminLoginUrl();
      // v2.16.20: the reset email's {{role}} and {{guide_link}} read the account's own data, so it is brought up to date first (the name stays as invited)
      {
        const rank = new Map((Array.isArray(snap?.roles) ? snap.roles : []).map((r: any) => [String(r.code), r]));
        const mine = (Array.isArray(snap?.assignments) ? snap.assignments : [])
          .filter((a: any) => String(a.user_id) === targetUserId && (!a.expires_at || new Date(a.expires_at).getTime() > now))
          .map((a: any) => rank.get(String(a.role_code))).filter(Boolean)
          .sort((a: any, b: any) => Number(b.rank || 0) - Number(a.rank || 0))[0] as any;
        const { data: savedTpl } = await serviceClient.rpc("svc_admin_auth_template_settings");
        const meta = { ...(target.user.user_metadata || {}), guide_url: String(savedTpl?.guide_link || "") || guideUrl(login),
          ...(mine ? { role: String(mine.name || mine.code), role_code: String(mine.code) } : {}) };
        const { error: metaError } = await serviceClient.auth.admin.updateUserById(targetUserId, { user_metadata: meta });
        if (metaError) console.warn("admin-user-management: reset email data was not refreshed", metaError.message);
      }
      const delivery = await loadDelivery(serviceClient);
      if (delivery.effective === "resend") {
        // v2.16.23: the single-use recovery link is made without sending; the email goes through Resend from the saved Reset Password template
        const { data: rec, error: linkError } = await serviceClient.auth.admin.generateLink({ type: "recovery", email, options: { redirectTo: login } });
        const link = String(rec?.properties?.action_link || "");
        if (linkError || !link) return reply(req, 400, { error: linkError?.message || "password_reset_failed" });
        const m = rec?.user?.user_metadata || target.user.user_metadata || {};
        try {
          await sendViaResend(delivery, email, "recovery", { link, guide_link: delivery.guideLink || guideUrl(login), user_email: email, user_name: String(m.full_name || ""), role: String(m.role || "") });
        } catch (e) { return reply(req, 502, { error: e instanceof Error ? e.message : "password_reset_email_failed" }); }
      } else {
      const { error: sendError } = await serviceClient.auth.resetPasswordForEmail(email, { redirectTo: login });
      if (sendError) return reply(req, 400, { error: sendError.message || "password_reset_failed" });
      }
      // v2.16.19 (RM0F follow-up, Platform Admin 17 Nov 2026 13:12): the reset is written to the access history. Its action list took
      // password_reset_sent in migration 20261117040000. The email is already sent, so a failed log write never fails the request.
      const { error: logError } = await serviceClient.rpc("svc_admin_access_log_event", {
        p_actor_user_id: actorUserId,
        p_target_user_id: targetUserId,
        p_action: "password_reset_sent",
        p_before_state: {},
        p_after_state: { email },
        p_metadata: { redirect_to: login, provider: delivery.effective },
      });
      if (logError) console.warn("admin-user-management: password_reset_sent was not logged", logError.message);
      return reply(req, 200, { ok: true, user_id: targetUserId, sent_to: email });
    }

    // v2.16.21 (Platform Admin 17 Nov 2026 15:45): send the invitation again to a person who has not accepted it yet. Supabase Auth sends an
    // invitation to an existing address only while it is unconfirmed; the email is the Invite user template Auth holds. Never the system account,
    // a disabled account or an account that has already signed in (that person gets Reset password instead).
    if (action === "resend_invite") {
      const targetUserId = String(body?.user_id || "");
      if (!uuidRe.test(targetUserId)) return reply(req, 400, { error: "valid_user_id_required" });
      const { data: target, error: targetError } = await serviceClient.auth.admin.getUserById(targetUserId);
      if (targetError || !target?.user) return reply(req, 404, { error: "target_user_not_found" });
      const email = String(target.user.email || "").toLowerCase();
      if (!emailRe.test(email) || SYSTEM_EMAIL.test(email)) return reply(req, 409, { error: "system_account_has_no_invitation" });
      if (target.user.banned_until && new Date(target.user.banned_until).getTime() > Date.now()) return reply(req, 409, { error: "account_disabled_enable_first" });
      if (target.user.email_confirmed_at) return reply(req, 409, { error: "invitation_already_accepted_use_reset_password" });
      const { data: snap, error: snapError } = await serviceClient.rpc("svc_admin_access_snapshot");
      if (snapError) throw new Error("access_snapshot_failed");
      const now = Date.now();
      const byCode = new Map((Array.isArray(snap?.roles) ? snap.roles : []).map((r: any) => [String(r.code), r]));
      const top = (Array.isArray(snap?.assignments) ? snap.assignments : [])
        .filter((a: any) => String(a.user_id) === targetUserId && (!a.expires_at || new Date(a.expires_at).getTime() > now))
        .map((a: any) => byCode.get(String(a.role_code))).filter(Boolean)
        .sort((a: any, b: any) => Number(b.rank || 0) - Number(a.rank || 0))[0] as any;
      const login = adminLoginUrl();
      const { data: savedTpl } = await serviceClient.rpc("svc_admin_auth_template_settings");
      const old = target.user.user_metadata || {};
      const againData = { ...old, guide_url: String(savedTpl?.guide_link || "") || guideUrl(login),
          ...(top ? { role: String(top.name || top.code), role_code: String(top.code) } : {}) };
      const delivery = await loadDelivery(serviceClient);
      if (delivery.effective === "resend") {
        const { data: again, error: linkError } = await serviceClient.auth.admin.generateLink({ type: "invite", email, options: { redirectTo: login, data: againData } });
        const link = String(again?.properties?.action_link || "");
        if (linkError || !link) return reply(req, 400, { error: linkError?.message || "invitation_resend_failed" });
        try {
          await sendViaResend(delivery, email, "invite", { link, guide_link: String(againData.guide_url), user_email: email, user_name: String(againData.full_name || ""), role: String(againData.role || "") });
        } catch (e) { return reply(req, 502, { error: e instanceof Error ? e.message : "invitation_email_failed" }); }
      } else {
      const { error: inviteError } = await serviceClient.auth.admin.inviteUserByEmail(email, {
        redirectTo: login,
        data: againData,
      });
      if (inviteError) return reply(req, 400, { error: inviteError.message || "invitation_resend_failed" });
      }
      const { error: logError } = await serviceClient.rpc("svc_admin_access_log_event", {
        p_actor_user_id: actorUserId,
        p_target_user_id: targetUserId,
        p_action: "user_invited",
        p_before_state: {},
        p_after_state: { email, confirmed: false },
        p_metadata: { mode: "invite", resent: true, redirect_to: login, provider: delivery.effective },
      });
      if (logError) console.warn("admin-user-management: the resent invitation was not logged", logError.message);
      return reply(req, 200, { ok: true, user_id: targetUserId, sent_to: email });
    }

    // 16 Oct 2026 (Platform Admin: "only Platform admin should be able to delete the user from UI, Platform admins roles user can't be
    // deleted"): the database guard decides; a user named on recorded work is soft-deleted so the history keeps its link
    if (action === "delete") {
      const targetUserId = String(body?.user_id || "");
      if (!uuidRe.test(targetUserId)) return reply(req, 400, { error: "valid_user_id_required" });
      const { data: guard, error: guardError } = await serviceClient.rpc("svc_admin_access_guard_delete", {
        p_actor_user_id: actorUserId,
        p_target_user_id: targetUserId,
      });
      if (guardError || !guard?.allowed) return reply(req, 409, { error: guardError?.message || "delete_not_allowed" });
      let mode = guard.soft ? "soft_deleted" : "removed";
      let { error: deleteError } = await serviceClient.auth.admin.deleteUser(targetUserId, guard.soft === true);
      if (deleteError && mode === "removed") {
        // work recorded since the check (or a link the check does not know): keep the history and soft-delete instead
        mode = "soft_deleted";
        ({ error: deleteError } = await serviceClient.auth.admin.deleteUser(targetUserId, true));
      }
      if (deleteError) return reply(req, 400, { error: deleteError.message || "user_delete_failed" });
      const { error: recordError } = await serviceClient.rpc("svc_admin_access_record_delete", {
        p_actor_user_id: actorUserId,
        p_target_user_id: targetUserId,
        p_email: guard.email || null,
        p_roles: guard.roles || [],
        p_mode: mode,
      });
      if (recordError) return reply(req, 500, { error: "deleted_but_not_recorded" });
      return reply(req, 200, { ok: true, user_id: targetUserId, mode });
    }

    return reply(req, 400, { error: "unsupported_action" });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unexpected_error";
    const status = message === "expiry_must_be_future" ? 400 : 500;
    return reply(req, status, { error: message });
  }
});
