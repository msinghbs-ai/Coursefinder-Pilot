import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { htmlToText, intakes } from "../coverage-sweep/extract.ts";
import {
  applyIntakeSafetyRule, focusText, INTAKE_RESPONSE_SCHEMA, INTAKE_SAFETY_RULES, INTAKE_SYSTEM_PROMPT, INTAKE_VALIDATOR_VERSION,
  intakeSafetyBlockers, MAX_QUOTES, monthNamesToNumbers, quoteInText, scoreCase, summarise, validateIntakeAnswer,
} from "../_shared/cf247-intake-validation.ts";

// CF-247 plan item A3: one-time Layer 3 intake benchmark (nonce-only, never scheduled).
//   mode excerpts: intake-relevant windows of stored sweep pages, used to read the gold set by hand (no model call).
//   mode run:      Layer 2 (the live sweep extractor) and Layer 3 (the pinned model) against every case of one FROZEN
//                  gold set (refused unless its current digest equals the frozen one); the deterministic safety rule
//                  runs before the model (no call) and on every accepted answer; one result row per case; hard
//                  OpenRouter budget cap across all runs and profiles.
//   mode verify:   a gold set's pinned text hash and gold excerpts against the stored pages (no model call).
//   mode finalise: records the run in layer3_quality_benchmark_runs and the intake profile's quality_benchmark.
// Nothing is admitted, scheduled or enabled here. The intake profile must stay paused.
const FN = "layer3-intake-benchmark", V = "cf247-intake-benchmark-v1.1.0";
const BUDGET_USD = 3.0, RESERVE_USD = 0.05;
const MAX_TOKENS = 600, MAX_CHARS = 30000;
const j = (s: number, b: unknown) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json", "cache-control": "no-store" } });
async function sha256(s: string) { return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))].map((x) => x.toString(16).padStart(2, "0")).join("") }
async function pool<T>(items: T[], n: number, f: (x: T) => Promise<void>) { let i = 0; await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => { while (i < items.length) await f(items[i++]) })) }

// The request body is built in one place so the binding hash covers what is actually sent.
function requestBody(model: string, text: string) {
  return {
    model, temperature: 0, seed: 0, max_tokens: MAX_TOKENS,
    provider: { require_parameters: true }, usage: { include: true },
    response_format: { type: "json_schema", json_schema: { name: "cf247_intake_months", strict: true, schema: INTAKE_RESPONSE_SCHEMA } },
    messages: [
      { role: "system", content: INTAKE_SYSTEM_PROMPT },
      { role: "user", content: `Course page text:\n${focusText(text, MAX_CHARS)}` },
    ],
  };
}
async function bindingHash(model: string) {
  return sha256(JSON.stringify({
    validator: INTAKE_VALIDATOR_VERSION, worker: V, model, prompt: INTAKE_SYSTEM_PROMPT, schema: INTAKE_RESPONSE_SCHEMA,
    request_body: requestBody.toString(), focus: focusText.toString(), validate: validateIntakeAnswer.toString(), max_chars: MAX_CHARS, max_tokens: MAX_TOKENS,
    max_quotes: MAX_QUOTES, safety_rules: INTAKE_SAFETY_RULES.map((r) => ({ code: r.code, re: String(r.re) })),
    safety_blockers: intakeSafetyBlockers.toString(), safety_apply: applyIntakeSafetyRule.toString(),
  }));
}
// A gold excerpt is one passage, or several joined by " | "; either way every character must be in the page text.
function goldExcerptOk(excerpt: unknown, text: string) {
  if (!excerpt) return true;
  const e = String(excerpt);
  return quoteInText(e, text) || e.split(" | ").every((q) => quoteInText(q, text));
}
function parse(v: unknown) {
  if (v && typeof v === "object") return v;
  return JSON.parse(String(v || "").trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, ""));
}
// Gold-reading windows: every month name/abbreviation and every intake lead word, with context, merged.
function goldWindows(text: string, radius = 170, cap = 7000) {
  const re = /(\b(?:January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept?|Oct|Nov|Dec)\b|intakes?|commenc\w*|start dates?|when (?:can|do) (?:i|you) start)/gi;
  const spans: [number, number][] = [];
  for (const m of text.matchAll(re)) {
    if (/^may$/i.test(m[0]) && m[0] !== "May") continue;
    const at = m.index || 0; spans.push([Math.max(0, at - radius), Math.min(text.length, at + m[0].length + radius)]);
  }
  spans.sort((a, b) => a[0] - b[0]);
  const merged: [number, number][] = [];
  for (const s of spans) { const l = merged[merged.length - 1]; if (l && s[0] <= l[1]) l[1] = Math.max(l[1], s[1]); else merged.push([s[0], s[1]]) }
  let out = ""; for (const [a, b] of merged) { if (out.length > cap) { out += " [...more windows cut]"; break } out += (out ? " || " : "") + text.slice(a, b) }
  return { windows: out, hits: spans.length };
}

