import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { htmlToText } from "../coverage-sweep/extract.ts";
import { intakeSafetyBlockers, quoteInText } from "../_shared/cf247-intake-validation.ts";
import { CF247_TUITION_BINDING_SOURCE_MANIFEST } from "../_shared/cf247-tuition-binding-source-manifest.ts";
import { tuitionBenchmarkRuntimeBindingHash } from "../_shared/cf247-tuition-benchmark-binding.ts";
import {
  checkEnglish, checkIntake, checkTuition, contractComponents, contractVersion, contractVersionFor, englishRequestBody, factBindingDescriptor, intakeBodyFor, intakeCheckFor, intakeRequestBody,
  isPinnedModel, parseModelJson, ROUTING_VERSION, scoreEnglish, scoreIntake, scoreTuition, TaskKey, TASKS, tuitionEvidenceText, tuitionMaxChars,
  tuitionRequestBody,
} from "../_shared/cf247-model-routing.ts";
import { AUDIT_RATE, CASCADE_VERSION, cascadeSignal, sameAnswer } from "../_shared/cf247-cascade.ts";
import { shadowInput } from "../_shared/cf247-adapter-shadow.ts";

// CF-CHG-20260915-247 Layer 3 model routing (Platform Admin direction 29 Sep 2026 18:30 IST). Nonce-only.
//   catalogue  OpenRouter /models (candidate ids only) and /credits; recorded as observations. No model call.
//   freeze     fingerprints of each task class's frozen prompt, schema and validators (recorded before gold reading).
//   excerpts   windows of stored page text for reading gold answers by hand (no model call).
//   qualify    one candidate profile on one FROZEN holdout set; hard US$8 cap across all qualification runs.
//   finalise   records a qualification run (scores recomputed in SQL from the stored rows).
//   work       live route for intake and English: claim (gated on a qualified, enabled profile with a matching binding
//              hash, the daily spend guard and the credit floor), call the pinned model, validate, record. Admission
//              is a separate governed SQL step (security.layer3_fact_admit_v1).
//   guard      OpenRouter credit floor: below US$5 remaining, the Layer 3 route crons are switched off.
// Decision 229 (2 Oct 2026): a profile whose prompt_profile_version is cf247-intake-validation-v1.3.0 runs the v1.3.0 intake
// contract (request body, checks, binding); every other profile runs exactly what it was qualified on.
const FN = "layer3-model-routing", V = ROUTING_VERSION;
// CF-247 Phase 3 (Platform Admin 9 Oct 2026): shadow reads of the merged adapter step. Kept apart from ROUTING_VERSION,
// which is part of every qualified binding hash and must not change.
const SHADOW_V = "cf247-adapter-shadow-v1.1.0";  // v1.1.0: tuition (Platform Admin 9 Oct 2026)
// Decision 221 (2 Oct 2026): a cascade task (intake, English) never falls back to the single routed profile; with no
// cascade step switched on, nothing is claimed and no model is called.
const QUALIFICATION_CAP_USD = 8.0, RESERVE_USD = 0.03;
// Decision 252 (4 Oct 2026): the credit floor and whether it stops anything come from the toolset register, which the
// Platform Admin changes in the UI (Models & services › Toolsets and limits). If it cannot be read, the floor applies.
async function creditPolicy(rpc: (n: string, a?: Record<string, unknown>) => Promise<any>): Promise<{ enforce: boolean; floor: number }> {
  try { const p = await rpc("svc_layer3_credit_policy", {}); return { enforce: p?.enforce !== false, floor: Number(p?.floor_usd ?? 0) } }
  catch { return { enforce: true, floor: Number.POSITIVE_INFINITY } }
}
const OPENROUTER = "https://openrouter.ai/api/v1";
const CREDIT_PROFILE_CODE = "openrouter-provider-tuition-validation-mistral-small-3-2-v1";
const j = (s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json", "cache-control": "no-store" } });
async function sha256(s: string) { return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))].map((x) => x.toString(16).padStart(2, "0")).join("") }
async function pool<T>(items: T[], n: number, f: (x: T) => Promise<void>) { let i = 0; await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => { while (i < items.length) await f(items[i++]) })) }
// Postgres jsonb cannot hold \u0000; a model answer that contains one is recorded without it (never rejected silently).
const pgSafe = (v: unknown): any => typeof v === "string" ? v.replace(/\u0000/g, "") : Array.isArray(v) ? v.map(pgSafe) : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, pgSafe(x)])) : v;
const taskOf = (s: unknown): TaskKey => { const t = String(s || ""); if (t === "intake" || t === "english" || t === "tuition") return t; throw new Error("task must be intake, english or tuition") };

