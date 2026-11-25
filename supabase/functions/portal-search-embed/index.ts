import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

// CF-247 s1153 (S2-Build; Platform Admin 25 Nov 2026 17:13): meaning vectors for the StudySearch Portal's course search.
//   mode "courses" (the coverage-lane-dispatch lane portal-search-embed, through security.portal_search_embed_fire_v1): takes batches of
//     queued courses (public.svc_portal_search_embed_next), embeds their title, level and field, majors and stored description, and records
//     the vectors under search profile portal-default (public.svc_portal_search_embed_record), until the time budget or the queue ends.
//   mode "query" (catalogue.portal_course_search_v1, when a typed topic has no cached vector): embeds that one topic and caches it.
// The model is the pinned setting portal_search.embedding_model (openai/text-embedding-3-small, 1536 dimensions) through OpenRouter, the
// platform's model gateway, with provider data collection denied (ISM-2103). Spend is logged in pipeline.ai_invocations; the batch read refuses
// once the day's logged AI spend reaches the platform ceiling or this service's own ceiling. Course text is the platform's own projected text
// (no page markup); hidden and control characters are removed before it is sent.
const VERSION = "portal-search-embed-v1.0.0";
const FN = "portal-search-embed";
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json", "cache-control": "no-store" } });
async function rpc(c: any, n: string, a: Record<string, unknown> = {}) { const { data, error } = await c.rpc(n, a); if (error) throw new Error(`${n}: ${error.message}`); return data; }
const clean = (t: string) => String(t || "").replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‏ - ⁠-⁯﻿]/g, " ").replace(/[ \t]+/g, " ").trim();

async function embed(key: string, model: string, dimensions: number, inputs: string[]): Promise<{ vectors: number[][]; tokens: number }> {
  const r = await fetch("https://openrouter.ai/api/v1/embeddings", {
    method: "POST",
    headers: { authorization: `Bearer ${key}`, "content-type": "application/json", "x-title": "StudySearch portal search" },
    body: JSON.stringify({ model, input: inputs, dimensions, encoding_format: "float", provider: { data_collection: "deny" } }),
    signal: AbortSignal.timeout(60000),  // fixed: API time-out
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`embeddings HTTP ${r.status}: ${text.slice(0, 300)}`);
  const j = JSON.parse(text);
  const data = [...(j.data || [])].sort((a: any, b: any) => a.index - b.index);
  if (data.length !== inputs.length) throw new Error(`embeddings returned ${data.length} vectors for ${inputs.length} inputs`);
  for (const d of data) if (!Array.isArray(d.embedding) || d.embedding.length !== dimensions) throw new Error("embedding has the wrong length");
  return { vectors: data.map((d: any) => d.embedding), tokens: Number(j.usage?.total_tokens ?? j.usage?.prompt_tokens ?? 0) };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "POST required" }, 405);
  const url = Deno.env.get("SUPABASE_URL")!, serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const svc = createClient(url, serviceKey, { auth: { persistSession: false } });
  try {
    const nonce = (req.headers.get("x-cf-run-nonce") || "").trim(), bearer = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
    if (nonce) { if (!await rpc(svc, "svc_pilot_consume_nonce", { p_function: FN, p_nonce: nonce })) throw new Error("invalid, expired or already-used nonce"); }
    else if (bearer !== serviceKey) throw new Error("service authorisation required");
    const key = Deno.env.get("OPENROUTER_API_KEY") || "";
    if (!key) throw new Error("OPENROUTER_API_KEY is not set on the edge runtime");
    const body = await req.json().catch(() => ({}));
    const started = Date.now();

    if (body.mode === "query") {
      const text = clean(body.text).slice(0, 500);  // fixed: a typed topic is short
      if (!text || !String(body.query_key || "").startsWith("portal:")) throw new Error("query mode needs text and a portal query_key");
      const first = await rpc(svc, "svc_portal_search_embed_next", { p_limit: 1 }) as any;  // reads the model and the spend gate; leases one course too
      if (!first?.allowed) return json({ ok: true, mode: "query", skipped: first?.reason || "not allowed", workerVersion: VERSION });
      const items = [...(first.items || [])];
      const out = await embed(key, first.model, first.dimensions, [text, ...items.map((i: any) => clean(i.text))]);
      const rec = await rpc(svc, "svc_portal_search_embed_record", { p_payload: { model: first.model, tokens: out.tokens, worker: VERSION,
        items: [{ query_key: body.query_key, embedding: out.vectors[0] }, ...items.map((i: any, n: number) => ({ job_id: i.job_id, course_id: i.course_id, content_hash: i.content_hash, embedding: out.vectors[n + 1] }))] } });
      return json({ ok: true, mode: "query", recorded: rec, ms: Date.now() - started, workerVersion: VERSION });
    }

    if (body.mode === "courses") {
      let batches = 0, recorded = 0, failed = 0, tokens = 0, cost = 0, stop = "";
      while (Date.now() - started < 100000) {  // fixed: stay inside the edge wall-clock limit
        const next = await rpc(svc, "svc_portal_search_embed_next", {}) as any;
        if (!next?.allowed) { stop = next?.reason || "not allowed"; break; }
        const items = [...(next.items || [])];
        if (!items.length) { stop = "queue empty"; break; }
        try {
          const out = await embed(key, next.model, next.dimensions, items.map((i: any) => clean(i.text) || "course"));
          const rec = await rpc(svc, "svc_portal_search_embed_record", { p_payload: { model: next.model, tokens: out.tokens, worker: VERSION,
            items: items.map((i: any, n: number) => ({ job_id: i.job_id, course_id: i.course_id, content_hash: i.content_hash, embedding: out.vectors[n] })) } }) as any;
          recorded += rec.recorded || 0; tokens += rec.tokens || 0; cost += Number(rec.cost_usd || 0);
        } catch (e) {
          const msg = String((e as Error).message || e);
          await rpc(svc, "svc_portal_search_embed_record", { p_payload: { model: next.model, tokens: 0, worker: VERSION,
            items: items.map((i: any) => ({ job_id: i.job_id, error: msg })) } });
          failed += items.length; stop = `embedding failed: ${msg.slice(0, 200)}`; break;
        }
        batches++;
      }
      return json({ ok: true, mode: "courses", batches, recorded, failed, tokens, cost_usd: Math.round(cost * 1e6) / 1e6, stop, ms: Date.now() - started, workerVersion: VERSION });
    }

    throw new Error("nothing to do: send mode courses or query");
  } catch (e) {
    return json({ ok: false, error: String((e as Error).message || e), workerVersion: VERSION }, 400);
  }
});