Deno.serve(async (req: Request) => {
  const t0 = Date.now();
  if (req.method !== "POST") return j(405, { ok: false, error: "POST required", worker_version: V });
  const svc = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const rpc = async (n: string, a: Record<string, unknown> = {}) => { const { data, error } = await svc.rpc(n, a); if (error) throw new Error(`${n}: ${error.message}`); return data };
  const pageText = async (path: string) => {
    const { data, error } = await svc.storage.from("evidence").download(path);
    if (error || !data) throw new Error("evidence download failed: " + (error?.message || path));
    const html = /\.gz$/i.test(path) ? await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text() : await data.text();
    return htmlToText(html);
  };
  try {
    const nonce = (req.headers.get("x-cf-run-nonce") || "").trim();
    if (!nonce || !(await rpc("svc_pilot_consume_nonce", { p_function: FN, p_nonce: nonce }))) return j(401, { ok: false, error: "valid one-time nonce required", worker_version: V });
    const body = await req.json().catch(() => ({}));
    const mode = String(body.mode || "");

    if (mode === "excerpts") {
      const ids = (Array.isArray(body.course_ids) ? body.course_ids : []).slice(0, 60);
      const pages: any[] = await rpc("layer3_intake_benchmark_pages_service", { p_course_ids: ids });
      const out: unknown[] = [];
      await pool(pages, 6, async (p) => {
        try {
          const text = await pageText(p.storage_path);
          const w = goldWindows(text, Number(body.radius || 170), Number(body.cap || 7000));
          out.push({ course_id: p.course_id, provider: String(p.provider).slice(0, 50), url: p.url, evidence_id: p.evidence_id, text_sha256: await sha256(text), text_len: text.length,
            stored_l2: p.layer2_intakes, live_l2: intakes(text), extractor: p.extractor, hits: w.hits, windows: w.windows });
        } catch (e) { out.push({ course_id: p.course_id, error: String((e as Error)?.message || e) }) }
      });
      return j(200, { ok: true, mode, worker_version: V, pages: out, ms: Date.now() - t0 });
    }

    // verify: a frozen gold set's pinned text and excerpts, with no model call
    if (mode === "verify") {
      const goldSet = String(body.gold_set || "").trim();
      const set = await rpc("layer3_intake_benchmark_cases_service", { p_gold_set: goldSet });
      const out: any[] = [];
      await pool(set.cases || [], 6, async (c: any) => {
        const text = await pageText(c.storage_path);
        out.push({ case_key: c.case_key, text_matches_gold: (await sha256(text)) === c.text_sha256, gold_excerpt_in_text: goldExcerptOk(c.evidence_excerpt, text), layer2: monthNamesToNumbers(intakes(text)) });
      });
      return j(200, { ok: true, mode, worker_version: V, gold_set: goldSet, frozen_digest: set.frozen_digest, current_digest: set.current_digest, cases: out.length,
        all_text_pinned: out.every((x) => x.text_matches_gold), all_excerpts_in_text: out.every((x) => x.gold_excerpt_in_text), problems: out.filter((x) => !x.text_matches_gold || !x.gold_excerpt_in_text) });
    }

    const profile = await rpc("layer3_intake_benchmark_profile_service", body.profile_code ? { p_code: String(body.profile_code) } : {});
    if (!profile?.id) throw new Error("intake profile missing");
    if (!profile.paused) throw new Error("intake profile must be paused during benchmark");
    const model = String(profile.model_identifier);
    if (!model || /(^|\/)auto$|openrouter\/auto|:auto/i.test(model)) throw new Error("a pinned, individually named model is required");
    const binding = await bindingHash(model);

    if (mode === "finalise") {
      const runLabel = String(body.run_label || "");
      const summary = body.summary && typeof body.summary === "object" ? body.summary : {};
      const recorded = await rpc("layer3_intake_benchmark_finalise_service", { p_run_label: runLabel, p_summary: { ...summary, worker_version: V, validator: INTAKE_VALIDATOR_VERSION }, p_binding_hash: binding });
      return j(200, { ok: true, mode, worker_version: V, binding_hash: binding, recorded });
    }

    if (mode === "run") {
      const runLabel = String(body.run_label || "").trim();
      if (!/^[a-z0-9][a-z0-9._-]{2,60}$/i.test(runLabel)) throw new Error("run_label required");
      const goldSet = String(body.gold_set || "").trim();
      const set = await rpc("layer3_intake_benchmark_cases_service", { p_gold_set: goldSet });
      // the gold set must be frozen, and unchanged since it was frozen, before any model call
      if (!set?.frozen_digest || set.frozen_digest !== set.current_digest) throw new Error(`gold set ${goldSet} is not frozen or has changed since it was frozen`);
      let cases: any[] = set.cases || [];
      const offset = Math.max(0, Number(body.offset || 0)), limit = Math.min(Math.max(1, Number(body.limit || 60)), 60);
      cases = cases.slice(offset, offset + limit);
      let key = Deno.env.get(String(profile.secret_env_key || ""));
      if (!key) { const { data } = await svc.rpc("layer3_provider_credential_resolve_service", { p_profile_id: profile.id }); key = typeof data === "string" ? data : "" }
      if (!key) throw new Error("server-side OpenRouter credential unavailable");
      let spent = Number(profile.spent_usd || 0);
      const cap = Math.min(BUDGET_USD, Number(profile.cost_ceiling_usd || BUDGET_USD));
      const rows: any[] = [], models = new Set<string>();
      let stoppedForBudget = false;
      await pool(cases, Math.min(Math.max(1, Number(body.concurrency || 6)), 8), async (c) => {
        const text = await pageText(c.storage_path);
        const textSha = await sha256(text);
        // the gold answer's own excerpt(s) must still be in the text it was read from
        const excerptOk = goldExcerptOk(c.evidence_excerpt, text);
        const gold = { status: c.gold_status, months: (c.gold_months || []).map(Number) };
        const l2 = monthNamesToNumbers(intakes(text));
        const l2Score = scoreCase(gold, { status: l2.length ? "months" : "not_stated", months: l2 });
        let answer: any = null, err: string | null = null, returned: string | null = null, input = 0, output = 0, cost = 0, calls = 0, latency = 0;
        const blockers = intakeSafetyBlockers(text);
        // safety rule before the model: a blocked page is not_stated and is never sent to the model
        if (blockers.length) answer = { status: "not_stated", months: [], quotes: blockers.map((b) => b.quote), rationale: "deterministic safety rule: " + blockers.map((b) => b.code).join(", ") };
        const attempts = blockers.length ? 0 : Math.max(1, Math.min(Number(profile.retry_ceiling || 0) + 1, 2));
        for (let i = 0; i < attempts; i++) {
          // hard budget cap: stop before a call that could cross it (a call on these pages costs well under a cent)
          if (spent + RESERVE_USD >= cap) { stoppedForBudget = true; err = "budget_cap_reached"; break }
          calls++;
          const st = performance.now();
          try {
            const res = await fetch(String(profile.base_url).replace(/\/$/, "") + "/chat/completions", {
              method: "POST", signal: AbortSignal.timeout(Number(profile.timeout_ms || 45000)),
              headers: { Authorization: "Bearer " + key, "Content-Type": "application/json", "HTTP-Referer": "https://coursefinder.app", "X-Title": "CourseFinder CF-247 A3 Intake Benchmark" },
              body: JSON.stringify(requestBody(model, text)),
            });
            const p = await res.json().catch(() => ({}));
            latency = Math.max(latency, Math.round(performance.now() - st));
            input += Number(p?.usage?.prompt_tokens || 0); output += Number(p?.usage?.completion_tokens || 0);
            const thisCost = Number(p?.usage?.cost || 0); cost += thisCost; spent += thisCost;
            if (p?.model) { returned = String(p.model); models.add(returned) }
            if (!res.ok) { err = `provider_${res.status}`; continue }
            answer = parse(p?.choices?.[0]?.message?.content); err = null; break;
          } catch (e) { err = String((e as Error)?.message || e); latency = Math.max(latency, Math.round(performance.now() - st)) }
        }
        // safety rule after the model: applied to every accepted answer (a blocker can only remove months)
        const val = answer ? applyIntakeSafetyRule(validateIntakeAnswer(answer, text), blockers) : { valid: false, errors: [err || "no_answer"], status: null, months: [] as number[], quotes: [] as string[] };
        const l3Score = scoreCase(gold, { status: val.status, months: val.months });
        const row = {
          profile_id: profile.id, configured_model: model, returned_model: returned, text_sha256: textSha, text_matches_gold: textSha === c.text_sha256, gold_excerpt_in_text: excerptOk,
          layer2_months: l2, layer2_exact: l2Score.exact,
          layer3_status: val.status ?? (answer?.status ? `rejected:${answer.status}` : "no_answer"), layer3_months: val.months, layer3_valid: val.valid, layer3_errors: val.errors,
          layer3_exact: l3Score.exact, invented_months: l3Score.invented, missed_months: l3Score.missed,
          quotes: answer?.quotes ?? null, raw_answer: answer, input_tokens: input, output_tokens: output, cost_usd: cost, latency_ms: latency, external_calls: calls,
          safety_blockers: blockers.map((b) => b.code), gold_set: goldSet,
        };
        if (err === "budget_cap_reached" && !calls) return; // not recorded: the case was never run
        await rpc("layer3_intake_benchmark_result_record_service", { p_run_label: runLabel, p_case_id: c.case_id, p_result: row });
        rows.push({ case_key: c.case_key, safety: blockers.map((b) => b.code), gold, layer2: l2, layer2_exact: l2Score.exact, layer3: { status: row.layer3_status, months: val.months, valid: val.valid, errors: val.errors }, layer3_exact: l3Score.exact, invented: l3Score.invented, missed: l3Score.missed, cost });
      });
      const l2Summary = summarise(rows.map((r) => ({ gold: r.gold, predicted: { status: r.layer2.length ? "months" : "not_stated", months: r.layer2 } })));
      const l3Summary = summarise(rows.map((r) => ({ gold: r.gold, predicted: { status: r.layer3.valid ? r.layer3.status : null, months: r.layer3.months } })));
      return j(200, { ok: true, mode, worker_version: V, run_label: runLabel, gold_set: goldSet, gold_digest: set.frozen_digest, model, binding_hash: binding, cases_run: rows.length, stopped_for_budget: stoppedForBudget,
        spent_usd_total: spent, returned_models: [...models], layer2: l2Summary, layer3: l3Summary, rows: rows.sort((a, b) => String(a.case_key).localeCompare(String(b.case_key))), ms: Date.now() - t0 });
    }
    return j(422, { ok: false, error: "supported modes: excerpts, verify, run, finalise", worker_version: V });
  } catch (e) {
    return j(500, { ok: false, error: String((e as Error)?.message || e), worker_version: V });
  }
});
