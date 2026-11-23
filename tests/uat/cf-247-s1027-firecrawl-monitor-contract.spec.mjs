// Guards: Platform Admin 24 Nov 2026 06:03, 06:10, 06:27 and 09:06 AEDT (UI-UX plan v1.2 slice 8: Firecrawl Monitor webhook with signature check; evidence archived with SHA-256 before routing; locked fields to Locked Field Update, other changes to Layer 4 with gate results, never admitted by the machine; weekly credit cap 150; no cron job; G3 frozen)
// s1027: migration (watchlist, events, routing, cap, status, gate items exempt from the adapter reroute), firecrawl-monitor-webhook, the register workflow.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261124120000_cf247_s1027_firecrawl_monitor.sql', 'utf8')
const FN = fs.readFileSync('supabase/functions/firecrawl-monitor-webhook/index.ts', 'utf8')
const WF = fs.readFileSync('.github/workflows/firecrawl-monitor.yml', 'utf8')
const fn = (name) => MIG.slice(MIG.indexOf(`CREATE OR REPLACE FUNCTION ${name}`), MIG.indexOf('$function$;', MIG.indexOf(`CREATE OR REPLACE FUNCTION ${name}`) + 40))

test('s1027: a delivery is refused without a valid signature, recorded once, answered at once, and archived before it is routed', () => {
  expect(FN).toContain('if (!(await signatureOk(raw, req.headers.get("x-firecrawl-signature"), Deno.env.get("FIRECRAWL_WEBHOOK_SECRET")))) return j({ error: "UNAUTHORISED" }, 401);')
  expect(FN).toContain('{ name: "HMAC", hash: "SHA-256" }')
  expect(FN).toContain('d |= a.charCodeAt(i) ^ b.charCodeAt(i)')
  expect(FN.indexOf('signatureOk(raw')).toBeLessThan(FN.indexOf('JSON.parse(new TextDecoder().decode(raw))'))
  expect(FN).toContain('EdgeRuntime.waitUntil(')
  expect(FN).toContain('`aer-artifacts/${ev.provider_id || "unknown"}/monitor/${sha}.json.gz`')
  expect(FN.indexOf('c.storage.from("evidence").upload')).toBeLessThan(FN.indexOf('c.rpc("svc_monitor_route_v1"'))
  expect(MIG).toContain('create unique index if not exists monitor_events_delivery_uq on pipeline.monitor_events (webhook_id, event_type, coalesce(url, \'\'));')
  const r = fn('public.svc_monitor_route_v1')
  expect(r).toContain("update pipeline.monitor_events set outcome = 'held_no_evidence'")
  expect(r.indexOf('insert into pipeline.evidence_artifacts')).toBeLessThan(r.indexOf('security.locked_field_update_raise_v1'))
})

test('s1027: nothing from Firecrawl is admitted: locked fields to Locked Field Update, other changes to Layer 4 with the gate result', () => {
  const r = fn('public.svc_monitor_route_v1')
  expect(r).toContain("security.locked_field_update_raise_v1('tuition', v_row, null)")
  expect(r).toContain("security.locked_field_update_raise_v1('intakes'")
  for (const f of ['provider_current_tuition', 'course_intake', 'course_english']) expect(r).toContain(`'course', v_c, '${f}', v_ev,`)
  expect(r).not.toMatch(/insert into catalogue\.|update catalogue\./i)
  expect(r).toContain("security.pipeline_num_v1('gates.fee_year_ahead', 1)")
  expect(MIG).toContain("$c$coalesce(new.layer2_state->>'source', '') <> 'preadmission_gate' and $c$")
  expect(MIG).toContain("<> 'fd3e6afef1b826533ab124bdcf48dfed' then raise exception")
  expect(r).not.toContain("jsonb_build_object('source', 'firecrawl_monitor'")
})

test('s1027: the watchlist is planned within the weekly cap (G2), the week is counted, and over the cap the monitors pause', () => {
  expect(MIG).toContain("('firecrawl', 'monitor_weekly_credits'")
  expect(MIG).toContain('to_jsonb(150), 0, 5000')
  const p = fn('security.monitor_watchlist_plan_v1')
  expect(p).toContain("case when sum(p.est) over (order by p.rk, p.psort, p.target_type desc, p.url) <= v_cap then 'planned' else 'held_budget' end")
  expect(MIG).toContain("if (v_plan->>'est_week_credits')::numeric > (v_plan->>'weekly_cap')::numeric then raise exception")
  expect(fn('public.svc_monitor_event_v1')).toContain("'over_cap', v_type = 'monitor.check.completed' and v_week > v_cap")
  expect(FN).toContain('if (d.over_cap) work.push(pauseAll(')
  expect(FN).toContain('{ status: "paused" }')
  expect(MIG).not.toMatch(/cron\.schedule/)
  expect(WF).not.toMatch(/^\s+schedule:/m)
  expect(FN).toContain('judgeEnabled: false')
})

test('s1027: platform calls need a one-time nonce; errors carry fixed codes; status read needs rank 4; nothing dropped', () => {
  expect(FN).toContain('c.rpc("svc_pilot_consume_nonce", { p_function: "firecrawl-monitor-webhook", p_nonce: nonce })')
  expect(MIG).toContain("insert into pipeline.pilot_nonce_functions (function_name) values ('firecrawl-monitor-webhook')")
  expect(FN).not.toMatch(/j\(\{\s*error:\s*(error|e)\b/)
  expect(fn('public.admin_monitor_status_v1')).toContain('coalesce(security.current_role_rank(), 0) < 4')
  expect(JSON.parse(fs.readFileSync('.github/edge-functions.json', 'utf8')).functions['firecrawl-monitor-webhook']).toBe(false)
  expect(MIG.replace(/on commit drop/g, '')).not.toMatch(/\bdrop\s+(table|function|trigger|index|view)|delete from|truncate /i)
  for (const s of ['post-check: the consumer API moved', 'post-check: manual locks changed', 'post-check: the number of active cron jobs changed', 'post-check: gate items are still rerouted']) expect(MIG).toContain(s)
})