function windows(text: string, re: RegExp, radius = 200, cap = 6000) {
  const spans: [number, number][] = [];
  for (const m of text.matchAll(re)) { const at = m.index || 0; spans.push([Math.max(0, at - radius), Math.min(text.length, at + m[0].length + radius)]) }
  spans.sort((a, b) => a[0] - b[0]);
  const merged: [number, number][] = [];
  for (const s of spans) { const l = merged[merged.length - 1]; if (l && s[0] <= l[1]) l[1] = Math.max(l[1], s[1]); else merged.push([s[0], s[1]]) }
  let out = ""; for (const [a, b] of merged) { if (out.length > cap) { out += " [...more cut]"; break } out += (out ? " || " : "") + text.slice(a, b) }
  return { windows: out, hits: spans.length };
}
const WINDOW_RE: Record<TaskKey, RegExp> = {
  intake: /(\b(?:January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept?|Oct|Nov|Dec)\b|intakes?|commenc\w*|start dates?|when (?:can|do) (?:i|you) start)/gi,
  english: /(IELTS|PTE|Pearson|TOEFL|English language|English requirement|language requirement|English proficiency)/gi,
  tuition: /(\$\s?\d|AUD|tuition|per year|annual|per annum|total)/gi,
};

Deno.serve(async (req: Request) => {
  const t0 = Date.now();
  if (req.method !== "POST") return j(405, { ok: false, error: "POST required", worker_version: V });
  const svc = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const rpc = async (n: string, a: Record<string, unknown> = {}) => { const { data, error } = await svc.rpc(n, a); if (error) throw new Error(`${n}: ${error.message}`); return data };
  const download = async (path: string) => {
    const { data, error } = await svc.storage.from("evidence").download(path);
    if (error || !data) throw new Error("evidence download failed: " + (error?.message || path));
    return data;
  };
  const pageHtml = async (path: string) => {
    const data = await download(path);
    return /\.gz$/i.test(path) ? await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text() : await data.text();
  };
  const pageText = async (path: string) => htmlToText(await pageHtml(path));
  const tuitionText = async (path: string, mime: string | null, profile: any) => tuitionEvidenceText(new Uint8Array(await (await download(path)).arrayBuffer()), mime, tuitionMaxChars(profile));
  // the account key: the Edge secret when set, otherwise the governed OpenRouter aggregator credential (vault)
  const orKey = async () => {
    const env = Deno.env.get("OPENROUTER_API_KEY"); if (env) return env;
    const p = await rpc("layer3_routing_profile_service", { p_code: CREDIT_PROFILE_CODE });
    const { data } = await svc.rpc("layer3_provider_credential_resolve_service", { p_profile_id: p?.id });
    if (typeof data === "string" && data) return data;
    throw new Error("OpenRouter credential unavailable");
  };
  const credits = async () => {
    const r = await fetch(`${OPENROUTER}/credits`, { headers: { Authorization: "Bearer " + await orKey() }, signal: AbortSignal.timeout(15000) });
    const p = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(`credits ${r.status}`);
    const total = Number(p?.data?.total_credits), used = Number(p?.data?.total_usage);
    const remaining = Math.round((total - used) * 1e6) / 1e6;
    await rpc("layer3_openrouter_observation_record_service", { p_kind: "credits", p_payload: p?.data ?? {}, p_remaining: remaining });
    return { total, used, remaining };
  };
  // one model call; returns parsed answer (or null), usage and the returned model id
  const callModel = async (profile: any, body: unknown) => {
    const st = performance.now();
    let key = Deno.env.get(String(profile.secret_env_key || "")) || "";
    if (!key) { const { data } = await svc.rpc("layer3_provider_credential_resolve_service", { p_profile_id: profile.id }); key = typeof data === "string" ? data : "" }
    if (!key) throw new Error("server-side OpenRouter credential unavailable");
    const res = await fetch(String(profile.base_url).replace(/\/$/, "") + "/chat/completions", {
      method: "POST", signal: AbortSignal.timeout(Number(profile.timeout_ms || 45000)),
      headers: { Authorization: "Bearer " + key, "Content-Type": "application/json", "HTTP-Referer": "https://coursefinder.app", "X-Title": "CourseFinder CF-247 Layer 3 model routing" },
      body: JSON.stringify(body),
    });
    const p = await res.json().catch(() => ({}));
    const out = {
      ok: res.ok, status: res.status, returned: p?.model ? String(p.model) : null, cost: Number(p?.usage?.cost || 0),
      input: Number(p?.usage?.prompt_tokens || 0), output: Number(p?.usage?.completion_tokens || 0), latency: Math.round(performance.now() - st),
      error: res.ok ? null : `provider_${res.status}: ${JSON.stringify(p?.error ?? p).slice(0, 300)}`, answer: null as any,
    };
    if (res.ok) { try { out.answer = parseModelJson(p?.choices?.[0]?.message?.content) } catch (e) { out.error = "unparseable: " + String((e as Error).message).slice(0, 120) } }
    return out;
  };
  const bindingHash = async (task: TaskKey, profile: any) => task === "tuition"
    ? await tuitionBenchmarkRuntimeBindingHash(CF247_TUITION_BINDING_SOURCE_MANIFEST, profile)
    : await sha256(factBindingDescriptor(task, profile));

  try {
    const nonce = (req.headers.get("x-cf-run-nonce") || "").trim();
    if (!nonce || !(await rpc("svc_pilot_consume_nonce", { p_function: FN, p_nonce: nonce }))) return j(401, { ok: false, error: "valid one-time nonce required", worker_version: V });
    const body = await req.json().catch(() => ({}));
    const mode = String(body.mode || "");

    if (mode === "catalogue") {
      const ids: string[] = Array.isArray(body.ids) ? body.ids.map(String) : [];
      const r = await fetch(`${OPENROUTER}/models`, { signal: AbortSignal.timeout(20000) });
      const p = await r.json();
      const all: any[] = p?.data || [];
      const pick = all.filter((m) => ids.length ? ids.includes(m.id) : false).map((m) => ({
        id: m.id, context_length: m.context_length, prompt_usd_per_m: Number(m.pricing?.prompt) * 1e6, completion_usd_per_m: Number(m.pricing?.completion) * 1e6,
        structured_outputs: (m.supported_parameters || []).includes("structured_outputs"), response_format: (m.supported_parameters || []).includes("response_format"),
        seed: (m.supported_parameters || []).includes("seed"), reasoning: (m.supported_parameters || []).includes("reasoning"),
        temperature: (m.supported_parameters || []).includes("temperature"),
      }));
      const prefix = String(body.prefix || "");
      const matching = prefix ? all.filter((m) => String(m.id).startsWith(prefix)).map((m) => `${m.id} in=${(Number(m.pricing?.prompt) * 1e6).toFixed(3)} out=${(Number(m.pricing?.completion) * 1e6).toFixed(3)} so=${(m.supported_parameters || []).includes("structured_outputs")}`) : [];
      await rpc("layer3_openrouter_observation_record_service", { p_kind: "models", p_payload: { requested: ids, found: pick, total_models: all.length }, p_remaining: null });
      const c = await credits();
      return j(200, { ok: true, mode, worker_version: V, models: pick, missing: ids.filter((i) => !pick.some((m) => m.id === i)), matching, credits: c, ms: Date.now() - t0 });
    }

    if (mode === "freeze") {
      const out: unknown[] = [];
      for (const task of ["intake", "english", "tuition"] as TaskKey[]) {
        const comp = contractComponents(task);
        const fp = await sha256(JSON.stringify(comp));
        out.push(await rpc("layer3_contract_freeze_record_service", { p_task_class: TASKS[task], p_version: contractVersion(task), p_fingerprint: fp, p_components: { sha256_by_component: Object.fromEntries(await Promise.all(Object.entries(comp).map(async ([k, v]) => [k, await sha256(typeof v === "string" ? v : JSON.stringify(v))]))), routing: V } }));
      }
      return j(200, { ok: true, mode, worker_version: V, freezes: out });
    }

    if (mode === "excerpts") {
      const task = taskOf(body.task);
      const ids = (Array.isArray(body.course_ids) ? body.course_ids : []).slice(0, 40);
      const pages: any[] = await rpc("layer3_routing_pages_service", { p_course_ids: ids });
      const out: unknown[] = [];
      await pool(pages, 6, async (p) => {
        try {
          let text: string;
          if (task === "tuition") {
            if (!p.text_storage_path) throw new Error("no hand-off text evidence");
            text = await tuitionText(p.text_storage_path, p.text_mime, { max_input_tokens: 12000 });
          } else text = await pageText(p.storage_path);
          const w = windows(text, WINDOW_RE[task], Number(body.radius || 200), Number(body.cap || 6000));
          out.push({ course_id: p.course_id, provider: String(p.provider).slice(0, 40), course: p.course, code: p.course_code, url: p.url, evidence_id: task === "tuition" ? p.text_evidence_id : p.evidence_id,
            text_sha256: await sha256(text), text_len: text.length, l2: task === "english" ? p.candidates?.english : task === "intake" ? p.candidates?.intakes : undefined,
            target: task === "tuition" ? p.work_candidate_context?.provider_current_tuition : undefined, work_status: task === "tuition" ? p.work_status : undefined,
            safety: task === "intake" ? intakeSafetyBlockers(text).map((b) => b.code) : undefined, hits: w.hits, windows: w.windows });
        } catch (e) { out.push({ course_id: p.course_id, error: String((e as Error)?.message || e) }) }
      });
      return j(200, { ok: true, mode, task, worker_version: V, pages: out, ms: Date.now() - t0 });
    }

    if (mode === "qualify" || mode === "finalise") {
      const profile = await rpc("layer3_routing_profile_service", { p_code: String(body.profile_code || "") });
      if (!profile?.id) throw new Error("profile not found");
      if (profile.enabled && !profile.paused && mode === "qualify" && !body.allow_active) throw new Error("candidate profile must be paused during qualification");
      const model = String(profile.model_identifier);
      if (!isPinnedModel(model)) throw new Error("a pinned, individually named model is required");
      const set = await rpc("layer3_holdout_cases_service", { p_gold_set: String(body.gold_set || "") });
      if (!set?.frozen_digest || set.frozen_digest !== set.current_digest) throw new Error(`gold set ${body.gold_set} is not frozen or changed since it was frozen`);
      const task = (Object.keys(TASKS) as TaskKey[]).find((k) => TASKS[k] === set.task_class)!;
      if (!(profile.allowed_task_classes || []).includes(set.task_class)) throw new Error("profile is not for this task class");
      const binding = await bindingHash(task, profile);
      const runLabel = String(body.run_label || "").trim();
      if (!/^q-[a-z0-9][a-z0-9._-]{2,60}$/i.test(runLabel)) throw new Error("run_label q-... required");
      if (mode === "finalise") return j(200, { ok: true, mode, worker_version: V, recorded: await rpc("layer3_holdout_finalise_service", { p_run_label: runLabel, p_binding_hash: binding, p_summary: { worker_version: V, contract: contractVersionFor(task, profile) } }) });

      let spent = Number(profile.qualification_spent_usd || 0);
      if (spent + RESERVE_USD >= QUALIFICATION_CAP_USD) throw new Error(`qualification cap US$${QUALIFICATION_CAP_USD} reached (spent ${spent})`);
      const offset = Math.max(0, Number(body.offset || 0)), limit = Math.min(Math.max(1, Number(body.limit || 50)), 50);
      const cases: any[] = (set.cases || []).slice(offset, offset + limit);
      const rows: any[] = []; let stopped = false;
      await pool(cases, Math.min(Math.max(1, Number(body.concurrency || 6)), 8), async (c) => {
        let text: string;
        if (task === "tuition") text = await tuitionText(c.storage_path, c.mime_type, profile);
        else text = await pageText(c.storage_path);
        const textSha = await sha256(text);
        const excerptOk = !c.evidence_excerpt || String(c.evidence_excerpt).split(" | ").every((q: string) => quoteInText(q, text));
        const blockers = task === "intake" ? intakeSafetyBlockers(text) : [];
        let r: any = { ok: false, returned: null, cost: 0, input: 0, output: 0, latency: 0, error: null, answer: null }, calls = 0;
        if (task === "intake" && blockers.length) r = { ...r, ok: true, answer: { status: "not_stated", months: [], quotes: blockers.map((b) => b.quote), rationale: "deterministic safety rule" } };
        else {
          const reqBody = task === "intake" ? intakeBodyFor(profile, model, text, Number(profile.max_output_tokens))
            : task === "english" ? englishRequestBody(model, text, Number(profile.max_output_tokens))
            : tuitionRequestBody(profile, c.source_url, c.candidate_context, text);
          const attempts = Math.max(1, Math.min(Number(profile.retry_ceiling || 0) + 1, 2));
          for (let i = 0; i < attempts; i++) {
            if (spent + RESERVE_USD >= QUALIFICATION_CAP_USD) { stopped = true; r.error = "qualification_cap_reached"; break }
            calls++;
            try { const x = await callModel(profile, reqBody); spent += x.cost; r = { ...x, cost: r.cost + x.cost, input: r.input + x.input, output: r.output + x.output }; if (x.ok && x.answer) break }
            catch (e) { r.error = String((e as Error)?.message || e).slice(0, 200) }
          }
        }
        if (!calls && r.error === "qualification_cap_reached") return;
        const modelOk = !calls || r.returned === model;
        let chk = r.answer
          ? task === "intake" ? intakeCheckFor(profile, r.answer, text, blockers) : task === "english" ? checkEnglish(r.answer, text) : checkTuition(r.answer, text, c.candidate_context, profile, r.cost)
          : { valid: false, errors: [r.error || "no_answer"], status: null, admitted: null };
        if (!modelOk) chk = { valid: false, errors: [...chk.errors, `returned_model_mismatch:${r.returned}`], status: null, admitted: null };
        const sc: any = task === "intake" ? scoreIntake(c.gold, chk) : task === "english" ? scoreEnglish(c.gold, chk) : scoreTuition(c.gold, chk);
        const row = { profile_id: profile.id, task_class: set.task_class, configured_model: model, returned_model: r.returned, outcome: sc.outcome, admitted: chk.admitted,
          answer: r.answer, errors: [...chk.errors, ...(sc.wrong || []).map((w: unknown) => `wrong:${w}`)], text_matches_gold: textSha === c.text_sha256, excerpt_in_text: excerptOk,
          cost_usd: r.cost, input_tokens: r.input, output_tokens: r.output, latency_ms: r.latency, external_calls: calls };
        await rpc("layer3_holdout_result_record_service", { p_run_label: runLabel, p_case_id: c.case_id, p_result: pgSafe(row) });
        rows.push({ case_key: c.case_key, gold: c.gold, outcome: sc.outcome, admitted: chk.admitted, status: chk.status, errors: row.errors.slice(0, 4), returned: r.returned, cost: r.cost, text_ok: row.text_matches_gold });
      });
      const tally: Record<string, number> = {}; for (const x of rows) tally[x.outcome] = (tally[x.outcome] || 0) + 1;
      return j(200, { ok: true, mode, worker_version: V, run_label: runLabel, model, binding_hash: binding, cases_run: rows.length, stopped_for_cap: stopped, qualification_spent_usd: spent, tally,
        rows: rows.sort((a, b) => String(a.case_key).localeCompare(String(b.case_key))), ms: Date.now() - t0 });
    }

    if (mode === "guard") {
      const c = await credits();
      const pol = await creditPolicy(rpc);
      const res = pol.enforce && c.remaining < pol.floor ? await rpc("layer3_route_credit_floor_service", { p_remaining: c.remaining, p_floor: pol.floor }) : null;
      return j(200, { ok: true, mode, worker_version: V, credits: c, floor: pol.floor, enforced: pol.enforce, stopped: res });
    }

    // CF-247 Phase 3 shadow: the merged step (the adapter's model on the adapter's input, same task contract and checks)
    // reads courses Layer 3 has finished and records its answer beside Layer 3's. Nothing is admitted. Limits (US$ and
    // reads a day) are applied by the claim; the OpenRouter credit floor applies as for Layer 3.
    if (mode === "shadow") {
      const task = taskOf(body.task);
      const c = await credits();
      const pol = await creditPolicy(rpc);
      if (pol.enforce && c.remaining < pol.floor) return j(200, { ok: true, mode, task, worker_version: SHADOW_V, claimed: 0, reason: "credit floor" });
      const claim = await rpc("svc_adapter_shadow_claim", { p_task: task, p_limit: Math.min(Math.max(1, Number(body.limit || 3)), 10), p_worker: `${FN}:shadow:${task}` });
      const items: any[] = claim?.items || [];
      if (!items.length) return j(200, { ok: true, mode, task, worker_version: SHADOW_V, claimed: 0, reason: claim?.reason || null });
      const tally: Record<string, number> = {}; let cost = 0;
      await pool(items, Math.min(Math.max(1, Number(body.concurrency || 3)), 4), async (it) => {
        let result: any;
        try {
          const profile = it.profile, model = String(profile?.model_identifier || "");
          if (!isPinnedModel(model)) throw new Error("the adapter's model is not a pinned model");
          const html = await pageHtml(it.storage_path);
          const inp = shadowInput(it.adapter, html, task);
          // tuition: on the whole page, the evidence text exactly as Layer 3 prepares it (its own stripping and length)
          const text = task === "tuition" && inp.basis === "page" ? tuitionEvidenceText(new TextEncoder().encode(html), it.mime_type || null, tuitionMaxChars(profile))
            : task === "tuition" ? inp.text.slice(0, tuitionMaxChars(profile)) : inp.text;
          if (task === "tuition") {
            const r: any = await callModel(profile, tuitionRequestBody(profile, it.source_url || null, it.context, text));
            let chk: any = r.answer ? checkTuition(r.answer, text, it.context, profile, r.cost) : { valid: false, errors: [r.error || "no_answer"], status: null, admitted: null };
            const pick = r.answer?.candidate_value ?? null;
            const mismatch = r.returned && r.returned !== model;
            if (mismatch) chk = { ...chk, valid: false, errors: [...(chk.errors || []), `returned_model_mismatch:${r.returned}`] };
            result = { valid: chk.valid, status: chk.status, admitted: mismatch ? null : pick, errors: chk.errors, cost_usd: r.cost, input_tokens: r.input, output_tokens: r.output,
              latency_ms: r.latency, input_basis: inp.basis, input_chars: text.length, worker_version: SHADOW_V };
          } else {
            const blockers = task === "intake" ? intakeSafetyBlockers(text) : [];
            let r: any = { ok: true, returned: null, cost: 0, input: 0, output: 0, latency: 0, error: null, answer: null }, called = false;
            if (task === "intake" && blockers.length) r.answer = { status: "not_stated", months: [], quotes: blockers.map((b) => b.quote), rationale: "deterministic safety rule" };
            else {
              called = true;
              const reqBody = task === "intake" ? intakeBodyFor(profile, model, text, Number(profile.max_output_tokens)) : englishRequestBody(model, text, Number(profile.max_output_tokens));
              r = await callModel(profile, reqBody);
            }
            let chk: any = r.answer ? (task === "intake" ? intakeCheckFor(profile, r.answer, text, blockers) : checkEnglish(r.answer, text)) : { valid: false, errors: [r.error || "no_answer"], status: null, admitted: null };
            if (called && r.returned && r.returned !== model) chk = { valid: false, errors: [...(chk.errors || []), `returned_model_mismatch:${r.returned}`], status: null, admitted: null };
            result = { valid: chk.valid, status: chk.status, admitted: chk.admitted, errors: chk.errors, cost_usd: r.cost, input_tokens: r.input, output_tokens: r.output,
              latency_ms: r.latency, input_basis: inp.basis, input_chars: text.length, worker_version: SHADOW_V };
          }
        } catch (e) {
          result = { worker_error: true, valid: false, errors: [String((e as Error)?.message || e).slice(0, 200)], cost_usd: 0, worker_version: SHADOW_V };
        }
        cost += Number(result.cost_usd || 0);
        let status = "complete_error";
        try { const done = await rpc("svc_adapter_shadow_complete", { p_id: it.shadow_id, p_result: pgSafe(result) }); status = done?.status || "?" }
        catch (e) { console.error("shadow complete failed", it.shadow_id, String((e as Error)?.message || e)) }
        tally[status] = (tally[status] || 0) + 1;
      });
      return j(200, { ok: true, mode, task, worker_version: SHADOW_V, claimed: items.length, tally, cost_usd: cost, ms: Date.now() - t0 });
    }

    if (mode === "work") {
      const task = taskOf(body.task);
      if (task === "tuition") throw new Error("tuition runs through layer3-work-dispatch / layer3-work-interpret");
      const c = await credits();
      const pol = await creditPolicy(rpc);
      if (pol.enforce && c.remaining < pol.floor) return j(200, { ok: true, mode, task, worker_version: V, stopped: await rpc("layer3_route_credit_floor_service", { p_remaining: c.remaining, p_floor: pol.floor }) });
      const worker = `layer3-model-routing:${task}:${crypto.randomUUID().slice(0, 8)}`;
      // Decision 221: a cascade task never falls back to the single routed profile. With no cascade step switched on,
      // nothing is claimed and no model is called.
      const pre = await rpc("layer3_cascade_ladder_service", { p_task_class: TASKS[task] });
      const usable = (l: any) => (l?.tiers || []).filter((t: any) => t.active && t.profile?.enabled && !t.profile?.paused && isPinnedModel(String(t.profile?.model_identifier)));
      if (pre?.route_mode === "ladder" && !usable(pre).length) return j(200, { ok: true, mode, task, worker_version: V, claimed: 0, reason: "no cascade step is switched on; nothing sent to any model" });
      // the claim resolves the routed profile; the binding hash sent must equal the one qualified
      const probe = await rpc("layer3_fact_route_profile_service", { p_task_class: TASKS[task] });
      if (!probe?.id) return j(200, { ok: true, mode, task, worker_version: V, claimed: 0, reason: probe?.reason || "no routed profile" });
      const binding = await bindingHash(task, probe);
      const claim = await rpc("layer3_fact_claim_service", { p_task_class: TASKS[task], p_limit: Math.min(Math.max(1, Number(body.limit || 10)), 40), p_worker: worker, p_binding_hash: binding });
      const items: any[] = claim?.items || [];
      if (!items.length) return j(200, { ok: true, mode, task, worker_version: V, claimed: 0, reason: claim?.reason || null, credits: c });
      const profile = claim.profile;
      const model = String(profile.model_identifier);
      const tally: Record<string, number> = {}; let cost = 0;
      // cascade ladder (route_mode = ladder): active tiers, cheapest first; otherwise the single routed profile
      const ladder = await rpc("layer3_cascade_ladder_service", { p_task_class: TASKS[task] });
      const isLadder = ladder?.route_mode === "ladder";
      const tiers: any[] = isLadder ? usable(ladder) : [];
      const tierTally: Record<string, number> = {};
      let refused = "";  // OpenRouter refused a call (key, billing or rate limit): stop and release, never escalate or send to Layer 4
      if (isLadder) {
        const finalTier = tiers[tiers.length - 1];
        await pool(items, Math.min(Math.max(1, Number(body.concurrency || 4)), 8), async (it) => {
          let status = "complete_error";
          try {
            const text = await pageText(it.storage_path);
            const textSha = await sha256(text);
            const blockers = task === "intake" ? intakeSafetyBlockers(text) : [];
            const signal = cascadeSignal(task as "intake" | "english", text);
            const ask = async (tp: any) => {
              const m = String(tp.model_identifier);
              const reqBody = task === "intake" ? intakeBodyFor(tp, m, text, Number(tp.max_output_tokens)) : englishRequestBody(m, text, Number(tp.max_output_tokens));
              let r: any = { ok: false, returned: null, cost: 0, input: 0, output: 0, latency: 0, error: null, answer: null };
              try { r = await callModel(tp, reqBody) } catch (e) { r.error = String((e as Error)?.message || e).slice(0, 200) }
              let chk: any = r.answer ? (task === "intake" ? intakeCheckFor(tp, r.answer, text, blockers) : checkEnglish(r.answer, text)) : { valid: false, errors: [r.error || "no_answer"], status: null, admitted: null };
              if (r.returned && r.returned !== m) chk = { valid: false, errors: [...chk.errors, `returned_model_mismatch:${r.returned}`], status: null, admitted: null };
              const result = { valid: chk.valid, status: chk.status, admitted: chk.admitted, errors: chk.errors, answer: r.answer, returned_model: r.returned, cost_usd: r.cost,
                input_tokens: r.input, output_tokens: r.output, latency_ms: r.latency, external_calls: 1, safety_blockers: [], text_sha256: textSha, binding_hash: null };
              return { chk, result, cost: Number(r.cost || 0) };
            };
            if (task === "intake" && blockers.length && tiers.length) {
              // deterministic safety rule: no model call, recorded against the first tier
              const result = { valid: true, status: "not_stated", admitted: null, errors: [], answer: { status: "not_stated", months: [], quotes: blockers.map((b) => b.quote), rationale: "deterministic safety rule" },
                returned_model: null, cost_usd: 0, external_calls: 0, safety_blockers: blockers.map((b) => b.code), text_sha256: textSha, binding_hash: null };
              const done = await rpc("layer3_fact_complete_ladder_service", { p_work_item_id: it.work_item_id, p_interpretation_id: it.interpretation_id, p_attempts: [], p_final: pgSafe({ profile_id: tiers[0].profile.id, tier_no: tiers[0].tier_no, escalation_reasons: [], result }) });
              status = done?.work_status || "?"; tierTally["safety_rule"] = (tierTally["safety_rule"] || 0) + 1;
            } else {
              if (refused) { const r = await rpc("layer3_fact_release_service", { p_work_item_id: it.work_item_id, p_interpretation_id: it.interpretation_id, p_reason: refused }); status = r?.work_status || "released"; tally[status] = (tally[status] || 0) + 1; return }
              const attempts: any[] = []; let final: any = null;
              // v1.1.0: a page sent back from Layer 4 to one named model goes to that model only (its cascade step may be
              // switched off, e.g. Claude Sonnet 4.6); no escalation and no spot check - an unsettled answer returns to Layer 4
              const pin = it.pinned_profile_id ? (ladder.tiers || []).find((t: any) => t.profile?.id === it.pinned_profile_id && t.profile?.enabled && !t.profile?.paused && isPinnedModel(String(t.profile?.model_identifier))) : null;
              const its: any[] = pin ? [pin] : tiers;
              // Decision 221: a step switched off between the check and the claim - release, never call another model
              if (!its.length) { const r = await rpc("layer3_fact_release_service", { p_work_item_id: it.work_item_id, p_interpretation_id: it.interpretation_id, p_reason: "no cascade step is switched on" }); status = r?.work_status || "released"; tally[status] = (tally[status] || 0) + 1; return }
              if (pin) tierTally["pinned"] = (tierTally["pinned"] || 0) + 1;
              for (let i = 0; i < its.length; i++) {
                const t = its[i], last = i === its.length - 1;
                const x = await ask(t.profile); cost += x.cost;
                if (/provider_(401|402|403|429)/.test(String(x.result.errors?.[0] || ""))) { refused = String(x.result.errors[0]).slice(0, 200); break }
                const answered = task === "intake" ? x.chk.status === "months" : x.chk.status === "stated";
                const reasons: string[] = !x.chk.valid ? (x.chk.errors || ["rejected"]).map((e: string) => String(e).split(":")[0]).slice(0, 4) : (!answered && signal ? ["not_stated_with_signal"] : []);
                if (reasons.length && !last) { attempts.push({ profile_id: t.profile.id, tier_no: t.tier_no, escalation_reasons: reasons, result: x.result }); continue }
                final = { profile_id: t.profile.id, tier_no: t.tier_no, escalation_reasons: attempts.length ? attempts[attempts.length - 1].escalation_reasons : [], result: x.result };
                // audit a sample of answers accepted below the final tier
                if (!last && x.chk.valid && x.chk.admitted && Math.random() < AUDIT_RATE) {
                  const y = await ask(finalTier.profile); cost += y.cost;
                  const agree = y.chk.valid && sameAnswer(task as "intake" | "english", x.chk.admitted, y.chk.admitted);
                  final.audit = { profile_id: finalTier.profile.id, agree, audited_answer: y.chk.admitted, audit_valid: y.chk.valid, audit_cost_usd: y.cost };
                  final.result = { ...final.result, cost_usd: Number(final.result.cost_usd || 0) + y.cost, external_calls: 2 };
                  if (!agree) final.result = { ...final.result, valid: false, admitted: null, errors: [...(final.result.errors || []), "audit_disagreement"] };
                }
                break;
              }
              if (refused) { const r = await rpc("layer3_fact_release_service", { p_work_item_id: it.work_item_id, p_interpretation_id: it.interpretation_id, p_reason: refused }); status = r?.work_status || "released"; tally[status] = (tally[status] || 0) + 1; return }
              tierTally[`tier${final.tier_no}`] = (tierTally[`tier${final.tier_no}`] || 0) + 1;
              const done = await rpc("layer3_fact_complete_ladder_service", { p_work_item_id: it.work_item_id, p_interpretation_id: it.interpretation_id, p_attempts: pgSafe(attempts), p_final: pgSafe(final) });
              status = done?.work_status || "?";
            }
          } catch (e) { console.error("ladder item failed", it.work_item_id, String((e as Error)?.message || e)) }
          tally[status] = (tally[status] || 0) + 1;
        });
        return j(200, { ok: true, mode, task, worker_version: V, cascade_version: CASCADE_VERSION, route: "ladder", tiers: tiers.map((t) => `${t.tier_no}:${t.profile.model_identifier}`), claimed: items.length, tally, tiers_used: tierTally, cost_usd: cost, credits: c, ms: Date.now() - t0 });
      }
      await pool(items, Math.min(Math.max(1, Number(body.concurrency || 4)), 6), async (it) => {
        let result: any;
        try {
          const text = await pageText(it.storage_path);
          const blockers = task === "intake" ? intakeSafetyBlockers(text) : [];
          let r: any = { ok: true, returned: null, cost: 0, input: 0, output: 0, latency: 0, error: null, answer: null }, calls = 0;
          if (task === "intake" && blockers.length) r.answer = { status: "not_stated", months: [], quotes: blockers.map((b) => b.quote), rationale: "deterministic safety rule" };
          else {
            const reqBody = task === "intake" ? intakeBodyFor(profile, model, text, Number(profile.max_output_tokens)) : englishRequestBody(model, text, Number(profile.max_output_tokens));
            const attempts = Math.max(1, Math.min(Number(profile.retry_ceiling || 0) + 1, 2));
            for (let i = 0; i < attempts; i++) {
              calls++;
              try { const x = await callModel(profile, reqBody); r = { ...x, cost: r.cost + x.cost, input: r.input + x.input, output: r.output + x.output }; if (x.ok && x.answer) break }
              catch (e) { r.error = String((e as Error)?.message || e).slice(0, 200); r.ok = false }
            }
          }
          cost += r.cost;
          const modelOk = !calls || r.returned === model;
          let chk = r.answer ? (task === "intake" ? intakeCheckFor(profile, r.answer, text, blockers) : checkEnglish(r.answer, text)) : { valid: false, errors: [r.error || "no_answer"], status: null, admitted: null };
          if (!modelOk) chk = { valid: false, errors: [...chk.errors, `returned_model_mismatch:${r.returned}`], status: null, admitted: null };
          result = { valid: chk.valid, status: chk.status, admitted: chk.admitted, errors: chk.errors, answer: r.answer, returned_model: r.returned, cost_usd: r.cost,
            input_tokens: r.input, output_tokens: r.output, latency_ms: r.latency, external_calls: calls, safety_blockers: blockers.map((b) => b.code), text_sha256: await sha256(text), binding_hash: binding };
        } catch (e) {
          result = { valid: false, status: null, admitted: null, errors: ["worker_error: " + String((e as Error)?.message || e).slice(0, 200)], external_calls: 0, cost_usd: 0 };
        }
        // one failed completion never stops the others (the item is released as stale and handed off again)
        let status = "complete_error";
        try { const done = await rpc("layer3_fact_complete_service", { p_work_item_id: it.work_item_id, p_interpretation_id: it.interpretation_id, p_result: pgSafe(result) }); status = done?.work_status || "?" }
        catch (e) { console.error("complete failed", it.work_item_id, String((e as Error)?.message || e)) }
        tally[status] = (tally[status] || 0) + 1;
      });
      return j(200, { ok: true, mode, task, worker_version: V, model, claimed: items.length, tally, cost_usd: cost, credits: c, ms: Date.now() - t0 });
    }
    return j(422, { ok: false, error: "supported modes: catalogue, freeze, excerpts, qualify, finalise, work, guard", worker_version: V });
  } catch (e) {
    return j(500, { ok: false, error: String((e as Error)?.message || e), worker_version: V });
  }
});
